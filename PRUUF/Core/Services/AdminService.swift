import Foundation
import Supabase

/// Admin Dashboard Service
/// Provides functionality for admin dashboard features including:
/// - User Management
/// - Connection Analytics
/// - Ping Analytics
/// - Subscription Metrics
/// - System Health
/// - Operations
@MainActor
public final class AdminService: ObservableObject {

    // MARK: - Singleton

    public static let shared = AdminService()

    // MARK: - Published Properties

    @Published public var isLoading = false
    @Published public var error: Error?
    @Published public var currentAdminUser: AdminUser?

    // User Management
    @Published public var userMetrics: UserMetrics?
    @Published public var searchedUsers: [UserDetails] = []

    // Connection Analytics
    @Published public var connectionAnalytics: ConnectionAnalytics?

    // Ping Analytics
    @Published public var pingAnalytics: PingAnalytics?

    // Subscription Metrics
    @Published public var subscriptionMetrics: SubscriptionMetrics?

    // System Health
    @Published public var systemHealth: SystemHealth?

    // MARK: - Private Properties

    private let supabase = SupabaseConfig.client

    // MARK: - Initialization

    private init() {}

    // MARK: - Admin Authentication

    /// Check if current user is an admin
    public func checkAdminAccess() async throws -> Bool {
        let response: Bool = try await supabase.rpc("is_admin").execute().value
        return response
    }

    /// Get current admin user details
    public func fetchCurrentAdminUser() async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AdminError.notAuthenticated
        }

        let response: AdminUser = try await supabase
            .from("admin_users")
            .select()
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
            .value

        self.currentAdminUser = response
    }

    // MARK: - User Management

    /// Fetch user metrics for admin dashboard
    public func fetchUserMetrics() async throws {
        isLoading = true
        defer { isLoading = false }

        let response: UserMetrics = try await supabase
            .rpc("get_admin_user_metrics")
            .execute()
            .value

        self.userMetrics = response
    }

    /// Search users by phone number
    public func searchUsersByPhone(_ phoneNumber: String) async throws -> [UserDetails] {
        let response: [UserDetails] = try await supabase
            .rpc("admin_search_users_by_phone", params: ["search_phone": phoneNumber])
            .execute()
            .value

        self.searchedUsers = response
        return response
    }

    /// Get detailed user information
    public func getUserDetails(userId: UUID) async throws -> UserDetails {
        let response: UserDetails = try await supabase
            .rpc("admin_get_user_details", params: ["target_user_id": userId.uuidString])
            .execute()
            .value

        return response
    }

    /// Impersonate user (for debugging)
    public func impersonateUser(userId: UUID) async throws -> ImpersonationSession {
        try await logAdminAction(
            action: "impersonate_user",
            resourceType: "user",
            resourceId: userId,
            details: ["reason": "admin_debug"]
        )

        let response: ImpersonationSession = try await supabase
            .rpc("admin_create_impersonation_session", params: ["target_user_id": userId.uuidString])
            .execute()
            .value

        return response
    }

    /// Deactivate user account
    public func deactivateUser(userId: UUID, reason: String) async throws {
        try await logAdminAction(
            action: "deactivate_user",
            resourceType: "user",
            resourceId: userId,
            details: ["reason": reason]
        )

        try await supabase
            .rpc("admin_deactivate_user", params: [
                "target_user_id": userId.uuidString,
                "deactivation_reason": reason
            ])
            .execute()
    }

    /// Reactivate user account
    public func reactivateUser(userId: UUID) async throws {
        try await logAdminAction(
            action: "reactivate_user",
            resourceType: "user",
            resourceId: userId,
            details: [:]
        )

        try await supabase
            .rpc("admin_reactivate_user", params: ["target_user_id": userId.uuidString])
            .execute()
    }

    /// Manually update subscription status
    public func updateUserSubscription(userId: UUID, status: String, endDate: Date?) async throws {
        try await logAdminAction(
            action: "update_subscription",
            resourceType: "subscription",
            resourceId: userId,
            details: ["new_status": status, "end_date": endDate?.ISO8601Format() ?? "nil"]
        )

        var params: [String: String] = [
            "target_user_id": userId.uuidString,
            "new_status": status
        ]

        if let endDate = endDate {
            params["new_end_date"] = endDate.ISO8601Format()
        }

        try await supabase
            .rpc("admin_update_subscription", params: params)
            .execute()
    }

    // MARK: - Connection Analytics

    /// Fetch connection analytics
    public func fetchConnectionAnalytics() async throws {
        isLoading = true
        defer { isLoading = false }

        let response: ConnectionAnalytics = try await supabase
            .rpc("get_admin_connection_analytics")
            .execute()
            .value

        self.connectionAnalytics = response
    }

    /// Get top users by connection count
    public func getTopUsersByConnections(limit: Int = 10) async throws -> [TopUserByConnections] {
        let response: [TopUserByConnections] = try await supabase
            .rpc("admin_get_top_users_by_connections", params: ["result_limit": limit])
            .execute()
            .value

        return response
    }

    /// Get connection growth over time
    public func getConnectionGrowth(days: Int = 30) async throws -> [ConnectionGrowthPoint] {
        let response: [ConnectionGrowthPoint] = try await supabase
            .rpc("admin_get_connection_growth", params: ["days_back": days])
            .execute()
            .value

        return response
    }

    // MARK: - Ping Analytics

    /// Fetch ping analytics
    public func fetchPingAnalytics() async throws {
        isLoading = true
        defer { isLoading = false }

        let response: PingAnalytics = try await supabase
            .rpc("get_admin_ping_analytics")
            .execute()
            .value

        self.pingAnalytics = response
    }

    /// Get ping completion rates
    public func getPingCompletionRates(days: Int = 30) async throws -> PingCompletionRates {
        let response: PingCompletionRates = try await supabase
            .rpc("admin_get_ping_completion_rates", params: ["days_back": days])
            .execute()
            .value

        return response
    }

    /// Get ping streaks distribution
    public func getPingStreaksDistribution() async throws -> [StreakDistribution] {
        let response: [StreakDistribution] = try await supabase
            .rpc("admin_get_streak_distribution")
            .execute()
            .value

        return response
    }

    /// Get missed ping alerts
    public func getMissedPingAlerts(limit: Int = 50) async throws -> [MissedPingAlert] {
        let response: [MissedPingAlert] = try await supabase
            .rpc("admin_get_missed_ping_alerts", params: ["result_limit": limit])
            .execute()
            .value

        return response
    }

    /// Get break usage statistics
    public func getBreakUsageStats() async throws -> BreakUsageStats {
        let response: BreakUsageStats = try await supabase
            .rpc("admin_get_break_usage_stats")
            .execute()
            .value

        return response
    }

    // MARK: - Subscription Metrics

    /// Fetch subscription metrics
    public func fetchSubscriptionMetrics() async throws {
        isLoading = true
        defer { isLoading = false }

        let response: SubscriptionMetrics = try await supabase
            .rpc("get_admin_subscription_metrics")
            .execute()
            .value

        self.subscriptionMetrics = response
    }

    /// Get payment failures
    public func getPaymentFailures(limit: Int = 50) async throws -> [PaymentFailure] {
        let response: [PaymentFailure] = try await supabase
            .rpc("admin_get_payment_failures", params: ["result_limit": limit])
            .execute()
            .value

        return response
    }

    /// Get refunds and chargebacks
    public func getRefundsAndChargebacks(limit: Int = 50) async throws -> [RefundChargeback] {
        let response: [RefundChargeback] = try await supabase
            .rpc("admin_get_refunds_chargebacks", params: ["result_limit": limit])
            .execute()
            .value

        return response
    }

    // MARK: - System Health

    /// Fetch system health metrics
    public func fetchSystemHealth() async throws {
        isLoading = true
        defer { isLoading = false }

        let response: SystemHealth = try await supabase
            .rpc("get_admin_system_health")
            .execute()
            .value

        self.systemHealth = response
    }

    /// Get edge function execution times
    public func getEdgeFunctionMetrics() async throws -> [EdgeFunctionMetric] {
        let response: [EdgeFunctionMetric] = try await supabase
            .rpc("admin_get_edge_function_metrics")
            .execute()
            .value

        return response
    }

    /// Get cron job success rates
    public func getCronJobStats() async throws -> [CronJobStat] {
        let response: [CronJobStat] = try await supabase
            .rpc("admin_get_cron_job_stats")
            .execute()
            .value

        return response
    }

    // MARK: - Operations

    /// Generate manual ping (for testing)
    public func generateManualPing(connectionId: UUID) async throws {
        try await logAdminAction(
            action: "generate_manual_ping",
            resourceType: "ping",
            resourceId: connectionId,
            details: ["type": "manual_test"]
        )

        try await supabase
            .rpc("admin_generate_manual_ping", params: ["connection_id": connectionId.uuidString])
            .execute()
    }

    /// Send test notification
    public func sendTestNotification(userId: UUID, title: String, body: String) async throws {
        try await logAdminAction(
            action: "send_test_notification",
            resourceType: "notification",
            resourceId: userId,
            details: ["title": title, "body": body]
        )

        try await supabase
            .rpc("admin_send_test_notification", params: [
                "target_user_id": userId.uuidString,
                "notification_title": title,
                "notification_body": body
            ])
            .execute()
    }

    /// Cancel subscription with reason
    public func cancelSubscription(userId: UUID, reason: String) async throws {
        try await logAdminAction(
            action: "cancel_subscription",
            resourceType: "subscription",
            resourceId: userId,
            details: ["reason": reason]
        )

        try await supabase
            .rpc("admin_cancel_subscription", params: [
                "target_user_id": userId.uuidString,
                "cancellation_reason": reason
            ])
            .execute()
    }

    /// Issue refund
    public func issueRefund(transactionId: UUID, amount: Decimal, reason: String) async throws {
        try await logAdminAction(
            action: "issue_refund",
            resourceType: "payment",
            resourceId: transactionId,
            details: ["amount": "\(amount)", "reason": reason]
        )

        try await supabase
            .rpc("admin_issue_refund", params: [
                "transaction_id": transactionId.uuidString,
                "refund_amount": "\(amount)",
                "refund_reason": reason
            ])
            .execute()
    }

    /// Get audit logs
    public func getAuditLogs(limit: Int = 100, offset: Int = 0) async throws -> [AuditLogEntry] {
        let response: [AuditLogEntry] = try await supabase
            .from("admin_audit_log")
            .select("*, admin_users(email)")
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + limit - 1)
            .execute()
            .value

        return response
    }

    /// Export report
    public func exportReport(reportType: ReportType, format: ExportFormat) async throws -> URL {
        try await logAdminAction(
            action: "export_report",
            resourceType: "report",
            resourceId: nil,
            details: ["type": reportType.rawValue, "format": format.rawValue]
        )

        let response: ExportResponse = try await supabase
            .rpc("admin_export_report", params: [
                "report_type": reportType.rawValue,
                "export_format": format.rawValue
            ])
            .execute()
            .value

        guard let url = URL(string: response.downloadUrl) else {
            throw AdminError.invalidExportUrl
        }

        return url
    }

    // MARK: - Audit Logging

    private func logAdminAction(
        action: String,
        resourceType: String,
        resourceId: UUID?,
        details: [String: String]
    ) async throws {
        var params: [String: String] = [
            "p_action": action,
            "p_resource_type": resourceType,
            "p_details": try JSONEncoder().encode(details).base64EncodedString()
        ]

        if let resourceId = resourceId {
            params["p_resource_id"] = resourceId.uuidString
        }

        try await supabase
            .rpc("log_admin_action", params: params)
            .execute()
    }
}

// MARK: - Models

public struct UserMetrics: Codable {
    public let totalUsers: Int
    public let activeUsersLast7Days: Int
    public let activeUsersLast30Days: Int
    public let newSignupsToday: Int
    public let newSignupsThisWeek: Int
    public let newSignupsThisMonth: Int
    public let senderCount: Int
    public let receiverCount: Int
    public let bothRoleCount: Int

    enum CodingKeys: String, CodingKey {
        case totalUsers = "total_users"
        case activeUsersLast7Days = "active_users_last_7_days"
        case activeUsersLast30Days = "active_users_last_30_days"
        case newSignupsToday = "new_signups_today"
        case newSignupsThisWeek = "new_signups_this_week"
        case newSignupsThisMonth = "new_signups_this_month"
        case senderCount = "sender_count"
        case receiverCount = "receiver_count"
        case bothRoleCount = "both_role_count"
    }
}

public struct UserDetails: Codable, Identifiable {
    public let id: UUID
    public let phoneNumber: String
    public let phoneCountryCode: String
    public let primaryRole: String?
    public let isActive: Bool
    public let hasCompletedOnboarding: Bool
    public let createdAt: Date
    public let lastSeenAt: Date?
    public let timezone: String
    public let subscriptionStatus: String?
    public let trialEndDate: Date?
    public let connectionCount: Int
    public let pingCount: Int
    public let completionRate: Double

    enum CodingKeys: String, CodingKey {
        case id
        case phoneNumber = "phone_number"
        case phoneCountryCode = "phone_country_code"
        case primaryRole = "primary_role"
        case isActive = "is_active"
        case hasCompletedOnboarding = "has_completed_onboarding"
        case createdAt = "created_at"
        case lastSeenAt = "last_seen_at"
        case timezone
        case subscriptionStatus = "subscription_status"
        case trialEndDate = "trial_end_date"
        case connectionCount = "connection_count"
        case pingCount = "ping_count"
        case completionRate = "completion_rate"
    }
}

public struct ImpersonationSession: Codable {
    public let sessionId: UUID
    public let targetUserId: UUID
    public let expiresAt: Date
    public let token: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case targetUserId = "target_user_id"
        case expiresAt = "expires_at"
        case token
    }
}

public struct ConnectionAnalytics: Codable {
    public let totalConnections: Int
    public let activeConnections: Int
    public let pausedConnections: Int
    public let deletedConnections: Int
    public let averageConnectionsPerUser: Double
    public let connectionGrowthThisMonth: Int
    public let connectionGrowthLastMonth: Int
    public let growthPercentage: Double

    enum CodingKeys: String, CodingKey {
        case totalConnections = "total_connections"
        case activeConnections = "active_connections"
        case pausedConnections = "paused_connections"
        case deletedConnections = "deleted_connections"
        case averageConnectionsPerUser = "average_connections_per_user"
        case connectionGrowthThisMonth = "connection_growth_this_month"
        case connectionGrowthLastMonth = "connection_growth_last_month"
        case growthPercentage = "growth_percentage"
    }
}

public struct TopUserByConnections: Codable, Identifiable {
    public let id: UUID
    public let phoneNumber: String
    public let connectionCount: Int
    public let role: String

    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case phoneNumber = "phone_number"
        case connectionCount = "connection_count"
        case role
    }
}

public struct ConnectionGrowthPoint: Codable, Identifiable {
    public var id: String { date }
    public let date: String
    public let newConnections: Int
    public let cumulativeTotal: Int

    enum CodingKeys: String, CodingKey {
        case date
        case newConnections = "new_connections"
        case cumulativeTotal = "cumulative_total"
    }
}

public struct PingAnalytics: Codable {
    public let totalPingsToday: Int
    public let totalPingsThisWeek: Int
    public let totalPingsThisMonth: Int
    public let onTimeCount: Int
    public let lateCount: Int
    public let missedCount: Int
    public let onBreakCount: Int
    public let completionRateOnTime: Double
    public let completionRateLate: Double
    public let missedRate: Double
    public let averageCompletionTimeMinutes: Double
    public let longestStreak: Int
    public let averageStreak: Double

    enum CodingKeys: String, CodingKey {
        case totalPingsToday = "total_pings_today"
        case totalPingsThisWeek = "total_pings_this_week"
        case totalPingsThisMonth = "total_pings_this_month"
        case onTimeCount = "on_time_count"
        case lateCount = "late_count"
        case missedCount = "missed_count"
        case onBreakCount = "on_break_count"
        case completionRateOnTime = "completion_rate_on_time"
        case completionRateLate = "completion_rate_late"
        case missedRate = "missed_rate"
        case averageCompletionTimeMinutes = "average_completion_time_minutes"
        case longestStreak = "longest_streak"
        case averageStreak = "average_streak"
    }
}

public struct PingCompletionRates: Codable {
    public let onTimePercentage: Double
    public let latePercentage: Double
    public let missedPercentage: Double
    public let totalPings: Int

    enum CodingKeys: String, CodingKey {
        case onTimePercentage = "on_time_percentage"
        case latePercentage = "late_percentage"
        case missedPercentage = "missed_percentage"
        case totalPings = "total_pings"
    }
}

public struct StreakDistribution: Codable, Identifiable {
    public var id: String { streakRange }
    public let streakRange: String
    public let userCount: Int

    enum CodingKeys: String, CodingKey {
        case streakRange = "streak_range"
        case userCount = "user_count"
    }
}

public struct MissedPingAlert: Codable, Identifiable {
    public let id: UUID
    public let senderPhone: String
    public let receiverPhone: String
    public let scheduledTime: Date
    public let deadlineTime: Date
    public let missedAt: Date
    public let consecutiveMisses: Int

    enum CodingKeys: String, CodingKey {
        case id = "ping_id"
        case senderPhone = "sender_phone"
        case receiverPhone = "receiver_phone"
        case scheduledTime = "scheduled_time"
        case deadlineTime = "deadline_time"
        case missedAt = "missed_at"
        case consecutiveMisses = "consecutive_misses"
    }
}

public struct BreakUsageStats: Codable {
    public let activeBreaks: Int
    public let scheduledBreaks: Int
    public let completedBreaksThisMonth: Int
    public let averageBreakDurationDays: Double
    public let usersWithActiveBreaks: Int

    enum CodingKeys: String, CodingKey {
        case activeBreaks = "active_breaks"
        case scheduledBreaks = "scheduled_breaks"
        case completedBreaksThisMonth = "completed_breaks_this_month"
        case averageBreakDurationDays = "average_break_duration_days"
        case usersWithActiveBreaks = "users_with_active_breaks"
    }
}

public struct SubscriptionMetrics: Codable {
    public let monthlyRecurringRevenue: Decimal
    public let activeSubscriptions: Int
    public let trialUsers: Int
    public let expiredSubscriptions: Int
    public let canceledSubscriptions: Int
    public let pastDueSubscriptions: Int
    public let trialConversionRate: Double
    public let churnRate: Double
    public let averageRevenuePerUser: Decimal
    public let lifetimeValue: Decimal
    public let paymentFailuresThisMonth: Int
    public let refundsThisMonth: Int
    public let chargebacksThisMonth: Int

    enum CodingKeys: String, CodingKey {
        case monthlyRecurringRevenue = "monthly_recurring_revenue"
        case activeSubscriptions = "active_subscriptions"
        case trialUsers = "trial_users"
        case expiredSubscriptions = "expired_subscriptions"
        case canceledSubscriptions = "canceled_subscriptions"
        case pastDueSubscriptions = "past_due_subscriptions"
        case trialConversionRate = "trial_conversion_rate"
        case churnRate = "churn_rate"
        case averageRevenuePerUser = "average_revenue_per_user"
        case lifetimeValue = "lifetime_value"
        case paymentFailuresThisMonth = "payment_failures_this_month"
        case refundsThisMonth = "refunds_this_month"
        case chargebacksThisMonth = "chargebacks_this_month"
    }
}

public struct PaymentFailure: Codable, Identifiable {
    public let id: UUID
    public let userId: UUID
    public let phoneNumber: String
    public let amount: Decimal
    public let failedAt: Date
    public let failureReason: String
    public let retryCount: Int

    enum CodingKeys: String, CodingKey {
        case id = "transaction_id"
        case userId = "user_id"
        case phoneNumber = "phone_number"
        case amount
        case failedAt = "failed_at"
        case failureReason = "failure_reason"
        case retryCount = "retry_count"
    }
}

public struct RefundChargeback: Codable, Identifiable {
    public let id: UUID
    public let userId: UUID
    public let phoneNumber: String
    public let amount: Decimal
    public let type: String
    public let reason: String
    public let processedAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "transaction_id"
        case userId = "user_id"
        case phoneNumber = "phone_number"
        case amount
        case type
        case reason
        case processedAt = "processed_at"
    }
}

public struct SystemHealth: Codable {
    public let databaseConnectionPoolUsage: Double
    public let averageQueryTimeMs: Double
    public let apiErrorRateLast24h: Double
    public let pushNotificationDeliveryRate: Double
    public let cronJobSuccessRate: Double
    public let storageUsageBytes: Int64
    public let storageUsageFormatted: String
    public let activeUserSessions: Int
    public let pendingPings: Int
    public let healthStatus: String

    enum CodingKeys: String, CodingKey {
        case databaseConnectionPoolUsage = "database_connection_pool_usage"
        case averageQueryTimeMs = "average_query_time_ms"
        case apiErrorRateLast24h = "api_error_rate_last_24h"
        case pushNotificationDeliveryRate = "push_notification_delivery_rate"
        case cronJobSuccessRate = "cron_job_success_rate"
        case storageUsageBytes = "storage_usage_bytes"
        case storageUsageFormatted = "storage_usage_formatted"
        case activeUserSessions = "active_user_sessions"
        case pendingPings = "pending_pings"
        case healthStatus = "health_status"
    }
}

public struct EdgeFunctionMetric: Codable, Identifiable {
    public var id: String { functionName }
    public let functionName: String
    public let invocationsLast24h: Int
    public let averageExecutionTimeMs: Double
    public let errorRate: Double
    public let p95ExecutionTimeMs: Double

    enum CodingKeys: String, CodingKey {
        case functionName = "function_name"
        case invocationsLast24h = "invocations_last_24h"
        case averageExecutionTimeMs = "average_execution_time_ms"
        case errorRate = "error_rate"
        case p95ExecutionTimeMs = "p95_execution_time_ms"
    }
}

public struct CronJobStat: Codable, Identifiable {
    public var id: String { jobName }
    public let jobName: String
    public let lastRunAt: Date?
    public let lastRunStatus: String
    public let successCount: Int
    public let failureCount: Int
    public let averageDurationMs: Double

    enum CodingKeys: String, CodingKey {
        case jobName = "job_name"
        case lastRunAt = "last_run_at"
        case lastRunStatus = "last_run_status"
        case successCount = "success_count"
        case failureCount = "failure_count"
        case averageDurationMs = "average_duration_ms"
    }
}

public struct AuditLogEntry: Codable, Identifiable {
    public let id: UUID
    public let adminId: UUID
    public let adminEmail: String?
    public let action: String
    public let resourceType: String
    public let resourceId: UUID?
    public let details: [String: String]?
    public let ipAddress: String?
    public let userAgent: String?
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case adminId = "admin_id"
        case adminEmail = "admin_email"
        case action
        case resourceType = "resource_type"
        case resourceId = "resource_id"
        case details
        case ipAddress = "ip_address"
        case userAgent = "user_agent"
        case createdAt = "created_at"
    }
}

public struct ExportResponse: Codable {
    public let downloadUrl: String
    public let expiresAt: Date
    public let fileSize: Int64

    enum CodingKeys: String, CodingKey {
        case downloadUrl = "download_url"
        case expiresAt = "expires_at"
        case fileSize = "file_size"
    }
}

// MARK: - Enums

public enum ReportType: String, CaseIterable {
    case users = "users"
    case connections = "connections"
    case pings = "pings"
    case subscriptions = "subscriptions"
    case revenue = "revenue"
    case systemHealth = "system_health"
}

public enum ExportFormat: String, CaseIterable {
    case csv = "csv"
    case json = "json"
}

public enum AdminError: Error, LocalizedError {
    case notAuthenticated
    case notAuthorized
    case userNotFound
    case invalidExportUrl
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to access admin features"
        case .notAuthorized:
            return "You do not have permission to perform this action"
        case .userNotFound:
            return "User not found"
        case .invalidExportUrl:
            return "Failed to generate export URL"
        case .operationFailed(let message):
            return "Operation failed: \(message)"
        }
    }
}
