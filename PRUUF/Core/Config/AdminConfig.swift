import Foundation

/// Admin Dashboard Configuration
/// Defines admin access credentials and permissions
///
/// IMPORTANT: In production, sensitive credentials should be stored securely
/// using environment variables or a secure secrets manager, not in source code.
/// This file documents the admin configuration structure.

// MARK: - Admin Role Enumeration

/// Defines the different admin role levels in the PRUUF system
public enum AdminRole: String, Codable, CaseIterable {
    case superAdmin = "super_admin"
    case admin = "admin"
    case moderator = "moderator"
    case support = "support"
    case viewer = "viewer"

    /// Human-readable display name for the role
    public var displayName: String {
        switch self {
        case .superAdmin: return "Super Admin"
        case .admin: return "Admin"
        case .moderator: return "Moderator"
        case .support: return "Support"
        case .viewer: return "Viewer"
        }
    }

    /// Description of role capabilities
    public var description: String {
        switch self {
        case .superAdmin:
            return "Full system access including analytics, user management, payment oversight, and system configuration"
        case .admin:
            return "User management, analytics dashboard, and payment oversight"
        case .moderator:
            return "User management and content moderation"
        case .support:
            return "View user details and handle support requests"
        case .viewer:
            return "Read-only access to dashboards and analytics"
        }
    }
}

// MARK: - Admin Permissions

/// Granular permissions for admin users
public struct AdminPermissions: Codable, Equatable {
    // User Management
    public var canViewUsers: Bool
    public var canEditUsers: Bool
    public var canDeleteUsers: Bool
    public var canImpersonateUsers: Bool

    // Analytics
    public var canViewAnalytics: Bool
    public var canExportAnalytics: Bool

    // Subscriptions
    public var canViewSubscriptions: Bool
    public var canModifySubscriptions: Bool
    public var canIssueRefunds: Bool

    // Payments
    public var canViewPayments: Bool
    public var canViewPaymentDetails: Bool

    // System
    public var canViewSystemHealth: Bool
    public var canModifySystemConfig: Bool
    public var canManageAdmins: Bool

    // Notifications
    public var canSendBroadcasts: Bool
    public var canViewNotificationLogs: Bool

    /// Default permissions for a given role
    public static func defaultPermissions(for role: AdminRole) -> AdminPermissions {
        switch role {
        case .superAdmin:
            // SUPER ADMIN ROLE (Section 11.3)
            // Configured for wesleymwilliams@gmail.com
            // Full permissions as defined in plan.md Section 11.3:
            // - Full system access
            // - User management
            // - Subscription management
            // - System configuration
            // - View all data
            // - Export reports
            return AdminPermissions(
                // User Management
                canViewUsers: true,           // View all data
                canEditUsers: true,           // User management
                canDeleteUsers: true,         // User management
                canImpersonateUsers: true,    // User management / Full system access

                // View All Data + Export Reports
                canViewAnalytics: true,       // View all data
                canExportAnalytics: true,     // Export reports

                // Subscription Management
                canViewSubscriptions: true,   // Subscription management
                canModifySubscriptions: true, // Subscription management
                canIssueRefunds: true,        // Subscription management

                // View All Data (Financial)
                canViewPayments: true,        // View all data
                canViewPaymentDetails: true,  // View all data

                // System Configuration / Full System Access
                canViewSystemHealth: true,    // System configuration
                canModifySystemConfig: true,  // System configuration
                canManageAdmins: true,        // Full system access
                canSendBroadcasts: true,      // Full system access
                canViewNotificationLogs: true // View all data
            )

        case .admin:
            return AdminPermissions(
                canViewUsers: true,
                canEditUsers: true,
                canDeleteUsers: false,
                canImpersonateUsers: true,
                canViewAnalytics: true,
                canExportAnalytics: true,
                canViewSubscriptions: true,
                canModifySubscriptions: true,
                canIssueRefunds: false,
                canViewPayments: true,
                canViewPaymentDetails: true,
                canViewSystemHealth: true,
                canModifySystemConfig: false,
                canManageAdmins: false,
                canSendBroadcasts: true,
                canViewNotificationLogs: true
            )

        case .moderator:
            return AdminPermissions(
                canViewUsers: true,
                canEditUsers: true,
                canDeleteUsers: false,
                canImpersonateUsers: false,
                canViewAnalytics: true,
                canExportAnalytics: false,
                canViewSubscriptions: true,
                canModifySubscriptions: false,
                canIssueRefunds: false,
                canViewPayments: false,
                canViewPaymentDetails: false,
                canViewSystemHealth: false,
                canModifySystemConfig: false,
                canManageAdmins: false,
                canSendBroadcasts: false,
                canViewNotificationLogs: true
            )

        case .support:
            // SUPPORT ADMIN ROLE (FUTURE - Section 11.3)
            // Permissions as defined in plan.md Section 11.3:
            // - View user data (read-only): canViewUsers = true
            // - View subscriptions (read-only): canViewSubscriptions = true
            // - Cannot modify data: canEditUsers, canDeleteUsers, canModifySubscriptions = false
            // - Cannot access financial info: canViewPayments, canViewPaymentDetails = false
            return AdminPermissions(
                canViewUsers: true,          // View user data (read-only)
                canEditUsers: false,         // Cannot modify data
                canDeleteUsers: false,       // Cannot modify data
                canImpersonateUsers: false,  // Cannot impersonate users
                canViewAnalytics: false,     // No analytics access
                canExportAnalytics: false,   // No export access
                canViewSubscriptions: true,  // View subscriptions (read-only)
                canModifySubscriptions: false, // Cannot modify data
                canIssueRefunds: false,      // Cannot access financial info
                canViewPayments: false,      // Cannot access financial info
                canViewPaymentDetails: false, // Cannot access financial info
                canViewSystemHealth: false,  // No system access
                canModifySystemConfig: false, // Cannot modify data
                canManageAdmins: false,      // No admin management
                canSendBroadcasts: false,    // No broadcast access
                canViewNotificationLogs: false // No notification logs access
            )

        case .viewer:
            return AdminPermissions(
                canViewUsers: true,
                canEditUsers: false,
                canDeleteUsers: false,
                canImpersonateUsers: false,
                canViewAnalytics: true,
                canExportAnalytics: false,
                canViewSubscriptions: true,
                canModifySubscriptions: false,
                canIssueRefunds: false,
                canViewPayments: false,
                canViewPaymentDetails: false,
                canViewSystemHealth: true,
                canModifySystemConfig: false,
                canManageAdmins: false,
                canSendBroadcasts: false,
                canViewNotificationLogs: false
            )
        }
    }
}

// MARK: - Admin User Model

/// Represents an admin user in the system
public struct AdminUser: Codable, Identifiable, Equatable {
    public let id: UUID
    public let email: String
    public let role: AdminRole
    public let permissions: AdminPermissions
    public let createdAt: Date
    public let lastLoginAt: Date?
    public let isActive: Bool

    public init(
        id: UUID = UUID(),
        email: String,
        role: AdminRole,
        permissions: AdminPermissions? = nil,
        createdAt: Date = Date(),
        lastLoginAt: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.email = email
        self.role = role
        self.permissions = permissions ?? AdminPermissions.defaultPermissions(for: role)
        self.createdAt = createdAt
        self.lastLoginAt = lastLoginAt
        self.isActive = isActive
    }
}

// MARK: - Admin Dashboard Access Configuration

/// Configuration for admin dashboard access
/// NOTE: Actual credentials are managed through Supabase Auth
/// and environment variables - NOT stored in code
public struct AdminDashboardConfig {

    /// Supabase project admin dashboard URL
    public static var supabaseDashboardURL: URL {
        URL(string: "https://oaiteiceynliooxpeuxt.supabase.co/project/_/admin")!
    }

    /// Admin session timeout in seconds (30 minutes)
    public static let sessionTimeout: TimeInterval = 1800

    /// Maximum failed login attempts before lockout
    public static let maxFailedLoginAttempts = 5

    /// Lockout duration in seconds (15 minutes)
    public static let lockoutDuration: TimeInterval = 900

    /// Required password minimum length for admin accounts
    public static let minPasswordLength = 12

    /// Require MFA for admin accounts
    public static let requireMFA = true

    /// Allowed IP ranges for admin access (CIDR notation)
    /// Empty array means all IPs allowed
    public static let allowedIPRanges: [String] = []

    /// Admin activity audit log retention in days
    public static let auditLogRetentionDays = 365
}

// MARK: - Admin Credentials Reference

/// Reference documentation for admin credentials
/// SECURITY: These values should NEVER be stored in source code in production
/// Use this struct only for development/documentation purposes
///
/// Production credentials should be managed via:
/// - Supabase Auth user management
/// - Environment variables
/// - Secure secrets manager (AWS Secrets Manager, HashiCorp Vault, etc.)
///
/// ===========================================
/// SECTION 11.3: ADMIN ROLES AND PERMISSIONS
/// ===========================================
///
/// SUPER ADMIN (wesleymwilliams@gmail.com):
/// - Full system access
/// - User management
/// - Subscription management
/// - System configuration
/// - View all data
/// - Export reports
///
/// SUPPORT ADMIN (Future Implementation):
/// - View user data (read-only)
/// - View subscriptions (read-only)
/// - Cannot modify data
/// - Cannot access financial info
///
/// Password should be set through Supabase Auth dashboard or CLI,
/// never committed to source control.
public struct AdminCredentialsDocumentation {
    /// The designated super admin email
    public static let superAdminEmail = "wesleymwilliams@gmail.com"

    /// The designated super admin role
    public static let superAdminRole = AdminRole.superAdmin

    /// Super admin has full permissions as defined in Section 11.3:
    /// - Full system access
    /// - User management
    /// - Subscription management
    /// - System configuration
    /// - View all data
    /// - Export reports
    public static let superAdminPermissions = AdminPermissions.defaultPermissions(for: .superAdmin)

    /// Support admin role permissions (future implementation - Section 11.3):
    /// - View user data (read-only)
    /// - View subscriptions (read-only)
    /// - Cannot modify data
    /// - Cannot access financial info
    public static let supportAdminPermissions = AdminPermissions.defaultPermissions(for: .support)
}

// MARK: - Section 11.3 Permission Mapping

/// Documents the mapping between Section 11.3 requirements and permission flags
public enum Section11_3PermissionMapping {

    /// Super Admin permissions mapped from Section 11.3 requirements
    public enum SuperAdmin {
        /// "Full system access" maps to:
        public static let fullSystemAccess = [
            "canModifySystemConfig",
            "canManageAdmins",
            "canSendBroadcasts",
            "canImpersonateUsers"
        ]

        /// "User management" maps to:
        public static let userManagement = [
            "canViewUsers",
            "canEditUsers",
            "canDeleteUsers",
            "canImpersonateUsers"
        ]

        /// "Subscription management" maps to:
        public static let subscriptionManagement = [
            "canViewSubscriptions",
            "canModifySubscriptions",
            "canIssueRefunds"
        ]

        /// "System configuration" maps to:
        public static let systemConfiguration = [
            "canViewSystemHealth",
            "canModifySystemConfig"
        ]

        /// "View all data" maps to:
        public static let viewAllData = [
            "canViewUsers",
            "canViewAnalytics",
            "canViewSubscriptions",
            "canViewPayments",
            "canViewPaymentDetails",
            "canViewNotificationLogs"
        ]

        /// "Export reports" maps to:
        public static let exportReports = [
            "canExportAnalytics"
        ]
    }

    /// Support Admin permissions mapped from Section 11.3 requirements
    public enum SupportAdmin {
        /// "View user data (read-only)" maps to:
        public static let viewUserDataReadOnly = [
            "canViewUsers: true",
            "canEditUsers: false",
            "canDeleteUsers: false"
        ]

        /// "View subscriptions (read-only)" maps to:
        public static let viewSubscriptionsReadOnly = [
            "canViewSubscriptions: true",
            "canModifySubscriptions: false"
        ]

        /// "Cannot modify data" enforced by:
        public static let cannotModifyData = [
            "canEditUsers: false",
            "canDeleteUsers: false",
            "canModifySubscriptions: false",
            "canModifySystemConfig: false"
        ]

        /// "Cannot access financial info" enforced by:
        public static let cannotAccessFinancialInfo = [
            "canViewPayments: false",
            "canViewPaymentDetails: false",
            "canIssueRefunds: false"
        ]
    }
}
