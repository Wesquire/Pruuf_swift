-- Migration: 025_ping_time_changed_notification.sql
-- Purpose: Add ping_time_changed notification type to notify receivers when sender changes ping time
-- Phase 10 Section 10.4: User Stories Settings (US-10.1)
-- Created: 2026-01-19

-- ============================================================================
-- 1. ADD PING_TIME_CHANGED TYPE TO NOTIFICATIONS TABLE
-- ============================================================================

-- Drop the existing constraint
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- Add the new constraint with ping_time_changed type
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
    CHECK (type IN (
        'ping_reminder',
        'deadline_warning',
        'deadline_final',
        'missed_ping',
        'ping_completed_ontime',
        'ping_completed_late',
        'break_started',
        'break_notification',
        'connection_request',
        'payment_reminder',
        'trial_ending',
        'data_export_ready',
        'data_export_email_sent',
        'ping_time_changed'
    ));

-- ============================================================================
-- 2. FUNCTION TO NOTIFY RECEIVERS OF PING TIME CHANGE (US-10.1)
-- ============================================================================

-- Function to send notifications to all connected receivers when a sender changes their ping time
CREATE OR REPLACE FUNCTION notify_receivers_ping_time_changed(
    p_sender_id UUID,
    p_old_time TIME,
    p_new_time TIME
)
RETURNS INTEGER AS $$
DECLARE
    v_sender_name TEXT;
    v_receiver_id UUID;
    v_notification_count INTEGER := 0;
    v_new_time_display TEXT;
BEGIN
    -- Get sender's name (using phone number as fallback)
    SELECT COALESCE(
        (SELECT phone_number FROM users WHERE id = p_sender_id),
        'A sender'
    ) INTO v_sender_name;

    -- Format the new time for display
    v_new_time_display := to_char(p_new_time, 'HH12:MI AM');

    -- Notify all active receivers
    FOR v_receiver_id IN
        SELECT receiver_id
        FROM connections
        WHERE sender_id = p_sender_id
          AND status = 'active'
    LOOP
        -- Insert notification for this receiver
        INSERT INTO notifications (
            user_id,
            type,
            title,
            body,
            metadata,
            delivery_status
        ) VALUES (
            v_receiver_id,
            'ping_time_changed',
            'Ping Time Updated',
            v_sender_name || ' changed their daily check-in time to ' || v_new_time_display,
            jsonb_build_object(
                'sender_id', p_sender_id::TEXT,
                'old_time', p_old_time::TEXT,
                'new_time', p_new_time::TEXT
            ),
            'pending'
        );

        v_notification_count := v_notification_count + 1;
    END LOOP;

    RETURN v_notification_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION notify_receivers_ping_time_changed(UUID, TIME, TIME) TO authenticated;

-- ============================================================================
-- 3. TRIGGER TO AUTO-NOTIFY RECEIVERS ON PING TIME UPDATE
-- ============================================================================

-- Create trigger function to auto-notify receivers when ping_time changes
CREATE OR REPLACE FUNCTION on_sender_ping_time_changed()
RETURNS TRIGGER AS $$
BEGIN
    -- Only fire if ping_time actually changed
    IF OLD.ping_time IS DISTINCT FROM NEW.ping_time THEN
        PERFORM notify_receivers_ping_time_changed(
            NEW.user_id,
            OLD.ping_time,
            NEW.ping_time
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger on sender_profiles table
DROP TRIGGER IF EXISTS trg_notify_ping_time_change ON sender_profiles;
CREATE TRIGGER trg_notify_ping_time_change
    AFTER UPDATE OF ping_time ON sender_profiles
    FOR EACH ROW
    EXECUTE FUNCTION on_sender_ping_time_changed();

-- ============================================================================
-- COMMENTS FOR DOCUMENTATION
-- ============================================================================

COMMENT ON CONSTRAINT notifications_type_check ON notifications IS
    'Allowed notification types including ping_time_changed for US-10.1 receiver notifications';

COMMENT ON FUNCTION notify_receivers_ping_time_changed(UUID, TIME, TIME) IS
    'Notifies all connected receivers when a sender changes their daily ping time (US-10.1)';

COMMENT ON TRIGGER trg_notify_ping_time_change ON sender_profiles IS
    'Automatically notifies receivers when sender updates their ping time (US-10.1)';
