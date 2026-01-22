-- Migration: 017_subscription_status_checks.sql
-- Purpose: Enhanced subscription status checks for daily ping generation (Section 9.5)
-- Created: 2026-01-17
--
-- Section 9.5 Requirements:
-- Before Ping Generation (Cron Job):
-- - Daily cron job checks receiver subscription status
-- - If expired -> Skip ping generation for that connection
-- - If past_due -> Grace period of 3 days, then skip
--
-- On App Launch:
-- - Check subscription status
-- - If expired -> Show "Subscription Expired" banner
-- - If past_due -> Show "Payment Failed - Update Payment Method"

-- ============================================================================
-- 1. FUNCTION: Check if receiver has valid subscription for ping generation
-- Returns TRUE if pings should be generated, FALSE if they should be skipped
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_subscription_valid_for_pings(p_receiver_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_subscription_status TEXT;
    v_trial_end_date TIMESTAMPTZ;
    v_subscription_end_date TIMESTAMPTZ;
    v_updated_at TIMESTAMPTZ;
    v_days_past_due INT;
    v_grace_period_days INT := 3; -- 3-day grace period for past_due
BEGIN
    -- Get receiver profile subscription info
    SELECT
        subscription_status,
        trial_end_date,
        subscription_end_date,
        updated_at
    INTO
        v_subscription_status,
        v_trial_end_date,
        v_subscription_end_date,
        v_updated_at
    FROM receiver_profiles
    WHERE user_id = p_receiver_id;

    -- No receiver profile = no subscription = skip pings
    IF v_subscription_status IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Check subscription status
    CASE v_subscription_status
        -- Trial: Valid if trial hasn't ended
        WHEN 'trial' THEN
            IF v_trial_end_date IS NULL THEN
                -- No trial end date set, assume invalid
                RETURN FALSE;
            END IF;
            RETURN v_trial_end_date > NOW();

        -- Active: Valid if subscription hasn't ended
        WHEN 'active' THEN
            IF v_subscription_end_date IS NULL THEN
                -- No end date means indefinite (unlikely but handle it)
                RETURN TRUE;
            END IF;
            RETURN v_subscription_end_date > NOW();

        -- Past Due: Valid within 3-day grace period
        WHEN 'past_due' THEN
            -- Calculate days since status became past_due
            -- We use updated_at as the timestamp when status changed to past_due
            v_days_past_due := EXTRACT(DAY FROM (NOW() - v_updated_at));

            -- Allow pings during grace period
            IF v_days_past_due <= v_grace_period_days THEN
                RETURN TRUE;
            END IF;

            -- Grace period exceeded, skip pings
            RETURN FALSE;

        -- Expired: No pings
        WHEN 'expired' THEN
            RETURN FALSE;

        -- Canceled: No pings (user explicitly canceled)
        WHEN 'canceled' THEN
            RETURN FALSE;

        -- Unknown status: Default to no pings
        ELSE
            RETURN FALSE;
    END CASE;
END;
$$;

-- ============================================================================
-- 2. FUNCTION: Get subscription status details for app display
-- Returns structured info about subscription status for UI banners
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_subscription_status_for_display(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_subscription_status TEXT;
    v_trial_end_date TIMESTAMPTZ;
    v_subscription_end_date TIMESTAMPTZ;
    v_updated_at TIMESTAMPTZ;
    v_days_past_due INT;
    v_grace_period_days INT := 3;
    v_days_remaining INT;
    v_show_banner BOOLEAN := FALSE;
    v_banner_type TEXT;
    v_banner_message TEXT;
BEGIN
    -- Get receiver profile subscription info
    SELECT
        subscription_status,
        trial_end_date,
        subscription_end_date,
        updated_at
    INTO
        v_subscription_status,
        v_trial_end_date,
        v_subscription_end_date,
        v_updated_at
    FROM receiver_profiles
    WHERE user_id = p_user_id;

    -- No receiver profile
    IF v_subscription_status IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'none',
            'show_banner', FALSE,
            'banner_type', NULL,
            'banner_message', NULL,
            'is_valid', FALSE
        );
    END IF;

    -- Process based on status
    CASE v_subscription_status
        WHEN 'trial' THEN
            IF v_trial_end_date IS NOT NULL AND v_trial_end_date <= NOW() THEN
                -- Trial expired
                v_show_banner := TRUE;
                v_banner_type := 'expired';
                v_banner_message := 'Your trial has ended. Subscribe to continue receiving check-ins.';
            ELSE
                -- Trial active - calculate days remaining
                v_days_remaining := GREATEST(0, EXTRACT(DAY FROM (v_trial_end_date - NOW()))::INT);
                IF v_days_remaining <= 3 THEN
                    v_show_banner := TRUE;
                    v_banner_type := 'trial_ending';
                    v_banner_message := format('Your trial ends in %s day%s. Subscribe now!',
                        v_days_remaining,
                        CASE WHEN v_days_remaining = 1 THEN '' ELSE 's' END);
                END IF;
            END IF;

        WHEN 'active' THEN
            -- Active subscription - no banner needed
            v_show_banner := FALSE;

        WHEN 'past_due' THEN
            v_days_past_due := GREATEST(0, EXTRACT(DAY FROM (NOW() - v_updated_at))::INT);
            v_show_banner := TRUE;
            v_banner_type := 'payment_failed';

            IF v_days_past_due <= v_grace_period_days THEN
                v_banner_message := format('Payment failed. Update your payment method within %s day%s to continue.',
                    v_grace_period_days - v_days_past_due,
                    CASE WHEN (v_grace_period_days - v_days_past_due) = 1 THEN '' ELSE 's' END);
            ELSE
                v_banner_message := 'Payment failed. Update your payment method to continue receiving check-ins.';
            END IF;

        WHEN 'expired' THEN
            v_show_banner := TRUE;
            v_banner_type := 'expired';
            v_banner_message := 'Your subscription has expired. Subscribe to continue receiving check-ins.';

        WHEN 'canceled' THEN
            v_show_banner := TRUE;
            v_banner_type := 'canceled';
            v_banner_message := 'Your subscription was canceled. Resubscribe to continue receiving check-ins.';

        ELSE
            v_show_banner := FALSE;
    END CASE;

    RETURN jsonb_build_object(
        'status', v_subscription_status,
        'show_banner', v_show_banner,
        'banner_type', v_banner_type,
        'banner_message', v_banner_message,
        'is_valid', is_subscription_valid_for_pings(p_user_id),
        'trial_end_date', v_trial_end_date,
        'subscription_end_date', v_subscription_end_date,
        'grace_period_days', v_grace_period_days
    );
END;
$$;

-- ============================================================================
-- 3. UPDATE: Enhanced generate_daily_pings function with subscription checks
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
    v_subscription_skipped INTEGER := 0;
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

        -- =================================================================
        -- SECTION 9.5: Subscription Status Check for Ping Generation
        -- =================================================================

        -- Check receiver subscription using the new validation function
        IF NOT is_subscription_valid_for_pings(v_connection.receiver_id) THEN
            v_subscription_skipped := v_subscription_skipped + 1;
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

    -- Build result with subscription skip count
    v_result := jsonb_build_object(
        'success', TRUE,
        'date', p_target_date,
        'pings_created', v_pings_created,
        'pings_skipped', v_pings_skipped,
        'subscription_skipped', v_subscription_skipped,
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
-- 4. FUNCTION: Auto-expire past_due subscriptions after grace period
-- Called by cron job to automatically expire subscriptions past grace period
-- ============================================================================

CREATE OR REPLACE FUNCTION public.expire_past_due_subscriptions()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_grace_period_days INT := 3;
    v_expired_count INT := 0;
BEGIN
    -- Update past_due subscriptions to expired if grace period exceeded
    WITH updated AS (
        UPDATE receiver_profiles
        SET subscription_status = 'expired',
            updated_at = NOW()
        WHERE subscription_status = 'past_due'
        AND updated_at < (NOW() - (v_grace_period_days || ' days')::INTERVAL)
        RETURNING user_id
    )
    SELECT COUNT(*) INTO v_expired_count FROM updated;

    -- Log audit event if any were expired
    IF v_expired_count > 0 THEN
        INSERT INTO audit_logs (action, resource_type, details)
        VALUES (
            'auto_expire_past_due',
            'receiver_profiles',
            jsonb_build_object(
                'expired_count', v_expired_count,
                'grace_period_days', v_grace_period_days,
                'timestamp', NOW()
            )
        );
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'expired_count', v_expired_count,
        'grace_period_days', v_grace_period_days,
        'timestamp', NOW()
    );
END;
$$;

-- ============================================================================
-- 5. SCHEDULE: Cron job to expire past_due subscriptions
-- Runs daily at 00:10 UTC (after ping generation)
-- ============================================================================

SELECT cron.schedule(
    'expire-past-due-subscriptions',
    '10 0 * * *',
    'SELECT public.expire_past_due_subscriptions()'
);

-- ============================================================================
-- 6. GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.is_subscription_valid_for_pings(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_subscription_status_for_display(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.expire_past_due_subscriptions() TO service_role;

-- ============================================================================
-- 7. COMMENTS
-- ============================================================================

COMMENT ON FUNCTION public.is_subscription_valid_for_pings IS
'Section 9.5: Checks if receiver subscription allows ping generation.
Returns TRUE for active/trial (not expired) subscriptions and past_due within 3-day grace period.
Returns FALSE for expired, canceled, or past_due beyond grace period.';

COMMENT ON FUNCTION public.get_subscription_status_for_display IS
'Section 9.5: Returns subscription status details for app display including banner type and message.
Used on app launch to show appropriate banners: Subscription Expired or Payment Failed.';

COMMENT ON FUNCTION public.expire_past_due_subscriptions IS
'Section 9.5: Automatically expires past_due subscriptions that exceed the 3-day grace period.
Runs daily via cron job after ping generation.';
