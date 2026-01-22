-- Migration: 20260119000006_device_tokens.sql
-- Description: Device tokens table for APNs push notifications
-- Phase 8 Section 8.1: Push Notification Setup
-- Created: 2026-01-19

-- ============================================================================
-- 1. DEVICE_TOKENS TABLE
-- Stores APNs device tokens for push notifications
-- Supports multiple devices per user
-- ============================================================================

CREATE TABLE IF NOT EXISTS device_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_token TEXT NOT NULL,
    platform TEXT NOT NULL CHECK (platform IN ('ios', 'ios_sandbox')),
    device_name TEXT, -- e.g., "iPhone 14 Pro"
    app_version TEXT, -- App version when token was registered
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    last_used_at TIMESTAMPTZ DEFAULT now(),
    is_active BOOLEAN DEFAULT true,
    -- Unique constraint: one token per device per user
    UNIQUE(user_id, device_token)
);

-- Indexes for device_tokens table
CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_device_tokens_token ON device_tokens(device_token);
CREATE INDEX IF NOT EXISTS idx_device_tokens_active ON device_tokens(is_active) WHERE is_active = true;

-- Enable RLS on device_tokens
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 2. RLS POLICIES FOR DEVICE_TOKENS
-- ============================================================================

-- Users can view their own device tokens
DROP POLICY IF EXISTS "Users can view own device tokens" ON device_tokens;
CREATE POLICY "Users can view own device tokens" ON device_tokens
    FOR SELECT
    USING (user_id = auth.uid());

-- Users can insert their own device tokens
DROP POLICY IF EXISTS "Users can insert own device tokens" ON device_tokens;
CREATE POLICY "Users can insert own device tokens" ON device_tokens
    FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- Users can update their own device tokens
DROP POLICY IF EXISTS "Users can update own device tokens" ON device_tokens;
CREATE POLICY "Users can update own device tokens" ON device_tokens
    FOR UPDATE
    USING (user_id = auth.uid());

-- Users can delete their own device tokens
DROP POLICY IF EXISTS "Users can delete own device tokens" ON device_tokens;
CREATE POLICY "Users can delete own device tokens" ON device_tokens
    FOR DELETE
    USING (user_id = auth.uid());

-- Service role can manage all device tokens (for cleanup, etc.)
DROP POLICY IF EXISTS "Service role can manage all device tokens" ON device_tokens;
CREATE POLICY "Service role can manage all device tokens" ON device_tokens
    FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role');

-- ============================================================================
-- 3. TRIGGER FOR updated_at
-- ============================================================================

DROP TRIGGER IF EXISTS device_tokens_updated_at ON device_tokens;
CREATE TRIGGER device_tokens_updated_at
    BEFORE UPDATE ON device_tokens
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- 4. FUNCTIONS FOR DEVICE TOKEN MANAGEMENT
-- ============================================================================

-- Register or update a device token
-- Called when device registers for notifications
CREATE OR REPLACE FUNCTION register_device_token(
    p_user_id UUID,
    p_device_token TEXT,
    p_platform TEXT DEFAULT 'ios',
    p_device_name TEXT DEFAULT NULL,
    p_app_version TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_token_id UUID;
BEGIN
    -- Upsert the device token
    INSERT INTO device_tokens (user_id, device_token, platform, device_name, app_version)
    VALUES (p_user_id, p_device_token, p_platform, p_device_name, p_app_version)
    ON CONFLICT (user_id, device_token) DO UPDATE SET
        platform = EXCLUDED.platform,
        device_name = COALESCE(EXCLUDED.device_name, device_tokens.device_name),
        app_version = COALESCE(EXCLUDED.app_version, device_tokens.app_version),
        updated_at = now(),
        last_used_at = now(),
        is_active = true
    RETURNING id INTO v_token_id;

    -- Also update the legacy device_token column in users table for backwards compatibility
    UPDATE users SET device_token = p_device_token WHERE id = p_user_id;

    RETURN v_token_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Mark a device token as invalid (on delivery failure)
-- Called when APNs returns an error for the token
CREATE OR REPLACE FUNCTION invalidate_device_token(
    p_device_token TEXT,
    p_reason TEXT DEFAULT 'delivery_failure'
)
RETURNS VOID AS $$
BEGIN
    UPDATE device_tokens
    SET is_active = false,
        updated_at = now()
    WHERE device_token = p_device_token;

    -- Log the invalidation for debugging
    INSERT INTO audit_logs (action, resource_type, details)
    VALUES (
        'device_token_invalidated',
        'device_token',
        jsonb_build_object(
            'device_token_prefix', LEFT(p_device_token, 8) || '...',
            'reason', p_reason,
            'timestamp', now()
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Remove old/inactive device tokens
-- Called periodically to clean up stale tokens
CREATE OR REPLACE FUNCTION cleanup_stale_device_tokens(
    p_days_inactive INT DEFAULT 90
)
RETURNS INT AS $$
DECLARE
    v_deleted_count INT;
BEGIN
    WITH deleted AS (
        DELETE FROM device_tokens
        WHERE is_active = false
           OR last_used_at < now() - (p_days_inactive || ' days')::INTERVAL
        RETURNING id
    )
    SELECT COUNT(*) INTO v_deleted_count FROM deleted;

    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get all active device tokens for a user
CREATE OR REPLACE FUNCTION get_user_device_tokens(p_user_id UUID)
RETURNS TABLE (
    device_token TEXT,
    platform TEXT,
    device_name TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT dt.device_token, dt.platform, dt.device_name
    FROM device_tokens dt
    WHERE dt.user_id = p_user_id
      AND dt.is_active = true
    ORDER BY dt.last_used_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Get all device tokens for multiple users (for batch notifications)
CREATE OR REPLACE FUNCTION get_device_tokens_for_users(p_user_ids UUID[])
RETURNS TABLE (
    user_id UUID,
    device_token TEXT,
    platform TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT dt.user_id, dt.device_token, dt.platform
    FROM device_tokens dt
    WHERE dt.user_id = ANY(p_user_ids)
      AND dt.is_active = true
    ORDER BY dt.user_id, dt.last_used_at DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 5. SCHEDULED JOB FOR TOKEN CLEANUP
-- ============================================================================

-- Add scheduled job to clean up stale device tokens (weekly)
SELECT cron.schedule(
    'cleanup-stale-device-tokens',
    '0 4 * * 0', -- Every Sunday at 4 AM UTC
    $$SELECT cleanup_stale_device_tokens(90)$$
);

-- ============================================================================
-- 6. GRANT PERMISSIONS
-- ============================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON device_tokens TO authenticated;
GRANT ALL ON device_tokens TO service_role;

-- Grant execute on functions
GRANT EXECUTE ON FUNCTION register_device_token TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_device_tokens TO authenticated;
GRANT EXECUTE ON FUNCTION invalidate_device_token TO service_role;
GRANT EXECUTE ON FUNCTION cleanup_stale_device_tokens TO service_role;
GRANT EXECUTE ON FUNCTION get_device_tokens_for_users TO service_role;

-- ============================================================================
-- 7. COMMENTS FOR DOCUMENTATION
-- ============================================================================

COMMENT ON TABLE device_tokens IS 'Stores APNs device tokens for push notifications, supports multiple devices per user';
COMMENT ON COLUMN device_tokens.device_token IS 'The APNs device token as a hex string';
COMMENT ON COLUMN device_tokens.platform IS 'ios for production, ios_sandbox for development';
COMMENT ON COLUMN device_tokens.is_active IS 'Set to false when token is invalid (e.g., app uninstalled)';
COMMENT ON COLUMN device_tokens.last_used_at IS 'Last time this token was used successfully';

COMMENT ON FUNCTION register_device_token IS 'Register or update a device token when app launches';
COMMENT ON FUNCTION invalidate_device_token IS 'Mark a token as invalid after APNs delivery failure';
COMMENT ON FUNCTION cleanup_stale_device_tokens IS 'Remove inactive tokens older than specified days';
COMMENT ON FUNCTION get_device_tokens_for_users IS 'Fetch active device tokens for multiple users';
