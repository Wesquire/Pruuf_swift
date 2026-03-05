-- Migration: Add missing columns to users table
-- These columns exist in the Swift model but were never added to the database

-- Approach 1: Add the missing columns
ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS device_transfer_code TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS onboarding_step TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url TEXT;

-- Approach 2: Recreate RPC with resilient column handling
-- Uses display_name now that column exists, plus updates display_name on re-auth
CREATE OR REPLACE FUNCTION find_or_create_user(
    p_auth_id UUID,
    p_phone TEXT,
    p_display_name TEXT DEFAULT NULL,
    p_timezone TEXT DEFAULT 'UTC'
) RETURNS SETOF users AS $func$
DECLARE
    v_user users%ROWTYPE;
    v_now TIMESTAMPTZ := NOW();
BEGIN
    -- 1. Try to find by auth ID (exact match)
    SELECT * INTO v_user FROM users WHERE id = p_auth_id;
    IF FOUND THEN
        -- Update display_name if provided and currently null
        IF p_display_name IS NOT NULL AND v_user.display_name IS NULL THEN
            UPDATE users SET display_name = p_display_name, updated_at = v_now
            WHERE id = p_auth_id
            RETURNING * INTO v_user;
        END IF;
        RETURN NEXT v_user;
        RETURN;
    END IF;

    -- 2. Try to find by phone number (handles re-auth with new anonymous session)
    IF p_phone IS NOT NULL AND p_phone != '' THEN
        SELECT * INTO v_user FROM users WHERE phone_number = p_phone;
        IF FOUND THEN
            -- Reassociate: update all foreign key references to the new auth ID
            UPDATE sender_profiles SET user_id = p_auth_id WHERE user_id = v_user.id;
            UPDATE receiver_profiles SET user_id = p_auth_id WHERE user_id = v_user.id;
            UPDATE connections SET sender_id = p_auth_id WHERE sender_id = v_user.id;
            UPDATE connections SET receiver_id = p_auth_id WHERE receiver_id = v_user.id;
            UPDATE unique_codes SET owner_id = p_auth_id WHERE owner_id = v_user.id;
            UPDATE device_tokens SET user_id = p_auth_id WHERE user_id = v_user.id;

            -- Now update the user record itself
            UPDATE users
            SET id = p_auth_id,
                display_name = COALESCE(p_display_name, display_name),
                updated_at = v_now
            WHERE phone_number = p_phone
            RETURNING * INTO v_user;

            RETURN NEXT v_user;
            RETURN;
        END IF;
    END IF;

    -- 3. No existing user found — create a new one
    IF p_phone IS NULL OR p_phone = '' THEN
        RAISE EXCEPTION 'Phone number required to create a new user';
    END IF;

    INSERT INTO users (
        id, phone_number, phone_country_code, display_name,
        timezone, is_active, has_completed_onboarding,
        notification_preferences, created_at, updated_at
    ) VALUES (
        p_auth_id, p_phone, '+1', p_display_name,
        COALESCE(p_timezone, 'UTC'), true, false,
        '{"push_enabled": true, "sound_enabled": true, "vibration_enabled": true}'::jsonb,
        v_now, v_now
    )
    RETURNING * INTO v_user;

    RETURN NEXT v_user;
    RETURN;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION find_or_create_user(UUID, TEXT, TEXT, TEXT) TO authenticated;
