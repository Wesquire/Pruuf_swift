import Foundation
import Supabase
import Combine

/// Store for managing in-app notifications
/// Handles fetching, caching, and real-time updates of notification data
@MainActor
final class InAppNotificationStore: ObservableObject {

    // MARK: - Singleton

    static let shared = InAppNotificationStore()

    // MARK: - Published Properties

    /// All notifications (last 30 days)
    @Published private(set) var notifications: [PruufNotification] = []

    /// Whether data is being loaded
    @Published private(set) var isLoading: Bool = false

    /// Error message if loading failed
    @Published var errorMessage: String?

    /// Unread notification count for badge
    @Published private(set) var unreadCount: Int = 0

    // MARK: - Private Properties

    private let database: PostgrestClient
    private var lastFetchDate: Date?
    private let cacheExpirationMinutes: TimeInterval = 5

    // MARK: - Notification for Navigation

    /// Posted when a notification should navigate to a specific screen
    static let navigateToNotificationDestination = Notification.Name("navigateToNotificationDestination")

    // MARK: - Initialization

    init(database: PostgrestClient? = nil) {
        self.database = database ?? SupabaseConfig.client.schema("public")
    }

    // MARK: - Public Methods

    /// Fetch notifications for the current user (last 30 days)
    /// - Parameter userId: The current user's ID
    /// - Parameter forceRefresh: Whether to bypass cache
    func fetchNotifications(userId: UUID, forceRefresh: Bool = false) async {
        // Check cache validity
        if !forceRefresh,
           let lastFetch = lastFetchDate,
           Date().timeIntervalSince(lastFetch) < cacheExpirationMinutes * 60 {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let formatter = ISO8601DateFormatter()

            let fetchedNotifications: [PruufNotification] = try await database
                .from("notifications")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("sent_at", value: formatter.string(from: thirtyDaysAgo))
                .order("sent_at", ascending: false)
                .execute()
                .value

            notifications = fetchedNotifications
            unreadCount = fetchedNotifications.filter { !$0.isRead }.count
            lastFetchDate = Date()
            updateAppBadge()

            Logger.info("Fetched \(fetchedNotifications.count) notifications (\(unreadCount) unread)")
        } catch {
            Logger.error("Failed to fetch notifications: \(error.localizedDescription)")
            errorMessage = "Failed to load notifications"
        }

        isLoading = false
    }

    /// Mark a single notification as read
    /// - Parameters:
    ///   - notificationId: The notification to mark as read
    ///   - userId: The current user's ID
    func markAsRead(notificationId: UUID, userId: UUID) async -> Bool {
        do {
            let now = Date()
            let formatter = ISO8601DateFormatter()

            try await database
                .from("notifications")
                .update(["read_at": formatter.string(from: now)])
                .eq("id", value: notificationId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .execute()

            // Update local state
            if let index = notifications.firstIndex(where: { $0.id == notificationId }) {
                var updated = notifications[index]
                updated.readAt = now
                notifications[index] = updated
            }

            unreadCount = notifications.filter { !$0.isRead }.count
            updateAppBadge()
            Logger.info("Marked notification \(notificationId) as read")
            return true
        } catch {
            Logger.error("Failed to mark notification as read: \(error.localizedDescription)")
            errorMessage = "Failed to update notification"
            return false
        }
    }

    /// Mark all notifications as read
    /// - Parameter userId: The current user's ID
    func markAllAsRead(userId: UUID) async -> Bool {
        do {
            let now = Date()
            let formatter = ISO8601DateFormatter()
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()

            try await database
                .from("notifications")
                .update(["read_at": formatter.string(from: now)])
                .eq("user_id", value: userId.uuidString)
                .is("read_at", value: nil)
                .gte("sent_at", value: formatter.string(from: thirtyDaysAgo))
                .execute()

            // Update local state
            notifications = notifications.map { notification in
                var updated = notification
                if !notification.isRead {
                    updated.readAt = now
                }
                return updated
            }

            unreadCount = 0
            updateAppBadge()
            Logger.info("Marked all notifications as read for user \(userId)")
            return true
        } catch {
            Logger.error("Failed to mark all notifications as read: \(error.localizedDescription)")
            errorMessage = "Failed to update notifications"
            return false
        }
    }

    /// Delete a single notification
    /// - Parameters:
    ///   - notificationId: The notification to delete
    ///   - userId: The current user's ID
    func deleteNotification(notificationId: UUID, userId: UUID) async -> Bool {
        do {
            try await database
                .from("notifications")
                .delete()
                .eq("id", value: notificationId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .execute()

            // Update local state
            if let removedNotification = notifications.first(where: { $0.id == notificationId }),
               !removedNotification.isRead {
                unreadCount = max(0, unreadCount - 1)
            }
            notifications.removeAll { $0.id == notificationId }
            updateAppBadge()

            Logger.info("Deleted notification \(notificationId)")
            return true
        } catch {
            Logger.error("Failed to delete notification: \(error.localizedDescription)")
            errorMessage = "Failed to delete notification"
            return false
        }
    }

    /// Delete multiple notifications
    /// - Parameters:
    ///   - notificationIds: The notifications to delete
    ///   - userId: The current user's ID
    func deleteNotifications(notificationIds: [UUID], userId: UUID) async -> Bool {
        do {
            try await database
                .from("notifications")
                .delete()
                .in("id", values: notificationIds.map { $0.uuidString })
                .eq("user_id", value: userId.uuidString)
                .execute()

            // Update local state
            let removedUnreadCount = notifications
                .filter { notificationIds.contains($0.id) && !$0.isRead }
                .count
            unreadCount = max(0, unreadCount - removedUnreadCount)
            notifications.removeAll { notificationIds.contains($0.id) }
            updateAppBadge()

            Logger.info("Deleted \(notificationIds.count) notifications")
            return true
        } catch {
            Logger.error("Failed to delete notifications: \(error.localizedDescription)")
            errorMessage = "Failed to delete notifications"
            return false
        }
    }

    /// Clear all cached data
    func clearCache() {
        notifications = []
        unreadCount = 0
        lastFetchDate = nil
        errorMessage = nil
        updateAppBadge()
    }

    /// Refresh badge count only (lightweight)
    /// - Parameter userId: The current user's ID
    func refreshUnreadCount(userId: UUID) async {
        do {
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let formatter = ISO8601DateFormatter()

            // Simple count query
            let unreadNotifications: [PruufNotification] = try await database
                .from("notifications")
                .select("id")
                .eq("user_id", value: userId.uuidString)
                .is("read_at", value: nil)
                .gte("sent_at", value: formatter.string(from: thirtyDaysAgo))
                .execute()
                .value

            unreadCount = unreadNotifications.count
            updateAppBadge()
        } catch {
            Logger.error("Failed to refresh unread count: \(error.localizedDescription)")
        }
    }

    // MARK: - Badge Updates

    private func updateAppBadge() {
        Task {
            await NotificationService.shared.updateBadge(count: unreadCount)
        }
    }

    // MARK: - Navigation Helpers

    /// Get the deep link destination for a notification
    /// - Parameter notification: The notification to navigate from
    /// - Returns: A NavigationDestination describing where to navigate
    func getNavigationDestination(for notification: PruufNotification) -> NotificationNavigationDestination {
        switch notification.type {
        case .pingReminder, .deadlineWarning, .deadlineFinal:
            // Navigate to sender dashboard / today's ping
            return .senderDashboard

        case .missedPing:
            // Navigate to the specific sender's activity
            if let senderId = notification.metadata?.senderId {
                return .senderActivity(senderId: senderId)
            }
            return .receiverDashboard

        case .pingCompletedOnTime, .pingCompletedLate:
            // Navigate to sender's ping history
            if let connectionId = notification.metadata?.connectionId {
                return .pingHistory(connectionId: connectionId)
            }
            return .receiverDashboard

        case .breakStarted, .breakNotification:
            // Navigate to sender's activity
            if let senderId = notification.metadata?.senderId {
                return .senderActivity(senderId: senderId)
            }
            return .receiverDashboard

        case .connectionRequest:
            // Navigate to connections/pending
            return .pendingConnections

        case .paymentReminder, .trialEnding:
            // Navigate to subscription management
            return .subscription

        case .dataExportReady, .dataExportEmailSent:
            // Navigate to settings/data export section
            return .settings

        case .pingTimeChanged:
            // Navigate to receiver dashboard to see updated ping time
            return .receiverDashboard
        }
    }

    /// Post a navigation notification to be handled by the app coordinator
    /// - Parameter notification: The notification that was tapped
    func navigateToDestination(for notification: PruufNotification) {
        let destination = getNavigationDestination(for: notification)
        NotificationCenter.default.post(
            name: Self.navigateToNotificationDestination,
            object: nil,
            userInfo: ["destination": destination, "notification": notification]
        )
    }
}

// MARK: - Navigation Destination

/// Describes where to navigate when a notification is tapped
enum NotificationNavigationDestination: Equatable {
    /// Navigate to sender dashboard (for ping reminders)
    case senderDashboard

    /// Navigate to receiver dashboard
    case receiverDashboard

    /// Navigate to a specific sender's activity (for receivers)
    case senderActivity(senderId: UUID)

    /// Navigate to ping history for a connection
    case pingHistory(connectionId: UUID)

    /// Navigate to pending connection requests
    case pendingConnections

    /// Navigate to subscription management
    case subscription

    /// Navigate to settings
    case settings
}
