-- Migration: 009_database_functions.sql
-- Description: Complete database functions for PRUUF iOS app
-- Phase 2 Section 2.3: Database Functions
-- Created: 2026-01-17

-- ============================================================================
-- 1. CREATE_RECEIVER_CODE FUNCTION
-- Creates a unique 6-digit code for a receiver and stores it in unique_codes
-- ============================================================================

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

    -- Generate a new unique code
    v_code := generate_unique_code();

    -- Deactivate any old codes for this user (shouldn't exist due to UNIQUE constraint, but safety first)
    UPDATE unique_codes
    SET is_active = false
    WHERE receiver_id = p_user_id AND is_active = true;

    -- Insert the new code
    INSERT INTO unique_codes (code, receiver_id, is_active)
    VALUES (v_code, p_user_id, true)
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

-- ============================================================================
-- 2. CHECK_SUBSCRIPTION_STATUS FUNCTION (TEXT return version)
-- Matches the exact signature from plan.md Section 2.3
-- Returns TEXT instead of subscription_status enum for flexibility
-- ============================================================================

CREATE OR REPLACE FUNCTION check_subscription_status(p_user_id UUID)
RETURNS TEXT AS $$
DECLARE
    v_status TEXT;
    v_trial_end TIMESTAMPTZ;
    v_sub_end TIMESTAMPTZ;
BEGIN
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

    RETURN v_status;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION check_subscription_status(UUID) TO authenticated;

-- ============================================================================
-- 3. GET_TODAY_PING_STATUS FUNCTION
-- Helper function to get the status of today's ping for a sender
-- ============================================================================

CREATE OR REPLACE FUNCTION get_today_ping_status(p_sender_id UUID)
RETURNS TABLE (
    ping_id UUID,
    status TEXT,
    scheduled_time TIMESTAMPTZ,
    deadline_time TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    is_on_break BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id as ping_id,
        p.status::TEXT,
        p.scheduled_time,
        p.deadline_time,
        p.completed_at,
        is_user_on_break(p_sender_id) as is_on_break
    FROM pings p
    WHERE p.sender_id = p_sender_id
    AND DATE(p.scheduled_time AT TIME ZONE 'UTC') = CURRENT_DATE
    ORDER BY p.scheduled_time DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_today_ping_status(UUID) TO authenticated;

-- ============================================================================
-- 4. COMPLETE_PING FUNCTION
-- Marks a ping as completed with the specified method
-- ============================================================================

CREATE OR REPLACE FUNCTION complete_ping(
    p_ping_id UUID,
    p_completion_method TEXT DEFAULT 'tap',
    p_verification_location JSONB DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_ping_sender_id UUID;
    v_current_status TEXT;
BEGIN
    -- Get ping details and verify ownership
    SELECT sender_id, status
    INTO v_ping_sender_id, v_current_status
    FROM pings
    WHERE id = p_ping_id;

    -- Check if ping exists
    IF v_ping_sender_id IS NULL THEN
        RAISE EXCEPTION 'Ping not found';
    END IF;

    -- Verify the user owns this ping
    IF v_ping_sender_id != auth.uid() THEN
        RAISE EXCEPTION 'Unauthorized: cannot complete another user''s ping';
    END IF;

    -- Check if already completed
    IF v_current_status = 'completed' THEN
        RETURN TRUE; -- Already completed, return success
    END IF;

    -- Update the ping
    UPDATE pings
    SET
        status = 'completed',
        completed_at = now(),
        completion_method = p_completion_method,
        verification_location = p_verification_location,
        notes = p_notes
    WHERE id = p_ping_id;

    -- Log the audit event
    PERFORM log_audit_event(
        auth.uid(),
        'ping_completed',
        'ping',
        p_ping_id,
        jsonb_build_object(
            'completion_method', p_completion_method,
            'completed_at', now()
        )
    );

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION complete_ping(UUID, TEXT, JSONB, TEXT) TO authenticated;

-- ============================================================================
-- 5. CREATE_DAILY_PINGS FUNCTION
-- Creates daily pings for all active senders not on break
-- Called by scheduled job
-- ============================================================================

CREATE OR REPLACE FUNCTION create_daily_pings()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
    v_sender RECORD;
    v_ping_time TIME;
    v_scheduled_time TIMESTAMPTZ;
    v_deadline_time TIMESTAMPTZ;
    v_connection RECORD;
BEGIN
    -- Loop through all active senders with ping enabled
    FOR v_sender IN
        SELECT sp.user_id, sp.ping_time, u.timezone
        FROM sender_profiles sp
        JOIN users u ON u.id = sp.user_id
        WHERE sp.ping_enabled = true
        AND u.is_active = true
        AND NOT is_user_on_break(sp.user_id)
    LOOP
        -- Calculate scheduled time for today in the user's timezone
        v_scheduled_time := (CURRENT_DATE || ' ' || v_sender.ping_time)::TIMESTAMPTZ
                            AT TIME ZONE COALESCE(v_sender.timezone, 'UTC');

        -- Deadline is 90 minutes (1.5 hours) after scheduled time
        v_deadline_time := v_scheduled_time + INTERVAL '90 minutes';

        -- Create ping for each active connection
        FOR v_connection IN
            SELECT id, receiver_id
            FROM connections
            WHERE sender_id = v_sender.user_id
            AND status = 'active'
        LOOP
            -- Check if ping already exists for today
            IF NOT EXISTS (
                SELECT 1 FROM pings
                WHERE connection_id = v_connection.id
                AND DATE(scheduled_time AT TIME ZONE 'UTC') = CURRENT_DATE
            ) THEN
                INSERT INTO pings (
                    connection_id,
                    sender_id,
                    receiver_id,
                    scheduled_time,
                    deadline_time,
                    status
                ) VALUES (
                    v_connection.id,
                    v_sender.user_id,
                    v_connection.receiver_id,
                    v_scheduled_time,
                    v_deadline_time,
                    'pending'
                );

                v_count := v_count + 1;
            END IF;
        END LOOP;
    END LOOP;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to service_role for scheduled jobs
GRANT EXECUTE ON FUNCTION create_daily_pings() TO service_role;

-- ============================================================================
-- 6. MARK_MISSED_PINGS FUNCTION
-- Marks pending pings as missed if deadline has passed
-- Called by scheduled job
-- ============================================================================

CREATE OR REPLACE FUNCTION mark_missed_pings()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
BEGIN
    UPDATE pings
    SET status = 'missed'
    WHERE status = 'pending'
    AND deadline_time < now()
    AND completed_at IS NULL;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to service_role for scheduled jobs
GRANT EXECUTE ON FUNCTION mark_missed_pings() TO service_role;

-- ============================================================================
-- 7. UPDATE_BREAK_STATUSES FUNCTION
-- Updates break statuses based on current date
-- Called by scheduled job
-- ============================================================================

CREATE OR REPLACE FUNCTION update_break_statuses()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
    v_updated INTEGER;
BEGIN
    -- Activate scheduled breaks that should start today
    UPDATE breaks
    SET status = 'active'
    WHERE status = 'scheduled'
    AND start_date <= CURRENT_DATE
    AND end_date >= CURRENT_DATE;

    GET DIAGNOSTICS v_updated = ROW_COUNT;
    v_count := v_count + v_updated;

    -- Complete active breaks that have ended
    UPDATE breaks
    SET status = 'completed'
    WHERE status = 'active'
    AND end_date < CURRENT_DATE;

    GET DIAGNOSTICS v_updated = ROW_COUNT;
    v_count := v_count + v_updated;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to service_role for scheduled jobs
GRANT EXECUTE ON FUNCTION update_break_statuses() TO service_role;

-- ============================================================================
-- 8. GET_RECEIVER_DASHBOARD_DATA FUNCTION
-- Gets all data needed for receiver dashboard in one call
-- ============================================================================

CREATE OR REPLACE FUNCTION get_receiver_dashboard_data(p_user_id UUID)
RETURNS TABLE (
    connection_id UUID,
    sender_id UUID,
    sender_phone TEXT,
    today_ping_status TEXT,
    today_ping_completed_at TIMESTAMPTZ,
    is_sender_on_break BOOLEAN,
    break_end_date DATE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id as connection_id,
        c.sender_id,
        u.phone_number as sender_phone,
        COALESCE(
            (SELECT p.status::TEXT FROM pings p
             WHERE p.connection_id = c.id
             AND DATE(p.scheduled_time AT TIME ZONE 'UTC') = CURRENT_DATE
             LIMIT 1),
            'no_ping'
        ) as today_ping_status,
        (SELECT p.completed_at FROM pings p
         WHERE p.connection_id = c.id
         AND DATE(p.scheduled_time AT TIME ZONE 'UTC') = CURRENT_DATE
         LIMIT 1) as today_ping_completed_at,
        is_user_on_break(c.sender_id) as is_sender_on_break,
        (SELECT b.end_date FROM breaks b
         WHERE b.sender_id = c.sender_id
         AND b.status IN ('scheduled', 'active')
         AND CURRENT_DATE BETWEEN b.start_date AND b.end_date
         LIMIT 1) as break_end_date
    FROM connections c
    JOIN users u ON u.id = c.sender_id
    WHERE c.receiver_id = p_user_id
    AND c.status = 'active';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_receiver_dashboard_data(UUID) TO authenticated;

-- ============================================================================
-- 9. GET_SENDER_STATS FUNCTION
-- Gets statistics for sender's ping history
-- ============================================================================

CREATE OR REPLACE FUNCTION get_sender_stats(
    p_sender_id UUID,
    p_days INTEGER DEFAULT 30
)
RETURNS TABLE (
    total_pings BIGINT,
    completed_pings BIGINT,
    missed_pings BIGINT,
    on_break_pings BIGINT,
    completion_rate NUMERIC,
    current_streak INTEGER
) AS $$
DECLARE
    v_streak INTEGER := 0;
    v_date DATE := CURRENT_DATE;
    v_ping_status TEXT;
BEGIN
    -- Calculate current streak
    LOOP
        SELECT p.status INTO v_ping_status
        FROM pings p
        WHERE p.sender_id = p_sender_id
        AND DATE(p.scheduled_time AT TIME ZONE 'UTC') = v_date
        LIMIT 1;

        EXIT WHEN v_ping_status IS NULL OR v_ping_status = 'missed';

        IF v_ping_status = 'completed' OR v_ping_status = 'on_break' THEN
            v_streak := v_streak + 1;
        END IF;

        v_date := v_date - 1;

        -- Safety limit
        EXIT WHEN v_date < CURRENT_DATE - INTERVAL '365 days';
    END LOOP;

    RETURN QUERY
    SELECT
        COUNT(*)::BIGINT as total_pings,
        COUNT(*) FILTER (WHERE p.status = 'completed')::BIGINT as completed_pings,
        COUNT(*) FILTER (WHERE p.status = 'missed')::BIGINT as missed_pings,
        COUNT(*) FILTER (WHERE p.status = 'on_break')::BIGINT as on_break_pings,
        CASE
            WHEN COUNT(*) FILTER (WHERE p.status IN ('completed', 'missed')) > 0
            THEN ROUND(
                (COUNT(*) FILTER (WHERE p.status = 'completed')::NUMERIC /
                 COUNT(*) FILTER (WHERE p.status IN ('completed', 'missed'))::NUMERIC) * 100,
                1
            )
            ELSE 100.0
        END as completion_rate,
        v_streak as current_streak
    FROM pings p
    WHERE p.sender_id = p_sender_id
    AND p.scheduled_time >= (CURRENT_DATE - (p_days || ' days')::INTERVAL);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_sender_stats(UUID, INTEGER) TO authenticated;

-- ============================================================================
-- 10. REFRESH_RECEIVER_CODE FUNCTION
-- Generates a new code for a receiver, invalidating the old one
-- ============================================================================

CREATE OR REPLACE FUNCTION refresh_receiver_code(p_user_id UUID)
RETURNS TEXT AS $$
DECLARE
    v_new_code TEXT;
BEGIN
    -- Verify user owns this operation
    IF p_user_id != auth.uid() THEN
        RAISE EXCEPTION 'Unauthorized: cannot refresh another user''s code';
    END IF;

    -- Deactivate old code
    UPDATE unique_codes
    SET is_active = false
    WHERE receiver_id = p_user_id AND is_active = true;

    -- Generate and return new code
    v_new_code := generate_unique_code();

    INSERT INTO unique_codes (code, receiver_id, is_active)
    VALUES (v_new_code, p_user_id, true);

    -- Log the action
    PERFORM log_audit_event(
        p_user_id,
        'code_refreshed',
        'unique_code',
        NULL,
        jsonb_build_object('new_code_prefix', LEFT(v_new_code, 2) || '****')
    );

    RETURN v_new_code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION refresh_receiver_code(UUID) TO authenticated;

-- ============================================================================
-- COMMENTS FOR DOCUMENTATION
-- ============================================================================

COMMENT ON FUNCTION create_receiver_code(UUID) IS 'Creates or retrieves a unique 6-digit code for a receiver user';
COMMENT ON FUNCTION check_subscription_status(UUID) IS 'Checks and updates subscription status, returning current status as TEXT';
COMMENT ON FUNCTION get_today_ping_status(UUID) IS 'Gets the status of today''s ping for a sender';
COMMENT ON FUNCTION complete_ping(UUID, TEXT, JSONB, TEXT) IS 'Marks a ping as completed with optional verification data';
COMMENT ON FUNCTION create_daily_pings() IS 'Creates daily pings for all active senders - called by scheduled job';
COMMENT ON FUNCTION mark_missed_pings() IS 'Marks pending pings as missed if deadline passed - called by scheduled job';
COMMENT ON FUNCTION update_break_statuses() IS 'Updates break statuses based on current date - called by scheduled job';
COMMENT ON FUNCTION get_receiver_dashboard_data(UUID) IS 'Gets all dashboard data for a receiver in one efficient query';
COMMENT ON FUNCTION get_sender_stats(UUID, INTEGER) IS 'Gets ping statistics for a sender over specified days';
COMMENT ON FUNCTION refresh_receiver_code(UUID) IS 'Generates a new unique code for a receiver, invalidating the old one';
