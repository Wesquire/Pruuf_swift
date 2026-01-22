-- Migration: 017_trial_period_scheduler.sql
-- Purpose: Add scheduled job for trial period management (Section 9.2)
-- Created: 2026-01-17

-- ============================================================================
-- 1. Create function to invoke check-trial-ending edge function
-- ============================================================================

-- Function to call check-trial-ending edge function via http extension
-- This function is called by pg_cron daily to check for trial expirations
CREATE OR REPLACE FUNCTION public.invoke_check_trial_ending()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    response_status INT;
BEGIN
    -- Call the check-trial-ending edge function via Supabase functions
    -- The edge function handles:
    -- Day 12: "Your trial ends in 3 days"
    -- Day 14: "Your trial ends tomorrow"
    -- Day 15: "Your trial has ended. Subscribe to continue" + expires subscription
    SELECT status INTO response_status
    FROM http_post(
        current_setting('app.settings.supabase_url') || '/functions/v1/check-trial-ending',
        '{}',
        'application/json'
    );

    -- Log the result
    IF response_status != 200 THEN
        RAISE WARNING 'check-trial-ending function returned status: %', response_status;
    END IF;
END;
$$;

-- ============================================================================
-- 2. Alternative: Direct database function for trial expiration
-- (Use this if edge function invocation is not available)
-- ============================================================================

-- Function to expire trials and send notifications directly from database
CREATE OR REPLACE FUNCTION public.check_and_expire_trials()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    profile_record RECORD;
    current_utc TIMESTAMP WITH TIME ZONE := NOW();
    today_str DATE := CURRENT_DATE;
    days_remaining INT;
BEGIN
    -- Find all receiver profiles with trial status
    FOR profile_record IN
        SELECT rp.user_id, rp.trial_end_date, u.notification_preferences
        FROM receiver_profiles rp
        JOIN users u ON u.id = rp.user_id
        WHERE rp.subscription_status = 'trial'
        AND rp.trial_end_date IS NOT NULL
    LOOP
        -- Calculate days remaining
        days_remaining := (profile_record.trial_end_date::DATE - today_str);

        -- Check notification preferences for muted types
        IF profile_record.notification_preferences IS NOT NULL AND
           profile_record.notification_preferences->'mutedNotificationTypes' ? 'trial_ending' THEN
            CONTINUE;
        END IF;

        -- Day 15 (0 days remaining): Trial has ended - expire subscription
        IF days_remaining <= 0 THEN
            -- Update subscription status to expired
            UPDATE receiver_profiles
            SET subscription_status = 'expired',
                updated_at = current_utc
            WHERE user_id = profile_record.user_id;

            -- Insert notification
            INSERT INTO notifications (user_id, type, title, body, metadata, delivery_status, sent_at)
            VALUES (
                profile_record.user_id,
                'trial_ending',
                'Trial Ended',
                'Your trial has ended. Subscribe to continue.',
                jsonb_build_object('days_remaining', 0, 'trial_end_date', profile_record.trial_end_date),
                'pending',
                current_utc
            )
            ON CONFLICT DO NOTHING;

        -- Day 14 (1 day remaining): Trial ends tomorrow
        ELSIF days_remaining = 1 THEN
            -- Check if notification already sent today
            IF NOT EXISTS (
                SELECT 1 FROM notifications
                WHERE user_id = profile_record.user_id
                AND type = 'trial_ending'
                AND sent_at::DATE = today_str
            ) THEN
                INSERT INTO notifications (user_id, type, title, body, metadata, delivery_status, sent_at)
                VALUES (
                    profile_record.user_id,
                    'trial_ending',
                    'Trial Ending Soon',
                    'Your trial ends tomorrow',
                    jsonb_build_object('days_remaining', 1, 'trial_end_date', profile_record.trial_end_date),
                    'pending',
                    current_utc
                );
            END IF;

        -- Day 12 (3 days remaining): Trial ends in 3 days
        ELSIF days_remaining = 3 THEN
            -- Check if notification already sent today
            IF NOT EXISTS (
                SELECT 1 FROM notifications
                WHERE user_id = profile_record.user_id
                AND type = 'trial_ending'
                AND sent_at::DATE = today_str
            ) THEN
                INSERT INTO notifications (user_id, type, title, body, metadata, delivery_status, sent_at)
                VALUES (
                    profile_record.user_id,
                    'trial_ending',
                    'Trial Ending Soon',
                    'Your trial ends in 3 days',
                    jsonb_build_object('days_remaining', 3, 'trial_end_date', profile_record.trial_end_date),
                    'pending',
                    current_utc
                );
            END IF;
        END IF;
    END LOOP;
END;
$$;

-- ============================================================================
-- 3. Schedule the trial expiration check
-- ============================================================================

-- Schedule check-and-expire-trials to run daily at 7 AM UTC
-- This handles trial notifications at 3 days, 1 day, and expiration
SELECT cron.schedule(
    'check-trial-expirations',
    '0 7 * * *',
    'SELECT public.check_and_expire_trials()'
);

-- ============================================================================
-- 4. Grant permissions
-- ============================================================================

-- Grant execute permission on functions
GRANT EXECUTE ON FUNCTION public.check_and_expire_trials() TO service_role;
GRANT EXECUTE ON FUNCTION public.invoke_check_trial_ending() TO service_role;

-- ============================================================================
-- 5. Comments
-- ============================================================================

COMMENT ON FUNCTION public.check_and_expire_trials() IS
'Checks for trial expirations per plan.md Section 9.2:
- Day 12: Sends "Your trial ends in 3 days" notification
- Day 14: Sends "Your trial ends tomorrow" notification
- Day 15: Sends "Your trial has ended. Subscribe to continue" and sets status to expired';

COMMENT ON FUNCTION public.invoke_check_trial_ending() IS
'Invokes the check-trial-ending edge function via HTTP. Use this if edge function integration is preferred over database-only solution.';
