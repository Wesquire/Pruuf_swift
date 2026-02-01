-- Migration: 20260131000002_break_notifications_and_auto_resume.sql
-- Purpose: Add break notifications and auto-resume notifications for Request 8
-- - Notify receivers when sender schedules/starts/ends/completes a break (Pruuf Pause)
-- - Notify sender when their break naturally completes (auto-resume)
-- Created: 2026-01-31

-- ============================================================================
-- 1. ADD BREAK_NOTIFICATION TYPE TO NOTIFICATIONS TABLE
-- ============================================================================

-- Drop the existing constraint if it exists
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- Add the new constraint with break_notification type
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
    CHECK (type IN (
        'ping_reminder',
        'deadline_warning',
        'missed_ping',
        'connection_request',
        'payment_reminder',
        'trial_ending',
        'break_notification',
        'break_resumed'  -- New type for auto-resume notifications
    ));

-- ============================================================================
-- 2. FUNCTION: Send Break Notification to Receivers
-- Notifies all receivers when a sender schedules/starts/ends/completes a break
-- Uses "Pruuf Pause" terminology per Request 7
-- ============================================================================

CREATE OR REPLACE FUNCTION public.send_break_notification(
    p_sender_id UUID,
    p_break_id UUID,
    p_notification_type TEXT,  -- 'scheduled', 'started', 'ended', 'completed'
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
    v_notification_title TEXT;
    v_notification_body TEXT;
BEGIN
    -- Get sender's display name
    SELECT COALESCE(display_name, 'Your sender') INTO v_sender_name
    FROM users
    WHERE id = p_sender_id;

    -- Build notification title and body based on type
    -- Using "Pruuf Pause" terminology per Request 7
    CASE p_notification_type
        WHEN 'scheduled' THEN
            v_notification_title := 'Pruuf Pause Scheduled';
            v_notification_body := v_sender_name || ' will be on Pruuf Pause from ' ||
                TO_CHAR(p_start_date, 'Mon DD') || ' to ' || TO_CHAR(p_end_date, 'Mon DD');
        WHEN 'started' THEN
            v_notification_title := 'Pruuf Pause Started';
            v_notification_body := v_sender_name || ' is on Pruuf Pause until ' || TO_CHAR(p_end_date, 'Mon DD');
        WHEN 'ended' THEN
            v_notification_title := 'Pruuf Pause Ended Early';
            v_notification_body := v_sender_name || ' ended their Pruuf Pause early';
        WHEN 'completed' THEN
            v_notification_title := 'Pruuf Pings Resumed';
            v_notification_body := v_sender_name || '''s Pruuf Pause has ended. Their daily Pruuf Pings have resumed.';
        ELSE
            v_notification_title := 'Pruuf Pause Update';
            v_notification_body := v_sender_name || ' has a Pruuf Pause update';
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
            CASE WHEN p_notification_type = 'completed' THEN 'break_resumed' ELSE 'break_notification' END,
            v_notification_title,
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
-- 3. FUNCTION: Send Break Completed Notification to Sender
-- Notifies the sender when their break naturally completes (auto-resume)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.send_break_completed_notification_to_sender(
    p_sender_id UUID,
    p_break_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO notifications (user_id, type, title, body, metadata)
    VALUES (
        p_sender_id,
        'break_resumed',
        'Pruuf Pause Complete',
        'Your Pruuf Pause has ended. Your daily Pruuf Pings have automatically resumed.',
        jsonb_build_object(
            'break_id', p_break_id,
            'notification_type', 'auto_resumed'
        )
    );
END;
$$;

-- ============================================================================
-- 4. TRIGGER: Auto-notify receivers when break is created
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
-- 5. TRIGGER: Auto-notify when break status changes
-- Includes notification for natural completion (auto-resume)
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

        -- Notify when break is canceled (ended early by user)
        ELSIF NEW.status = 'canceled' THEN
            PERFORM send_break_notification(
                NEW.sender_id,
                NEW.id,
                'ended',
                NEW.start_date,
                NEW.end_date
            );

        -- NEW: Notify when break naturally completes (auto-resume)
        -- This happens when the cron job updates status from 'active' to 'completed'
        ELSIF NEW.status = 'completed' AND OLD.status = 'active' THEN
            -- Notify all receivers that Pruuf Pings have resumed
            PERFORM send_break_notification(
                NEW.sender_id,
                NEW.id,
                'completed',
                NEW.start_date,
                NEW.end_date
            );

            -- Notify the sender that their Pruuf Pings have automatically resumed
            PERFORM send_break_completed_notification_to_sender(
                NEW.sender_id,
                NEW.id
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
-- 6. HELPER FUNCTION: Get sender's current break info for receivers
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
-- 7. GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.send_break_notification(UUID, UUID, TEXT, DATE, DATE) TO service_role;
GRANT EXECUTE ON FUNCTION public.send_break_completed_notification_to_sender(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_sender_break_info(UUID) TO authenticated;

-- ============================================================================
-- 8. COMMENTS
-- ============================================================================

COMMENT ON FUNCTION public.send_break_notification IS 'Sends Pruuf Pause notifications to all receivers connected to a sender. Supports scheduled, started, ended, and completed events.';
COMMENT ON FUNCTION public.send_break_completed_notification_to_sender IS 'Sends auto-resume notification to sender when their Pruuf Pause naturally completes';
COMMENT ON FUNCTION public.on_break_created IS 'Trigger function to notify receivers when a Pruuf Pause is created';
COMMENT ON FUNCTION public.on_break_status_changed IS 'Trigger function to notify receivers and sender when a Pruuf Pause status changes, including auto-resume on completion';
COMMENT ON FUNCTION public.get_sender_break_info IS 'Returns current or upcoming Pruuf Pause info for a sender (for receiver dashboard display)';
