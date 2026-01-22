-- Migration: 007_core_database_tables.sql
-- Description: Create all core database tables for PRUUF iOS app
-- Phase 2 Section 2.1: Database Tables
-- Created: 2026-01-17

-- ============================================================================
-- 1. USERS TABLE
-- Stores all user account information
-- ============================================================================

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_number TEXT UNIQUE NOT NULL,
    phone_country_code TEXT NOT NULL DEFAULT '+1',
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    last_seen_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT true,
    has_completed_onboarding BOOLEAN DEFAULT false,
    primary_role TEXT CHECK (primary_role IN ('sender', 'receiver', 'both')),
    timezone TEXT DEFAULT 'UTC',
    device_token TEXT, -- For push notifications
    notification_preferences JSONB DEFAULT '{"ping_reminders": true, "deadline_alerts": true, "connection_requests": true}'::jsonb,
    onboarding_step TEXT -- Added for onboarding flow tracking
);

-- Indexes for users table
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone_number);
CREATE INDEX IF NOT EXISTS idx_users_active ON users(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_users_device_token ON users(device_token) WHERE device_token IS NOT NULL;

-- Enable RLS on users
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 2. UNIQUE_CODES TABLE
-- Manages 6-digit unique codes for connections
-- ============================================================================

CREATE TABLE IF NOT EXISTS unique_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL CHECK (code ~ '^[0-9]{6}$'),
    receiver_id UUID REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ, -- NULL = never expires
    is_active BOOLEAN DEFAULT true,
    UNIQUE(receiver_id) -- One code per receiver
);

-- Indexes for unique_codes table
CREATE INDEX IF NOT EXISTS idx_unique_codes_code ON unique_codes(code) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_unique_codes_receiver ON unique_codes(receiver_id);

-- Enable RLS on unique_codes
ALTER TABLE unique_codes ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 3. CONNECTIONS TABLE
-- Manages sender-receiver relationships
-- ============================================================================

CREATE TABLE IF NOT EXISTS connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID REFERENCES users(id) ON DELETE CASCADE,
    receiver_id UUID REFERENCES users(id) ON DELETE CASCADE,
    status TEXT CHECK (status IN ('pending', 'active', 'paused', 'deleted')) DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    connection_code TEXT, -- The code used to establish connection
    UNIQUE(sender_id, receiver_id)
);

-- Indexes for connections table
CREATE INDEX IF NOT EXISTS idx_connections_sender ON connections(sender_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_connections_receiver ON connections(receiver_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_connections_status ON connections(status);

-- Enable RLS on connections
ALTER TABLE connections ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 4. PINGS TABLE
-- Tracks all ping events
-- ============================================================================

CREATE TABLE IF NOT EXISTS pings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id UUID REFERENCES connections(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES users(id) ON DELETE CASCADE,
    receiver_id UUID REFERENCES users(id) ON DELETE CASCADE,
    scheduled_time TIMESTAMPTZ NOT NULL,
    deadline_time TIMESTAMPTZ NOT NULL, -- scheduled_time + grace period
    completed_at TIMESTAMPTZ,
    completion_method TEXT CHECK (completion_method IN ('tap', 'in_person', 'auto_break')),
    status TEXT CHECK (status IN ('pending', 'completed', 'missed', 'on_break')) DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now(),
    verification_location JSONB, -- {lat, lon, accuracy} if in-person verification
    notes TEXT
);

-- Indexes for pings table
CREATE INDEX IF NOT EXISTS idx_pings_connection ON pings(connection_id);
CREATE INDEX IF NOT EXISTS idx_pings_sender ON pings(sender_id);
CREATE INDEX IF NOT EXISTS idx_pings_receiver ON pings(receiver_id);
CREATE INDEX IF NOT EXISTS idx_pings_status ON pings(status);
CREATE INDEX IF NOT EXISTS idx_pings_scheduled ON pings(scheduled_time) WHERE status = 'pending';
-- Note: Date-based index removed due to PostgreSQL immutability requirements with timestamptz

-- Enable RLS on pings
ALTER TABLE pings ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 5. BREAKS TABLE
-- Manages scheduled breaks from ping requirements
-- ============================================================================

CREATE TABLE IF NOT EXISTS breaks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID REFERENCES users(id) ON DELETE CASCADE,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    status TEXT CHECK (status IN ('scheduled', 'active', 'completed', 'canceled')) DEFAULT 'scheduled',
    notes TEXT,
    CHECK (end_date >= start_date)
);

-- Indexes for breaks table
CREATE INDEX IF NOT EXISTS idx_breaks_sender ON breaks(sender_id);
CREATE INDEX IF NOT EXISTS idx_breaks_dates ON breaks(start_date, end_date) WHERE status IN ('scheduled', 'active');
CREATE INDEX IF NOT EXISTS idx_breaks_status ON breaks(status);

-- Enable RLS on breaks
ALTER TABLE breaks ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 6. NOTIFICATIONS TABLE
-- Stores notification history for audit trail
-- ============================================================================

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    type TEXT CHECK (type IN ('ping_reminder', 'deadline_warning', 'missed_ping', 'connection_request', 'payment_reminder', 'trial_ending')) NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    sent_at TIMESTAMPTZ DEFAULT now(),
    read_at TIMESTAMPTZ,
    metadata JSONB, -- {ping_id, connection_id, etc.}
    delivery_status TEXT CHECK (delivery_status IN ('sent', 'failed', 'pending')) DEFAULT 'sent'
);

-- Indexes for notifications table
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_sent ON notifications(sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON notifications(user_id) WHERE read_at IS NULL;

-- Enable RLS on notifications
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 7. AUDIT_LOGS TABLE
-- Tracks system events for compliance and debugging
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    resource_type TEXT, -- 'user', 'connection', 'ping', 'payment', etc.
    resource_id UUID,
    details JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for audit_logs table
CREATE INDEX IF NOT EXISTS idx_audit_logs_user ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_resource ON audit_logs(resource_type, resource_id);

-- Enable RLS on audit_logs
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 8. PAYMENT_TRANSACTIONS TABLE
-- Tracks all payment events
-- ============================================================================

CREATE TABLE IF NOT EXISTS payment_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    stripe_payment_intent_id TEXT,
    amount DECIMAL(10,2) NOT NULL,
    currency TEXT DEFAULT 'USD',
    status TEXT CHECK (status IN ('pending', 'succeeded', 'failed', 'refunded')) DEFAULT 'pending',
    transaction_type TEXT CHECK (transaction_type IN ('subscription', 'refund', 'chargeback')),
    created_at TIMESTAMPTZ DEFAULT now(),
    metadata JSONB
);

-- Indexes for payment_transactions table
CREATE INDEX IF NOT EXISTS idx_payment_transactions_user ON payment_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_status ON payment_transactions(status);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_stripe ON payment_transactions(stripe_payment_intent_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_date ON payment_transactions(created_at DESC);

-- Enable RLS on payment_transactions
ALTER TABLE payment_transactions ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 9. TRIGGERS FOR updated_at COLUMNS
-- ============================================================================

-- Create trigger function if it doesn't exist
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply triggers to tables with updated_at column
DROP TRIGGER IF EXISTS users_updated_at ON users;
CREATE TRIGGER users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS connections_updated_at ON connections;
CREATE TRIGGER connections_updated_at
    BEFORE UPDATE ON connections
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- 10. RLS POLICIES FOR ALL TABLES
-- ============================================================================

-- ----- USERS POLICIES -----
DROP POLICY IF EXISTS "Users can view own profile" ON users;
CREATE POLICY "Users can view own profile" ON users
    FOR SELECT
    USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update own profile" ON users;
CREATE POLICY "Users can update own profile" ON users
    FOR UPDATE
    USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can insert own profile" ON users;
CREATE POLICY "Users can insert own profile" ON users
    FOR INSERT
    WITH CHECK (auth.uid() = id);

-- Connected users can view each other's basic info
DROP POLICY IF EXISTS "Connected users can view profiles" ON users;
CREATE POLICY "Connected users can view profiles" ON users
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM connections c
            WHERE c.status = 'active'
            AND (
                (c.sender_id = auth.uid() AND c.receiver_id = users.id) OR
                (c.receiver_id = auth.uid() AND c.sender_id = users.id)
            )
        )
    );

-- ----- UNIQUE_CODES POLICIES -----
DROP POLICY IF EXISTS "Receivers can view own code" ON unique_codes;
CREATE POLICY "Receivers can view own code" ON unique_codes
    FOR SELECT
    USING (receiver_id = auth.uid());

DROP POLICY IF EXISTS "Anyone can lookup active codes" ON unique_codes;
CREATE POLICY "Anyone can lookup active codes" ON unique_codes
    FOR SELECT
    USING (is_active = true);

DROP POLICY IF EXISTS "Receivers can create own code" ON unique_codes;
CREATE POLICY "Receivers can create own code" ON unique_codes
    FOR INSERT
    WITH CHECK (receiver_id = auth.uid());

DROP POLICY IF EXISTS "Receivers can update own code" ON unique_codes;
CREATE POLICY "Receivers can update own code" ON unique_codes
    FOR UPDATE
    USING (receiver_id = auth.uid());

-- ----- CONNECTIONS POLICIES -----
DROP POLICY IF EXISTS "Users can view own connections" ON connections;
CREATE POLICY "Users can view own connections" ON connections
    FOR SELECT
    USING (sender_id = auth.uid() OR receiver_id = auth.uid());

DROP POLICY IF EXISTS "Users can create connections as sender" ON connections;
CREATE POLICY "Users can create connections as sender" ON connections
    FOR INSERT
    WITH CHECK (sender_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own connections" ON connections;
CREATE POLICY "Users can update own connections" ON connections
    FOR UPDATE
    USING (sender_id = auth.uid() OR receiver_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete own connections" ON connections;
CREATE POLICY "Users can delete own connections" ON connections
    FOR DELETE
    USING (sender_id = auth.uid() OR receiver_id = auth.uid());

-- ----- PINGS POLICIES -----
DROP POLICY IF EXISTS "Users can view own pings" ON pings;
CREATE POLICY "Users can view own pings" ON pings
    FOR SELECT
    USING (sender_id = auth.uid() OR receiver_id = auth.uid());

DROP POLICY IF EXISTS "Senders can update own pings" ON pings;
CREATE POLICY "Senders can update own pings" ON pings
    FOR UPDATE
    USING (sender_id = auth.uid());

DROP POLICY IF EXISTS "System can create pings" ON pings;
CREATE POLICY "System can create pings" ON pings
    FOR INSERT
    WITH CHECK (sender_id = auth.uid() OR receiver_id = auth.uid());

-- ----- BREAKS POLICIES -----
DROP POLICY IF EXISTS "Senders can view own breaks" ON breaks;
CREATE POLICY "Senders can view own breaks" ON breaks
    FOR SELECT
    USING (sender_id = auth.uid());

DROP POLICY IF EXISTS "Senders can create own breaks" ON breaks;
CREATE POLICY "Senders can create own breaks" ON breaks
    FOR INSERT
    WITH CHECK (sender_id = auth.uid());

DROP POLICY IF EXISTS "Senders can update own breaks" ON breaks;
CREATE POLICY "Senders can update own breaks" ON breaks
    FOR UPDATE
    USING (sender_id = auth.uid());

DROP POLICY IF EXISTS "Senders can delete own breaks" ON breaks;
CREATE POLICY "Senders can delete own breaks" ON breaks
    FOR DELETE
    USING (sender_id = auth.uid());

-- Receivers can view breaks for their connected senders
DROP POLICY IF EXISTS "Receivers can view connected sender breaks" ON breaks;
CREATE POLICY "Receivers can view connected sender breaks" ON breaks
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM connections c
            WHERE c.status = 'active'
            AND c.receiver_id = auth.uid()
            AND c.sender_id = breaks.sender_id
        )
    );

-- ----- NOTIFICATIONS POLICIES -----
DROP POLICY IF EXISTS "Users can view own notifications" ON notifications;
CREATE POLICY "Users can view own notifications" ON notifications
    FOR SELECT
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own notifications" ON notifications;
CREATE POLICY "Users can update own notifications" ON notifications
    FOR UPDATE
    USING (user_id = auth.uid());

-- ----- AUDIT_LOGS POLICIES -----
DROP POLICY IF EXISTS "Users can view own audit logs" ON audit_logs;
CREATE POLICY "Users can view own audit logs" ON audit_logs
    FOR SELECT
    USING (user_id = auth.uid());

-- ----- PAYMENT_TRANSACTIONS POLICIES -----
DROP POLICY IF EXISTS "Users can view own payments" ON payment_transactions;
CREATE POLICY "Users can view own payments" ON payment_transactions
    FOR SELECT
    USING (user_id = auth.uid());

-- ============================================================================
-- 11. HELPER FUNCTIONS
-- ============================================================================

-- Function to generate unique 6-digit code for receivers
CREATE OR REPLACE FUNCTION generate_unique_code()
RETURNS TEXT AS $$
DECLARE
    new_code TEXT;
    code_exists BOOLEAN;
BEGIN
    LOOP
        -- Generate random 6-digit code
        new_code := LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0');

        -- Check if code already exists in active codes
        SELECT EXISTS(
            SELECT 1 FROM unique_codes
            WHERE code = new_code
            AND is_active = true
        ) INTO code_exists;

        -- Exit loop if code is unique
        EXIT WHEN NOT code_exists;
    END LOOP;

    RETURN new_code;
END;
$$ LANGUAGE plpgsql;

-- Function to check if user is on break
CREATE OR REPLACE FUNCTION is_user_on_break(p_sender_id UUID, p_date DATE DEFAULT CURRENT_DATE)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM breaks
        WHERE sender_id = p_sender_id
        AND status IN ('scheduled', 'active')
        AND p_date BETWEEN start_date AND end_date
    );
END;
$$ LANGUAGE plpgsql;

-- Function to get active connections for a user
CREATE OR REPLACE FUNCTION get_active_connections(p_user_id UUID)
RETURNS TABLE (
    connection_id UUID,
    connected_user_id UUID,
    role TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id as connection_id,
        CASE
            WHEN c.sender_id = p_user_id THEN c.receiver_id
            ELSE c.sender_id
        END as connected_user_id,
        CASE
            WHEN c.sender_id = p_user_id THEN 'sender'
            ELSE 'receiver'
        END as role,
        c.created_at
    FROM connections c
    WHERE c.status = 'active'
    AND (c.sender_id = p_user_id OR c.receiver_id = p_user_id);
END;
$$ LANGUAGE plpgsql;

-- Function to log audit events
CREATE OR REPLACE FUNCTION log_audit_event(
    p_user_id UUID,
    p_action TEXT,
    p_resource_type TEXT DEFAULT NULL,
    p_resource_id UUID DEFAULT NULL,
    p_details JSONB DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_log_id UUID;
BEGIN
    INSERT INTO audit_logs (user_id, action, resource_type, resource_id, details)
    VALUES (p_user_id, p_action, p_resource_type, p_resource_id, p_details)
    RETURNING id INTO v_log_id;

    RETURN v_log_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 12. GRANT PERMISSIONS
-- ============================================================================

-- Grant usage on all sequences
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon;

-- Grant permissions on tables to authenticated users
GRANT SELECT, INSERT, UPDATE, DELETE ON users TO authenticated;
GRANT SELECT, INSERT, UPDATE ON unique_codes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON connections TO authenticated;
GRANT SELECT, INSERT, UPDATE ON pings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON breaks TO authenticated;
GRANT SELECT, UPDATE ON notifications TO authenticated;
GRANT SELECT ON audit_logs TO authenticated;
GRANT SELECT ON payment_transactions TO authenticated;

-- Grant insert on notifications and audit_logs to service role (for system operations)
GRANT INSERT ON notifications TO service_role;
GRANT INSERT ON audit_logs TO service_role;
GRANT INSERT, UPDATE ON payment_transactions TO service_role;

-- ============================================================================
-- 13. COMMENTS FOR DOCUMENTATION
-- ============================================================================

COMMENT ON TABLE users IS 'Stores all user account information including phone, role, and preferences';
COMMENT ON COLUMN users.primary_role IS 'User role: sender (checks in), receiver (monitors), or both';
COMMENT ON COLUMN users.device_token IS 'APNs device token for push notifications';
COMMENT ON COLUMN users.notification_preferences IS 'JSON object with notification settings';

COMMENT ON TABLE unique_codes IS 'Manages 6-digit codes for receivers to share with senders for connection';
COMMENT ON COLUMN unique_codes.code IS '6-digit numeric code for connection establishment';

COMMENT ON TABLE connections IS 'Links senders with their receivers (one-to-many relationship)';
COMMENT ON COLUMN connections.connection_code IS 'The unique code used to establish this connection';

COMMENT ON TABLE pings IS 'Records all ping events including scheduled, completed, and missed';
COMMENT ON COLUMN pings.deadline_time IS 'scheduled_time plus grace period (default 2 hours)';
COMMENT ON COLUMN pings.verification_location IS 'GPS coordinates if in-person verification was used';

COMMENT ON TABLE breaks IS 'Scheduled periods when sender does not need to ping (vacation, etc.)';
COMMENT ON COLUMN breaks.status IS 'scheduled (future), active (current), completed (past), canceled';

COMMENT ON TABLE notifications IS 'History of all notifications sent for audit and debugging';
COMMENT ON COLUMN notifications.metadata IS 'Additional context like ping_id, connection_id, etc.';

COMMENT ON TABLE audit_logs IS 'Security and compliance audit trail of all significant actions';
COMMENT ON COLUMN audit_logs.resource_type IS 'Type of entity affected: user, connection, ping, payment, etc.';

COMMENT ON TABLE payment_transactions IS 'Record of all payment events for reconciliation';
COMMENT ON COLUMN payment_transactions.stripe_payment_intent_id IS 'Stripe payment intent ID for payment tracking';
