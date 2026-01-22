import Foundation

/// Represents an audit log entry for tracking system events
/// Maps to the `audit_logs` table in Supabase
struct AuditLog: Codable, Identifiable, Equatable {
    /// Unique log identifier
    let id: UUID

    /// User who performed the action (nil for system actions)
    let userId: UUID?

    /// Action that was performed
    let action: String

    /// Type of resource affected
    let resourceType: ResourceType?

    /// ID of the affected resource
    let resourceId: UUID?

    /// Additional details about the action
    var details: AuditDetails?

    /// IP address of the request
    let ipAddress: String?

    /// User agent string of the request
    let userAgent: String?

    /// When the action occurred
    let createdAt: Date

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case action
        case resourceType = "resource_type"
        case resourceId = "resource_id"
        case details
        case ipAddress = "ip_address"
        case userAgent = "user_agent"
        case createdAt = "created_at"
    }
}

// MARK: - Resource Type

/// Types of resources that can be affected by audit events
enum ResourceType: String, Codable, CaseIterable {
    case user = "user"
    case connection = "connection"
    case ping = "ping"
    case payment = "payment"
    case subscription = "subscription"
    case breakPeriod = "break"
    case notification = "notification"
    case uniqueCode = "unique_code"

    var displayName: String {
        switch self {
        case .user:
            return "User"
        case .connection:
            return "Connection"
        case .ping:
            return "Ping"
        case .payment:
            return "Payment"
        case .subscription:
            return "Subscription"
        case .breakPeriod:
            return "Break"
        case .notification:
            return "Notification"
        case .uniqueCode:
            return "Unique Code"
        }
    }
}

// MARK: - Audit Actions

/// Common audit actions
enum AuditAction {
    // User actions
    static let userCreated = "user.created"
    static let userUpdated = "user.updated"
    static let userDeleted = "user.deleted"
    static let userLogin = "user.login"
    static let userLogout = "user.logout"

    // Connection actions
    static let connectionCreated = "connection.created"
    static let connectionAccepted = "connection.accepted"
    static let connectionPaused = "connection.paused"
    static let connectionResumed = "connection.resumed"
    static let connectionDeleted = "connection.deleted"

    // Ping actions
    static let pingCreated = "ping.created"
    static let pingCompleted = "ping.completed"
    static let pingMissed = "ping.missed"

    // Break actions
    static let breakCreated = "break.created"
    static let breakCanceled = "break.canceled"
    static let breakCompleted = "break.completed"

    // Payment actions
    static let subscriptionCreated = "subscription.created"
    static let subscriptionRenewed = "subscription.renewed"
    static let subscriptionCanceled = "subscription.canceled"
    static let paymentSucceeded = "payment.succeeded"
    static let paymentFailed = "payment.failed"
    static let refundIssued = "refund.issued"
}

// MARK: - Audit Details

/// Additional details for audit events
struct AuditDetails: Codable, Equatable {
    /// Previous value (for updates)
    var previousValue: String?

    /// New value (for updates)
    var newValue: String?

    /// Reason for the action
    var reason: String?

    /// Related entity IDs
    var relatedIds: [String: String]?

    /// Additional context
    var context: [String: String]?

    enum CodingKeys: String, CodingKey {
        case previousValue = "previous_value"
        case newValue = "new_value"
        case reason
        case relatedIds = "related_ids"
        case context
    }
}
