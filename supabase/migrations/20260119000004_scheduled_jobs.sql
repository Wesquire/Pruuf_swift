-- Scheduled Jobs for PRUUF iOS App
-- Uses pg_cron extension for automated tasks
-- Note: pg_cron is enabled in Supabase Pro+ plans

-- ============================================
-- ENABLE PG_CRON EXTENSION
-- ============================================

-- Enable the pg_cron extension (if not already enabled)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Grant usage to postgres role
GRANT USAGE ON SCHEMA cron TO postgres;

-- ============================================
-- SCHEDULED JOB FUNCTIONS
-- ============================================

-- Function: Check for missed pings and notify connections
-- Runs every 5 minutes to catch missed pings promptly
CREATE OR REPLACE FUNCTION public.check_and_notify_missed_pings()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_record RECORD;
    current_utc TIMESTAMP WITH TIME ZONE := NOW();
    user_local_time TIME;
    ping_exists BOOLEAN;
BEGIN
    -- Loop through all active users with ping schedules
    FOR user_record IN
        SELECT
            u.id AS user_id,
            u.timezone,
            ps.ping_window_end,
            ps.grace_period_minutes
        FROM users u
        INNER JOIN ping_schedules ps ON ps.user_id = u.id
        WHERE ps.is_active = true
        AND u.status = 'active'
    LOOP
        -- Calculate user's local time
        user_local_time := (current_utc AT TIME ZONE COALESCE(user_record.timezone, 'UTC'))::TIME;

        -- Check if we're past the ping window + grace period
        IF user_local_time > (user_record.ping_window_end + (user_record.grace_period_minutes || ' minutes')::INTERVAL)::TIME THEN
            -- Check if user has pinged today
            SELECT EXISTS (
                SELECT 1 FROM pings
                WHERE user_id = user_record.user_id
                AND ping_date = CURRENT_DATE
                AND status = 'completed'
            ) INTO ping_exists;

            -- If no ping today, record as missed and notify
            IF NOT ping_exists THEN
                -- Insert missed ping record (if not already recorded)
                INSERT INTO pings (user_id, status, ping_date, created_at)
                VALUES (user_record.user_id, 'missed', CURRENT_DATE, current_utc)
                ON CONFLICT (user_id, ping_date) DO NOTHING;

                -- Create notifications for connected users
                INSERT INTO notifications (user_id, title, body, type, related_user_id, read, created_at)
                SELECT
                    CASE
                        WHEN c.user_id = user_record.user_id THEN c.connected_user_id
                        ELSE c.user_id
                    END,
                    'Missed Ping Alert',
                    (SELECT display_name FROM users WHERE id = user_record.user_id) || ' has not checked in today.',
                    'ping_missed',
                    user_record.user_id,
                    false,
                    current_utc
                FROM connections c
                WHERE c.status = 'accepted'
                AND (c.user_id = user_record.user_id OR c.connected_user_id = user_record.user_id);
            END IF;
        END IF;
    END LOOP;
END;
$$;

-- Function: Send ping reminders to users in their ping window
-- Runs every 15 minutes during typical waking hours
CREATE OR REPLACE FUNCTION public.send_ping_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_record RECORD;
    current_utc TIMESTAMP WITH TIME ZONE := NOW();
    user_local_time TIME;
    ping_exists BOOLEAN;
    reminder_exists BOOLEAN;
BEGIN
    FOR user_record IN
        SELECT
            u.id AS user_id,
            u.timezone,
            ps.ping_window_start,
            ps.ping_window_end
        FROM users u
        INNER JOIN ping_schedules ps ON ps.user_id = u.id
        WHERE ps.is_active = true
        AND u.status = 'active'
    LOOP
        user_local_time := (current_utc AT TIME ZONE COALESCE(user_record.timezone, 'UTC'))::TIME;

        -- Check if user is in their ping window
        IF user_local_time >= user_record.ping_window_start
           AND user_local_time <= user_record.ping_window_end THEN

            -- Check if user has already pinged today
            SELECT EXISTS (
                SELECT 1 FROM pings
                WHERE user_id = user_record.user_id
                AND ping_date = CURRENT_DATE
            ) INTO ping_exists;

            -- Check if reminder was already sent in the last hour
            SELECT EXISTS (
                SELECT 1 FROM notifications
                WHERE user_id = user_record.user_id
                AND type = 'ping_reminder'
                AND created_at > current_utc - INTERVAL '1 hour'
            ) INTO reminder_exists;

            -- Send reminder if no ping and no recent reminder
            IF NOT ping_exists AND NOT reminder_exists THEN
                INSERT INTO notifications (user_id, title, body, type, read, created_at)
                VALUES (
                    user_record.user_id,
                    'Ping Reminder',
                    'Don''t forget to check in today!',
                    'ping_reminder',
                    false,
                    current_utc
                );
            END IF;
        END IF;
    END LOOP;
END;
$$;

-- Function: Check subscription status and handle expirations
-- Runs daily at 6 AM UTC
CREATE OR REPLACE FUNCTION public.check_subscription_expirations()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    sub_record RECORD;
    current_utc TIMESTAMP WITH TIME ZONE := NOW();
BEGIN
    -- Find subscriptions that have expired
    FOR sub_record IN
        SELECT s.id, s.user_id, s.tier, s.expires_at
        FROM subscriptions s
        WHERE s.status = 'active'
        AND s.expires_at < current_utc
    LOOP
        -- Update subscription status to expired
        UPDATE subscriptions
        SET status = 'expired', updated_at = current_utc
        WHERE id = sub_record.id;

        -- Revert user to free tier
        UPDATE users
        SET subscription_tier = 'free'
        WHERE id = sub_record.user_id;

        -- Notify user about expiration
        INSERT INTO notifications (user_id, title, body, type, read, created_at)
        VALUES (
            sub_record.user_id,
            'Subscription Expired',
            'Your ' || sub_record.tier || ' subscription has expired. Renew to continue enjoying premium features.',
            'subscription_expired',
            false,
            current_utc
        );
    END LOOP;

    -- Find subscriptions expiring in 3 days (warning notification)
    FOR sub_record IN
        SELECT s.id, s.user_id, s.tier, s.expires_at
        FROM subscriptions s
        WHERE s.status = 'active'
        AND s.expires_at BETWEEN current_utc AND current_utc + INTERVAL '3 days'
        AND NOT EXISTS (
            SELECT 1 FROM notifications
            WHERE user_id = s.user_id
            AND type = 'subscription_expiring_soon'
            AND created_at > current_utc - INTERVAL '3 days'
        )
    LOOP
        INSERT INTO notifications (user_id, title, body, type, read, created_at)
        VALUES (
            sub_record.user_id,
            'Subscription Expiring Soon',
            'Your ' || sub_record.tier || ' subscription expires in 3 days. Renew now to avoid interruption.',
            'subscription_expiring_soon',
            false,
            current_utc
        );
    END LOOP;
END;
$$;

-- Function: Clean up old notifications (retention policy)
-- Runs daily to remove notifications older than 30 days
CREATE OR REPLACE FUNCTION public.cleanup_old_notifications()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM notifications
    WHERE read = true
    AND created_at < NOW() - INTERVAL '30 days';

    -- Keep unread notifications for 90 days
    DELETE FROM notifications
    WHERE read = false
    AND created_at < NOW() - INTERVAL '90 days';
END;
$$;

-- ============================================
-- SCHEDULE THE JOBS (pg_cron)
-- ============================================

-- Check for missed pings every 5 minutes
SELECT cron.schedule(
    'check-missed-pings',
    '*/5 * * * *',
    'SELECT public.check_and_notify_missed_pings()'
);

-- Send ping reminders every 15 minutes
SELECT cron.schedule(
    'send-ping-reminders',
    '*/15 * * * *',
    'SELECT public.send_ping_reminders()'
);

-- Check subscription expirations daily at 6 AM UTC
SELECT cron.schedule(
    'check-subscription-expirations',
    '0 6 * * *',
    'SELECT public.check_subscription_expirations()'
);

-- Cleanup old notifications daily at 3 AM UTC
SELECT cron.schedule(
    'cleanup-old-notifications',
    '0 3 * * *',
    'SELECT public.cleanup_old_notifications()'
);

-- ============================================
-- VIEW SCHEDULED JOBS
-- ============================================

-- Query to view all scheduled jobs:
-- SELECT * FROM cron.job;

-- Query to view job run history:
-- SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 50;
