-- Migration: 022_account_management.sql
-- Phase 10 Section 10.2: Account Management
-- Features: Add Role, Change Ping Time, Delete Account (soft delete with 30-day retention)

-- =====================================================
-- Section 1: Add deleted_at column to users table if not exists
-- =====================================================

-- Add deleted_at column for tracking soft deletion date
ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Create index for cleanup job to find deleted users efficiently
CREATE INDEX IF NOT EXISTS idx_users_deleted_at ON users(deleted_at) WHERE deleted_at IS NOT NULL;

-- =====================================================
-- Section 2: Scheduled Hard Delete Job
-- Per Section 10.2: Schedule hard delete after 30 days via scheduled job
-- =====================================================

-- Function to hard delete users who have been soft deleted for 30+ days
CREATE OR REPLACE FUNCTION hard_delete_expired_users()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    retention_days INTEGER := 30;
    deleted_count INTEGER := 0;
    user_record RECORD;
BEGIN
    -- Find users marked as inactive more than 30 days ago
    FOR user_record IN
        SELECT id, phone_number
        FROM users
        WHERE is_active = false
          AND updated_at < (NOW() - (retention_days || ' days')::INTERVAL)
    LOOP
        -- Log the hard deletion in audit_logs before deletion
        INSERT INTO audit_logs (
            user_id,
            action,
            resource_type,
            resource_id,
            details,
            created_at
        ) VALUES (
            user_record.id,
            'user.hard_deleted',
            'user',
            user_record.id,
            jsonb_build_object(
                'reason', 'Automatic hard delete after 30-day retention period',
                'retention_days', retention_days,
                'original_phone_last_4', RIGHT(user_record.phone_number, 4)
            ),
            NOW()
        );

        -- Delete related data in correct order (respecting foreign keys)

        -- Delete pings
        DELETE FROM pings WHERE sender_id = user_record.id OR receiver_id = user_record.id;

        -- Delete breaks
        DELETE FROM breaks WHERE sender_id = user_record.id;

        -- Delete connections
        DELETE FROM connections WHERE sender_id = user_record.id OR receiver_id = user_record.id;

        -- Delete notifications
        DELETE FROM notifications WHERE user_id = user_record.id;

        -- Delete unique codes
        DELETE FROM unique_codes WHERE receiver_id = user_record.id;

        -- Delete payment transactions
        DELETE FROM payment_transactions WHERE user_id = user_record.id;

        -- Delete sender profile
        DELETE FROM sender_profiles WHERE user_id = user_record.id;

        -- Delete receiver profile
        DELETE FROM receiver_profiles WHERE user_id = user_record.id;

        -- Finally delete the user
        DELETE FROM users WHERE id = user_record.id;

        deleted_count := deleted_count + 1;
    END LOOP;

    -- Log summary
    IF deleted_count > 0 THEN
        RAISE NOTICE 'Hard deleted % user(s) after % day retention period', deleted_count, retention_days;
    END IF;
END;
$$;

-- Schedule the hard delete job to run daily at 2 AM UTC
-- This complements the existing cleanup job in 003_scheduled_jobs.sql
SELECT cron.schedule(
    'hard-delete-expired-users',
    '0 2 * * *',  -- Daily at 2 AM UTC
    'SELECT hard_delete_expired_users()'
);

-- =====================================================
-- Section 3: Soft Delete Account Function
-- Per Section 10.2: Comprehensive account deletion
-- =====================================================

-- Function to soft delete a user account with all required steps
CREATE OR REPLACE FUNCTION soft_delete_user_account(p_user_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_connections_deleted INTEGER := 0;
    v_subscription_canceled BOOLEAN := false;
    v_code_deactivated BOOLEAN := false;
    v_hard_delete_date TIMESTAMPTZ;
    v_result jsonb;
BEGIN
    -- Set hard delete date (30 days from now)
    v_hard_delete_date := NOW() + INTERVAL '30 days';

    -- 1. Soft delete user: set is_active = false
    UPDATE users
    SET is_active = false,
        updated_at = NOW()
    WHERE id = p_user_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'User not found'
        );
    END IF;

    -- 2. Set all connections status = 'deleted'
    UPDATE connections
    SET status = 'deleted',
        deleted_at = NOW(),
        updated_at = NOW()
    WHERE sender_id = p_user_id OR receiver_id = p_user_id;

    GET DIAGNOSTICS v_connections_deleted = ROW_COUNT;

    -- 3. Cancel subscription if receiver
    UPDATE receiver_profiles
    SET subscription_status = 'canceled',
        updated_at = NOW()
    WHERE user_id = p_user_id;

    v_subscription_canceled := FOUND;

    -- 4. Deactivate unique code
    UPDATE unique_codes
    SET is_active = false
    WHERE receiver_id = p_user_id;

    v_code_deactivated := FOUND;

    -- 5. Log audit event
    INSERT INTO audit_logs (
        user_id,
        action,
        resource_type,
        resource_id,
        details,
        created_at
    ) VALUES (
        p_user_id,
        'user.deleted',
        'user',
        p_user_id,
        jsonb_build_object(
            'deletion_type', 'soft_delete',
            'connections_deleted', v_connections_deleted,
            'subscription_canceled', v_subscription_canceled,
            'code_deactivated', v_code_deactivated,
            'hard_delete_scheduled', v_hard_delete_date,
            'retention_days', 30
        ),
        NOW()
    );

    -- Build result
    v_result := jsonb_build_object(
        'success', true,
        'soft_delete_date', NOW(),
        'hard_delete_scheduled', v_hard_delete_date,
        'connections_deleted', v_connections_deleted,
        'subscription_canceled', v_subscription_canceled,
        'retention_days', 30,
        'message', 'Account soft deleted. Data will be permanently removed after 30 days.'
    );

    RETURN v_result;
END;
$$;

-- =====================================================
-- Section 4: Ping Time Update Audit
-- Per Section 10.2: Track ping time changes
-- =====================================================

-- Trigger function to log ping time changes
CREATE OR REPLACE FUNCTION log_ping_time_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.ping_time IS DISTINCT FROM NEW.ping_time THEN
        INSERT INTO audit_logs (
            user_id,
            action,
            resource_type,
            resource_id,
            details,
            created_at
        ) VALUES (
            NEW.user_id,
            'ping_time.updated',
            'user',
            NEW.user_id,
            jsonb_build_object(
                'previous_time', OLD.ping_time,
                'new_time', NEW.ping_time,
                'effective_note', 'Takes effect tomorrow'
            ),
            NOW()
        );
    END IF;
    RETURN NEW;
END;
$$;

-- Create trigger for ping time changes
DROP TRIGGER IF EXISTS trg_log_ping_time_change ON sender_profiles;
CREATE TRIGGER trg_log_ping_time_change
    AFTER UPDATE OF ping_time ON sender_profiles
    FOR EACH ROW
    EXECUTE FUNCTION log_ping_time_change();

-- =====================================================
-- Section 5: Role Addition Audit
-- Per Section 10.2: Track role additions
-- =====================================================

-- Trigger function to log role changes
CREATE OR REPLACE FUNCTION log_role_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.primary_role IS DISTINCT FROM NEW.primary_role THEN
        INSERT INTO audit_logs (
            user_id,
            action,
            resource_type,
            resource_id,
            details,
            created_at
        ) VALUES (
            NEW.id,
            'user.role_changed',
            'user',
            NEW.id,
            jsonb_build_object(
                'previous_role', OLD.primary_role,
                'new_role', NEW.primary_role,
                'is_role_addition', NEW.primary_role = 'both'
            ),
            NOW()
        );
    END IF;
    RETURN NEW;
END;
$$;

-- Create trigger for role changes
DROP TRIGGER IF EXISTS trg_log_role_change ON users;
CREATE TRIGGER trg_log_role_change
    AFTER UPDATE OF primary_role ON users
    FOR EACH ROW
    EXECUTE FUNCTION log_role_change();

-- =====================================================
-- Section 6: Grant permissions
-- =====================================================

-- Grant execute permission on functions to authenticated users
GRANT EXECUTE ON FUNCTION soft_delete_user_account(UUID) TO authenticated;

-- Note: hard_delete_expired_users should only be called by cron job (SECURITY DEFINER)

-- =====================================================
-- Section 7: Comments for documentation
-- =====================================================

COMMENT ON FUNCTION soft_delete_user_account(UUID) IS
'Soft deletes a user account per Section 10.2 requirements:
- Sets users.is_active = false
- Sets all connections status to deleted
- Cancels subscription
- Deactivates unique code
- Logs audit event
- Data retained for 30 days before hard delete';

COMMENT ON FUNCTION hard_delete_expired_users() IS
'Hard deletes users who have been soft deleted for 30+ days.
Called daily by cron job at 2 AM UTC.
Per Section 10.2: Schedule hard delete after 30 days via scheduled job';

COMMENT ON FUNCTION log_ping_time_change() IS
'Trigger function to audit ping time changes.
Per Section 10.2: Track all ping time updates';

COMMENT ON FUNCTION log_role_change() IS
'Trigger function to audit role changes.
Per Section 10.2: Track when users add sender or receiver roles';
