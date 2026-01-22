-- Migration: 005_role_selection_tables.sql
-- Purpose: Add role selection and profile tables for PRUUF onboarding (Section 3.2)
-- Created: 2026-01-17

-- ============================================================================
-- 1. Add onboarding_step column to users table
-- ============================================================================

-- Create onboarding_step enum type
DO $$ BEGIN
    CREATE TYPE onboarding_step AS ENUM (
        'role_selection',
        'sender_tutorial',
        'sender_ping_time',
        'sender_connections',
        'sender_notifications',
        'sender_complete',
        'receiver_tutorial',
        'receiver_code',
        'receiver_subscription',
        'receiver_notifications',
        'receiver_complete'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Add onboarding_step column to users if it doesn't exist
ALTER TABLE users
ADD COLUMN IF NOT EXISTS onboarding_step onboarding_step;

-- Add primary_role column to users if it doesn't exist
ALTER TABLE users
ADD COLUMN IF NOT EXISTS primary_role TEXT CHECK (primary_role IN ('sender', 'receiver', 'both'));

-- ============================================================================
-- 2. Create sender_profiles table
-- ============================================================================

CREATE TABLE IF NOT EXISTS sender_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE UNIQUE,
    ping_time TIME NOT NULL DEFAULT '09:00:00', -- UTC time for daily ping
    ping_enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Index for faster user lookups
CREATE INDEX IF NOT EXISTS idx_sender_profiles_user ON sender_profiles(user_id);

-- Enable RLS
ALTER TABLE sender_profiles ENABLE ROW LEVEL SECURITY;

-- RLS Policies for sender_profiles
DROP POLICY IF EXISTS "Senders can view own profile" ON sender_profiles;
CREATE POLICY "Senders can view own profile" ON sender_profiles
    FOR SELECT
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Senders can update own profile" ON sender_profiles;
CREATE POLICY "Senders can update own profile" ON sender_profiles
    FOR UPDATE
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Senders can insert own profile" ON sender_profiles;
CREATE POLICY "Senders can insert own profile" ON sender_profiles
    FOR INSERT
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Senders can delete own profile" ON sender_profiles;
CREATE POLICY "Senders can delete own profile" ON sender_profiles
    FOR DELETE
    USING (user_id = auth.uid());

-- ============================================================================
-- 3. Create receiver_profiles table
-- ============================================================================

-- Create subscription_status enum type
DO $$ BEGIN
    CREATE TYPE subscription_status AS ENUM (
        'trial',
        'active',
        'past_due',
        'canceled',
        'expired'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS receiver_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE UNIQUE,
    subscription_status subscription_status DEFAULT 'trial',
    subscription_start_date TIMESTAMPTZ,
    subscription_end_date TIMESTAMPTZ,
    trial_end_date TIMESTAMPTZ,
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for faster lookups
CREATE INDEX IF NOT EXISTS idx_receiver_profiles_user ON receiver_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_receiver_profiles_subscription ON receiver_profiles(subscription_status);
CREATE INDEX IF NOT EXISTS idx_receiver_profiles_stripe ON receiver_profiles(stripe_customer_id);

-- Enable RLS
ALTER TABLE receiver_profiles ENABLE ROW LEVEL SECURITY;

-- RLS Policies for receiver_profiles
DROP POLICY IF EXISTS "Receivers can view own profile" ON receiver_profiles;
CREATE POLICY "Receivers can view own profile" ON receiver_profiles
    FOR SELECT
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Receivers can update own profile" ON receiver_profiles;
CREATE POLICY "Receivers can update own profile" ON receiver_profiles
    FOR UPDATE
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Receivers can insert own profile" ON receiver_profiles;
CREATE POLICY "Receivers can insert own profile" ON receiver_profiles
    FOR INSERT
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Receivers can delete own profile" ON receiver_profiles;
CREATE POLICY "Receivers can delete own profile" ON receiver_profiles
    FOR DELETE
    USING (user_id = auth.uid());

-- ============================================================================
-- 4. Triggers for updated_at columns
-- ============================================================================

-- Trigger function for updating updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply trigger to sender_profiles
DROP TRIGGER IF EXISTS sender_profiles_updated_at ON sender_profiles;
CREATE TRIGGER sender_profiles_updated_at
    BEFORE UPDATE ON sender_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Apply trigger to receiver_profiles
DROP TRIGGER IF EXISTS receiver_profiles_updated_at ON receiver_profiles;
CREATE TRIGGER receiver_profiles_updated_at
    BEFORE UPDATE ON receiver_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- 5. Helper function to check subscription status
-- ============================================================================

CREATE OR REPLACE FUNCTION check_receiver_subscription_status(p_user_id UUID)
RETURNS subscription_status AS $$
DECLARE
    v_status subscription_status;
    v_trial_end TIMESTAMPTZ;
    v_sub_end TIMESTAMPTZ;
BEGIN
    SELECT subscription_status, trial_end_date, subscription_end_date
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

-- ============================================================================
-- 6. Grant permissions for Edge Functions
-- ============================================================================

-- Grant usage on sequences
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Grant permissions on new tables
GRANT ALL ON sender_profiles TO authenticated;
GRANT ALL ON receiver_profiles TO authenticated;

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE sender_profiles IS 'Stores sender-specific settings including daily ping time';
COMMENT ON TABLE receiver_profiles IS 'Stores receiver-specific settings and subscription information';
COMMENT ON COLUMN sender_profiles.ping_time IS 'UTC time for daily ping reminder (HH:MM:SS format)';
COMMENT ON COLUMN receiver_profiles.subscription_status IS 'Current subscription status: trial, active, past_due, canceled, expired';
COMMENT ON COLUMN receiver_profiles.trial_end_date IS '15 days from signup for free trial period';
COMMENT ON COLUMN users.primary_role IS 'User primary role: sender, receiver, or both';
COMMENT ON COLUMN users.onboarding_step IS 'Current onboarding step for resuming mid-onboarding flow';
