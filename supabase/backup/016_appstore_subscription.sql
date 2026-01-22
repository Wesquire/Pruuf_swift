-- Migration: 016_appstore_subscription.sql
-- Purpose: Add App Store subscription support for Section 9.1 Subscription Model
-- Created: 2026-01-17
--
-- Subscription Model per plan.md Section 9.1:
-- - Receiver-only users: $2.99/month
-- - Senders: Always free
-- - Dual role users (Both): $2.99/month (only if they have receiver connections)
-- - 15-day free trial for all receivers
-- - No credit card required to start trial
-- - Product ID: com.pruuf.receiver.monthly
-- - Price: $2.99 USD/month
-- - Auto-renewable subscription managed through App Store

-- ============================================================================
-- 1. Add App Store fields to receiver_profiles table
-- ============================================================================

-- Add App Store transaction fields
ALTER TABLE receiver_profiles
ADD COLUMN IF NOT EXISTS app_store_transaction_id TEXT,
ADD COLUMN IF NOT EXISTS app_store_original_transaction_id TEXT,
ADD COLUMN IF NOT EXISTS app_store_product_id TEXT,
ADD COLUMN IF NOT EXISTS app_store_environment TEXT CHECK (app_store_environment IN ('Production', 'Sandbox'));

-- Index for App Store transaction lookups
CREATE INDEX IF NOT EXISTS idx_receiver_profiles_app_store_transaction
ON receiver_profiles(app_store_original_transaction_id);

-- ============================================================================
-- 2. Update check_subscription_status function for App Store
-- ============================================================================

-- Alias the old function to the RPC name used by iOS
CREATE OR REPLACE FUNCTION check_subscription_status(p_user_id UUID)
RETURNS TEXT AS $$
BEGIN
    RETURN check_receiver_subscription_status(p_user_id)::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 3. Function to start 15-day free trial
-- ============================================================================

CREATE OR REPLACE FUNCTION start_receiver_trial(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_profile_id UUID;
    v_trial_end TIMESTAMPTZ;
BEGIN
    -- Calculate trial end date (15 days from now)
    v_trial_end := now() + INTERVAL '15 days';

    -- Check if profile exists
    SELECT id INTO v_profile_id
    FROM receiver_profiles
    WHERE user_id = p_user_id;

    IF v_profile_id IS NULL THEN
        -- Create new receiver profile with trial
        INSERT INTO receiver_profiles (
            user_id,
            subscription_status,
            subscription_start_date,
            trial_end_date
        ) VALUES (
            p_user_id,
            'trial',
            now(),
            v_trial_end
        )
        RETURNING id INTO v_profile_id;
    ELSE
        -- Update existing profile to trial (if not already subscribed)
        UPDATE receiver_profiles
        SET subscription_status = 'trial',
            subscription_start_date = now(),
            trial_end_date = v_trial_end,
            updated_at = now()
        WHERE user_id = p_user_id
        AND subscription_status NOT IN ('active');
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'trial_end_date', v_trial_end,
        'days_remaining', 15
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 4. Function to activate subscription from App Store
-- ============================================================================

CREATE OR REPLACE FUNCTION activate_appstore_subscription(
    p_user_id UUID,
    p_transaction_id TEXT,
    p_original_transaction_id TEXT,
    p_product_id TEXT,
    p_expiration_date TIMESTAMPTZ,
    p_environment TEXT DEFAULT 'Production'
)
RETURNS JSONB AS $$
DECLARE
    v_profile_id UUID;
BEGIN
    -- Upsert receiver profile with subscription
    INSERT INTO receiver_profiles (
        user_id,
        subscription_status,
        subscription_start_date,
        subscription_end_date,
        app_store_transaction_id,
        app_store_original_transaction_id,
        app_store_product_id,
        app_store_environment
    ) VALUES (
        p_user_id,
        'active',
        now(),
        p_expiration_date,
        p_transaction_id,
        p_original_transaction_id,
        p_product_id,
        p_environment
    )
    ON CONFLICT (user_id) DO UPDATE SET
        subscription_status = 'active',
        subscription_end_date = p_expiration_date,
        app_store_transaction_id = p_transaction_id,
        app_store_original_transaction_id = COALESCE(
            receiver_profiles.app_store_original_transaction_id,
            p_original_transaction_id
        ),
        app_store_product_id = p_product_id,
        app_store_environment = p_environment,
        updated_at = now()
    RETURNING id INTO v_profile_id;

    -- Log audit event
    INSERT INTO audit_logs (user_id, action, resource_type, resource_id, details)
    VALUES (
        p_user_id,
        'subscription_activated',
        'receiver_profile',
        v_profile_id::TEXT,
        jsonb_build_object(
            'product_id', p_product_id,
            'transaction_id', p_transaction_id,
            'expiration_date', p_expiration_date,
            'environment', p_environment
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'subscription_status', 'active',
        'expiration_date', p_expiration_date
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 5. Function to handle subscription expiration/cancellation
-- ============================================================================

CREATE OR REPLACE FUNCTION expire_appstore_subscription(
    p_user_id UUID,
    p_reason TEXT DEFAULT 'expired'
)
RETURNS JSONB AS $$
DECLARE
    v_new_status subscription_status;
BEGIN
    -- Determine new status based on reason
    IF p_reason = 'canceled' THEN
        v_new_status := 'canceled';
    ELSE
        v_new_status := 'expired';
    END IF;

    -- Update receiver profile
    UPDATE receiver_profiles
    SET subscription_status = v_new_status,
        updated_at = now()
    WHERE user_id = p_user_id;

    -- Log audit event
    INSERT INTO audit_logs (user_id, action, resource_type, details)
    VALUES (
        p_user_id,
        'subscription_' || p_reason,
        'receiver_profile',
        jsonb_build_object('reason', p_reason)
    );

    RETURN jsonb_build_object(
        'success', true,
        'subscription_status', v_new_status
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 6. Function to check if user has active subscription
-- ============================================================================

CREATE OR REPLACE FUNCTION has_active_receiver_subscription(p_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_status subscription_status;
    v_trial_end TIMESTAMPTZ;
    v_sub_end TIMESTAMPTZ;
BEGIN
    SELECT subscription_status, trial_end_date, subscription_end_date
    INTO v_status, v_trial_end, v_sub_end
    FROM receiver_profiles
    WHERE user_id = p_user_id;

    -- No profile means no subscription
    IF v_status IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Check trial status
    IF v_status = 'trial' THEN
        RETURN v_trial_end IS NOT NULL AND v_trial_end > now();
    END IF;

    -- Check active subscription
    IF v_status = 'active' THEN
        RETURN v_sub_end IS NULL OR v_sub_end > now();
    END IF;

    -- All other statuses mean no active subscription
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 7. Function to get subscription info
-- ============================================================================

CREATE OR REPLACE FUNCTION get_receiver_subscription_info(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_profile receiver_profiles%ROWTYPE;
    v_days_remaining INT;
BEGIN
    SELECT * INTO v_profile
    FROM receiver_profiles
    WHERE user_id = p_user_id;

    IF v_profile IS NULL THEN
        RETURN jsonb_build_object(
            'has_subscription', false,
            'status', 'none',
            'requires_subscription', true
        );
    END IF;

    -- Calculate days remaining
    IF v_profile.subscription_status = 'trial' AND v_profile.trial_end_date IS NOT NULL THEN
        v_days_remaining := GREATEST(0, EXTRACT(DAY FROM (v_profile.trial_end_date - now()))::INT);
    ELSIF v_profile.subscription_status = 'active' AND v_profile.subscription_end_date IS NOT NULL THEN
        v_days_remaining := GREATEST(0, EXTRACT(DAY FROM (v_profile.subscription_end_date - now()))::INT);
    ELSE
        v_days_remaining := 0;
    END IF;

    RETURN jsonb_build_object(
        'has_subscription', has_active_receiver_subscription(p_user_id),
        'status', v_profile.subscription_status,
        'start_date', v_profile.subscription_start_date,
        'end_date', COALESCE(v_profile.subscription_end_date, v_profile.trial_end_date),
        'trial_end_date', v_profile.trial_end_date,
        'days_remaining', v_days_remaining,
        'is_trial', v_profile.subscription_status = 'trial',
        'product_id', v_profile.app_store_product_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 8. Grant permissions
-- ============================================================================

-- Grant execute permissions on new functions
GRANT EXECUTE ON FUNCTION check_subscription_status(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION start_receiver_trial(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION activate_appstore_subscription(UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION expire_appstore_subscription(UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION has_active_receiver_subscription(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_receiver_subscription_info(UUID) TO authenticated;

-- ============================================================================
-- 9. Comments
-- ============================================================================

COMMENT ON COLUMN receiver_profiles.app_store_transaction_id IS 'Latest App Store transaction ID';
COMMENT ON COLUMN receiver_profiles.app_store_original_transaction_id IS 'Original App Store transaction ID (for subscription family)';
COMMENT ON COLUMN receiver_profiles.app_store_product_id IS 'App Store product ID (com.pruuf.receiver.monthly)';
COMMENT ON COLUMN receiver_profiles.app_store_environment IS 'App Store environment (Production or Sandbox)';

COMMENT ON FUNCTION start_receiver_trial(UUID) IS 'Starts 15-day free trial for a receiver';
COMMENT ON FUNCTION activate_appstore_subscription(UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ, TEXT) IS 'Activates subscription from App Store purchase';
COMMENT ON FUNCTION expire_appstore_subscription(UUID, TEXT) IS 'Marks subscription as expired or canceled';
COMMENT ON FUNCTION has_active_receiver_subscription(UUID) IS 'Checks if user has active subscription (trial or paid)';
COMMENT ON FUNCTION get_receiver_subscription_info(UUID) IS 'Returns full subscription info for a user';
