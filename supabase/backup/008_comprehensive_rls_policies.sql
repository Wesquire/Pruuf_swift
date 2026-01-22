-- Migration: 008_comprehensive_rls_policies.sql
-- Description: Comprehensive Row Level Security (RLS) Policies for all PRUUF tables
-- Phase 2 Section 2.2: Row Level Security (RLS) Policies
-- Created: 2026-01-17
--
-- This migration ensures all tables have proper RLS policies as specified in plan.md
-- It adds missing admin access policies and ensures connected-user visibility

-- ============================================================================
-- 1. ADMIN ACCESS POLICIES FOR USERS TABLE
-- Plan.md Section 2.2 specifies: "Admins can view all users"
-- ============================================================================

-- Drop existing admin policy if it exists
DROP POLICY IF EXISTS "Admin can view all users" ON users;

-- Admins can view all users (using admin_users table check)
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

-- Super admins can update any user (for admin dashboard operations)
DROP POLICY IF EXISTS "Super admin can update all users" ON users;
CREATE POLICY "Super admin can update all users" ON users
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM admin_users au
            WHERE au.user_id = auth.uid()
            AND au.is_active = true
            AND au.role = 'super_admin'
        )
    );

-- ============================================================================
-- 2. ADMIN ACCESS POLICIES FOR AUDIT_LOGS TABLE
-- Plan.md Section 2.2 specifies: "Admin can view all audit logs"
-- ============================================================================

-- Drop existing admin policy if it exists
DROP POLICY IF EXISTS "Admin can view all audit logs" ON audit_logs;

-- Admins can view all audit logs
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

-- Allow system/service role to insert audit logs
DROP POLICY IF EXISTS "System can insert audit logs" ON audit_logs;
CREATE POLICY "System can insert audit logs" ON audit_logs
    FOR INSERT
    WITH CHECK (true);

-- ============================================================================
-- 3. ADMIN ACCESS POLICIES FOR SENDER_PROFILES TABLE
-- Allow admins to view sender profiles for dashboard
-- ============================================================================

-- Drop if exists to avoid conflicts
DROP POLICY IF EXISTS "Admin can view all sender profiles" ON sender_profiles;

-- Admins can view all sender profiles
CREATE POLICY "Admin can view all sender profiles" ON sender_profiles
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM admin_users au
            WHERE au.user_id = auth.uid()
            AND au.is_active = true
        )
    );

-- Connected receivers can view sender profiles
DROP POLICY IF EXISTS "Connected receivers can view sender profiles" ON sender_profiles;
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
-- 4. ADMIN ACCESS POLICIES FOR RECEIVER_PROFILES TABLE
-- Allow admins to view receiver profiles for dashboard
-- ============================================================================

-- Drop if exists to avoid conflicts
DROP POLICY IF EXISTS "Admin can view all receiver profiles" ON receiver_profiles;

-- Admins can view all receiver profiles
CREATE POLICY "Admin can view all receiver profiles" ON receiver_profiles
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM admin_users au
            WHERE au.user_id = auth.uid()
            AND au.is_active = true
        )
    );

-- Connected senders can view receiver profiles (for connection info)
DROP POLICY IF EXISTS "Connected senders can view receiver profiles" ON receiver_profiles;
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
-- 5. ADMIN ACCESS POLICIES FOR CONNECTIONS TABLE
-- Allow admins to view all connections for dashboard
-- ============================================================================

-- Drop if exists
DROP POLICY IF EXISTS "Admin can view all connections" ON connections;

-- Admins can view all connections
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
-- 6. ADMIN ACCESS POLICIES FOR PINGS TABLE
-- Allow admins to view all pings for dashboard and analytics
-- ============================================================================

-- Drop if exists
DROP POLICY IF EXISTS "Admin can view all pings" ON pings;

-- Admins can view all pings
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
-- 7. ADMIN ACCESS POLICIES FOR BREAKS TABLE
-- Allow admins to view all breaks for dashboard
-- ============================================================================

-- Drop if exists
DROP POLICY IF EXISTS "Admin can view all breaks" ON breaks;

-- Admins can view all breaks
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
-- 8. ADMIN ACCESS POLICIES FOR NOTIFICATIONS TABLE
-- Allow admins to view all notifications for debugging
-- ============================================================================

-- Drop if exists
DROP POLICY IF EXISTS "Admin can view all notifications" ON notifications;

-- Admins can view all notifications
CREATE POLICY "Admin can view all notifications" ON notifications
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM admin_users au
            WHERE au.user_id = auth.uid()
            AND au.is_active = true
        )
    );

-- Allow system to insert notifications (for push notification system)
DROP POLICY IF EXISTS "System can insert notifications" ON notifications;
CREATE POLICY "System can insert notifications" ON notifications
    FOR INSERT
    WITH CHECK (true);

-- ============================================================================
-- 9. ADMIN ACCESS POLICIES FOR PAYMENT_TRANSACTIONS TABLE
-- Allow admins to view all payments for financial dashboard
-- ============================================================================

-- Drop if exists
DROP POLICY IF EXISTS "Admin can view all payments" ON payment_transactions;

-- Admins can view all payment transactions
CREATE POLICY "Admin can view all payments" ON payment_transactions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM admin_users au
            WHERE au.user_id = auth.uid()
            AND au.is_active = true
        )
    );

-- Allow system to manage payment transactions (for webhook processing)
DROP POLICY IF EXISTS "System can manage payments" ON payment_transactions;
CREATE POLICY "System can manage payments" ON payment_transactions
    FOR ALL
    USING (true)
    WITH CHECK (true);

-- ============================================================================
-- 10. ADMIN ACCESS POLICIES FOR UNIQUE_CODES TABLE
-- Allow admins to view all unique codes
-- ============================================================================

-- Drop if exists
DROP POLICY IF EXISTS "Admin can view all unique codes" ON unique_codes;

-- Admins can view all unique codes
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
-- 11. HELPER FUNCTION: Check if user is admin
-- This function provides a cleaner way to check admin status in policies
-- ============================================================================

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

-- ============================================================================
-- 12. GRANT EXECUTE ON HELPER FUNCTIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION is_admin_user TO authenticated;
GRANT EXECUTE ON FUNCTION is_super_admin TO authenticated;

-- ============================================================================
-- 13. DOCUMENTATION COMMENTS
-- ============================================================================

COMMENT ON POLICY "Admin can view all users" ON users IS 'Allows admin dashboard users to view all user records';
COMMENT ON POLICY "Super admin can update all users" ON users IS 'Allows super admins to modify user records from dashboard';
COMMENT ON POLICY "Admin can view all audit logs" ON audit_logs IS 'Allows admin dashboard users to view full audit trail';
COMMENT ON POLICY "Admin can view all sender profiles" ON sender_profiles IS 'Allows admin dashboard to view all sender settings';
COMMENT ON POLICY "Admin can view all receiver profiles" ON receiver_profiles IS 'Allows admin dashboard to view all receiver settings';
COMMENT ON POLICY "Admin can view all connections" ON connections IS 'Allows admin dashboard to view all sender-receiver connections';
COMMENT ON POLICY "Admin can view all pings" ON pings IS 'Allows admin dashboard to view all ping history for analytics';
COMMENT ON POLICY "Admin can view all breaks" ON breaks IS 'Allows admin dashboard to view all scheduled breaks';
COMMENT ON POLICY "Admin can view all notifications" ON notifications IS 'Allows admin dashboard to debug notification delivery';
COMMENT ON POLICY "Admin can view all payments" ON payment_transactions IS 'Allows admin dashboard to view financial data';
COMMENT ON POLICY "Admin can view all unique codes" ON unique_codes IS 'Allows admin dashboard to view receiver connection codes';

COMMENT ON FUNCTION is_admin_user IS 'Check if a user has any admin role (any level)';
COMMENT ON FUNCTION is_super_admin IS 'Check if a user has super_admin role';

-- ============================================================================
-- 14. RLS POLICY SUMMARY
-- ============================================================================

/*
TABLE: users
  - Users can view own profile (SELECT) ✓
  - Users can update own profile (UPDATE) ✓
  - Users can insert own profile (INSERT) ✓
  - Connected users can view profiles (SELECT) ✓
  - Admin can view all users (SELECT) ✓ [NEW]
  - Super admin can update all users (UPDATE) ✓ [NEW]

TABLE: sender_profiles
  - Senders can view own profile (SELECT) ✓
  - Senders can update own profile (UPDATE) ✓
  - Senders can insert own profile (INSERT) ✓
  - Senders can delete own profile (DELETE) ✓
  - Admin can view all sender profiles (SELECT) ✓ [NEW]
  - Connected receivers can view sender profiles (SELECT) ✓ [NEW]

TABLE: receiver_profiles
  - Receivers can view own profile (SELECT) ✓
  - Receivers can update own profile (UPDATE) ✓
  - Receivers can insert own profile (INSERT) ✓
  - Receivers can delete own profile (DELETE) ✓
  - Admin can view all receiver profiles (SELECT) ✓ [NEW]
  - Connected senders can view receiver profiles (SELECT) ✓ [NEW]

TABLE: unique_codes
  - Receivers can view own code (SELECT) ✓
  - Anyone can lookup active codes (SELECT) ✓
  - Receivers can create own code (INSERT) ✓
  - Receivers can update own code (UPDATE) ✓
  - Admin can view all unique codes (SELECT) ✓ [NEW]

TABLE: connections
  - Users can view own connections (SELECT) ✓
  - Users can create connections as sender (INSERT) ✓
  - Users can update own connections (UPDATE) ✓
  - Users can delete own connections (DELETE) ✓
  - Admin can view all connections (SELECT) ✓ [NEW]

TABLE: pings
  - Users can view own pings (SELECT) ✓
  - Senders can update own pings (UPDATE) ✓
  - System can create pings (INSERT) ✓
  - Admin can view all pings (SELECT) ✓ [NEW]

TABLE: breaks
  - Senders can view own breaks (SELECT) ✓
  - Senders can create own breaks (INSERT) ✓
  - Senders can update own breaks (UPDATE) ✓
  - Senders can delete own breaks (DELETE) ✓
  - Receivers can view connected sender breaks (SELECT) ✓
  - Admin can view all breaks (SELECT) ✓ [NEW]

TABLE: notifications
  - Users can view own notifications (SELECT) ✓
  - Users can update own notifications (UPDATE) ✓
  - System can insert notifications (INSERT) ✓ [NEW]
  - Admin can view all notifications (SELECT) ✓ [NEW]

TABLE: audit_logs
  - Users can view own audit logs (SELECT) ✓
  - Admin can view all audit logs (SELECT) ✓ [NEW]
  - System can insert audit logs (INSERT) ✓ [NEW]

TABLE: payment_transactions
  - Users can view own payments (SELECT) ✓
  - Admin can view all payments (SELECT) ✓ [NEW]
  - System can manage payments (ALL) ✓ [NEW]
*/
