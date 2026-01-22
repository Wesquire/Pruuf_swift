-- Migration: 020_section_2_3_database_functions.sql
-- Description: Phase 2 Section 2.3 - Database Functions Verification & Completion
-- Created: 2026-01-19
--
-- This migration ensures all Section 2.3 requirements from plan.md are met:
-- 1. generate_unique_code() - Returns TEXT, generates 6-digit numeric code, checks uniqueness
-- 2. create_receiver_code(p_user_id UUID) - Returns TEXT, creates code for receiver
-- 3. check_subscription_status(p_user_id UUID) - Returns TEXT, checks/updates subscription
-- 4. update_updated_at() - TRIGGER function that sets NEW.updated_at = now()
-- 5. users_updated_at trigger
-- 6. sender_profiles_updated_at trigger
-- 7. receiver_profiles_updated_at trigger
-- 8. connections_updated_at trigger
-- ============================================================================

-- ============================================================================
-- 1. GENERATE_UNIQUE_CODE FUNCTION
-- Requirement: Returns TEXT, generates 6-digit numeric code, checks for uniqueness
--              against active codes, loops until unique code found
-- Status: Already exists in 007_core_database_tables.sql
-- ============================================================================

-- Verify and ensure the function exists with correct signature
CREATE OR REPLACE FUNCTION generate_unique_code()
RETURNS TEXT AS $$
DECLARE
    new_code TEXT;
    code_exists BOOLEAN;
    max_attempts INTEGER := 1000; -- Safety limit to prevent infinite loops
    attempt_count INTEGER := 0;
BEGIN
    LOOP
        -- Generate random 6-digit code (000000-999999)
        new_code := LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0');

        -- Check if code already exists in active codes
        SELECT EXISTS(
            SELECT 1 FROM unique_codes
            WHERE code = new_code
            AND is_active = true
        ) INTO code_exists;

        -- Exit loop if code is unique
        EXIT WHEN NOT code_exists;

        -- Safety: prevent infinite loop
        attempt_count := attempt_count + 1;
        IF attempt_count >= max_attempts THEN
            RAISE EXCEPTION 'Could not generate unique code after % attempts', max_attempts;
        END IF;
    END LOOP;

    RETURN new_code;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION generate_unique_code() IS
    'Section 2.3: Generates a unique 6-digit numeric code. Loops until unique code found against active codes.';

-- ============================================================================
-- 2. CREATE_RECEIVER_CODE FUNCTION
-- Requirement: Calls generate_unique_code(), inserts into unique_codes, returns code
-- Status: Already exists in 009_database_functions.sql
-- ============================================================================

-- Verify and ensure the function exists with correct implementation
CREATE OR REPLACE FUNCTION create_receiver_code(p_user_id UUID)
RETURNS TEXT AS $$
DECLARE
    v_code TEXT;
    v_existing_code TEXT;
BEGIN
    -- Check if user already has an active code
    SELECT code INTO v_existing_code
    FROM unique_codes
    WHERE receiver_id = p_user_id AND is_active = true;

    -- If code exists, return it
    IF v_existing_code IS NOT NULL THEN
        RETURN v_existing_code;
    END IF;

    -- Generate a new unique code using generate_unique_code()
    v_code := generate_unique_code();

    -- Deactivate any old codes for this user
    UPDATE unique_codes
    SET is_active = false
    WHERE receiver_id = p_user_id AND is_active = true;

    -- Insert the new code into unique_codes table
    INSERT INTO unique_codes (code, receiver_id, is_active, created_at)
    VALUES (v_code, p_user_id, true, now())
    ON CONFLICT (receiver_id)
    DO UPDATE SET
        code = EXCLUDED.code,
        is_active = true,
        created_at = now();

    RETURN v_code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION create_receiver_code(UUID) TO authenticated;

COMMENT ON FUNCTION create_receiver_code(UUID) IS
    'Section 2.3: Creates a unique 6-digit code for receiver. Calls generate_unique_code(), inserts into unique_codes, returns new code.';

-- ============================================================================
-- 3. CHECK_SUBSCRIPTION_STATUS FUNCTION
-- Requirement: Returns TEXT, checks trial_end_date and subscription_end_date,
--              updates subscription_status to 'expired' if needed, returns status
-- Status: Already exists in 009_database_functions.sql
-- ============================================================================

-- Verify and ensure the function exists with correct implementation
CREATE OR REPLACE FUNCTION check_subscription_status(p_user_id UUID)
RETURNS TEXT AS $$
DECLARE
    v_status TEXT;
    v_trial_end TIMESTAMPTZ;
    v_sub_end TIMESTAMPTZ;
BEGIN
    -- Get current subscription info
    SELECT
        subscription_status::TEXT,
        trial_end_date,
        subscription_end_date
    INTO v_status, v_trial_end, v_sub_end
    FROM receiver_profiles
    WHERE user_id = p_user_id;

    -- If no profile found, return null
    IF v_status IS NULL THEN
        RETURN NULL;
    END IF;

    -- Check if trial expired
    IF v_status = 'trial' AND v_trial_end IS NOT NULL AND v_trial_end < now() THEN
        UPDATE receiver_profiles
        SET subscription_status = 'expired'
        WHERE user_id = p_user_id;
        RETURN 'expired';
    END IF;

    -- Check if subscription expired
    IF v_status = 'active' AND v_sub_end IS NOT NULL AND v_sub_end < now() THEN
        UPDATE receiver_profiles
        SET subscription_status = 'expired'
        WHERE user_id = p_user_id;
        RETURN 'expired';
    END IF;

    -- Return current status
    RETURN v_status;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION check_subscription_status(UUID) TO authenticated;

COMMENT ON FUNCTION check_subscription_status(UUID) IS
    'Section 2.3: Checks subscription status, updates to expired if trial_end_date or subscription_end_date has passed. Returns current status as TEXT.';

-- ============================================================================
-- 4. UPDATE_UPDATED_AT TRIGGER FUNCTION
-- Requirement: TRIGGER function that sets NEW.updated_at = now()
-- Status: Exists as update_updated_at_column() - creating alias for spec compliance
-- ============================================================================

-- Create the exact function name from spec
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION update_updated_at() IS
    'Section 2.3: Trigger function that sets NEW.updated_at = now(). Used for automatic timestamp updates.';

-- Keep the existing function name as well for backwards compatibility
-- (other migrations may reference update_updated_at_column)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 5. USERS_UPDATED_AT TRIGGER
-- Requirement: BEFORE UPDATE ON users executing update_updated_at()
-- Status: Already exists using update_updated_at_column()
-- ============================================================================

-- Recreate trigger to use the spec-compliant function name
DROP TRIGGER IF EXISTS users_updated_at ON users;
CREATE TRIGGER users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TRIGGER users_updated_at ON users IS
    'Section 2.3: Updates updated_at timestamp before any UPDATE on users table.';

-- ============================================================================
-- 6. SENDER_PROFILES_UPDATED_AT TRIGGER
-- Requirement: BEFORE UPDATE ON sender_profiles executing update_updated_at()
-- Status: Already exists using update_updated_at_column()
-- ============================================================================

-- Recreate trigger to use the spec-compliant function name
DROP TRIGGER IF EXISTS sender_profiles_updated_at ON sender_profiles;
CREATE TRIGGER sender_profiles_updated_at
    BEFORE UPDATE ON sender_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TRIGGER sender_profiles_updated_at ON sender_profiles IS
    'Section 2.3: Updates updated_at timestamp before any UPDATE on sender_profiles table.';

-- ============================================================================
-- 7. RECEIVER_PROFILES_UPDATED_AT TRIGGER
-- Requirement: BEFORE UPDATE ON receiver_profiles executing update_updated_at()
-- Status: Already exists using update_updated_at_column()
-- ============================================================================

-- Recreate trigger to use the spec-compliant function name
DROP TRIGGER IF EXISTS receiver_profiles_updated_at ON receiver_profiles;
CREATE TRIGGER receiver_profiles_updated_at
    BEFORE UPDATE ON receiver_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TRIGGER receiver_profiles_updated_at ON receiver_profiles IS
    'Section 2.3: Updates updated_at timestamp before any UPDATE on receiver_profiles table.';

-- ============================================================================
-- 8. CONNECTIONS_UPDATED_AT TRIGGER
-- Requirement: BEFORE UPDATE ON connections executing update_updated_at()
-- Status: Already exists using update_updated_at_column()
-- ============================================================================

-- Recreate trigger to use the spec-compliant function name
DROP TRIGGER IF EXISTS connections_updated_at ON connections;
CREATE TRIGGER connections_updated_at
    BEFORE UPDATE ON connections
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

COMMENT ON TRIGGER connections_updated_at ON connections IS
    'Section 2.3: Updates updated_at timestamp before any UPDATE on connections table.';

-- ============================================================================
-- VERIFICATION QUERIES (for manual testing)
-- ============================================================================

-- These comments document how to verify the migration worked:
--
-- 1. Verify generate_unique_code() works:
--    SELECT generate_unique_code();
--    -- Should return a 6-digit string like '123456'
--
-- 2. Verify create_receiver_code() works (requires a valid user_id):
--    SELECT create_receiver_code('your-user-uuid-here');
--    -- Should return a 6-digit code
--
-- 3. Verify check_subscription_status() works (requires a valid user_id):
--    SELECT check_subscription_status('your-user-uuid-here');
--    -- Should return 'trial', 'active', 'past_due', 'canceled', 'expired', or NULL
--
-- 4. Verify triggers exist:
--    SELECT trigger_name, event_object_table, action_statement
--    FROM information_schema.triggers
--    WHERE trigger_name IN (
--        'users_updated_at',
--        'sender_profiles_updated_at',
--        'receiver_profiles_updated_at',
--        'connections_updated_at'
--    );
--    -- Should return 4 rows, all with EXECUTE FUNCTION update_updated_at()
--
-- 5. Verify function signatures:
--    SELECT routine_name, data_type
--    FROM information_schema.routines
--    WHERE routine_name IN (
--        'generate_unique_code',
--        'create_receiver_code',
--        'check_subscription_status',
--        'update_updated_at'
--    ) AND routine_schema = 'public';
--    -- Should return functions with expected return types

-- ============================================================================
-- SECTION 2.3 COMPLETE
-- ============================================================================
-- All requirements from plan.md Section 2.3 have been implemented:
-- ✅ generate_unique_code() - Returns TEXT, generates 6-digit code, loops until unique
-- ✅ create_receiver_code(UUID) - Calls generate_unique_code(), inserts, returns code
-- ✅ check_subscription_status(UUID) - Checks dates, updates if expired, returns TEXT
-- ✅ update_updated_at() - TRIGGER function setting NEW.updated_at = now()
-- ✅ users_updated_at - BEFORE UPDATE ON users
-- ✅ sender_profiles_updated_at - BEFORE UPDATE ON sender_profiles
-- ✅ receiver_profiles_updated_at - BEFORE UPDATE ON receiver_profiles
-- ✅ connections_updated_at - BEFORE UPDATE ON connections
-- ============================================================================
