-- Migration: 013_breaks_notifications.sql
-- Purpose: Add break_notification type to notifications table and related functions
-- Phase 7 Section 7.1: Scheduling Breaks
-- Created: 2026-01-17

-- ============================================================================
-- 1. ADD BREAK_NOTIFICATION TYPE TO NOTIFICATIONS TABLE
-- ============================================================================

-- Drop the existing constraint
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- Add the new constraint with break_notification type
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
    CHECK (type IN ('ping_reminder', 'deadline_warning', 'missed_ping', 'connection_request', 'payment_reminder', 'trial_ending', 'break_notification'));

-- ============================================================================
-- 2. FUNCTION: Send Break Notification to Receivers
-- Notifies all receivers when a sender schedules/starts/ends a break
-- ============================================================================

CREATE OR REPLACE FUNCTION public.send_break_notification(
    p_sender_id UUID,
    p_break_id UUID,
    p_notification_type TEXT,  -- 'scheduled', 'started', 'ended'
    p_start_date DATE,
    p_end_date DATE
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_connection RECORD;
    v_sender_name TEXT;
    v_notification_body TEXT;
BEGIN
    -- Get sender's display name
    SELECT COALESCE(display_name, 'Your sender') INTO v_sender_name
    FROM users
    WHERE id = p_sender_id;

    -- Build notification body based on type
    CASE p_notification_type
        WHEN 'scheduled' THEN
            v_notification_body := v_sender_name || ' will be on break from ' ||
                TO_CHAR(p_start_date, 'Mon DD') || ' to ' || TO_CHAR(p_end_date, 'Mon DD');
        WHEN 'started' THEN
            v_notification_body := v_sender_name || ' is on break until ' || TO_CHAR(p_end_date, 'Mon DD');
        WHEN 'ended' THEN
            v_notification_body := v_sender_name || ' ended their break early';
        ELSE
            v_notification_body := v_sender_name || ' has a break update';
    END CASE;

    -- Send notification to all connected receivers
    FOR v_connection IN
        SELECT receiver_id
        FROM connections
        WHERE sender_id = p_sender_id
        AND status = 'active'
    LOOP
        INSERT INTO notifications (user_id, type, title, body, metadata)
        VALUES (
            v_connection.receiver_id,
            'break_notification',
            'Break Update',
            v_notification_body,
            jsonb_build_object(
                'sender_id', p_sender_id,
                'break_id', p_break_id,
                'notification_type', p_notification_type
            )
        );
    END LOOP;
END;
$$;

-- ============================================================================
-- 3. TRIGGER: Auto-notify receivers when break is created
-- ============================================================================

CREATE OR REPLACE FUNCTION public.on_break_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM send_break_notification(
        NEW.sender_id,
        NEW.id,
        CASE WHEN NEW.status = 'active' THEN 'started' ELSE 'scheduled' END,
        NEW.start_date,
        NEW.end_date
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS break_created_trigger ON breaks;
CREATE TRIGGER break_created_trigger
    AFTER INSERT ON breaks
    FOR EACH ROW
    EXECUTE FUNCTION public.on_break_created();

-- ============================================================================
-- 4. TRIGGER: Auto-notify receivers when break status changes
-- ============================================================================

CREATE OR REPLACE FUNCTION public.on_break_status_changed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Only notify if status actually changed
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        -- Notify when break becomes active (started)
        IF NEW.status = 'active' AND OLD.status = 'scheduled' THEN
            PERFORM send_break_notification(
                NEW.sender_id,
                NEW.id,
                'started',
                NEW.start_date,
                NEW.end_date
            );
        -- Notify when break is canceled (ended early)
        ELSIF NEW.status = 'canceled' THEN
            PERFORM send_break_notification(
                NEW.sender_id,
                NEW.id,
                'ended',
                NEW.start_date,
                NEW.end_date
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS break_status_changed_trigger ON breaks;
CREATE TRIGGER break_status_changed_trigger
    AFTER UPDATE ON breaks
    FOR EACH ROW
    EXECUTE FUNCTION public.on_break_status_changed();

-- ============================================================================
-- 5. HELPER FUNCTION: Get sender's current break info for receivers
-- Returns break information for display in receiver dashboard
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_sender_break_info(p_sender_id UUID)
RETURNS TABLE (
    break_id UUID,
    start_date DATE,
    end_date DATE,
    status TEXT,
    notes TEXT
)
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        b.id,
        b.start_date,
        b.end_date,
        b.status,
        b.notes
    FROM breaks b
    WHERE b.sender_id = p_sender_id
    AND b.status IN ('scheduled', 'active')
    AND b.end_date >= CURRENT_DATE
    ORDER BY b.start_date ASC
    LIMIT 1;
END;
$$;

-- ============================================================================
-- 6. GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.send_break_notification(UUID, UUID, TEXT, DATE, DATE) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_sender_break_info(UUID) TO authenticated;

-- ============================================================================
-- 7. COMMENTS
-- ============================================================================

COMMENT ON FUNCTION public.send_break_notification IS 'Sends break notifications to all receivers connected to a sender';
COMMENT ON FUNCTION public.on_break_created IS 'Trigger function to notify receivers when a break is created';
COMMENT ON FUNCTION public.on_break_status_changed IS 'Trigger function to notify receivers when a break status changes';
COMMENT ON FUNCTION public.get_sender_break_info IS 'Returns current or upcoming break info for a sender';
