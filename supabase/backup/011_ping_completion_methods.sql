-- Migration: 011_ping_completion_methods.sql
-- Purpose: Add database functions for ping completion methods
-- Phase 6 Section 6.2: Ping Completion Methods
-- Created: 2026-01-17

-- ============================================================================
-- 1. FUNCTION: Complete Ping(s)
-- Completes one or more pending pings for a sender
-- Supports tap and in_person methods
-- ============================================================================

CREATE OR REPLACE FUNCTION public.complete_ping(
    p_sender_id UUID,
    p_method TEXT,
    p_ping_id UUID DEFAULT NULL,
    p_location JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_now TIMESTAMPTZ := NOW();
    v_today DATE := CURRENT_DATE;
    v_ping RECORD;
    v_completed_count INTEGER := 0;
    v_late_count INTEGER := 0;
    v_on_time_count INTEGER := 0;
    v_receiver_ids UUID[] := '{}';
    v_ping_ids UUID[] := '{}';
    v_result JSONB;
BEGIN
    -- Validate method
    IF p_method NOT IN ('tap', 'in_person') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', 'Invalid method. Must be tap or in_person.'
        );
    END IF;

    -- Validate location for in_person method
    IF p_method = 'in_person' AND p_location IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', 'Location is required for in_person verification.'
        );
    END IF;

    -- Get pending pings for today
    FOR v_ping IN
        SELECT id, receiver_id, deadline_time
        FROM pings
        WHERE sender_id = p_sender_id
        AND status = 'pending'
        AND DATE(scheduled_time) = v_today
        AND (p_ping_id IS NULL OR id = p_ping_id)
    LOOP
        -- Update the ping
        UPDATE pings
        SET
            completed_at = v_now,
            completion_method = p_method,
            status = 'completed',
            verification_location = CASE WHEN p_method = 'in_person' THEN p_location ELSE NULL END
        WHERE id = v_ping.id;

        -- Count on-time vs late
        IF v_now > v_ping.deadline_time THEN
            v_late_count := v_late_count + 1;
        ELSE
            v_on_time_count := v_on_time_count + 1;
        END IF;

        v_completed_count := v_completed_count + 1;
        v_ping_ids := array_append(v_ping_ids, v_ping.id);

        -- Track receivers to notify
        IF NOT v_ping.receiver_id = ANY(v_receiver_ids) THEN
            v_receiver_ids := array_append(v_receiver_ids, v_ping.receiver_id);
        END IF;
    END LOOP;

    -- Build result
    v_result := jsonb_build_object(
        'success', TRUE,
        'completed_count', v_completed_count,
        'on_time_count', v_on_time_count,
        'late_count', v_late_count,
        'method', p_method,
        'completed_at', v_now,
        'has_location', p_location IS NOT NULL,
        'receiver_ids', to_jsonb(v_receiver_ids),
        'ping_ids', to_jsonb(v_ping_ids)
    );

    -- Log audit event
    INSERT INTO audit_logs (user_id, action, resource_type, details)
    VALUES (p_sender_id, 'complete_ping', 'ping', v_result);

    RETURN v_result;
END;
$$;

-- ============================================================================
-- 2. FUNCTION: Check if ping is late
-- Returns true if the ping's deadline has passed
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_ping_late(p_ping_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_deadline TIMESTAMPTZ;
BEGIN
    SELECT deadline_time INTO v_deadline
    FROM pings
    WHERE id = p_ping_id;

    IF v_deadline IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN NOW() > v_deadline;
END;
$$;

-- ============================================================================
-- 3. FUNCTION: Get pending pings for sender
-- Returns all pending pings for today that need to be completed
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_pending_pings(p_sender_id UUID)
RETURNS TABLE (
    ping_id UUID,
    connection_id UUID,
    receiver_id UUID,
    scheduled_time TIMESTAMPTZ,
    deadline_time TIMESTAMPTZ,
    is_late BOOLEAN,
    time_remaining INTERVAL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id AS ping_id,
        p.connection_id,
        p.receiver_id,
        p.scheduled_time,
        p.deadline_time,
        NOW() > p.deadline_time AS is_late,
        CASE
            WHEN NOW() > p.deadline_time THEN INTERVAL '0'
            ELSE p.deadline_time - NOW()
        END AS time_remaining
    FROM pings p
    WHERE p.sender_id = p_sender_id
    AND p.status = 'pending'
    AND DATE(p.scheduled_time) = CURRENT_DATE
    ORDER BY p.deadline_time ASC;
END;
$$;

-- ============================================================================
-- 4. FUNCTION: Get ping completion status
-- Returns detailed status of today's ping(s) for a sender
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_ping_status_today(p_sender_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pending_count INTEGER;
    v_completed_count INTEGER;
    v_missed_count INTEGER;
    v_on_break_count INTEGER;
    v_total_count INTEGER;
    v_earliest_deadline TIMESTAMPTZ;
    v_has_pending BOOLEAN;
    v_is_late BOOLEAN := FALSE;
    v_result JSONB;
BEGIN
    -- Get counts for today
    SELECT
        COUNT(*) FILTER (WHERE status = 'pending'),
        COUNT(*) FILTER (WHERE status = 'completed'),
        COUNT(*) FILTER (WHERE status = 'missed'),
        COUNT(*) FILTER (WHERE status = 'on_break'),
        COUNT(*)
    INTO v_pending_count, v_completed_count, v_missed_count, v_on_break_count, v_total_count
    FROM pings
    WHERE sender_id = p_sender_id
    AND DATE(scheduled_time) = CURRENT_DATE;

    -- Check if there are pending pings
    v_has_pending := v_pending_count > 0;

    -- Get earliest deadline for pending pings
    IF v_has_pending THEN
        SELECT MIN(deadline_time) INTO v_earliest_deadline
        FROM pings
        WHERE sender_id = p_sender_id
        AND status = 'pending'
        AND DATE(scheduled_time) = CURRENT_DATE;

        v_is_late := NOW() > v_earliest_deadline;
    END IF;

    -- Build result
    v_result := jsonb_build_object(
        'has_pending_pings', v_has_pending,
        'is_late', v_is_late,
        'pending_count', v_pending_count,
        'completed_count', v_completed_count,
        'missed_count', v_missed_count,
        'on_break_count', v_on_break_count,
        'total_count', v_total_count,
        'earliest_deadline', v_earliest_deadline,
        'checked_at', NOW()
    );

    RETURN v_result;
END;
$$;

-- ============================================================================
-- 5. FUNCTION: Calculate current streak for sender
-- Counts consecutive days of completed pings (breaks don't break streak)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.calculate_streak(p_sender_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_streak INTEGER := 0;
    v_current_date DATE := CURRENT_DATE;
    v_ping_status TEXT;
BEGIN
    -- Start from yesterday (today might not be complete yet)
    v_current_date := CURRENT_DATE - INTERVAL '1 day';

    LOOP
        -- Get the status of pings for this date
        -- If any ping is completed or on_break, day counts toward streak
        -- If any ping is missed, streak breaks
        -- If no pings exist, we've gone past the start of pinging
        SELECT status INTO v_ping_status
        FROM pings
        WHERE sender_id = p_sender_id
        AND DATE(scheduled_time) = v_current_date
        ORDER BY
            CASE status
                WHEN 'missed' THEN 1
                WHEN 'completed' THEN 2
                WHEN 'on_break' THEN 3
                ELSE 4
            END
        LIMIT 1;

        -- No pings for this date - we've reached the start
        IF v_ping_status IS NULL THEN
            EXIT;
        END IF;

        -- Missed ping breaks the streak
        IF v_ping_status = 'missed' THEN
            EXIT;
        END IF;

        -- Completed or on_break counts toward streak
        IF v_ping_status IN ('completed', 'on_break') THEN
            v_streak := v_streak + 1;
        END IF;

        -- Move to previous day
        v_current_date := v_current_date - INTERVAL '1 day';

        -- Safety limit - don't go back more than 1000 days
        IF v_streak > 1000 THEN
            EXIT;
        END IF;
    END LOOP;

    RETURN v_streak;
END;
$$;

-- ============================================================================
-- 6. FUNCTION: Notify receivers of ping completion
-- Creates notification records for all receivers of a completed ping
-- ============================================================================

CREATE OR REPLACE FUNCTION public.notify_ping_completion(
    p_sender_id UUID,
    p_method TEXT,
    p_is_late BOOLEAN DEFAULT FALSE
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sender_name TEXT;
    v_receiver_id UUID;
    v_title TEXT;
    v_body TEXT;
    v_notification_count INTEGER := 0;
BEGIN
    -- Get sender's display name (phone number for now)
    SELECT phone_number INTO v_sender_name
    FROM users
    WHERE id = p_sender_id;

    v_sender_name := COALESCE(v_sender_name, 'Your connection');

    -- Build notification message based on method and lateness
    IF p_is_late THEN
        v_title := 'Late Check-In';
        v_body := v_sender_name || ' pinged late at ' || to_char(NOW(), 'HH12:MI AM');
    ELSIF p_method = 'in_person' THEN
        v_title := 'In-Person Verification';
        v_body := v_sender_name || ' verified in person - all is well!';
    ELSE
        v_title := 'Ping Received';
        v_body := v_sender_name || ' is okay!';
    END IF;

    -- Create notifications for all active connections where this user is sender
    FOR v_receiver_id IN
        SELECT DISTINCT receiver_id
        FROM connections
        WHERE sender_id = p_sender_id
        AND status = 'active'
    LOOP
        INSERT INTO notifications (user_id, type, title, body, metadata)
        VALUES (
            v_receiver_id,
            'ping_completed',
            v_title,
            v_body,
            jsonb_build_object(
                'sender_id', p_sender_id,
                'method', p_method,
                'is_late', p_is_late,
                'timestamp', NOW()
            )
        );

        v_notification_count := v_notification_count + 1;
    END LOOP;

    RETURN v_notification_count;
END;
$$;

-- ============================================================================
-- 7. Add 'ping_completed' and 'ping_late' to notifications type enum if not exists
-- ============================================================================

-- First, check and update the constraint to include new types
DO $$
BEGIN
    -- Drop existing constraint
    ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

    -- Add updated constraint with new types
    ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
    CHECK (type IN (
        'ping_reminder',
        'deadline_warning',
        'missed_ping',
        'connection_request',
        'payment_reminder',
        'trial_ending',
        'ping_completed',
        'ping_late'
    ));
END $$;

-- ============================================================================
-- 8. GRANT PERMISSIONS
-- ============================================================================

-- Grant execute on functions to authenticated users
GRANT EXECUTE ON FUNCTION public.complete_ping(UUID, TEXT, UUID, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_ping_late(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pending_pings(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_ping_status_today(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_streak(UUID) TO authenticated;

-- Service role for system notifications
GRANT EXECUTE ON FUNCTION public.notify_ping_completion(UUID, TEXT, BOOLEAN) TO service_role;

-- ============================================================================
-- 9. COMMENTS
-- ============================================================================

COMMENT ON FUNCTION public.complete_ping IS 'Completes pending pings for a sender. Supports tap and in_person methods. Returns completion stats.';
COMMENT ON FUNCTION public.is_ping_late IS 'Returns true if the specified ping''s deadline has passed.';
COMMENT ON FUNCTION public.get_pending_pings IS 'Returns all pending pings for today for a sender, including deadline and late status.';
COMMENT ON FUNCTION public.get_ping_status_today IS 'Returns comprehensive status of today''s pings for a sender.';
COMMENT ON FUNCTION public.calculate_streak IS 'Calculates consecutive days of completed pings. Breaks (on_break status) do not break the streak.';
COMMENT ON FUNCTION public.notify_ping_completion IS 'Creates notification records for all receivers when a sender completes their ping.';
