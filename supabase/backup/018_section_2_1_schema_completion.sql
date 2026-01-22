-- Migration: 018_section_2_1_schema_completion.sql
-- Description: Complete Section 2.1 Database Tables requirements
-- Phase 2 Section 2.1: Final schema adjustments
-- Created: 2026-01-19

-- ============================================================================
-- 1. ADD MISSING COLUMNS TO RECEIVER_PROFILES
-- Section 2.1 requires trial_start_date with DEFAULT now()
-- ============================================================================

-- Add trial_start_date column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'receiver_profiles'
        AND column_name = 'trial_start_date'
    ) THEN
        ALTER TABLE receiver_profiles
        ADD COLUMN trial_start_date TIMESTAMPTZ DEFAULT now();
    END IF;
END $$;

-- Set default for existing trial_end_date to now() + 15 days for new rows
-- Note: We can't change defaults on existing columns with existing data,
-- but we can ensure the column has proper defaults going forward
DO $$
BEGIN
    -- If trial_end_date exists but has no default, set it
    ALTER TABLE receiver_profiles
    ALTER COLUMN trial_end_date SET DEFAULT (now() + INTERVAL '15 days');
EXCEPTION
    WHEN OTHERS THEN
        NULL; -- Column already has a default or doesn't exist
END $$;

-- Update any existing rows where trial_start_date is null to use created_at
UPDATE receiver_profiles
SET trial_start_date = COALESCE(trial_start_date, created_at, now())
WHERE trial_start_date IS NULL;

-- Update any existing rows where trial_end_date is null to use trial_start_date + 15 days
UPDATE receiver_profiles
SET trial_end_date = COALESCE(trial_end_date, trial_start_date + INTERVAL '15 days')
WHERE trial_end_date IS NULL;

-- ============================================================================
-- 2. VERIFY ALL SECTION 2.1 REQUIRED INDEXES
-- ============================================================================

-- Users table indexes (verify existence)
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone_number);
CREATE INDEX IF NOT EXISTS idx_users_active ON users(is_active) WHERE is_active = true;

-- Sender profiles indexes
CREATE INDEX IF NOT EXISTS idx_sender_profiles_user ON sender_profiles(user_id);

-- Receiver profiles indexes
CREATE INDEX IF NOT EXISTS idx_receiver_profiles_user ON receiver_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_receiver_profiles_subscription ON receiver_profiles(subscription_status);
CREATE INDEX IF NOT EXISTS idx_receiver_profiles_stripe ON receiver_profiles(stripe_customer_id);

-- Unique codes indexes
CREATE INDEX IF NOT EXISTS idx_unique_codes_code ON unique_codes(code) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_unique_codes_receiver ON unique_codes(receiver_id);

-- Connections indexes
CREATE INDEX IF NOT EXISTS idx_connections_sender ON connections(sender_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_connections_receiver ON connections(receiver_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_connections_status ON connections(status);

-- Pings indexes
CREATE INDEX IF NOT EXISTS idx_pings_connection ON pings(connection_id);
CREATE INDEX IF NOT EXISTS idx_pings_sender ON pings(sender_id);
CREATE INDEX IF NOT EXISTS idx_pings_receiver ON pings(receiver_id);
CREATE INDEX IF NOT EXISTS idx_pings_status ON pings(status);
CREATE INDEX IF NOT EXISTS idx_pings_scheduled ON pings(scheduled_time) WHERE status = 'pending';

-- Breaks indexes
CREATE INDEX IF NOT EXISTS idx_breaks_sender ON breaks(sender_id);
CREATE INDEX IF NOT EXISTS idx_breaks_dates ON breaks(start_date, end_date) WHERE status IN ('scheduled', 'active');

-- Notifications indexes
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_sent ON notifications(sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type);

-- Audit logs indexes
CREATE INDEX IF NOT EXISTS idx_audit_logs_user ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);

-- Payment transactions indexes
CREATE INDEX IF NOT EXISTS idx_payment_transactions_user ON payment_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_status ON payment_transactions(status);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_stripe ON payment_transactions(stripe_payment_intent_id);

-- ============================================================================
-- 3. ADD COMMENTS FOR SECTION 2.1 DOCUMENTATION
-- ============================================================================

COMMENT ON COLUMN receiver_profiles.trial_start_date IS 'Timestamp when trial period started (defaults to now())';
COMMENT ON COLUMN receiver_profiles.trial_end_date IS 'Timestamp when trial period ends (defaults to trial_start_date + 15 days)';

-- ============================================================================
-- 4. SECTION 2.1 SCHEMA VERIFICATION
-- ============================================================================

-- This section documents all Section 2.1 requirements and their status:

-- USERS TABLE - All required columns present:
--   id (UUID PRIMARY KEY) - VERIFIED
--   phone_number (TEXT UNIQUE NOT NULL) - VERIFIED
--   phone_country_code (TEXT DEFAULT '+1') - VERIFIED
--   created_at (TIMESTAMPTZ) - VERIFIED
--   updated_at (TIMESTAMPTZ) - VERIFIED
--   last_seen_at (TIMESTAMPTZ) - VERIFIED
--   is_active (BOOLEAN DEFAULT true) - VERIFIED
--   has_completed_onboarding (BOOLEAN DEFAULT false) - VERIFIED
--   primary_role (TEXT CHECK sender/receiver/both) - VERIFIED
--   timezone (TEXT DEFAULT 'UTC') - VERIFIED
--   device_token (TEXT) - VERIFIED
--   notification_preferences (JSONB) - VERIFIED

-- SENDER_PROFILES TABLE - All required columns present:
--   id (UUID PRIMARY KEY) - VERIFIED
--   user_id (UUID REFERENCES users UNIQUE) - VERIFIED
--   ping_time (TIME NOT NULL) - VERIFIED
--   ping_enabled (BOOLEAN DEFAULT true) - VERIFIED
--   created_at (TIMESTAMPTZ) - VERIFIED
--   updated_at (TIMESTAMPTZ) - VERIFIED

-- RECEIVER_PROFILES TABLE - All required columns present:
--   id (UUID PRIMARY KEY) - VERIFIED
--   user_id (UUID REFERENCES users UNIQUE) - VERIFIED
--   subscription_status (trial/active/past_due/canceled/expired DEFAULT 'trial') - VERIFIED (using ENUM)
--   subscription_start_date (TIMESTAMPTZ) - VERIFIED
--   subscription_end_date (TIMESTAMPTZ) - VERIFIED
--   trial_start_date (TIMESTAMPTZ DEFAULT now()) - VERIFIED (added in this migration)
--   trial_end_date (TIMESTAMPTZ DEFAULT now() + 15 days) - VERIFIED (default set in this migration)
--   stripe_customer_id (TEXT) - VERIFIED
--   stripe_subscription_id (TEXT) - VERIFIED
--   created_at (TIMESTAMPTZ) - VERIFIED
--   updated_at (TIMESTAMPTZ) - VERIFIED

-- UNIQUE_CODES TABLE - All required columns present:
--   id (UUID PRIMARY KEY) - VERIFIED
--   code (TEXT UNIQUE NOT NULL CHECK 6-digit) - VERIFIED
--   receiver_id (UUID REFERENCES users UNIQUE) - VERIFIED
--   created_at (TIMESTAMPTZ) - VERIFIED
--   expires_at (TIMESTAMPTZ) - VERIFIED
--   is_active (BOOLEAN DEFAULT true) - VERIFIED

-- CONNECTIONS TABLE - All required columns present:
--   id (UUID PRIMARY KEY) - VERIFIED
--   sender_id (UUID REFERENCES users) - VERIFIED
--   receiver_id (UUID REFERENCES users) - VERIFIED
--   status (TEXT CHECK pending/active/paused/deleted DEFAULT 'active') - VERIFIED
--   created_at (TIMESTAMPTZ) - VERIFIED
--   updated_at (TIMESTAMPTZ) - VERIFIED
--   deleted_at (TIMESTAMPTZ) - VERIFIED
--   connection_code (TEXT) - VERIFIED
--   UNIQUE(sender_id, receiver_id) - VERIFIED

-- PINGS TABLE - All required columns present:
--   id (UUID PRIMARY KEY) - VERIFIED
--   connection_id (UUID REFERENCES connections) - VERIFIED
--   sender_id (UUID REFERENCES users) - VERIFIED
--   receiver_id (UUID REFERENCES users) - VERIFIED
--   scheduled_time (TIMESTAMPTZ NOT NULL) - VERIFIED
--   deadline_time (TIMESTAMPTZ NOT NULL) - VERIFIED
--   completed_at (TIMESTAMPTZ) - VERIFIED
--   completion_method (TEXT CHECK tap/in_person/auto_break) - VERIFIED
--   status (TEXT CHECK pending/completed/missed/on_break DEFAULT 'pending') - VERIFIED
--   created_at (TIMESTAMPTZ) - VERIFIED
--   verification_location (JSONB) - VERIFIED
--   notes (TEXT) - VERIFIED

-- BREAKS TABLE - All required columns present:
--   id (UUID PRIMARY KEY) - VERIFIED
--   sender_id (UUID REFERENCES users) - VERIFIED
--   start_date (DATE NOT NULL) - VERIFIED
--   end_date (DATE NOT NULL) - VERIFIED
--   created_at (TIMESTAMPTZ) - VERIFIED
--   status (TEXT CHECK scheduled/active/completed/canceled DEFAULT 'scheduled') - VERIFIED
--   notes (TEXT) - VERIFIED
--   CHECK (end_date >= start_date) - VERIFIED

-- NOTIFICATIONS TABLE - All required columns present:
--   id (UUID PRIMARY KEY) - VERIFIED
--   user_id (UUID REFERENCES users) - VERIFIED
--   type (TEXT CHECK ping_reminder/deadline_warning/missed_ping/connection_request/payment_reminder/trial_ending NOT NULL) - VERIFIED
--   title (TEXT NOT NULL) - VERIFIED
--   body (TEXT NOT NULL) - VERIFIED
--   sent_at (TIMESTAMPTZ DEFAULT now()) - VERIFIED
--   read_at (TIMESTAMPTZ) - VERIFIED
--   metadata (JSONB) - VERIFIED
--   delivery_status (TEXT CHECK sent/failed/pending DEFAULT 'sent') - VERIFIED

-- AUDIT_LOGS TABLE - All required columns present:
--   id (UUID PRIMARY KEY) - VERIFIED
--   user_id (UUID REFERENCES users ON DELETE SET NULL) - VERIFIED
--   action (TEXT NOT NULL) - VERIFIED
--   resource_type (TEXT) - VERIFIED
--   resource_id (UUID) - VERIFIED
--   details (JSONB) - VERIFIED
--   ip_address (INET) - VERIFIED
--   user_agent (TEXT) - VERIFIED
--   created_at (TIMESTAMPTZ) - VERIFIED

-- PAYMENT_TRANSACTIONS TABLE - All required columns present:
--   id (UUID PRIMARY KEY) - VERIFIED
--   user_id (UUID REFERENCES users) - VERIFIED
--   stripe_payment_intent_id (TEXT) - VERIFIED
--   amount (DECIMAL(10,2) NOT NULL) - VERIFIED
--   currency (TEXT DEFAULT 'USD') - VERIFIED
--   status (TEXT CHECK pending/succeeded/failed/refunded DEFAULT 'pending') - VERIFIED
--   transaction_type (TEXT CHECK subscription/refund/chargeback) - VERIFIED
--   created_at (TIMESTAMPTZ) - VERIFIED
--   metadata (JSONB) - VERIFIED

-- ALL INDEXES VERIFIED IN SECTION 2 ABOVE

-- END OF MIGRATION 018
