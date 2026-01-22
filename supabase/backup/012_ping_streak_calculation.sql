-- ============================================================================
-- Migration: 012_ping_streak_calculation.sql
-- Purpose: Implement ping streak calculation as specified in Phase 6 Section 6.4
-- ============================================================================

-- ============================================================================
-- CALCULATE_STREAK FUNCTION
-- ============================================================================
-- Calculates the consecutive ping streak for a sender
-- Rules (from plan.md Section 6.4):
--   1. Consecutive days of completed pings
--   2. Breaks do NOT break the streak (counted as completed)
--   3. Missed pings reset streak to 0
--   4. Late pings count toward streak (they have status 'completed')
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_streak(
    p_sender_id UUID,
    p_receiver_id UUID DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_streak INTEGER := 0;
    v_current_date DATE := CURRENT_DATE;
    v_ping_status TEXT;
    v_first_ping_date DATE;
    v_has_pings BOOLEAN := FALSE;
BEGIN
    -- If receiver_id is provided, calculate streak only for that specific connection
    -- Otherwise, calculate overall streak for the sender across all connections

    -- First, check if today's ping exists and what its status is
    -- We start counting from the most recent complete day (yesterday or today if completed)

    -- Get the earliest ping date to know when to stop checking
    IF p_receiver_id IS NOT NULL THEN
        SELECT MIN(DATE(scheduled_time AT TIME ZONE 'UTC'))
        INTO v_first_ping_date
        FROM pings
        WHERE sender_id = p_sender_id
        AND receiver_id = p_receiver_id;
    ELSE
        SELECT MIN(DATE(scheduled_time AT TIME ZONE 'UTC'))
        INTO v_first_ping_date
        FROM pings
        WHERE sender_id = p_sender_id;
    END IF;

    -- If no pings exist, return 0
    IF v_first_ping_date IS NULL THEN
        RETURN 0;
    END IF;

    -- Check if today's ping is already completed or on_break
    -- If so, include today in the streak count
    IF p_receiver_id IS NOT NULL THEN
        SELECT p.status INTO v_ping_status
        FROM pings p
        WHERE p.sender_id = p_sender_id
        AND p.receiver_id = p_receiver_id
        AND DATE(p.scheduled_time AT TIME ZONE 'UTC') = v_current_date
        ORDER BY p.scheduled_time DESC
        LIMIT 1;
    ELSE
        -- For overall streak, get the most relevant status for today
        -- Use a single ping's status (if multiple connections, any completed counts)
        SELECT p.status INTO v_ping_status
        FROM pings p
        WHERE p.sender_id = p_sender_id
        AND DATE(p.scheduled_time AT TIME ZONE 'UTC') = v_current_date
        ORDER BY
            CASE p.status
                WHEN 'completed' THEN 1
                WHEN 'on_break' THEN 2
                WHEN 'pending' THEN 3
                WHEN 'missed' THEN 4
            END ASC
        LIMIT 1;
    END IF;

    -- If today's ping is missed, streak is 0
    IF v_ping_status = 'missed' THEN
        RETURN 0;
    END IF;

    -- If today's ping is completed or on_break, count it
    IF v_ping_status IN ('completed', 'on_break') THEN
        v_streak := 1;
        v_has_pings := TRUE;
    END IF;

    -- Now go backwards from yesterday
    v_current_date := v_current_date - 1;

    -- Loop through previous days
    WHILE v_current_date >= v_first_ping_date LOOP
        -- Get the ping status for this date
        IF p_receiver_id IS NOT NULL THEN
            SELECT p.status INTO v_ping_status
            FROM pings p
            WHERE p.sender_id = p_sender_id
            AND p.receiver_id = p_receiver_id
            AND DATE(p.scheduled_time AT TIME ZONE 'UTC') = v_current_date
            ORDER BY p.scheduled_time DESC
            LIMIT 1;
        ELSE
            -- For overall streak, prioritize best status if multiple connections
            SELECT p.status INTO v_ping_status
            FROM pings p
            WHERE p.sender_id = p_sender_id
            AND DATE(p.scheduled_time AT TIME ZONE 'UTC') = v_current_date
            ORDER BY
                CASE p.status
                    WHEN 'completed' THEN 1
                    WHEN 'on_break' THEN 2
                    WHEN 'pending' THEN 3
                    WHEN 'missed' THEN 4
                END ASC
            LIMIT 1;
        END IF;

        -- No ping found for this date - if we haven't started counting, continue
        -- but if we've started (v_has_pings), this breaks the streak
        IF v_ping_status IS NULL THEN
            -- Only break if we've already started counting
            IF v_has_pings THEN
                EXIT;
            END IF;
        ELSIF v_ping_status = 'missed' THEN
            -- Missed ping resets/breaks the streak
            EXIT;
        ELSIF v_ping_status = 'pending' THEN
            -- Pending is for today's ping that hasn't been acted on yet
            -- For historical days, this shouldn't happen, but if it does, treat as break
            EXIT;
        ELSIF v_ping_status IN ('completed', 'on_break') THEN
            -- Completed or on_break counts toward the streak
            v_streak := v_streak + 1;
            v_has_pings := TRUE;
        END IF;

        -- Move to previous day
        v_current_date := v_current_date - 1;

        -- Safety limit: don't go back more than 2 years
        EXIT WHEN v_current_date < CURRENT_DATE - INTERVAL '730 days';
    END LOOP;

    RETURN v_streak;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION calculate_streak(UUID, UUID) TO authenticated;

-- ============================================================================
-- CALCULATE_STREAK_FOR_CONNECTION FUNCTION (Convenience Wrapper)
-- ============================================================================
-- Calculates streak for a specific sender-receiver connection
-- Used by receiver dashboard to show streak for each sender

CREATE OR REPLACE FUNCTION calculate_streak_for_connection(
    p_connection_id UUID
)
RETURNS INTEGER AS $$
DECLARE
    v_sender_id UUID;
    v_receiver_id UUID;
BEGIN
    -- Get sender and receiver from connection
    SELECT sender_id, receiver_id
    INTO v_sender_id, v_receiver_id
    FROM connections
    WHERE id = p_connection_id AND status = 'active';

    IF v_sender_id IS NULL THEN
        RETURN 0;
    END IF;

    RETURN calculate_streak(v_sender_id, v_receiver_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION calculate_streak_for_connection(UUID) TO authenticated;

-- ============================================================================
-- GET_SENDER_STREAK_INFO FUNCTION
-- ============================================================================
-- Returns detailed streak information for display purposes

CREATE OR REPLACE FUNCTION get_sender_streak_info(
    p_sender_id UUID,
    p_receiver_id UUID DEFAULT NULL
)
RETURNS TABLE (
    current_streak INTEGER,
    longest_streak INTEGER,
    last_completed_date DATE,
    last_missed_date DATE,
    total_completed_days INTEGER,
    total_break_days INTEGER,
    total_missed_days INTEGER
) AS $$
BEGIN
    RETURN QUERY
    WITH ping_stats AS (
        SELECT
            DATE(p.scheduled_time AT TIME ZONE 'UTC') as ping_date,
            p.status
        FROM pings p
        WHERE p.sender_id = p_sender_id
        AND (p_receiver_id IS NULL OR p.receiver_id = p_receiver_id)
        ORDER BY ping_date DESC
    ),
    aggregated AS (
        SELECT
            COUNT(*) FILTER (WHERE status = 'completed')::INTEGER as total_completed,
            COUNT(*) FILTER (WHERE status = 'on_break')::INTEGER as total_breaks,
            COUNT(*) FILTER (WHERE status = 'missed')::INTEGER as total_missed,
            MAX(ping_date) FILTER (WHERE status = 'completed') as last_completed,
            MAX(ping_date) FILTER (WHERE status = 'missed') as last_missed
        FROM ping_stats
    )
    SELECT
        calculate_streak(p_sender_id, p_receiver_id) as current_streak,
        COALESCE((
            -- Calculate longest streak using a more complex window function approach
            SELECT MAX(streak_length)::INTEGER
            FROM (
                SELECT
                    COUNT(*) as streak_length
                FROM (
                    SELECT
                        ping_date,
                        status,
                        ping_date - (ROW_NUMBER() OVER (ORDER BY ping_date))::INTEGER as grp
                    FROM ping_stats
                    WHERE status IN ('completed', 'on_break')
                ) sub
                GROUP BY grp
            ) streaks
        ), 0) as longest_streak,
        a.last_completed as last_completed_date,
        a.last_missed as last_missed_date,
        a.total_completed as total_completed_days,
        a.total_breaks as total_break_days,
        a.total_missed as total_missed_days
    FROM aggregated a;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_sender_streak_info(UUID, UUID) TO authenticated;

-- ============================================================================
-- UPDATE get_sender_stats TO USE NEW STREAK LOGIC
-- ============================================================================
-- This replaces the existing function with the corrected streak calculation

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
BEGIN
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
        calculate_streak(p_sender_id, NULL) as current_streak
    FROM pings p
    WHERE p.sender_id = p_sender_id
    AND p.scheduled_time >= (CURRENT_DATE - (p_days || ' days')::INTERVAL);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission (re-granting in case it was dropped)
GRANT EXECUTE ON FUNCTION get_sender_stats(UUID, INTEGER) TO authenticated;

-- ============================================================================
-- CREATE INDEX FOR STREAK CALCULATIONS (Performance Optimization)
-- ============================================================================

-- Index to speed up streak calculations by sender and date
CREATE INDEX IF NOT EXISTS idx_pings_sender_scheduled_date
ON pings (sender_id, (DATE(scheduled_time AT TIME ZONE 'UTC')) DESC);

-- Index for connection-specific streak calculations
CREATE INDEX IF NOT EXISTS idx_pings_sender_receiver_scheduled_date
ON pings (sender_id, receiver_id, (DATE(scheduled_time AT TIME ZONE 'UTC')) DESC);

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================
