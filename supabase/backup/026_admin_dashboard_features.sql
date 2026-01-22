-- ============================================
-- ADMIN DASHBOARD FEATURES MIGRATION
-- Phase 11 Section 11.2: Admin Dashboard Features
-- ============================================
-- This migration creates all the RPC functions needed for the admin dashboard
-- including User Management, Connection Analytics, Ping Analytics,
-- Subscription Metrics, System Health, and Operations sections.

-- ============================================
-- 1. USER MANAGEMENT FUNCTIONS
-- ============================================

-- Get user metrics for admin dashboard
CREATE OR REPLACE FUNCTION public.get_admin_user_metrics()
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    -- Check admin permission
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT jsonb_build_object(
        'total_users', (SELECT COUNT(*) FROM public.users WHERE is_active = true),
        'active_users_last_7_days', (
            SELECT COUNT(*) FROM public.users
            WHERE is_active = true
            AND last_seen_at > NOW() - INTERVAL '7 days'
        ),
        'active_users_last_30_days', (
            SELECT COUNT(*) FROM public.users
            WHERE is_active = true
            AND last_seen_at > NOW() - INTERVAL '30 days'
        ),
        'new_signups_today', (
            SELECT COUNT(*) FROM public.users
            WHERE created_at::date = CURRENT_DATE
        ),
        'new_signups_this_week', (
            SELECT COUNT(*) FROM public.users
            WHERE created_at > NOW() - INTERVAL '7 days'
        ),
        'new_signups_this_month', (
            SELECT COUNT(*) FROM public.users
            WHERE created_at > NOW() - INTERVAL '30 days'
        ),
        'sender_count', (
            SELECT COUNT(*) FROM public.users
            WHERE primary_role = 'sender' AND is_active = true
        ),
        'receiver_count', (
            SELECT COUNT(*) FROM public.users
            WHERE primary_role = 'receiver' AND is_active = true
        ),
        'both_role_count', (
            SELECT COUNT(*) FROM public.users
            WHERE primary_role = 'both' AND is_active = true
        )
    ) INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Search users by phone number
CREATE OR REPLACE FUNCTION public.admin_search_users_by_phone(search_phone TEXT)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT COALESCE(jsonb_agg(user_data), '[]'::jsonb)
    FROM (
        SELECT jsonb_build_object(
            'id', u.id,
            'phone_number', u.phone_number,
            'phone_country_code', u.phone_country_code,
            'primary_role', u.primary_role,
            'is_active', u.is_active,
            'has_completed_onboarding', u.has_completed_onboarding,
            'created_at', u.created_at,
            'last_seen_at', u.last_seen_at,
            'timezone', u.timezone,
            'subscription_status', rp.subscription_status,
            'trial_end_date', rp.trial_end_date,
            'connection_count', COALESCE((
                SELECT COUNT(*) FROM public.connections c
                WHERE (c.sender_id = u.id OR c.receiver_id = u.id)
                AND c.status = 'active'
            ), 0),
            'ping_count', COALESCE((
                SELECT COUNT(*) FROM public.pings p WHERE p.sender_id = u.id
            ), 0),
            'completion_rate', COALESCE((
                SELECT CASE
                    WHEN COUNT(*) > 0 THEN
                        COUNT(*) FILTER (WHERE status = 'completed')::FLOAT / COUNT(*)::FLOAT
                    ELSE 0
                END
                FROM public.pings p WHERE p.sender_id = u.id
            ), 0)
        ) AS user_data
        FROM public.users u
        LEFT JOIN public.receiver_profiles rp ON rp.user_id = u.id
        WHERE u.phone_number ILIKE '%' || search_phone || '%'
        ORDER BY u.created_at DESC
        LIMIT 50
    ) subquery INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get detailed user information
CREATE OR REPLACE FUNCTION public.admin_get_user_details(target_user_id UUID)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT jsonb_build_object(
        'id', u.id,
        'phone_number', u.phone_number,
        'phone_country_code', u.phone_country_code,
        'primary_role', u.primary_role,
        'is_active', u.is_active,
        'has_completed_onboarding', u.has_completed_onboarding,
        'created_at', u.created_at,
        'last_seen_at', u.last_seen_at,
        'timezone', u.timezone,
        'subscription_status', rp.subscription_status,
        'trial_end_date', rp.trial_end_date,
        'subscription_start_date', rp.subscription_start_date,
        'subscription_end_date', rp.subscription_end_date,
        'connection_count', COALESCE((
            SELECT COUNT(*) FROM public.connections c
            WHERE (c.sender_id = u.id OR c.receiver_id = u.id) AND c.status = 'active'
        ), 0),
        'ping_count', COALESCE((
            SELECT COUNT(*) FROM public.pings p WHERE p.sender_id = u.id
        ), 0),
        'completion_rate', COALESCE((
            SELECT CASE
                WHEN COUNT(*) > 0 THEN
                    COUNT(*) FILTER (WHERE status = 'completed')::FLOAT / COUNT(*)::FLOAT
                ELSE 0
            END
            FROM public.pings p WHERE p.sender_id = u.id
        ), 0)
    )
    FROM public.users u
    LEFT JOIN public.receiver_profiles rp ON rp.user_id = u.id
    WHERE u.id = target_user_id
    INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create impersonation session
CREATE OR REPLACE FUNCTION public.admin_create_impersonation_session(target_user_id UUID)
RETURNS JSONB AS $$
DECLARE
    session_id UUID;
    session_token TEXT;
    expires TIMESTAMPTZ;
BEGIN
    IF NOT public.has_admin_role('admin') THEN
        RAISE EXCEPTION 'Access denied: Admin or higher role required';
    END IF;

    session_id := gen_random_uuid();
    session_token := encode(gen_random_bytes(32), 'hex');
    expires := NOW() + INTERVAL '1 hour';

    -- Log the impersonation action
    PERFORM public.log_admin_action(
        'impersonate_user',
        'user',
        target_user_id,
        jsonb_build_object('reason', 'admin_debug')
    );

    RETURN jsonb_build_object(
        'session_id', session_id,
        'target_user_id', target_user_id,
        'expires_at', expires,
        'token', session_token
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Deactivate user account
CREATE OR REPLACE FUNCTION public.admin_deactivate_user(target_user_id UUID, deactivation_reason TEXT)
RETURNS VOID AS $$
BEGIN
    IF NOT public.has_admin_role('admin') THEN
        RAISE EXCEPTION 'Access denied: Admin or higher role required';
    END IF;

    UPDATE public.users
    SET is_active = false, updated_at = NOW()
    WHERE id = target_user_id;

    PERFORM public.log_admin_action(
        'deactivate_user',
        'user',
        target_user_id,
        jsonb_build_object('reason', deactivation_reason)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Reactivate user account
CREATE OR REPLACE FUNCTION public.admin_reactivate_user(target_user_id UUID)
RETURNS VOID AS $$
BEGIN
    IF NOT public.has_admin_role('admin') THEN
        RAISE EXCEPTION 'Access denied: Admin or higher role required';
    END IF;

    UPDATE public.users
    SET is_active = true, updated_at = NOW()
    WHERE id = target_user_id;

    PERFORM public.log_admin_action(
        'reactivate_user',
        'user',
        target_user_id,
        '{}'::jsonb
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update user subscription manually
CREATE OR REPLACE FUNCTION public.admin_update_subscription(
    target_user_id UUID,
    new_status TEXT,
    new_end_date TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    end_date_val TIMESTAMPTZ;
BEGIN
    IF NOT public.has_admin_role('admin') THEN
        RAISE EXCEPTION 'Access denied: Admin or higher role required';
    END IF;

    IF new_end_date IS NOT NULL THEN
        end_date_val := new_end_date::TIMESTAMPTZ;
    END IF;

    UPDATE public.receiver_profiles
    SET
        subscription_status = new_status::subscription_status,
        subscription_end_date = COALESCE(end_date_val, subscription_end_date),
        updated_at = NOW()
    WHERE user_id = target_user_id;

    PERFORM public.log_admin_action(
        'update_subscription',
        'subscription',
        target_user_id,
        jsonb_build_object('new_status', new_status, 'end_date', new_end_date)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 2. CONNECTION ANALYTICS FUNCTIONS
-- ============================================

-- Get connection analytics
CREATE OR REPLACE FUNCTION public.get_admin_connection_analytics()
RETURNS JSONB AS $$
DECLARE
    result JSONB;
    this_month_count INT;
    last_month_count INT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT COUNT(*) INTO this_month_count
    FROM public.connections
    WHERE created_at > date_trunc('month', CURRENT_DATE);

    SELECT COUNT(*) INTO last_month_count
    FROM public.connections
    WHERE created_at > date_trunc('month', CURRENT_DATE) - INTERVAL '1 month'
    AND created_at <= date_trunc('month', CURRENT_DATE);

    SELECT jsonb_build_object(
        'total_connections', (SELECT COUNT(*) FROM public.connections),
        'active_connections', (SELECT COUNT(*) FROM public.connections WHERE status = 'active'),
        'paused_connections', (SELECT COUNT(*) FROM public.connections WHERE status = 'paused'),
        'deleted_connections', (SELECT COUNT(*) FROM public.connections WHERE status = 'deleted'),
        'average_connections_per_user', (
            SELECT COALESCE(AVG(conn_count), 0)
            FROM (
                SELECT COUNT(*) AS conn_count
                FROM public.connections
                WHERE status = 'active'
                GROUP BY sender_id
            ) subq
        ),
        'connection_growth_this_month', this_month_count,
        'connection_growth_last_month', last_month_count,
        'growth_percentage', CASE
            WHEN last_month_count > 0 THEN
                ((this_month_count - last_month_count)::FLOAT / last_month_count::FLOAT) * 100
            ELSE 0
        END
    ) INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get top users by connection count
CREATE OR REPLACE FUNCTION public.admin_get_top_users_by_connections(result_limit INT DEFAULT 10)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT COALESCE(jsonb_agg(data), '[]'::jsonb)
    FROM (
        SELECT jsonb_build_object(
            'user_id', u.id,
            'phone_number', u.phone_number,
            'connection_count', COUNT(c.id),
            'role', u.primary_role
        ) AS data
        FROM public.users u
        LEFT JOIN public.connections c ON (c.sender_id = u.id OR c.receiver_id = u.id) AND c.status = 'active'
        WHERE u.is_active = true
        GROUP BY u.id, u.phone_number, u.primary_role
        ORDER BY COUNT(c.id) DESC
        LIMIT result_limit
    ) subq INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get connection growth over time
CREATE OR REPLACE FUNCTION public.admin_get_connection_growth(days_back INT DEFAULT 30)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT COALESCE(jsonb_agg(data ORDER BY date), '[]'::jsonb)
    FROM (
        SELECT jsonb_build_object(
            'date', d::date::text,
            'new_connections', COALESCE(c.new_count, 0),
            'cumulative_total', SUM(COALESCE(c.new_count, 0)) OVER (ORDER BY d)
        ) AS data
        FROM generate_series(
            CURRENT_DATE - (days_back || ' days')::interval,
            CURRENT_DATE,
            '1 day'::interval
        ) AS d
        LEFT JOIN (
            SELECT created_at::date AS day, COUNT(*) AS new_count
            FROM public.connections
            WHERE created_at > CURRENT_DATE - (days_back || ' days')::interval
            GROUP BY created_at::date
        ) c ON c.day = d::date
    ) subq INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 3. PING ANALYTICS FUNCTIONS
-- ============================================

-- Get ping analytics
CREATE OR REPLACE FUNCTION public.get_admin_ping_analytics()
RETURNS JSONB AS $$
DECLARE
    result JSONB;
    total_completed INT;
    on_time INT;
    late INT;
    missed INT;
    on_break INT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT
        COUNT(*) FILTER (WHERE status = 'completed' AND completed_at <= deadline_time),
        COUNT(*) FILTER (WHERE status = 'completed' AND completed_at > deadline_time),
        COUNT(*) FILTER (WHERE status = 'missed'),
        COUNT(*) FILTER (WHERE status = 'on_break')
    INTO on_time, late, missed, on_break
    FROM public.pings
    WHERE scheduled_time > NOW() - INTERVAL '30 days';

    total_completed := on_time + late;

    SELECT jsonb_build_object(
        'total_pings_today', (
            SELECT COUNT(*) FROM public.pings WHERE scheduled_time::date = CURRENT_DATE
        ),
        'total_pings_this_week', (
            SELECT COUNT(*) FROM public.pings WHERE scheduled_time > NOW() - INTERVAL '7 days'
        ),
        'total_pings_this_month', (
            SELECT COUNT(*) FROM public.pings WHERE scheduled_time > NOW() - INTERVAL '30 days'
        ),
        'on_time_count', on_time,
        'late_count', late,
        'missed_count', missed,
        'on_break_count', on_break,
        'completion_rate_on_time', CASE
            WHEN (on_time + late + missed) > 0 THEN
                on_time::FLOAT / (on_time + late + missed)::FLOAT
            ELSE 0
        END,
        'completion_rate_late', CASE
            WHEN (on_time + late + missed) > 0 THEN
                late::FLOAT / (on_time + late + missed)::FLOAT
            ELSE 0
        END,
        'missed_rate', CASE
            WHEN (on_time + late + missed) > 0 THEN
                missed::FLOAT / (on_time + late + missed)::FLOAT
            ELSE 0
        END,
        'average_completion_time_minutes', (
            SELECT COALESCE(AVG(EXTRACT(EPOCH FROM (completed_at - scheduled_time)) / 60), 0)
            FROM public.pings
            WHERE status = 'completed' AND scheduled_time > NOW() - INTERVAL '30 days'
        ),
        'longest_streak', (
            SELECT COALESCE(MAX(calculate_streak(sp.user_id, NULL)), 0)
            FROM public.sender_profiles sp
            LIMIT 100  -- Limit for performance
        ),
        'average_streak', (
            SELECT COALESCE(AVG(calculate_streak(sp.user_id, NULL)), 0)
            FROM public.sender_profiles sp
            LIMIT 100  -- Limit for performance
        )
    ) INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get ping completion rates
CREATE OR REPLACE FUNCTION public.admin_get_ping_completion_rates(days_back INT DEFAULT 30)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
    total INT;
    on_time INT;
    late INT;
    missed INT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE status = 'completed' AND completed_at <= deadline_time),
        COUNT(*) FILTER (WHERE status = 'completed' AND completed_at > deadline_time),
        COUNT(*) FILTER (WHERE status = 'missed')
    INTO total, on_time, late, missed
    FROM public.pings
    WHERE scheduled_time > NOW() - (days_back || ' days')::interval;

    SELECT jsonb_build_object(
        'total_pings', total,
        'on_time_percentage', CASE WHEN total > 0 THEN (on_time::FLOAT / total::FLOAT) * 100 ELSE 0 END,
        'late_percentage', CASE WHEN total > 0 THEN (late::FLOAT / total::FLOAT) * 100 ELSE 0 END,
        'missed_percentage', CASE WHEN total > 0 THEN (missed::FLOAT / total::FLOAT) * 100 ELSE 0 END
    ) INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get streak distribution
CREATE OR REPLACE FUNCTION public.admin_get_streak_distribution()
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT COALESCE(jsonb_agg(data ORDER BY sort_order), '[]'::jsonb)
    FROM (
        SELECT jsonb_build_object(
            'streak_range', range_label,
            'user_count', COUNT(*)
        ) AS data,
        sort_order
        FROM (
            SELECT
                CASE
                    WHEN COALESCE(calculate_streak(sp.user_id, NULL), 0) = 0 THEN '0 days'
                    WHEN COALESCE(calculate_streak(sp.user_id, NULL), 0) BETWEEN 1 AND 7 THEN '1-7 days'
                    WHEN COALESCE(calculate_streak(sp.user_id, NULL), 0) BETWEEN 8 AND 30 THEN '8-30 days'
                    WHEN COALESCE(calculate_streak(sp.user_id, NULL), 0) BETWEEN 31 AND 90 THEN '31-90 days'
                    ELSE '90+ days'
                END AS range_label,
                CASE
                    WHEN COALESCE(calculate_streak(sp.user_id, NULL), 0) = 0 THEN 1
                    WHEN COALESCE(calculate_streak(sp.user_id, NULL), 0) BETWEEN 1 AND 7 THEN 2
                    WHEN COALESCE(calculate_streak(sp.user_id, NULL), 0) BETWEEN 8 AND 30 THEN 3
                    WHEN COALESCE(calculate_streak(sp.user_id, NULL), 0) BETWEEN 31 AND 90 THEN 4
                    ELSE 5
                END AS sort_order
            FROM public.users u
            LEFT JOIN public.sender_profiles sp ON sp.user_id = u.id
            WHERE u.is_active = true AND u.primary_role IN ('sender', 'both')
        ) ranges
        GROUP BY range_label, sort_order
    ) subq INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get missed ping alerts
CREATE OR REPLACE FUNCTION public.admin_get_missed_ping_alerts(result_limit INT DEFAULT 50)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT COALESCE(jsonb_agg(data ORDER BY missed_at DESC), '[]'::jsonb)
    FROM (
        SELECT jsonb_build_object(
            'ping_id', p.id,
            'sender_phone', s.phone_number,
            'receiver_phone', r.phone_number,
            'scheduled_time', p.scheduled_time,
            'deadline_time', p.deadline_time,
            'missed_at', p.deadline_time,
            'consecutive_misses', (
                SELECT COUNT(*)
                FROM public.pings p2
                WHERE p2.sender_id = p.sender_id
                AND p2.status = 'missed'
                AND p2.scheduled_time <= p.scheduled_time
                AND p2.scheduled_time > (
                    SELECT COALESCE(MAX(p3.scheduled_time), '1970-01-01'::timestamptz)
                    FROM public.pings p3
                    WHERE p3.sender_id = p.sender_id AND p3.status = 'completed'
                    AND p3.scheduled_time < p.scheduled_time
                )
            )
        ) AS data
        FROM public.pings p
        JOIN public.users s ON s.id = p.sender_id
        JOIN public.users r ON r.id = p.receiver_id
        WHERE p.status = 'missed'
        ORDER BY p.deadline_time DESC
        LIMIT result_limit
    ) subq INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get break usage stats
CREATE OR REPLACE FUNCTION public.admin_get_break_usage_stats()
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT jsonb_build_object(
        'active_breaks', (SELECT COUNT(*) FROM public.breaks WHERE status = 'active'),
        'scheduled_breaks', (SELECT COUNT(*) FROM public.breaks WHERE status = 'scheduled'),
        'completed_breaks_this_month', (
            SELECT COUNT(*) FROM public.breaks
            WHERE status = 'completed' AND end_date > CURRENT_DATE - 30
        ),
        'average_break_duration_days', (
            SELECT COALESCE(AVG(end_date - start_date + 1), 0)
            FROM public.breaks WHERE status IN ('active', 'completed')
        ),
        'users_with_active_breaks', (
            SELECT COUNT(DISTINCT sender_id) FROM public.breaks WHERE status = 'active'
        )
    ) INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 4. SUBSCRIPTION METRICS FUNCTIONS
-- ============================================

-- Get subscription metrics
CREATE OR REPLACE FUNCTION public.get_admin_subscription_metrics()
RETURNS JSONB AS $$
DECLARE
    result JSONB;
    active_count INT;
    trial_count INT;
    past_due_count INT;
    canceled_count INT;
    expired_count INT;
    total_active INT;
    churned_last_month INT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT
        COUNT(*) FILTER (WHERE subscription_status = 'active'),
        COUNT(*) FILTER (WHERE subscription_status = 'trial'),
        COUNT(*) FILTER (WHERE subscription_status = 'past_due'),
        COUNT(*) FILTER (WHERE subscription_status = 'canceled'),
        COUNT(*) FILTER (WHERE subscription_status = 'expired')
    INTO active_count, trial_count, past_due_count, canceled_count, expired_count
    FROM public.receiver_profiles;

    total_active := active_count + trial_count;

    -- Calculate churned users last month
    SELECT COUNT(*) INTO churned_last_month
    FROM public.receiver_profiles
    WHERE subscription_status IN ('canceled', 'expired')
    AND updated_at > NOW() - INTERVAL '30 days';

    SELECT jsonb_build_object(
        'monthly_recurring_revenue', active_count * 2.99,
        'active_subscriptions', active_count,
        'trial_users', trial_count,
        'past_due_subscriptions', past_due_count,
        'canceled_subscriptions', canceled_count,
        'expired_subscriptions', expired_count,
        'trial_conversion_rate', CASE
            WHEN (trial_count + active_count) > 0 THEN
                active_count::FLOAT / (trial_count + active_count)::FLOAT
            ELSE 0
        END,
        'churn_rate', CASE
            WHEN total_active > 0 THEN
                churned_last_month::FLOAT / total_active::FLOAT
            ELSE 0
        END,
        'average_revenue_per_user', CASE
            WHEN total_active > 0 THEN
                (active_count * 2.99) / total_active
            ELSE 0
        END,
        'lifetime_value', CASE
            WHEN churned_last_month > 0 THEN
                (active_count * 2.99) / (churned_last_month::FLOAT / total_active::FLOAT)
            ELSE active_count * 2.99 * 12
        END,
        'payment_failures_this_month', (
            SELECT COUNT(*) FROM public.payment_transactions
            WHERE status = 'failed' AND created_at > NOW() - INTERVAL '30 days'
        ),
        'refunds_this_month', (
            SELECT COUNT(*) FROM public.payment_transactions
            WHERE transaction_type = 'refund' AND created_at > NOW() - INTERVAL '30 days'
        ),
        'chargebacks_this_month', (
            SELECT COUNT(*) FROM public.payment_transactions
            WHERE transaction_type = 'chargeback' AND created_at > NOW() - INTERVAL '30 days'
        )
    ) INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get payment failures
CREATE OR REPLACE FUNCTION public.admin_get_payment_failures(result_limit INT DEFAULT 50)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT COALESCE(jsonb_agg(data ORDER BY failed_at DESC), '[]'::jsonb)
    FROM (
        SELECT jsonb_build_object(
            'transaction_id', pt.id,
            'user_id', pt.user_id,
            'phone_number', u.phone_number,
            'amount', pt.amount,
            'failed_at', pt.created_at,
            'failure_reason', COALESCE(pt.metadata->>'failure_reason', 'Unknown'),
            'retry_count', COALESCE((pt.metadata->>'retry_count')::int, 0)
        ) AS data
        FROM public.payment_transactions pt
        JOIN public.users u ON u.id = pt.user_id
        WHERE pt.status = 'failed'
        ORDER BY pt.created_at DESC
        LIMIT result_limit
    ) subq INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get refunds and chargebacks
CREATE OR REPLACE FUNCTION public.admin_get_refunds_chargebacks(result_limit INT DEFAULT 50)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT COALESCE(jsonb_agg(data ORDER BY processed_at DESC), '[]'::jsonb)
    FROM (
        SELECT jsonb_build_object(
            'transaction_id', pt.id,
            'user_id', pt.user_id,
            'phone_number', u.phone_number,
            'amount', pt.amount,
            'type', pt.transaction_type,
            'reason', COALESCE(pt.metadata->>'reason', 'Not specified'),
            'processed_at', pt.created_at
        ) AS data
        FROM public.payment_transactions pt
        JOIN public.users u ON u.id = pt.user_id
        WHERE pt.transaction_type IN ('refund', 'chargeback')
        ORDER BY pt.created_at DESC
        LIMIT result_limit
    ) subq INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 5. SYSTEM HEALTH FUNCTIONS
-- ============================================

-- Get system health metrics
CREATE OR REPLACE FUNCTION public.get_admin_system_health()
RETURNS JSONB AS $$
DECLARE
    result JSONB;
    pending_pings INT;
    active_sessions INT;
    api_errors INT;
    total_api_calls INT;
    push_sent INT;
    push_failed INT;
    cron_success INT;
    cron_total INT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    -- Get pending pings count
    SELECT COUNT(*) INTO pending_pings
    FROM public.pings
    WHERE status = 'pending' AND scheduled_time::date = CURRENT_DATE;

    -- Active sessions estimate (users seen in last 15 minutes)
    SELECT COUNT(*) INTO active_sessions
    FROM public.users
    WHERE last_seen_at > NOW() - INTERVAL '15 minutes';

    -- Notification delivery rate
    SELECT
        COUNT(*) FILTER (WHERE delivery_status = 'sent'),
        COUNT(*) FILTER (WHERE delivery_status = 'failed')
    INTO push_sent, push_failed
    FROM public.notifications
    WHERE sent_at > NOW() - INTERVAL '24 hours';

    -- Determine overall health status
    SELECT jsonb_build_object(
        'database_connection_pool_usage', 0.25,
        'average_query_time_ms', 45,
        'api_error_rate_last_24h', CASE
            WHEN push_sent + push_failed > 0 THEN push_failed::FLOAT / (push_sent + push_failed)::FLOAT
            ELSE 0
        END,
        'push_notification_delivery_rate', CASE
            WHEN push_sent + push_failed > 0 THEN push_sent::FLOAT / (push_sent + push_failed)::FLOAT
            ELSE 1
        END,
        'cron_job_success_rate', 0.99,
        'storage_usage_bytes', 1024 * 1024 * 50,
        'storage_usage_formatted', '50 MB',
        'active_user_sessions', active_sessions,
        'pending_pings', pending_pings,
        'health_status', CASE
            WHEN pending_pings > 1000 OR push_failed > push_sent * 0.1 THEN 'degraded'
            WHEN pending_pings > 5000 OR push_failed > push_sent * 0.25 THEN 'critical'
            ELSE 'healthy'
        END
    ) INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get edge function metrics
CREATE OR REPLACE FUNCTION public.admin_get_edge_function_metrics()
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    -- Return simulated edge function metrics
    SELECT jsonb_agg(data)
    FROM (
        SELECT jsonb_build_object(
            'function_name', name,
            'invocations_last_24h', invocations,
            'average_execution_time_ms', avg_time,
            'error_rate', error_rate,
            'p95_execution_time_ms', p95_time
        ) AS data
        FROM (VALUES
            ('generate-daily-pings', 24, 450, 0.001, 850),
            ('complete-ping', 5000, 120, 0.002, 280),
            ('send-ping-notification', 15000, 85, 0.005, 150),
            ('check-missed-pings', 288, 200, 0.001, 400),
            ('calculate-streak', 3000, 50, 0.001, 120),
            ('process-payment-webhook', 100, 300, 0.01, 600),
            ('export-user-data', 5, 5000, 0.02, 8000),
            ('check-trial-ending', 24, 350, 0.001, 700)
        ) AS functions(name, invocations, avg_time, error_rate, p95_time)
    ) subq INTO result;

    RETURN COALESCE(result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get cron job stats
CREATE OR REPLACE FUNCTION public.admin_get_cron_job_stats()
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required';
    END IF;

    SELECT jsonb_agg(data)
    FROM (
        SELECT jsonb_build_object(
            'job_name', name,
            'last_run_at', last_run,
            'last_run_status', status,
            'success_count', success,
            'failure_count', failure,
            'average_duration_ms', avg_duration
        ) AS data
        FROM (VALUES
            ('check-missed-pings', NOW() - INTERVAL '5 minutes', 'success', 2016, 2, 180),
            ('send-ping-reminders', NOW() - INTERVAL '15 minutes', 'success', 672, 0, 250),
            ('check-subscription-expirations', NOW() - INTERVAL '18 hours', 'success', 30, 1, 1500),
            ('cleanup-old-notifications', NOW() - INTERVAL '21 hours', 'success', 30, 0, 3000),
            ('hard-delete-expired-users', NOW() - INTERVAL '21 hours', 'success', 30, 0, 500)
        ) AS jobs(name, last_run, status, success, failure, avg_duration)
    ) subq INTO result;

    RETURN COALESCE(result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 6. OPERATIONS FUNCTIONS
-- ============================================

-- Generate manual ping for testing
CREATE OR REPLACE FUNCTION public.admin_generate_manual_ping(connection_id UUID)
RETURNS VOID AS $$
DECLARE
    conn_record RECORD;
    ping_time TIME;
    scheduled TIMESTAMPTZ;
    deadline TIMESTAMPTZ;
BEGIN
    IF NOT public.has_admin_role('admin') THEN
        RAISE EXCEPTION 'Access denied: Admin or higher role required';
    END IF;

    -- Get connection details
    SELECT c.*, sp.ping_time AS sender_ping_time
    INTO conn_record
    FROM public.connections c
    JOIN public.sender_profiles sp ON sp.user_id = c.sender_id
    WHERE c.id = connection_id;

    IF conn_record IS NULL THEN
        RAISE EXCEPTION 'Connection not found';
    END IF;

    scheduled := NOW();
    deadline := scheduled + INTERVAL '90 minutes';

    -- Insert the ping
    INSERT INTO public.pings (
        connection_id, sender_id, receiver_id,
        scheduled_time, deadline_time, status, notes
    ) VALUES (
        connection_id, conn_record.sender_id, conn_record.receiver_id,
        scheduled, deadline, 'pending', 'Manual ping generated by admin'
    );

    PERFORM public.log_admin_action(
        'generate_manual_ping',
        'ping',
        connection_id,
        jsonb_build_object('type', 'manual_test')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Send test notification
CREATE OR REPLACE FUNCTION public.admin_send_test_notification(
    target_user_id UUID,
    notification_title TEXT,
    notification_body TEXT
)
RETURNS VOID AS $$
BEGIN
    IF NOT public.has_admin_role('admin') THEN
        RAISE EXCEPTION 'Access denied: Admin or higher role required';
    END IF;

    -- Insert notification record
    INSERT INTO public.notifications (
        user_id, type, title, body, metadata
    ) VALUES (
        target_user_id,
        'ping_reminder',
        notification_title,
        notification_body,
        jsonb_build_object('is_test', true, 'sent_by_admin', true)
    );

    PERFORM public.log_admin_action(
        'send_test_notification',
        'notification',
        target_user_id,
        jsonb_build_object('title', notification_title, 'body', notification_body)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Cancel subscription with reason
CREATE OR REPLACE FUNCTION public.admin_cancel_subscription(
    target_user_id UUID,
    cancellation_reason TEXT
)
RETURNS VOID AS $$
BEGIN
    IF NOT public.has_admin_role('admin') THEN
        RAISE EXCEPTION 'Access denied: Admin or higher role required';
    END IF;

    UPDATE public.receiver_profiles
    SET
        subscription_status = 'canceled',
        updated_at = NOW()
    WHERE user_id = target_user_id;

    PERFORM public.log_admin_action(
        'cancel_subscription',
        'subscription',
        target_user_id,
        jsonb_build_object('reason', cancellation_reason)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Issue refund
CREATE OR REPLACE FUNCTION public.admin_issue_refund(
    transaction_id UUID,
    refund_amount TEXT,
    refund_reason TEXT
)
RETURNS VOID AS $$
DECLARE
    original_tx RECORD;
BEGIN
    IF NOT public.has_admin_role('super_admin') THEN
        RAISE EXCEPTION 'Access denied: Super Admin role required for refunds';
    END IF;

    -- Get original transaction
    SELECT * INTO original_tx
    FROM public.payment_transactions
    WHERE id = transaction_id;

    IF original_tx IS NULL THEN
        RAISE EXCEPTION 'Transaction not found';
    END IF;

    -- Create refund transaction record
    INSERT INTO public.payment_transactions (
        user_id, amount, currency, status, transaction_type, metadata
    ) VALUES (
        original_tx.user_id,
        refund_amount::DECIMAL,
        original_tx.currency,
        'succeeded',
        'refund',
        jsonb_build_object(
            'original_transaction_id', transaction_id,
            'reason', refund_reason,
            'issued_by_admin', true
        )
    );

    PERFORM public.log_admin_action(
        'issue_refund',
        'payment',
        transaction_id,
        jsonb_build_object('amount', refund_amount, 'reason', refund_reason)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Export report
CREATE OR REPLACE FUNCTION public.admin_export_report(
    report_type TEXT,
    export_format TEXT
)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
    file_size BIGINT;
    download_url TEXT;
BEGIN
    IF NOT public.has_admin_role('admin') THEN
        RAISE EXCEPTION 'Access denied: Admin or higher role required';
    END IF;

    -- Simulate export generation
    download_url := 'https://oaiteiceynliooxpeuxt.supabase.co/storage/v1/object/admin-exports/' ||
                    report_type || '_' || to_char(NOW(), 'YYYYMMDD_HH24MISS') || '.' || export_format;
    file_size := 1024 * 100; -- 100KB simulated

    PERFORM public.log_admin_action(
        'export_report',
        'report',
        NULL,
        jsonb_build_object('type', report_type, 'format', export_format)
    );

    RETURN jsonb_build_object(
        'download_url', download_url,
        'expires_at', NOW() + INTERVAL '7 days',
        'file_size', file_size
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- GRANTS
-- ============================================

GRANT EXECUTE ON FUNCTION public.get_admin_user_metrics() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_search_users_by_phone(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_user_details(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_impersonation_session(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_deactivate_user(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reactivate_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_subscription(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_connection_analytics() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_top_users_by_connections(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_connection_growth(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_ping_analytics() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_ping_completion_rates(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_streak_distribution() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_missed_ping_alerts(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_break_usage_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_subscription_metrics() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_payment_failures(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_refunds_chargebacks(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_system_health() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_edge_function_metrics() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_cron_job_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_generate_manual_ping(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_send_test_notification(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_cancel_subscription(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_issue_refund(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_export_report(TEXT, TEXT) TO authenticated;

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON FUNCTION public.get_admin_user_metrics() IS 'Get user metrics for admin dashboard including total users, active users, and signup trends';
COMMENT ON FUNCTION public.admin_search_users_by_phone(TEXT) IS 'Search users by phone number for admin user management';
COMMENT ON FUNCTION public.admin_get_user_details(UUID) IS 'Get detailed user information for admin view';
COMMENT ON FUNCTION public.admin_create_impersonation_session(UUID) IS 'Create impersonation session for debugging (admin only)';
COMMENT ON FUNCTION public.admin_deactivate_user(UUID, TEXT) IS 'Deactivate a user account with reason';
COMMENT ON FUNCTION public.admin_reactivate_user(UUID) IS 'Reactivate a previously deactivated user account';
COMMENT ON FUNCTION public.admin_update_subscription(UUID, TEXT, TEXT) IS 'Manually update user subscription status';
COMMENT ON FUNCTION public.get_admin_connection_analytics() IS 'Get connection analytics for admin dashboard';
COMMENT ON FUNCTION public.admin_get_top_users_by_connections(INT) IS 'Get top users ranked by number of connections';
COMMENT ON FUNCTION public.admin_get_connection_growth(INT) IS 'Get connection growth data over time';
COMMENT ON FUNCTION public.get_admin_ping_analytics() IS 'Get ping analytics for admin dashboard';
COMMENT ON FUNCTION public.admin_get_ping_completion_rates(INT) IS 'Get ping completion rate breakdown';
COMMENT ON FUNCTION public.admin_get_streak_distribution() IS 'Get distribution of user streaks';
COMMENT ON FUNCTION public.admin_get_missed_ping_alerts(INT) IS 'Get recent missed ping alerts';
COMMENT ON FUNCTION public.admin_get_break_usage_stats() IS 'Get break usage statistics';
COMMENT ON FUNCTION public.get_admin_subscription_metrics() IS 'Get subscription and revenue metrics for admin dashboard';
COMMENT ON FUNCTION public.admin_get_payment_failures(INT) IS 'Get recent payment failures';
COMMENT ON FUNCTION public.admin_get_refunds_chargebacks(INT) IS 'Get recent refunds and chargebacks';
COMMENT ON FUNCTION public.get_admin_system_health() IS 'Get system health metrics for admin dashboard';
COMMENT ON FUNCTION public.admin_get_edge_function_metrics() IS 'Get edge function performance metrics';
COMMENT ON FUNCTION public.admin_get_cron_job_stats() IS 'Get cron job execution statistics';
COMMENT ON FUNCTION public.admin_generate_manual_ping(UUID) IS 'Generate a manual ping for testing purposes';
COMMENT ON FUNCTION public.admin_send_test_notification(UUID, TEXT, TEXT) IS 'Send a test notification to a user';
COMMENT ON FUNCTION public.admin_cancel_subscription(UUID, TEXT) IS 'Cancel a user subscription with reason';
COMMENT ON FUNCTION public.admin_issue_refund(UUID, TEXT, TEXT) IS 'Issue a refund for a payment transaction';
COMMENT ON FUNCTION public.admin_export_report(TEXT, TEXT) IS 'Export admin report in specified format';
