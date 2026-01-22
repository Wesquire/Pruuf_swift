-- Migration: 010_daily_ping_generation.sql
-- Purpose: Add scheduled job for daily ping generation at midnight UTC
-- Phase 6 Section 6.1: Daily Ping Generation
-- Created: 2026-01-17

-- ============================================================================
-- 1. FUNCTION: Generate Daily Pings
-- Creates ping records for all active sender/receiver connections
-- Called by the Edge Function or can be called directly via pg_cron
-- ============================================================================

CREATE OR REPLACE FUNCTION public.generate_daily_pings(p_target_date DATE DEFAULT CURRENT_DATE)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_connection RECORD;
    v_sender_profile RECORD;
    v_receiver_profile RECORD;
    v_on_break BOOLEAN;
    v_ping_status TEXT;
    v_scheduled_time TIMESTAMPTZ;
    v_deadline_time TIMESTAMPTZ;
    v_pings_created INTEGER := 0;
    v_pings_skipped INTEGER := 0;
    v_on_break_count INTEGER := 0;
    v_result JSONB;
BEGIN
    -- Loop through all active connections
    FOR v_connection IN
        SELECT
            c.id AS connection_id,
            c.sender_id,
            c.receiver_id
        FROM connections c
        WHERE c.status = 'active'
    LOOP
        -- Check if ping already exists for this connection and date
        IF EXISTS (
            SELECT 1 FROM pings
            WHERE connection_id = v_connection.connection_id
            AND DATE(scheduled_time) = p_target_date
        ) THEN
            v_pings_skipped := v_pings_skipped + 1;
            CONTINUE;
        END IF;

        -- Get sender profile
        SELECT user_id, ping_time, ping_enabled
        INTO v_sender_profile
        FROM sender_profiles
        WHERE user_id = v_connection.sender_id;

        -- Skip if no sender profile or ping disabled
        IF v_sender_profile IS NULL OR NOT v_sender_profile.ping_enabled THEN
            v_pings_skipped := v_pings_skipped + 1;
            CONTINUE;
        END IF;

        -- Get receiver profile and check subscription
        SELECT user_id, subscription_status, trial_end_date, subscription_end_date
        INTO v_receiver_profile
        FROM receiver_profiles
        WHERE user_id = v_connection.receiver_id;

        -- Skip if no receiver profile
        IF v_receiver_profile IS NULL THEN
            v_pings_skipped := v_pings_skipped + 1;
            CONTINUE;
        END IF;

        -- Check if receiver subscription is active
        IF v_receiver_profile.subscription_status NOT IN ('active', 'trial') THEN
            v_pings_skipped := v_pings_skipped + 1;
            CONTINUE;
        END IF;

        -- Check if trial/subscription has expired
        IF v_receiver_profile.subscription_status = 'trial'
           AND v_receiver_profile.trial_end_date IS NOT NULL
           AND v_receiver_profile.trial_end_date < NOW() THEN
            v_pings_skipped := v_pings_skipped + 1;
            CONTINUE;
        END IF;

        IF v_receiver_profile.subscription_status = 'active'
           AND v_receiver_profile.subscription_end_date IS NOT NULL
           AND v_receiver_profile.subscription_end_date < NOW() THEN
            v_pings_skipped := v_pings_skipped + 1;
            CONTINUE;
        END IF;

        -- Check if sender is on break
        v_on_break := is_user_on_break(v_connection.sender_id, p_target_date);

        -- Determine ping status
        v_ping_status := CASE WHEN v_on_break THEN 'on_break' ELSE 'pending' END;

        -- Calculate scheduled time (ping_time applied to target date in UTC)
        v_scheduled_time := p_target_date + v_sender_profile.ping_time;

        -- Calculate deadline as scheduled_time + 90 minutes
        v_deadline_time := v_scheduled_time + INTERVAL '90 minutes';

        -- Insert ping record
        INSERT INTO pings (
            connection_id,
            sender_id,
            receiver_id,
            scheduled_time,
            deadline_time,
            status
        ) VALUES (
            v_connection.connection_id,
            v_connection.sender_id,
            v_connection.receiver_id,
            v_scheduled_time,
            v_deadline_time,
            v_ping_status
        );

        v_pings_created := v_pings_created + 1;
        IF v_on_break THEN
            v_on_break_count := v_on_break_count + 1;
        END IF;
    END LOOP;

    -- Build result
    v_result := jsonb_build_object(
        'success', TRUE,
        'date', p_target_date,
        'pings_created', v_pings_created,
        'pings_skipped', v_pings_skipped,
        'on_break_count', v_on_break_count,
        'pending_count', v_pings_created - v_on_break_count,
        'timestamp', NOW()
    );

    -- Log audit event
    INSERT INTO audit_logs (action, resource_type, details)
    VALUES ('generate_daily_pings', 'pings', v_result);

    RETURN v_result;
END;
$$;

-- ============================================================================
-- 2. SCHEDULED JOB: Run at midnight UTC
-- Triggers the Edge Function via HTTP call
-- ============================================================================

-- Create function to invoke the Edge Function
CREATE OR REPLACE FUNCTION public.invoke_generate_daily_pings()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Call the generate_daily_pings function directly
    -- The Edge Function can also be called via HTTP if preferred
    PERFORM generate_daily_pings(CURRENT_DATE);
END;
$$;

-- Schedule the job to run at midnight UTC (0 0 * * *)
-- Note: This uses pg_cron extension which must be enabled
SELECT cron.schedule(
    'generate-daily-pings',
    '0 0 * * *',
    'SELECT public.invoke_generate_daily_pings()'
);

-- ============================================================================
-- 3. HELPER: Update breaks status (scheduled -> active -> completed)
-- ============================================================================

DROP FUNCTION IF EXISTS public.update_break_statuses();
CREATE OR REPLACE FUNCTION public.update_break_statuses()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Move scheduled breaks to active if start_date is today or past
    UPDATE breaks
    SET status = 'active'
    WHERE status = 'scheduled'
    AND start_date <= CURRENT_DATE;

    -- Move active breaks to completed if end_date is past
    UPDATE breaks
    SET status = 'completed'
    WHERE status = 'active'
    AND end_date < CURRENT_DATE;
END;
$$;

-- Schedule break status updates to run daily at midnight UTC (after ping generation)
SELECT cron.schedule(
    'update-break-statuses',
    '5 0 * * *',
    'SELECT public.update_break_statuses()'
);

-- ============================================================================
-- 4. GRANT PERMISSIONS
-- ============================================================================

-- Grant execute on functions to service role
GRANT EXECUTE ON FUNCTION public.generate_daily_pings(DATE) TO service_role;
GRANT EXECUTE ON FUNCTION public.invoke_generate_daily_pings() TO service_role;
GRANT EXECUTE ON FUNCTION public.update_break_statuses() TO service_role;

-- ============================================================================
-- 5. COMMENTS
-- ============================================================================

COMMENT ON FUNCTION public.generate_daily_pings IS 'Creates daily ping records for all active connections. Respects sender breaks and receiver subscription status. Deadline is scheduled_time + 90 minutes.';
COMMENT ON FUNCTION public.invoke_generate_daily_pings IS 'Wrapper function to invoke generate_daily_pings, called by pg_cron at midnight UTC.';
COMMENT ON FUNCTION public.update_break_statuses IS 'Updates break statuses from scheduled to active to completed based on dates.';
