-- ============================================
-- ADMIN USER STORIES IMPLEMENTATION
-- Phase 11 Section 11.5
-- ============================================
-- This migration implements the specific functions for:
-- US-11.1: View User Metrics
-- US-11.2: Manage Subscriptions
-- US-11.3: Monitor System Health

-- ============================================
-- US-11.1: VIEW USER METRICS
-- ============================================

-- Function: Get user growth over time
-- Returns daily signup data with cumulative totals
CREATE OR REPLACE FUNCTION public.admin_get_user_growth(days_back INT DEFAULT 30)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    WITH date_series AS (
        SELECT generate_series(
            CURRENT_DATE - (days_back || ' days')::INTERVAL,
            CURRENT_DATE,
            '1 day'::INTERVAL
        )::DATE as date
    ),
    daily_signups AS (
        SELECT
            created_at::DATE as signup_date,
            COUNT(*) as count
        FROM public.users
        GROUP BY created_at::DATE
    ),
    cumulative AS (
        SELECT
            ds.date,
            COALESCE(ds_signups.count, 0) as new_signups,
            SUM(COALESCE(ds_signups.count, 0)) OVER (ORDER BY ds.date) +
                (SELECT COUNT(*) FROM public.users WHERE created_at::DATE < (CURRENT_DATE - (days_back || ' days')::INTERVAL)::DATE)
            as cumulative_users
        FROM date_series ds
        LEFT JOIN daily_signups ds_signups ON ds.date = ds_signups.signup_date
    )
    SELECT jsonb_agg(
        jsonb_build_object(
            'date', date,
            'new_signups', new_signups,
            'cumulative_users', cumulative_users
        ) ORDER BY date
    ) INTO result
    FROM cumulative;

    RETURN COALESCE(result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- US-11.2: MANAGE SUBSCRIPTIONS
-- ============================================

-- Function: Get subscription details for a user
CREATE OR REPLACE FUNCTION public.admin_get_subscription_details(target_user_id UUID)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT jsonb_build_object(
        'user_id', u.id,
        'phone_number', u.phone_number,
        'primary_role', u.primary_role,
        'subscription_status', rp.subscription_status,
        'subscription_start_date', rp.subscription_start_date,
        'subscription_end_date', rp.subscription_end_date,
        'trial_start_date', rp.trial_start_date,
        'trial_end_date', rp.trial_end_date,
        'stripe_customer_id', rp.stripe_customer_id,
        'stripe_subscription_id', rp.stripe_subscription_id,
        'created_at', rp.created_at,
        'updated_at', rp.updated_at
    ) INTO result
    FROM public.users u
    LEFT JOIN public.receiver_profiles rp ON u.id = rp.user_id
    WHERE u.id = target_user_id;

    IF result IS NULL THEN
        RAISE EXCEPTION 'User not found';
    END IF;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Extend subscription
CREATE OR REPLACE FUNCTION public.admin_extend_subscription(
    target_user_id UUID,
    days_to_extend INT,
    reason TEXT DEFAULT 'Admin extension'
)
RETURNS JSONB AS $$
DECLARE
    current_end_date DATE;
    new_end_date DATE;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    -- Get current end date
    SELECT subscription_end_date INTO current_end_date
    FROM public.receiver_profiles
    WHERE user_id = target_user_id;

    IF current_end_date IS NULL THEN
        RAISE EXCEPTION 'User does not have a receiver profile';
    END IF;

    -- Calculate new end date
    new_end_date := current_end_date + (days_to_extend || ' days')::INTERVAL;

    -- Update subscription
    UPDATE public.receiver_profiles
    SET
        subscription_end_date = new_end_date,
        updated_at = NOW()
    WHERE user_id = target_user_id;

    -- Log to audit
    INSERT INTO public.audit_logs (
        user_id,
        action,
        resource_type,
        resource_id,
        details,
        created_at
    ) VALUES (
        target_user_id,
        'subscription_extended',
        'subscription',
        target_user_id,
        jsonb_build_object(
            'days_extended', days_to_extend,
            'old_end_date', current_end_date,
            'new_end_date', new_end_date,
            'reason', reason
        ),
        NOW()
    );

    RETURN jsonb_build_object(
        'success', true,
        'old_end_date', current_end_date,
        'new_end_date', new_end_date,
        'days_extended', days_to_extend
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Get payment history for a user
CREATE OR REPLACE FUNCTION public.admin_get_payment_history(
    target_user_id UUID,
    result_limit INT DEFAULT 50
)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT COALESCE(jsonb_agg(payment_data ORDER BY created_at DESC), '[]'::jsonb)
    INTO result
    FROM (
        SELECT jsonb_build_object(
            'id', id,
            'stripe_payment_intent_id', stripe_payment_intent_id,
            'amount', amount,
            'currency', currency,
            'status', status,
            'transaction_type', transaction_type,
            'created_at', created_at,
            'metadata', metadata
        ) as payment_data
        FROM public.payment_transactions
        WHERE user_id = target_user_id
        ORDER BY created_at DESC
        LIMIT result_limit
    ) payments;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- US-11.3: MONITOR SYSTEM HEALTH
-- ============================================

-- Function: Get edge function execution statistics
CREATE OR REPLACE FUNCTION public.admin_get_edge_function_stats(hours_back INT DEFAULT 24)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    -- Note: This returns mock data as edge function logs are not in the database
    -- In production, this would query Supabase edge function logs via API
    SELECT jsonb_agg(
        jsonb_build_object(
            'function_name', function_name,
            'executions', executions,
            'avg_duration_ms', avg_duration_ms,
            'error_count', error_count,
            'success_rate', success_rate
        )
    ) INTO result
    FROM (
        SELECT
            'generate_daily_pings' as function_name,
            0 as executions,
            0 as avg_duration_ms,
            0 as error_count,
            100.0 as success_rate
        UNION ALL
        SELECT
            'complete_ping' as function_name,
            0 as executions,
            0 as avg_duration_ms,
            0 as error_count,
            100.0 as success_rate
        UNION ALL
        SELECT
            'send_ping_notifications' as function_name,
            0 as executions,
            0 as avg_duration_ms,
            0 as error_count,
            100.0 as success_rate
    ) stats;

    RETURN COALESCE(result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Check error rate thresholds and alert
CREATE OR REPLACE FUNCTION public.admin_check_error_thresholds()
RETURNS JSONB AS $$
DECLARE
    result JSONB;
    alert_array JSONB := '[]'::jsonb;
    failed_notifications INT;
    missed_pings INT;
    failed_cron_jobs INT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    -- Check notification failures (last 24 hours)
    SELECT COUNT(*) INTO failed_notifications
    FROM public.notifications
    WHERE delivery_status = 'failed'
    AND sent_at > NOW() - INTERVAL '24 hours';

    IF failed_notifications > 10 THEN
        alert_array := alert_array || jsonb_build_object(
            'type', 'notification_failures',
            'severity', 'warning',
            'count', failed_notifications,
            'message', 'High notification failure rate detected'
        );
    END IF;

    -- Check missed pings (last 24 hours)
    SELECT COUNT(*) INTO missed_pings
    FROM public.pings
    WHERE status = 'missed'
    AND scheduled_time > NOW() - INTERVAL '24 hours';

    IF missed_pings > 50 THEN
        alert_array := alert_array || jsonb_build_object(
            'type', 'missed_pings',
            'severity', 'info',
            'count', missed_pings,
            'message', 'Elevated missed ping count'
        );
    END IF;

    -- Check cron job failures (last 7 days)
    SELECT COUNT(*) INTO failed_cron_jobs
    FROM public.cron_job_logs
    WHERE status = 'failed'
    AND started_at > NOW() - INTERVAL '7 days';

    IF failed_cron_jobs > 5 THEN
        alert_array := alert_array || jsonb_build_object(
            'type', 'cron_failures',
            'severity', 'error',
            'count', failed_cron_jobs,
            'message', 'Multiple cron job failures detected'
        );
    END IF;

    result := jsonb_build_object(
        'alerts', alert_array,
        'total_alerts', jsonb_array_length(alert_array),
        'checked_at', NOW()
    );

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Get notification delivery statistics
CREATE OR REPLACE FUNCTION public.admin_get_notification_stats(hours_back INT DEFAULT 24)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
    total_sent INT;
    total_failed INT;
    delivery_rate DECIMAL;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    -- Get counts
    SELECT
        COUNT(*) FILTER (WHERE delivery_status IN ('sent', 'failed')) as sent,
        COUNT(*) FILTER (WHERE delivery_status = 'failed') as failed
    INTO total_sent, total_failed
    FROM public.notifications
    WHERE sent_at > NOW() - (hours_back || ' hours')::INTERVAL;

    -- Calculate delivery rate
    IF total_sent > 0 THEN
        delivery_rate := ((total_sent - total_failed)::DECIMAL / total_sent::DECIMAL) * 100;
    ELSE
        delivery_rate := 100.0;
    END IF;

    result := jsonb_build_object(
        'total_sent', total_sent,
        'total_failed', total_failed,
        'total_delivered', total_sent - total_failed,
        'delivery_rate_percent', ROUND(delivery_rate, 2),
        'period_hours', hours_back,
        'by_type', (
            SELECT COALESCE(jsonb_object_agg(type, count), '{}'::jsonb)
            FROM (
                SELECT
                    type,
                    COUNT(*) as count
                FROM public.notifications
                WHERE sent_at > NOW() - (hours_back || ' hours')::INTERVAL
                GROUP BY type
            ) type_counts
        )
    );

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Get cron job status and history
CREATE OR REPLACE FUNCTION public.admin_get_cron_job_status()
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT COALESCE(jsonb_agg(job_data ORDER BY last_run DESC), '[]'::jsonb)
    INTO result
    FROM (
        SELECT DISTINCT ON (job_name)
            jsonb_build_object(
                'job_name', job_name,
                'status', status,
                'last_run', started_at,
                'duration_seconds', EXTRACT(EPOCH FROM (completed_at - started_at)),
                'error_message', error_message
            ) as job_data
        FROM public.cron_job_logs
        ORDER BY job_name, started_at DESC
    ) jobs;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- GRANT PERMISSIONS
-- ============================================

GRANT EXECUTE ON FUNCTION public.admin_get_user_growth(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_subscription_details(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_extend_subscription(UUID, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_payment_history(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_edge_function_stats(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_check_error_thresholds() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_notification_stats(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_cron_job_status() TO authenticated;

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON FUNCTION public.admin_get_user_growth(INT) IS 'US-11.1: Get user growth chart data over time';
COMMENT ON FUNCTION public.admin_get_subscription_details(UUID) IS 'US-11.2: Get detailed subscription info for a user';
COMMENT ON FUNCTION public.admin_extend_subscription(UUID, INT, TEXT) IS 'US-11.2: Manually extend subscription';
COMMENT ON FUNCTION public.admin_get_payment_history(UUID, INT) IS 'US-11.2: Get payment transaction history';
COMMENT ON FUNCTION public.admin_get_edge_function_stats(INT) IS 'US-11.3: Get edge function execution statistics';
COMMENT ON FUNCTION public.admin_check_error_thresholds() IS 'US-11.3: Check error rates against thresholds';
COMMENT ON FUNCTION public.admin_get_notification_stats(INT) IS 'US-11.3: Get push notification delivery statistics';
COMMENT ON FUNCTION public.admin_get_cron_job_status() IS 'US-11.3: Get cron job execution status';
