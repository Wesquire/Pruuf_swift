-- ============================================================================
-- PRUUF App Revamp Migration
-- Date: 2026-02-16
-- Changes:
--   1. Add device_transfer_code column to users
--   2. Migrate 'both' role users to 'sender'
--   3. Remove 'both' from primary_role constraint
--   4. Change unique_codes from 6-digit to 5-digit
--   5. Add owner_role to unique_codes (bidirectional code support)
--   6. Rename receiver_id to owner_id in unique_codes
--   7. Update RLS policies for unique_codes
--   8. Update generate_unique_code() for 5-digit codes
--   9. Create generalized create_user_code() function
--  10. Deactivate existing 6-digit codes
-- ============================================================================

-- ============================================================================
-- 1. ADD DEVICE TRANSFER CODE TO USERS
-- 4-digit PIN for account recovery on new devices
-- ============================================================================
ALTER TABLE users ADD COLUMN IF NOT EXISTS device_transfer_code TEXT;

-- ============================================================================
-- 2. MIGRATE EXISTING 'both' USERS TO 'sender'
-- Preserve sender functionality as primary; receiver profile remains intact
-- ============================================================================
UPDATE users SET primary_role = 'sender' WHERE primary_role = 'both';

-- ============================================================================
-- 3. UPDATE PRIMARY_ROLE CHECK CONSTRAINT (remove 'both')
-- ============================================================================
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_primary_role_check;
ALTER TABLE users ADD CONSTRAINT users_primary_role_check
  CHECK (primary_role IN ('sender', 'receiver'));

-- ============================================================================
-- 4. DEACTIVATE EXISTING 6-DIGIT CODES BEFORE CONSTRAINT CHANGE
-- Must happen before changing the CHECK constraint
-- ============================================================================
UPDATE unique_codes SET is_active = false WHERE LENGTH(code) = 6;

-- Delete inactive 6-digit codes so they don't violate the new constraint
DELETE FROM unique_codes WHERE LENGTH(code) = 6 AND is_active = false;

-- ============================================================================
-- 5. CHANGE UNIQUE_CODES FROM 6-DIGIT TO 5-DIGIT
-- ============================================================================
ALTER TABLE unique_codes DROP CONSTRAINT IF EXISTS unique_codes_code_check;
ALTER TABLE unique_codes ADD CONSTRAINT unique_codes_code_check
  CHECK (code ~ '^\d{5}$');

-- ============================================================================
-- 6. ADD OWNER_ROLE TO UNIQUE_CODES (bidirectional code support)
-- Allows both senders and receivers to generate linking codes
-- ============================================================================
ALTER TABLE unique_codes ADD COLUMN IF NOT EXISTS owner_role TEXT
  DEFAULT 'receiver' CHECK (owner_role IN ('sender', 'receiver'));

-- ============================================================================
-- 7. RENAME RECEIVER_ID TO OWNER_ID IN UNIQUE_CODES
-- Reflects that either role can own a code
-- ============================================================================
ALTER TABLE unique_codes RENAME COLUMN receiver_id TO owner_id;

-- Drop and recreate the unique constraint with new column name
ALTER TABLE unique_codes DROP CONSTRAINT IF EXISTS unique_codes_receiver_id_key;
-- Note: the constraint might have a different name depending on migration order
DO $$
BEGIN
  -- Try dropping by common constraint names
  EXECUTE 'ALTER TABLE unique_codes DROP CONSTRAINT IF EXISTS unique_codes_receiver_id_key';
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

-- Recreate unique constraint on owner_id
ALTER TABLE unique_codes ADD CONSTRAINT unique_codes_owner_id_key UNIQUE (owner_id);

-- Drop old indexes and create new ones
DROP INDEX IF EXISTS idx_unique_codes_receiver;
CREATE INDEX IF NOT EXISTS idx_unique_codes_owner ON unique_codes(owner_id);

-- ============================================================================
-- 8. UPDATE RLS POLICIES FOR UNIQUE_CODES
-- ============================================================================
DROP POLICY IF EXISTS "Receivers can view own code" ON unique_codes;
DROP POLICY IF EXISTS "Receivers can create own code" ON unique_codes;
DROP POLICY IF EXISTS "Receivers can update own code" ON unique_codes;

CREATE POLICY "Users can view own code" ON unique_codes
  FOR SELECT
  USING (owner_id = auth.uid());

CREATE POLICY "Anyone can lookup active codes" ON unique_codes
  FOR SELECT
  USING (is_active = true);

CREATE POLICY "Users can create own code" ON unique_codes
  FOR INSERT
  WITH CHECK (owner_id = auth.uid());

CREATE POLICY "Users can update own code" ON unique_codes
  FOR UPDATE
  USING (owner_id = auth.uid());

-- ============================================================================
-- 9. UPDATE GENERATE_UNIQUE_CODE() FOR 5-DIGIT CODES
-- ============================================================================
CREATE OR REPLACE FUNCTION generate_unique_code()
RETURNS TEXT AS $$
DECLARE
    new_code TEXT;
    code_exists BOOLEAN;
BEGIN
    LOOP
        -- Generate random 5-digit code (00000-99999)
        new_code := LPAD(FLOOR(RANDOM() * 100000)::TEXT, 5, '0');

        -- Check if code already exists in active codes
        SELECT EXISTS(
            SELECT 1 FROM unique_codes
            WHERE code = new_code
            AND is_active = true
        ) INTO code_exists;

        -- If code doesn't exist, we found a unique one
        IF NOT code_exists THEN
            RETURN new_code;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 10. CREATE GENERALIZED CREATE_USER_CODE() FUNCTION
-- Works for both senders and receivers
-- ============================================================================
CREATE OR REPLACE FUNCTION create_user_code(p_user_id UUID, p_role TEXT DEFAULT 'receiver')
RETURNS TEXT AS $$
DECLARE
    v_code TEXT;
    v_existing_code TEXT;
BEGIN
    -- Check if user already has an active code
    SELECT code INTO v_existing_code
    FROM unique_codes
    WHERE owner_id = p_user_id
    AND is_active = true;

    -- If active code exists, return it
    IF v_existing_code IS NOT NULL THEN
        RETURN v_existing_code;
    END IF;

    -- Generate a new unique code
    v_code := generate_unique_code();

    -- Deactivate any old codes for this user
    UPDATE unique_codes
    SET is_active = false
    WHERE owner_id = p_user_id AND is_active = true;

    -- Insert the new code
    INSERT INTO unique_codes (code, owner_id, owner_role, is_active)
    VALUES (v_code, p_user_id, p_role, true)
    ON CONFLICT DO NOTHING;

    RETURN v_code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION create_user_code(UUID, TEXT) TO authenticated;

-- ============================================================================
-- UPDATE COMMENTS
-- ============================================================================
COMMENT ON TABLE unique_codes IS 'Manages 5-digit codes for senders and receivers to share for connection linking';
COMMENT ON COLUMN unique_codes.code IS '5-digit numeric code for connection establishment';
COMMENT ON COLUMN unique_codes.owner_id IS 'User ID of the code owner (sender or receiver)';
COMMENT ON COLUMN unique_codes.owner_role IS 'Role of the code owner: sender or receiver';
COMMENT ON FUNCTION generate_unique_code() IS 'Generates a unique 5-digit numeric code not currently in use';
COMMENT ON FUNCTION create_user_code(UUID, TEXT) IS 'Creates or retrieves a unique 5-digit code for a user (sender or receiver)';
