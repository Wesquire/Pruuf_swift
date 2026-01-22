-- Admin Roles and Permissions Migration - Section 11.3
-- PRUUF iOS App - Comprehensive Admin Roles Configuration
-- This migration ensures proper configuration for Super Admin and plans Support Admin role

-- ============================================
-- SUPER ADMIN CONFIGURATION VERIFICATION
-- ============================================

-- Verify and ensure Super Admin (wesleymwilliams@gmail.com) has all required permissions:
-- - Full system access
-- - User management
-- - Subscription management
-- - System configuration
-- - View all data
-- - Export reports

-- Update Super Admin to ensure all permissions are set correctly
UPDATE public.admin_users
SET
    role = 'super_admin',
    is_active = true,
    permissions = jsonb_build_object(
        -- Full System Access
        'canModifySystemConfig', true,
        'canManageAdmins', true,

        -- User Management
        'canViewUsers', true,
        'canEditUsers', true,
        'canDeleteUsers', true,
        'canImpersonateUsers', true,

        -- Subscription Management
        'canViewSubscriptions', true,
        'canModifySubscriptions', true,
        'canIssueRefunds', true,

        -- System Configuration / View All Data
        'canViewSystemHealth', true,
        'canViewAnalytics', true,
        'canViewPayments', true,
        'canViewPaymentDetails', true,
        'canViewNotificationLogs', true,

        -- Export Reports
        'canExportAnalytics', true,
        'canSendBroadcasts', true
    ),
    updated_at = now()
WHERE email = 'wesleymwilliams@gmail.com';

-- Insert if not exists (in case the 004_admin_roles.sql was not run)
INSERT INTO public.admin_users (
    email,
    role,
    is_active,
    permissions
)
SELECT
    'wesleymwilliams@gmail.com',
    'super_admin',
    true,
    jsonb_build_object(
        'canModifySystemConfig', true,
        'canManageAdmins', true,
        'canViewUsers', true,
        'canEditUsers', true,
        'canDeleteUsers', true,
        'canImpersonateUsers', true,
        'canViewSubscriptions', true,
        'canModifySubscriptions', true,
        'canIssueRefunds', true,
        'canViewSystemHealth', true,
        'canViewAnalytics', true,
        'canViewPayments', true,
        'canViewPaymentDetails', true,
        'canViewNotificationLogs', true,
        'canExportAnalytics', true,
        'canSendBroadcasts', true
    )
WHERE NOT EXISTS (
    SELECT 1 FROM public.admin_users WHERE email = 'wesleymwilliams@gmail.com'
);

-- ============================================
-- SUPPORT ADMIN ROLE CONFIGURATION (FUTURE)
-- ============================================

-- Documentation for Support Admin role permissions:
-- The 'support' role is pre-configured with the following constraints:
--
-- ALLOWED:
--   - View user data (read-only)
--   - View subscriptions (read-only)
--
-- DENIED:
--   - Cannot modify data (canEditUsers, canDeleteUsers, canModifySubscriptions = false)
--   - Cannot access financial info (canViewPayments, canViewPaymentDetails = false)
--   - Cannot issue refunds (canIssueRefunds = false)
--   - Cannot impersonate users (canImpersonateUsers = false)
--   - Cannot view analytics (canViewAnalytics = false)
--   - Cannot export reports (canExportAnalytics = false)
--   - Cannot view system health (canViewSystemHealth = false)
--   - Cannot modify system config (canModifySystemConfig = false)
--   - Cannot manage admins (canManageAdmins = false)
--   - Cannot send broadcasts (canSendBroadcasts = false)
--   - Cannot view notification logs (canViewNotificationLogs = false)

-- Create a function to get default permissions for support role
CREATE OR REPLACE FUNCTION public.get_support_admin_permissions()
RETURNS JSONB AS $$
BEGIN
    RETURN jsonb_build_object(
        -- View user data (read-only)
        'canViewUsers', true,
        'canEditUsers', false,
        'canDeleteUsers', false,
        'canImpersonateUsers', false,

        -- View subscriptions (read-only)
        'canViewSubscriptions', true,
        'canModifySubscriptions', false,
        'canIssueRefunds', false,

        -- Cannot access financial info
        'canViewPayments', false,
        'canViewPaymentDetails', false,

        -- Other permissions (all denied)
        'canViewAnalytics', false,
        'canExportAnalytics', false,
        'canViewSystemHealth', false,
        'canModifySystemConfig', false,
        'canManageAdmins', false,
        'canSendBroadcasts', false,
        'canViewNotificationLogs', false
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================
-- RLS POLICIES FOR SUPPORT ADMIN CONSTRAINTS
-- ============================================

-- Policy: Support admins can only view user data (SELECT only)
DROP POLICY IF EXISTS "Support admins can view users" ON public.users;
CREATE POLICY "Support admins can view users"
ON public.users
FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.admin_users au
        WHERE au.user_id = auth.uid()
        AND au.role = 'support'
        AND au.is_active = true
    )
);

-- Policy: Support admins can view subscriptions (via receiver_profiles)
DROP POLICY IF EXISTS "Support admins can view receiver profiles" ON public.receiver_profiles;
CREATE POLICY "Support admins can view receiver profiles"
ON public.receiver_profiles
FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.admin_users au
        WHERE au.user_id = auth.uid()
        AND au.role = 'support'
        AND au.is_active = true
    )
);

-- Policy: Support admins can view sender profiles
DROP POLICY IF EXISTS "Support admins can view sender profiles" ON public.sender_profiles;
CREATE POLICY "Support admins can view sender profiles"
ON public.sender_profiles
FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.admin_users au
        WHERE au.user_id = auth.uid()
        AND au.role = 'support'
        AND au.is_active = true
    )
);

-- Policy: Support admins can view connections (read-only)
DROP POLICY IF EXISTS "Support admins can view connections" ON public.connections;
CREATE POLICY "Support admins can view connections"
ON public.connections
FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.admin_users au
        WHERE au.user_id = auth.uid()
        AND au.role = 'support'
        AND au.is_active = true
    )
);

-- Policy: Support admins can view pings (read-only)
DROP POLICY IF EXISTS "Support admins can view pings" ON public.pings;
CREATE POLICY "Support admins can view pings"
ON public.pings
FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.admin_users au
        WHERE au.user_id = auth.uid()
        AND au.role = 'support'
        AND au.is_active = true
    )
);

-- Policy: Support admins CANNOT view payment_transactions (financial info)
-- No policy created means access is denied by default with RLS enabled

-- ============================================
-- PERMISSION CHECK FUNCTIONS
-- ============================================

-- Function to check if a user has permission for a specific action
CREATE OR REPLACE FUNCTION public.admin_has_permission(
    p_permission TEXT,
    p_user_uuid UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN AS $$
DECLARE
    v_permissions JSONB;
    v_role admin_role;
BEGIN
    -- Get the admin's permissions and role
    SELECT permissions, role INTO v_permissions, v_role
    FROM public.admin_users
    WHERE user_id = p_user_uuid
    AND is_active = true;

    -- If not an admin, deny
    IF v_permissions IS NULL THEN
        RETURN false;
    END IF;

    -- Super admins always have all permissions
    IF v_role = 'super_admin' THEN
        RETURN true;
    END IF;

    -- Check specific permission in JSONB
    RETURN COALESCE((v_permissions ->> p_permission)::BOOLEAN, false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check if support admin can access data (read-only checks)
CREATE OR REPLACE FUNCTION public.is_support_admin_read_only_access(p_user_uuid UUID DEFAULT auth.uid())
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.admin_users
        WHERE user_id = p_user_uuid
        AND role = 'support'
        AND is_active = true
        AND (permissions->>'canViewUsers')::BOOLEAN = true
        AND (permissions->>'canEditUsers')::BOOLEAN = false
        AND (permissions->>'canViewPayments')::BOOLEAN = false
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to verify support admin cannot access financial data
CREATE OR REPLACE FUNCTION public.support_admin_cannot_access_financial()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.admin_users
        WHERE user_id = auth.uid()
        AND role = 'support'
        AND is_active = true
    ) THEN
        RAISE EXCEPTION 'Support admins cannot access financial data';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- ADMIN ROLE DEFINITIONS DOCUMENTATION TABLE
-- ============================================

-- Create a table to document role definitions
CREATE TABLE IF NOT EXISTS public.admin_role_definitions (
    role admin_role PRIMARY KEY,
    display_name TEXT NOT NULL,
    description TEXT NOT NULL,
    allowed_permissions TEXT[] NOT NULL,
    denied_permissions TEXT[] NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS on role definitions (read-only for all admins)
ALTER TABLE public.admin_role_definitions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can view role definitions"
ON public.admin_role_definitions
FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.admin_users
        WHERE user_id = auth.uid()
        AND is_active = true
    )
);

-- Insert role definitions
INSERT INTO public.admin_role_definitions (role, display_name, description, allowed_permissions, denied_permissions)
VALUES
    (
        'super_admin',
        'Super Admin',
        'Full system access including user management, subscription management, system configuration, view all data, and export reports',
        ARRAY[
            'canViewUsers', 'canEditUsers', 'canDeleteUsers', 'canImpersonateUsers',
            'canViewAnalytics', 'canExportAnalytics',
            'canViewSubscriptions', 'canModifySubscriptions', 'canIssueRefunds',
            'canViewPayments', 'canViewPaymentDetails',
            'canViewSystemHealth', 'canModifySystemConfig',
            'canManageAdmins', 'canSendBroadcasts', 'canViewNotificationLogs'
        ],
        ARRAY[]::TEXT[]
    ),
    (
        'admin',
        'Admin',
        'User management, analytics dashboard, and payment oversight without system configuration or admin management',
        ARRAY[
            'canViewUsers', 'canEditUsers', 'canImpersonateUsers',
            'canViewAnalytics', 'canExportAnalytics',
            'canViewSubscriptions', 'canModifySubscriptions',
            'canViewPayments', 'canViewPaymentDetails',
            'canViewSystemHealth', 'canSendBroadcasts', 'canViewNotificationLogs'
        ],
        ARRAY['canDeleteUsers', 'canIssueRefunds', 'canModifySystemConfig', 'canManageAdmins']
    ),
    (
        'moderator',
        'Moderator',
        'User management and content moderation without payment or system access',
        ARRAY['canViewUsers', 'canEditUsers', 'canViewAnalytics', 'canViewSubscriptions', 'canViewNotificationLogs'],
        ARRAY[
            'canDeleteUsers', 'canImpersonateUsers', 'canExportAnalytics',
            'canModifySubscriptions', 'canIssueRefunds',
            'canViewPayments', 'canViewPaymentDetails',
            'canViewSystemHealth', 'canModifySystemConfig',
            'canManageAdmins', 'canSendBroadcasts'
        ]
    ),
    (
        'support',
        'Support Admin',
        'View user data (read-only), view subscriptions (read-only), cannot modify data, cannot access financial info',
        ARRAY['canViewUsers', 'canViewSubscriptions'],
        ARRAY[
            'canEditUsers', 'canDeleteUsers', 'canImpersonateUsers',
            'canViewAnalytics', 'canExportAnalytics',
            'canModifySubscriptions', 'canIssueRefunds',
            'canViewPayments', 'canViewPaymentDetails',
            'canViewSystemHealth', 'canModifySystemConfig',
            'canManageAdmins', 'canSendBroadcasts', 'canViewNotificationLogs'
        ]
    ),
    (
        'viewer',
        'Viewer',
        'Read-only access to dashboards, analytics, and system health without user management',
        ARRAY['canViewUsers', 'canViewAnalytics', 'canViewSubscriptions', 'canViewSystemHealth'],
        ARRAY[
            'canEditUsers', 'canDeleteUsers', 'canImpersonateUsers',
            'canExportAnalytics', 'canModifySubscriptions', 'canIssueRefunds',
            'canViewPayments', 'canViewPaymentDetails',
            'canModifySystemConfig', 'canManageAdmins',
            'canSendBroadcasts', 'canViewNotificationLogs'
        ]
    )
ON CONFLICT (role) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    allowed_permissions = EXCLUDED.allowed_permissions,
    denied_permissions = EXCLUDED.denied_permissions,
    updated_at = now();

-- ============================================
-- FUTURE SUPPORT ADMIN CREATION HELPER
-- ============================================

-- Function to create a support admin user (for future use)
CREATE OR REPLACE FUNCTION public.create_support_admin(
    p_email TEXT,
    p_created_by_admin_id UUID DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_new_admin_id UUID;
BEGIN
    -- Verify caller is super_admin or admin
    IF NOT EXISTS (
        SELECT 1 FROM public.admin_users
        WHERE user_id = auth.uid()
        AND role IN ('super_admin', 'admin')
        AND is_active = true
    ) THEN
        RAISE EXCEPTION 'Only super_admin or admin can create support admins';
    END IF;

    -- Create the support admin
    INSERT INTO public.admin_users (
        email,
        role,
        is_active,
        permissions,
        created_by
    )
    VALUES (
        p_email,
        'support',
        true,
        public.get_support_admin_permissions(),
        COALESCE(p_created_by_admin_id, (SELECT id FROM public.admin_users WHERE user_id = auth.uid()))
    )
    RETURNING id INTO v_new_admin_id;

    -- Log the action
    PERFORM public.log_admin_action(
        'create_support_admin',
        'admin_users',
        v_new_admin_id,
        jsonb_build_object('email', p_email)
    );

    RETURN v_new_admin_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- GRANTS
-- ============================================

GRANT EXECUTE ON FUNCTION public.get_support_admin_permissions() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_has_permission(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_support_admin_read_only_access(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_support_admin(TEXT, UUID) TO authenticated;
GRANT SELECT ON public.admin_role_definitions TO authenticated;

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON FUNCTION public.get_support_admin_permissions() IS 'Returns the default JSONB permissions for support admin role - read-only access, no financial data';
COMMENT ON FUNCTION public.admin_has_permission(TEXT, UUID) IS 'Check if an admin user has a specific permission';
COMMENT ON FUNCTION public.is_support_admin_read_only_access(UUID) IS 'Verify a user is a support admin with proper read-only constraints';
COMMENT ON FUNCTION public.create_support_admin(TEXT, UUID) IS 'Create a new support admin user with proper permissions (future use)';
COMMENT ON TABLE public.admin_role_definitions IS 'Documentation table for admin role definitions and their permissions';

-- ============================================
-- VERIFICATION QUERIES (for debugging)
-- ============================================

-- Uncomment to verify Super Admin configuration:
-- SELECT email, role, is_active, permissions FROM public.admin_users WHERE email = 'wesleymwilliams@gmail.com';

-- Uncomment to verify role definitions:
-- SELECT * FROM public.admin_role_definitions;
