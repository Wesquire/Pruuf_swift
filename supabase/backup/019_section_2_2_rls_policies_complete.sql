-- Migration: 019_section_2_2_rls_policies_complete.sql
-- Description: Complete RLS Policies for PRUUF as specified in plan.md Section 2.2
-- Phase 2 Section 2.2: Row Level Security Policies
-- Created: 2026-01-19
--
-- This migration ensures ALL RLS policies match exactly the names and requirements
-- specified in plan.md Section 2.2. It drops existing policies and recreates them
-- with the exact naming convention from the plan.

-- ============================================================================
-- STEP 1: ENABLE ROW LEVEL SECURITY ON ALL TABLES
-- Plan.md Section 2.2 Requirements:
-- - Enable RLS on users table
-- - Enable RLS on sender_profiles table
-- - Enable RLS on receiver_profiles table
-- - Enable RLS on unique_codes table
-- - Enable RLS on connections table
-- - Enable RLS on pings table
-- - Enable RLS on breaks table
-- - Enable RLS on notifications table
-- - Enable RLS on audit_logs table
-- - Enable RLS on payment_transactions table
-- ============================================================================

ALTER TABLE IF EXISTS users ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS sender_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS receiver_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS unique_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS pings ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS breaks ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS payment_transactions ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- STEP 2: USERS TABLE POLICIES
-- Plan.md Requirements:
-- - "Users can view own profile" ON users FOR SELECT USING (auth.uid() = id)
-- - "Users can update own profile" ON users FOR UPDATE USING (auth.uid() = id)
-- - "Admin can view all users" ON users FOR SELECT for admin users
-- ============================================================================

-- Drop existing policies to recreate with exact names
DROP POLICY IF EXISTS "Users can view own profile" ON users;
DROP POLICY IF EXISTS "Users can update own profile" ON users;
DROP POLICY IF EXISTS "Users can insert own profile" ON users;
DROP POLICY IF EXISTS "Admin can view all users" ON users;
DROP POLICY IF EXISTS "Super admin can update all users" ON users;
DROP POLICY IF EXISTS "Connected users can view profiles" ON users;

-- Policy: Users can view own profile
CREATE POLICY "Users can view own profile" ON users
    FOR SELECT
    USING (auth.uid() = id);

-- Policy: Users can update own profile
CREATE POLICY "Users can update own profile" ON users
    FOR UPDATE
    USING (auth.uid() = id);

-- Policy: Users can insert own profile (during signup)
CREATE POLICY "Users can insert own profile" ON users
    FOR INSERT
    WITH CHECK (auth.uid() = id);

-- Policy: Admin can view all users
CREATE POLICY "Admin can view all users" ON users
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM admin_users au
            WHERE au.user_id = auth.uid()
            AND au.is_active = true
            AND au.role IN ('super_admin', 'admin', 'moderator', 'support', 'viewer')
        )
    );

-- Additional: Connected users can view each other's profiles
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

-- ============================================================================
-- STEP 3: SENDER_PROFILES TABLE POLICIES
-- Plan.md Requirements:
-- - "Senders can view own profile" ON sender_profiles FOR SELECT USING (user_id = auth.uid())
-- - "Senders can update own profile" ON sender_profiles FOR UPDATE USING (user_id = auth.uid())
-- - "Senders can insert own profile" ON sender_profiles FOR INSERT WITH CHECK (user_id = auth.uid())
-- ============================================================================

-- Drop existing policies
DROP POLICY IF EXISTS "Senders can view own profile" ON sender_profiles;
DROP POLICY IF EXISTS "Senders can update own profile" ON sender_profiles;
DROP POLICY IF EXISTS "Senders can insert own profile" ON sender_profiles;
DROP POLICY IF EXISTS "Senders can delete own profile" ON sender_profiles;
DROP POLICY IF EXISTS "Admin can view all sender profiles" ON sender_profiles;
DROP POLICY IF EXISTS "Connected receivers can view sender profiles" ON sender_profiles;

-- Policy: Senders can view own profile
CREATE POLICY "Senders can view own profile" ON sender_profiles
    FOR SELECT
    USING (user_id = auth.uid());

-- Policy: Senders can update own profile
CREATE POLICY "Senders can update own profile" ON sender_profiles
    FOR UPDATE
    USING (user_id = auth.uid());

-- Policy: Senders can insert own profile
CREATE POLICY "Senders can insert own profile" ON sender_profiles
    FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- Additional: Senders can delete own profile (for account management)
CREATE POLICY "Senders can delete own profile" ON sender_profiles
    FOR DELETE
    USING (user_id = auth.uid());

-- Additional: Admin can view all sender profiles
CREATE POLICY "Admin can view all sender profiles" ON sender_profiles
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM admin_users au
            WHERE au.user_id = auth.uid()
            AND au.is_active = true
        )
    );

-- Additional: Connected receivers can view sender profiles (for ping info display)
CREATE POLICY "Connected receivers can view sender profiles" ON sender_profiles
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM connections c
            WHERE c.status = 'active'
            AND c.receiver_id = auth.uid()
            AND c.sender_id = sender_profiles.user_id
        )
    );

-- ============================================================================
-- STEP 4: RECEIVER_PROFILES TABLE POLICIES
-- Plan.md Requirements:
-- - "Receivers can view own profile" ON receiver_profiles FOR SELECT USING (user_id = auth.uid())
-- - "Receivers can update own profile" ON receiver_profiles FOR UPDATE USING (user_id = auth.uid())
-- - "Receivers can insert own profile" ON receiver_profiles FOR INSERT WITH CHECK (user_id = auth.uid())
-- ============================================================================

-- Drop existing policies
DROP POLICY IF EXISTS "Receivers can view own profile" ON receiver_profiles;
DROP POLICY IF EXISTS "Receivers can update own profile" ON receiver_profiles;
DROP POLICY IF EXISTS "Receivers can insert own profile" ON receiver_profiles;
DROP POLICY IF EXISTS "Receivers can delete own profile" ON receiver_profiles;
DROP POLICY IF EXISTS "Admin can view all receiver profiles" ON receiver_profiles;
DROP POLICY IF EXISTS "Connected senders can view receiver profiles" ON receiver_profiles;

-- Policy: Receivers can view own profile
CREATE POLICY "Receivers can view own profile" ON receiver_profiles
    FOR SELECT
    USING (user_id = auth.uid());

-- Policy: Receivers can update own profile
CREATE POLICY "Receivers can update own profile" ON receiver_profiles
    FOR UPDATE
    USING (user_id = auth.uid());

-- Policy: Receivers can insert own profile
CREATE POLICY "Receivers can insert own profile" ON receiver_profiles
    FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- Additional: Receivers can delete own profile (for account management)
CREATE POLICY "Receivers can delete own profile" ON receiver_profiles
    FOR DELETE
    USING (user_id = auth.uid());

-- Additional: Admin can view all receiver profiles
CREATE POLICY "Admin can view all receiver profiles" ON receiver_profiles
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM admin_users au
            WHERE au.user_id = auth.uid()
            AND au.is_active = true
        )
    );

-- Additional: Connected senders can view receiver profiles
CREATE POLICY "Connected senders can view receiver profiles" ON receiver_profiles
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM connections c
            WHERE c.status = 'active'
            AND c.sender_id = auth.uid()
            AND c.receiver_id = receiver_profiles.user_id
        )
    );

-- ============================================================================
-- STEP 5: UNIQUE_CODES TABLE POLICIES
-- Plan.md Requirements:
-- - "Receivers can view own code" ON unique_codes FOR SELECT USING (receiver_id = auth.uid())
-- - "Anyone can lookup active codes" ON unique_codes FOR SELECT USING (is_active = true)
-- ============================================================================

-- Drop existing policies
DROP POLICY IF EXISTS "Receivers can view own code" ON unique_codes;
DROP POLICY IF EXISTS "Anyone can lookup active codes" ON unique_codes;
DROP POLICY IF EXISTS "Receivers can create own code" ON unique_codes;
DROP POLICY IF EXISTS "Receivers can update own code" ON unique_codes;
DROP POLICY IF EXISTS "Admin can view all unique codes" ON unique_codes;

-- Policy: Receivers can view own code
CREATE POLICY "Receivers can view own code" ON unique_codes
    FOR SELECT
    USING (receiver_id = auth.uid());

-- Policy: Anyone can lookup active codes (for connection establishment)
CREATE POLICY "Anyone can lookup active codes" ON unique_codes
    FOR SELECT
    USING (is_active = true);

-- Additional: Receivers can create own code
CREATE POLICY "Receivers can create own code" ON unique_codes
    FOR INSERT
    WITH CHECK (receiver_id = auth.uid());

-- Additional: Receivers can update own code
CREATE POLICY "Receivers can update own code" ON unique_codes
    FOR UPDATE
    USING (receiver_id = auth.uid());

-- Additional: Admin can view all unique codes
CREATE POLICY "Admin can view all unique codes" ON unique_codes
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM admin_users au
            WHERE au.user_id = auth.uid()
            AND au.is_active = true
        )
    );

-- ============================================================================
-- STEP 6: CONNECTIONS TABLE POLICIES
-- Plan.md Requirements:
-- - "Users can view own connections" ON connections FOR SELECT USING (sender_id = auth.uid() OR receiver_id = auth.uid())
-- - "Users can create connections as sender" ON connections FOR INSERT WITH CHECK (sender_id = auth.uid())
-- - "Users can update own connections" ON connections FOR UPDATE USING (sender_id = auth.uid() OR receiver_id = auth.uid())
-- - "Users can delete own connections" ON connections FOR DELETE USING (sender_id = auth.uid() OR receiver_id = auth.uid())
-- ============================================================================

-- Drop existing policies
DROP POLICY IF EXISTS "Users can view own connections" ON connections;
DROP POLICY IF EXISTS "Users can create connections as sender" ON connections;
DROP POLICY IF EXISTS "Users can update own connections" ON connections;
DROP POLICY IF EXISTS "Users can delete own connections" ON connections;
DROP POLICY IF EXISTS "Users can view their connections" ON connections;
DROP POLICY IF EXISTS "Users can create connections" ON connections;
DROP POLICY IF EXISTS "Users can update their connections" ON connections;
DROP POLICY IF EXISTS "Users can delete their connections" ON connections;
DROP POLICY IF EXISTS "Admin can view all connections" ON connections;

-- Policy: Users can view own connections
CREATE POLICY "Users can view own connections" ON connections
    FOR SELECT
    USING (sender_id = auth.uid() OR receiver_id = auth.uid());

-- Policy: Users can create connections as sender
CREATE POLICY "Users can create connections as sender" ON connections
    FOR INSERT
    WITH CHECK (sender_id = auth.uid());

-- Policy: Users can update own connections
CREATE POLICY "Users can update own connections" ON connections
    FOR UPDATE
    USING (sender_id = auth.uid() OR receiver_id = auth.uid());

-- Policy: Users can delete own connections
CREATE POLICY "Users can delete own connections" ON connections
    FOR DELETE
    USING (sender_id = auth.uid() OR receiver_id = auth.uid());

-- Additional: Admin can view all connections
CREATE POLICY "Admin can view all connections" ON connections
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM admin_users au
            WHERE au.user_id = auth.uid()
            AND au.is_active = true
        )
    );

-- ============================================================================
-- STEP 7: PINGS TABLE POLICIES
-- Plan.md Requirements:
-- - "Users can view own pings" ON pings FOR SELECT USING (sender_id = auth.uid() OR receiver_id = auth.uid())
-- - "Senders can update own pings" ON pings FOR UPDATE USING (sender_id = auth.uid())
-- ============================================================================

-- Drop existing policies
DROP POLICY IF EXISTS "Users can view own pings" ON pings;
DROP POLICY IF EXISTS "Senders can update own pings" ON pings;
DROP POLICY IF EXISTS "System can create pings" ON pings;
DROP POLICY IF EXISTS "Connected users can view pings" ON pings;
DROP POLICY IF EXISTS "Users can create own pings" ON pings;
DROP POLICY IF EXISTS "Admin can view all pings" ON pings;

-- Policy: Users can view own pings
CREATE POLICY "Users can view own pings" ON pings
    FOR SELECT
    USING (sender_id = auth.uid() OR receiver_id = auth.uid());

-- Policy: Senders can update own pings
CREATE POLICY "Senders can update own pings" ON pings
    FOR UPDATE
    USING (sender_id = auth.uid());

-- Additional: System/users can create pings
CREATE POLICY "System can create pings" ON pings
    FOR INSERT
    WITH CHECK (sender_id = auth.uid() OR receiver_id = auth.uid());

-- Additional: Admin can view all pings
CREATE POLICY "Admin can view all pings" ON pings
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM admin_users au
            WHERE au.user_id = auth.uid()
            AND au.is_active = true
        )
    );

-- ============================================================================
-- STEP 8: BREAKS TABLE POLICIES
-- Plan.md Requirements:
-- - "Senders can view own breaks" ON breaks FOR SELECT USING (sender_id = auth.uid())
-- - "Senders can create own breaks" ON breaks FOR INSERT WITH CHECK (sender_id = auth.uid())
-- - "Senders can update own breaks" ON breaks FOR UPDATE USING (sender_id = auth.uid())
-- - "Senders can delete own breaks" ON breaks FOR DELETE USING (sender_id = auth.uid())
-- ============================================================================

-- Drop existing policies
DROP POLICY IF EXISTS "Senders can view own breaks" ON breaks;
DROP POLICY IF EXISTS "Senders can create own breaks" ON breaks;
DROP POLICY IF EXISTS "Senders can update own breaks" ON breaks;
DROP POLICY IF EXISTS "Senders can delete own breaks" ON breaks;
DROP POLICY IF EXISTS "Receivers can view connected sender breaks" ON breaks;
DROP POLICY IF EXISTS "Admin can view all breaks" ON breaks;

-- Policy: Senders can view own breaks
CREATE POLICY "Senders can view own breaks" ON breaks
    FOR SELECT
    USING (sender_id = auth.uid());

-- Policy: Senders can create own breaks
CREATE POLICY "Senders can create own breaks" ON breaks
    FOR INSERT
    WITH CHECK (sender_id = auth.uid());

-- Policy: Senders can update own breaks
CREATE POLICY "Senders can update own breaks" ON breaks
    FOR UPDATE
    USING (sender_id = auth.uid());

-- Policy: Senders can delete own breaks
CREATE POLICY "Senders can delete own breaks" ON breaks
    FOR DELETE
    USING (sender_id = auth.uid());

-- Additional: Receivers can view breaks for their connected senders
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

-- Additional: Admin can view all breaks
CREATE POLICY "Admin can view all breaks" ON breaks
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM admin_users au
            WHERE au.user_id = auth.uid()
            AND au.is_active = true
        )
    );

-- ============================================================================
-- STEP 9: NOTIFICATIONS TABLE POLICIES
-- Plan.md Requirements:
-- - "Users can view own notifications" ON notifications FOR SELECT USING (user_id = auth.uid())
-- - "Users can update own notifications" ON notifications FOR UPDATE USING (user_id = auth.uid())
-- ============================================================================

-- Drop existing policies
DROP POLICY IF EXISTS "Users can view own notifications" ON notifications;
DROP POLICY IF EXISTS "Users can update own notifications" ON notifications;
DROP POLICY IF EXISTS "System can insert notifications" ON notifications;
DROP POLICY IF EXISTS "Admin can view all notifications" ON notifications;

-- Policy: Users can view own notifications
CREATE POLICY "Users can view own notifications" ON notifications
    FOR SELECT
    USING (user_id = auth.uid());

-- Policy: Users can update own notifications
CREATE POLICY "Users can update own notifications" ON notifications
    FOR UPDATE
    USING (user_id = auth.uid());

-- Additional: System can insert notifications (for push notification system)
CREATE POLICY "System can insert notifications" ON notifications
    FOR INSERT
    WITH CHECK (true);

-- Additional: Admin can view all notifications
CREATE POLICY "Admin can view all notifications" ON notifications
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM admin_users au
            WHERE au.user_id = auth.uid()
            AND au.is_active = true
        )
    );

-- ============================================================================
-- STEP 10: AUDIT_LOGS TABLE POLICIES
-- Plan.md Requirements:
-- - "Users can view own audit logs" ON audit_logs FOR SELECT USING (user_id = auth.uid())
-- - "Admin can view all audit logs" ON audit_logs FOR SELECT for admin users
-- ============================================================================

-- Drop existing policies
DROP POLICY IF EXISTS "Users can view own audit logs" ON audit_logs;
DROP POLICY IF EXISTS "Admin can view all audit logs" ON audit_logs;
DROP POLICY IF EXISTS "System can insert audit logs" ON audit_logs;

-- Policy: Users can view own audit logs
CREATE POLICY "Users can view own audit logs" ON audit_logs
    FOR SELECT
    USING (user_id = auth.uid());

-- Policy: Admin can view all audit logs
CREATE POLICY "Admin can view all audit logs" ON audit_logs
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM admin_users au
            WHERE au.user_id = auth.uid()
            AND au.is_active = true
            AND au.role IN ('super_admin', 'admin')
        )
    );

-- Additional: System can insert audit logs
CREATE POLICY "System can insert audit logs" ON audit_logs
    FOR INSERT
    WITH CHECK (true);

-- ============================================================================
-- STEP 11: PAYMENT_TRANSACTIONS TABLE POLICIES
-- Plan.md Requirements:
-- - "Users can view own transactions" ON payment_transactions FOR SELECT USING (user_id = auth.uid())
-- ============================================================================

-- Drop existing policies
DROP POLICY IF EXISTS "Users can view own transactions" ON payment_transactions;
DROP POLICY IF EXISTS "Users can view own payments" ON payment_transactions;
DROP POLICY IF EXISTS "Admin can view all payments" ON payment_transactions;
DROP POLICY IF EXISTS "System can manage payments" ON payment_transactions;

-- Policy: Users can view own transactions
CREATE POLICY "Users can view own transactions" ON payment_transactions
    FOR SELECT
    USING (user_id = auth.uid());

-- Additional: Admin can view all payments
CREATE POLICY "Admin can view all payments" ON payment_transactions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM admin_users au
            WHERE au.user_id = auth.uid()
            AND au.is_active = true
        )
    );

-- Additional: System can manage payments (for webhook processing)
CREATE POLICY "System can manage payments" ON payment_transactions
    FOR ALL
    USING (true)
    WITH CHECK (true);

-- ============================================================================
-- STEP 12: HELPER FUNCTIONS FOR RLS
-- ============================================================================

-- Function to check if user is admin
CREATE OR REPLACE FUNCTION is_admin_user(check_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM admin_users
        WHERE user_id = check_user_id
        AND is_active = true
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Function to check if user is super admin
CREATE OR REPLACE FUNCTION is_super_admin(check_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM admin_users
        WHERE user_id = check_user_id
        AND is_active = true
        AND role = 'super_admin'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Grant execute on helper functions
GRANT EXECUTE ON FUNCTION is_admin_user TO authenticated;
GRANT EXECUTE ON FUNCTION is_super_admin TO authenticated;

-- ============================================================================
-- STEP 13: POLICY DOCUMENTATION COMMENTS
-- ============================================================================

-- Users table policies
COMMENT ON POLICY "Users can view own profile" ON users IS 'Plan.md 2.2: Users can view own profile';
COMMENT ON POLICY "Users can update own profile" ON users IS 'Plan.md 2.2: Users can update own profile';
COMMENT ON POLICY "Admin can view all users" ON users IS 'Plan.md 2.2: Admin can view all users';

-- Sender profiles policies
COMMENT ON POLICY "Senders can view own profile" ON sender_profiles IS 'Plan.md 2.2: Senders can view own profile';
COMMENT ON POLICY "Senders can update own profile" ON sender_profiles IS 'Plan.md 2.2: Senders can update own profile';
COMMENT ON POLICY "Senders can insert own profile" ON sender_profiles IS 'Plan.md 2.2: Senders can insert own profile';

-- Receiver profiles policies
COMMENT ON POLICY "Receivers can view own profile" ON receiver_profiles IS 'Plan.md 2.2: Receivers can view own profile';
COMMENT ON POLICY "Receivers can update own profile" ON receiver_profiles IS 'Plan.md 2.2: Receivers can update own profile';
COMMENT ON POLICY "Receivers can insert own profile" ON receiver_profiles IS 'Plan.md 2.2: Receivers can insert own profile';

-- Unique codes policies
COMMENT ON POLICY "Receivers can view own code" ON unique_codes IS 'Plan.md 2.2: Receivers can view own code';
COMMENT ON POLICY "Anyone can lookup active codes" ON unique_codes IS 'Plan.md 2.2: Anyone can lookup active codes';

-- Connections policies
COMMENT ON POLICY "Users can view own connections" ON connections IS 'Plan.md 2.2: Users can view own connections';
COMMENT ON POLICY "Users can create connections as sender" ON connections IS 'Plan.md 2.2: Users can create connections as sender';
COMMENT ON POLICY "Users can update own connections" ON connections IS 'Plan.md 2.2: Users can update own connections';
COMMENT ON POLICY "Users can delete own connections" ON connections IS 'Plan.md 2.2: Users can delete own connections';

-- Pings policies
COMMENT ON POLICY "Users can view own pings" ON pings IS 'Plan.md 2.2: Users can view own pings';
COMMENT ON POLICY "Senders can update own pings" ON pings IS 'Plan.md 2.2: Senders can update own pings';

-- Breaks policies
COMMENT ON POLICY "Senders can view own breaks" ON breaks IS 'Plan.md 2.2: Senders can view own breaks';
COMMENT ON POLICY "Senders can create own breaks" ON breaks IS 'Plan.md 2.2: Senders can create own breaks';
COMMENT ON POLICY "Senders can update own breaks" ON breaks IS 'Plan.md 2.2: Senders can update own breaks';
COMMENT ON POLICY "Senders can delete own breaks" ON breaks IS 'Plan.md 2.2: Senders can delete own breaks';

-- Notifications policies
COMMENT ON POLICY "Users can view own notifications" ON notifications IS 'Plan.md 2.2: Users can view own notifications';
COMMENT ON POLICY "Users can update own notifications" ON notifications IS 'Plan.md 2.2: Users can update own notifications';

-- Audit logs policies
COMMENT ON POLICY "Users can view own audit logs" ON audit_logs IS 'Plan.md 2.2: Users can view own audit logs';
COMMENT ON POLICY "Admin can view all audit logs" ON audit_logs IS 'Plan.md 2.2: Admin can view all audit logs';

-- Payment transactions policies
COMMENT ON POLICY "Users can view own transactions" ON payment_transactions IS 'Plan.md 2.2: Users can view own transactions';

-- ============================================================================
-- STEP 14: RLS POLICY VERIFICATION SUMMARY
-- ============================================================================

/*
COMPLETE RLS POLICY LIST - Plan.md Section 2.2 Compliance

TABLE: users
  [✓] "Users can view own profile" - SELECT - auth.uid() = id
  [✓] "Users can update own profile" - UPDATE - auth.uid() = id
  [✓] "Admin can view all users" - SELECT - admin check
  [+] "Users can insert own profile" - INSERT - auth.uid() = id (additional)
  [+] "Connected users can view profiles" - SELECT - connection check (additional)

TABLE: sender_profiles
  [✓] "Senders can view own profile" - SELECT - user_id = auth.uid()
  [✓] "Senders can update own profile" - UPDATE - user_id = auth.uid()
  [✓] "Senders can insert own profile" - INSERT - user_id = auth.uid()
  [+] "Senders can delete own profile" - DELETE - user_id = auth.uid() (additional)
  [+] "Admin can view all sender profiles" - SELECT - admin check (additional)
  [+] "Connected receivers can view sender profiles" - SELECT - connection check (additional)

TABLE: receiver_profiles
  [✓] "Receivers can view own profile" - SELECT - user_id = auth.uid()
  [✓] "Receivers can update own profile" - UPDATE - user_id = auth.uid()
  [✓] "Receivers can insert own profile" - INSERT - user_id = auth.uid()
  [+] "Receivers can delete own profile" - DELETE - user_id = auth.uid() (additional)
  [+] "Admin can view all receiver profiles" - SELECT - admin check (additional)
  [+] "Connected senders can view receiver profiles" - SELECT - connection check (additional)

TABLE: unique_codes
  [✓] "Receivers can view own code" - SELECT - receiver_id = auth.uid()
  [✓] "Anyone can lookup active codes" - SELECT - is_active = true
  [+] "Receivers can create own code" - INSERT - receiver_id = auth.uid() (additional)
  [+] "Receivers can update own code" - UPDATE - receiver_id = auth.uid() (additional)
  [+] "Admin can view all unique codes" - SELECT - admin check (additional)

TABLE: connections
  [✓] "Users can view own connections" - SELECT - sender_id = auth.uid() OR receiver_id = auth.uid()
  [✓] "Users can create connections as sender" - INSERT - sender_id = auth.uid()
  [✓] "Users can update own connections" - UPDATE - sender_id = auth.uid() OR receiver_id = auth.uid()
  [✓] "Users can delete own connections" - DELETE - sender_id = auth.uid() OR receiver_id = auth.uid()
  [+] "Admin can view all connections" - SELECT - admin check (additional)

TABLE: pings
  [✓] "Users can view own pings" - SELECT - sender_id = auth.uid() OR receiver_id = auth.uid()
  [✓] "Senders can update own pings" - UPDATE - sender_id = auth.uid()
  [+] "System can create pings" - INSERT - true (additional, for edge functions)
  [+] "Admin can view all pings" - SELECT - admin check (additional)

TABLE: breaks
  [✓] "Senders can view own breaks" - SELECT - sender_id = auth.uid()
  [✓] "Senders can create own breaks" - INSERT - sender_id = auth.uid()
  [✓] "Senders can update own breaks" - UPDATE - sender_id = auth.uid()
  [✓] "Senders can delete own breaks" - DELETE - sender_id = auth.uid()
  [+] "Receivers can view connected sender breaks" - SELECT - connection check (additional)
  [+] "Admin can view all breaks" - SELECT - admin check (additional)

TABLE: notifications
  [✓] "Users can view own notifications" - SELECT - user_id = auth.uid()
  [✓] "Users can update own notifications" - UPDATE - user_id = auth.uid()
  [+] "System can insert notifications" - INSERT - true (additional, for edge functions)
  [+] "Admin can view all notifications" - SELECT - admin check (additional)

TABLE: audit_logs
  [✓] "Users can view own audit logs" - SELECT - user_id = auth.uid()
  [✓] "Admin can view all audit logs" - SELECT - admin check (super_admin, admin only)
  [+] "System can insert audit logs" - INSERT - true (additional, for edge functions)

TABLE: payment_transactions
  [✓] "Users can view own transactions" - SELECT - user_id = auth.uid()
  [+] "Admin can view all payments" - SELECT - admin check (additional)
  [+] "System can manage payments" - ALL - true (additional, for webhooks)

Legend:
  [✓] = Required by plan.md Section 2.2
  [+] = Additional policies for complete functionality
*/
