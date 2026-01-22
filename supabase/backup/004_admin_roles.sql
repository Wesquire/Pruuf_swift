-- Admin Roles and Permissions Migration
-- PRUUF iOS App - Admin Dashboard Configuration
-- This migration creates the admin roles system and seeds the initial super admin

-- ============================================
-- ADMIN ROLES ENUM
-- ============================================

-- Create enum type for admin roles
DO $$ BEGIN
    CREATE TYPE admin_role AS ENUM (
        'super_admin',
        'admin',
        'moderator',
        'support',
        'viewer'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- ============================================
-- ADMIN USERS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.admin_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT UNIQUE NOT NULL,
    role admin_role NOT NULL DEFAULT 'viewer',
    is_active BOOLEAN NOT NULL DEFAULT true,

    -- Permissions (granular override of role defaults)
    permissions JSONB NOT NULL DEFAULT '{}',

    -- Security tracking
    last_login_at TIMESTAMPTZ,
    failed_login_attempts INTEGER NOT NULL DEFAULT 0,
    locked_until TIMESTAMPTZ,
    mfa_enabled BOOLEAN NOT NULL DEFAULT false,

    -- Metadata
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID REFERENCES public.admin_users(id),

    -- Constraints
    CONSTRAINT valid_email CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_admin_users_email ON public.admin_users(email);
CREATE INDEX IF NOT EXISTS idx_admin_users_user_id ON public.admin_users(user_id);
CREATE INDEX IF NOT EXISTS idx_admin_users_role ON public.admin_users(role);
CREATE INDEX IF NOT EXISTS idx_admin_users_is_active ON public.admin_users(is_active);

-- ============================================
-- ADMIN AUDIT LOG TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.admin_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID NOT NULL REFERENCES public.admin_users(id),
    action TEXT NOT NULL,
    resource_type TEXT NOT NULL,
    resource_id UUID,
    details JSONB DEFAULT '{}',
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create indexes for audit log queries
CREATE INDEX IF NOT EXISTS idx_admin_audit_log_admin_id ON public.admin_audit_log(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_log_action ON public.admin_audit_log(action);
CREATE INDEX IF NOT EXISTS idx_admin_audit_log_resource ON public.admin_audit_log(resource_type, resource_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_log_created_at ON public.admin_audit_log(created_at);

-- ============================================
-- ADMIN SESSIONS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.admin_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID NOT NULL REFERENCES public.admin_users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL,
    ip_address INET,
    user_agent TEXT,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_activity_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create indexes for session management
CREATE INDEX IF NOT EXISTS idx_admin_sessions_admin_id ON public.admin_sessions(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_sessions_expires_at ON public.admin_sessions(expires_at);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

-- Enable RLS on admin tables
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_sessions ENABLE ROW LEVEL SECURITY;

-- Admin users policies
-- Super admins can do everything
CREATE POLICY "Super admins have full access to admin_users"
ON public.admin_users
FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM public.admin_users au
        WHERE au.user_id = auth.uid()
        AND au.role = 'super_admin'
        AND au.is_active = true
    )
);

-- Admins can view all admin users
CREATE POLICY "Admins can view admin_users"
ON public.admin_users
FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.admin_users au
        WHERE au.user_id = auth.uid()
        AND au.role IN ('super_admin', 'admin')
        AND au.is_active = true
    )
);

-- Users can view their own admin record
CREATE POLICY "Users can view own admin record"
ON public.admin_users
FOR SELECT
USING (user_id = auth.uid());

-- Audit log policies
-- All admins can view audit logs
CREATE POLICY "Admins can view audit logs"
ON public.admin_audit_log
FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.admin_users au
        WHERE au.user_id = auth.uid()
        AND au.is_active = true
    )
);

-- System/service role can insert audit logs
CREATE POLICY "System can insert audit logs"
ON public.admin_audit_log
FOR INSERT
WITH CHECK (true);

-- Session policies
-- Users can only access their own sessions
CREATE POLICY "Users can view own sessions"
ON public.admin_sessions
FOR SELECT
USING (
    admin_id IN (
        SELECT id FROM public.admin_users WHERE user_id = auth.uid()
    )
);

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Function to check if user is admin
CREATE OR REPLACE FUNCTION public.is_admin(user_uuid UUID DEFAULT auth.uid())
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.admin_users
        WHERE user_id = user_uuid
        AND is_active = true
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check if user has specific admin role
CREATE OR REPLACE FUNCTION public.has_admin_role(required_role admin_role, user_uuid UUID DEFAULT auth.uid())
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.admin_users
        WHERE user_id = user_uuid
        AND is_active = true
        AND (
            role = 'super_admin' OR
            role = required_role
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get admin role for user
CREATE OR REPLACE FUNCTION public.get_admin_role(user_uuid UUID DEFAULT auth.uid())
RETURNS admin_role AS $$
DECLARE
    user_role admin_role;
BEGIN
    SELECT role INTO user_role
    FROM public.admin_users
    WHERE user_id = user_uuid
    AND is_active = true;

    RETURN user_role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to log admin action
CREATE OR REPLACE FUNCTION public.log_admin_action(
    p_action TEXT,
    p_resource_type TEXT,
    p_resource_id UUID DEFAULT NULL,
    p_details JSONB DEFAULT '{}'
)
RETURNS UUID AS $$
DECLARE
    v_admin_id UUID;
    v_log_id UUID;
BEGIN
    -- Get admin ID for current user
    SELECT id INTO v_admin_id
    FROM public.admin_users
    WHERE user_id = auth.uid();

    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'User is not an admin';
    END IF;

    -- Insert audit log entry
    INSERT INTO public.admin_audit_log (admin_id, action, resource_type, resource_id, details)
    VALUES (v_admin_id, p_action, p_resource_type, p_resource_id, p_details)
    RETURNING id INTO v_log_id;

    RETURN v_log_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to update admin user timestamp
CREATE OR REPLACE FUNCTION public.update_admin_user_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for updated_at
DROP TRIGGER IF EXISTS trigger_admin_users_updated_at ON public.admin_users;
CREATE TRIGGER trigger_admin_users_updated_at
    BEFORE UPDATE ON public.admin_users
    FOR EACH ROW
    EXECUTE FUNCTION public.update_admin_user_timestamp();

-- ============================================
-- SEED SUPER ADMIN USER
-- ============================================

-- Note: The actual user must be created in Supabase Auth first
-- This inserts the admin_users record for the super admin
-- The password 'W@$hingt0n1' should be set via Supabase Auth dashboard or CLI

-- Insert super admin credentials reference
-- This will be linked to the auth.users record once created
INSERT INTO public.admin_users (
    email,
    role,
    is_active,
    permissions,
    mfa_enabled
) VALUES (
    'wesleymwilliams@gmail.com',
    'super_admin',
    true,
    '{
        "canViewUsers": true,
        "canEditUsers": true,
        "canDeleteUsers": true,
        "canImpersonateUsers": true,
        "canViewAnalytics": true,
        "canExportAnalytics": true,
        "canViewSubscriptions": true,
        "canModifySubscriptions": true,
        "canIssueRefunds": true,
        "canViewPayments": true,
        "canViewPaymentDetails": true,
        "canViewSystemHealth": true,
        "canModifySystemConfig": true,
        "canManageAdmins": true,
        "canSendBroadcasts": true,
        "canViewNotificationLogs": true
    }',
    false
) ON CONFLICT (email) DO UPDATE SET
    role = 'super_admin',
    is_active = true,
    permissions = EXCLUDED.permissions,
    updated_at = now();

-- ============================================
-- GRANTS
-- ============================================

-- Grant access to authenticated users (actual permissions controlled by RLS)
GRANT SELECT ON public.admin_users TO authenticated;
GRANT SELECT ON public.admin_audit_log TO authenticated;
GRANT SELECT ON public.admin_sessions TO authenticated;

-- Grant insert to audit log for service role
GRANT INSERT ON public.admin_audit_log TO service_role;

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON TABLE public.admin_users IS 'Admin users with roles and permissions for the PRUUF admin dashboard';
COMMENT ON TABLE public.admin_audit_log IS 'Audit log tracking all admin actions for security and compliance';
COMMENT ON TABLE public.admin_sessions IS 'Active admin sessions for session management';

COMMENT ON COLUMN public.admin_users.role IS 'Admin role: super_admin, admin, moderator, support, viewer';
COMMENT ON COLUMN public.admin_users.permissions IS 'JSON object with granular permission overrides';
COMMENT ON COLUMN public.admin_users.locked_until IS 'Account lockout timestamp after failed login attempts';

COMMENT ON FUNCTION public.is_admin IS 'Check if a user has any admin role';
COMMENT ON FUNCTION public.has_admin_role IS 'Check if a user has a specific admin role or higher';
COMMENT ON FUNCTION public.log_admin_action IS 'Log an admin action to the audit log';
