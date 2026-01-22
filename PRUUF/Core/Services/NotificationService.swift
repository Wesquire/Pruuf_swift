import Foundation
import UserNotifications
import Supabase
import UIKit

/// Service for managing push and local notifications
/// Handles device registration, notification scheduling, and handling
@MainActor
final class NotificationService: ObservableObject {

    // MARK: - Singleton

    static let shared = NotificationService()

    // MARK: - Published Properties

    @Published private(set) var isNotificationsEnabled: Bool = false
    @Published private(set) var deviceToken: String?

    // MARK: - Private Properties

    private let database: PostgrestClient
    private let notificationCenter = UNUserNotificationCenter.current()

    // MARK: - Notification Categories

    private enum NotificationCategory {
        static let pingReminder = "PING_REMINDER"
        static let missedPingAlert = "MISSED_PING_ALERT"
        static let missedPing = "MISSED_PING"
        static let connectionRequest = "CONNECTION_REQUEST"
        static let trialEnding = "TRIAL_ENDING"
        static let pingReceived = "PING_RECEIVED"
        static let breakNotification = "BREAK_NOTIFICATION"
    }

    // MARK: - Initialization

    init(database: PostgrestClient? = nil) {
        self.database = database ?? SupabaseConfig.client.schema("public")
        Task {
            await checkNotificationStatus()
        }
    }

    // MARK: - Check Notification Status

    /// Check current notification authorization status
    func checkNotificationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        isNotificationsEnabled = settings.authorizationStatus == .authorized
    }

    // MARK: - Request Notification Permission

    /// Request permission to send notifications
    /// - Returns: Whether permission was granted
    @discardableResult
    func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            await MainActor.run {
                self.isNotificationsEnabled = granted
            }
            return granted
        } catch {
            Logger.error("Failed to request notification permission: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Register Device Token

    /// Register the device token with the backend
    /// This is called whenever the device registers for remote notifications (app launch, token refresh)
    /// - Parameter token: The APNs device token as a hex string
    func registerDeviceToken(_ token: String) async {
        // Check if token has changed
        let previousToken = self.deviceToken
        self.deviceToken = token

        // Get user session
        guard let userId = try? await SupabaseConfig.auth.session.user.id else {
            Logger.warning("Cannot register device token: No authenticated user")
            return
        }

        do {
            // Determine platform (sandbox vs production)
            #if DEBUG
            let platform = "ios_sandbox"
            #else
            let platform = "ios"
            #endif

            // Get device info
            let deviceName = await MainActor.run { UIDevice.current.name }
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

            // Call the register_device_token database function
            // This handles upsert (update if exists, insert if new)
            try await database.rpc(
                "register_device_token",
                params: [
                    "p_user_id": userId.uuidString,
                    "p_device_token": token,
                    "p_platform": platform,
                    "p_device_name": deviceName,
                    "p_app_version": appVersion
                ]
            )
            .execute()

            if previousToken != nil && previousToken != token {
                Logger.info("Device token updated (token changed)")
            } else if previousToken == nil {
                Logger.info("Device token registered successfully")
            } else {
                Logger.info("Device token refreshed (unchanged)")
            }
        } catch {
            Logger.error("Failed to register device token: \(error.localizedDescription)")

            // Fallback: Update the legacy device_token column directly
            do {
                try await database
                    .from("users")
                    .update(["device_token": token])
                    .eq("id", value: userId.uuidString)
                    .execute()
                Logger.info("Device token saved to users table (fallback)")
            } catch {
                Logger.error("Fallback device token save also failed: \(error.localizedDescription)")
            }
        }
    }

    /// Unregister the device token when user logs out
    /// This marks the token as inactive so notifications won't be sent
    func unregisterDeviceToken() async {
        guard let token = deviceToken,
              let userId = try? await SupabaseConfig.auth.session.user.id else {
            return
        }

        do {
            // Mark the token as inactive
            try await database
                .from("device_tokens")
                .update(["is_active": false])
                .eq("user_id", value: userId.uuidString)
                .eq("device_token", value: token)
                .execute()

            self.deviceToken = nil
            Logger.info("Device token unregistered successfully")
        } catch {
            Logger.error("Failed to unregister device token: \(error.localizedDescription)")
        }
    }

    /// Re-register device token after login
    /// Called when user signs in to ensure their token is active
    func reactivateDeviceToken() async {
        guard let token = deviceToken else {
            // No token stored, request new registration
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return
        }

        // Re-register with current token
        await registerDeviceToken(token)
    }

    // MARK: - Schedule Local Notification

    /// Schedule a local notification for a ping reminder
    /// - Parameters:
    ///   - ping: The ping to remind about
    ///   - reminderMinutes: Minutes before deadline to send reminder
    func schedulePingReminder(for ping: Ping, reminderMinutes: Int = 15) async {
        let content = UNMutableNotificationContent()
        content.title = "Ping Reminder"
        content.body = "Your daily check-in is due soon. Tap to confirm you're okay."
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.pingReminder
        content.userInfo = [
            "type": "ping_reminder",
            "ping_id": ping.id.uuidString
        ]

        // Schedule for X minutes before deadline
        let triggerDate = ping.deadlineTime.addingTimeInterval(-Double(reminderMinutes * 60))

        // Only schedule if trigger date is in the future
        guard triggerDate > Date() else { return }

        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        let request = UNNotificationRequest(
            identifier: "ping_reminder_\(ping.id.uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            Logger.info("Scheduled ping reminder for \(triggerDate)")
        } catch {
            Logger.error("Failed to schedule ping reminder: \(error.localizedDescription)")
        }
    }

    // MARK: - Cancel Scheduled Notification

    /// Cancel a scheduled notification
    /// - Parameter identifier: The notification identifier
    func cancelNotification(identifier: String) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Cancel all ping reminder notifications
    func cancelAllPingReminders() {
        Task { @MainActor in
            let requests = await notificationCenter.pendingNotificationRequests()
            let pingReminderIds = requests
                .filter { $0.identifier.hasPrefix("ping_reminder_") }
                .map { $0.identifier }
            notificationCenter.removePendingNotificationRequests(withIdentifiers: pingReminderIds)
        }
    }

    // MARK: - Handle Incoming Notifications

    /// Handle a ping reminder notification
    func handlePingReminder(_ userInfo: [AnyHashable: Any]) async {
        guard let pingIdString = userInfo["ping_id"] as? String,
              let pingId = UUID(uuidString: pingIdString) else {
            return
        }

        Logger.info("Handling ping reminder for ping: \(pingId)")
        // The actual navigation is handled by AppDelegate posting a notification
    }

    /// Handle a missed ping alert notification
    func handleMissedPingAlert(_ userInfo: [AnyHashable: Any]) async {
        guard let connectionIdString = userInfo["connection_id"] as? String,
              let _ = UUID(uuidString: connectionIdString) else {
            return
        }

        Logger.info("Handling missed ping alert")
        // The actual navigation is handled by AppDelegate posting a notification
    }

    // MARK: - Clear Badge

    /// Clear the notification badge
    func clearBadge() async {
        await MainActor.run {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }

    // MARK: - Update Badge Count

    /// Update the notification badge with a count
    func updateBadge(count: Int) async {
        await MainActor.run {
            UIApplication.shared.applicationIconBadgeNumber = count
        }
    }

    // MARK: - Configure Notification Categories

    /// Set up notification categories and actions
    func configureNotificationCategories() {
        // Ping Reminder Actions
        let confirmAction = UNNotificationAction(
            identifier: "CONFIRM_PING",
            title: "I'm Okay",
            options: [.foreground]
        )

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_PING",
            title: "Remind in 10 min",
            options: []
        )

        let pingCategory = UNNotificationCategory(
            identifier: NotificationCategory.pingReminder,
            actions: [confirmAction, snoozeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Connection Request Actions
        let acceptAction = UNNotificationAction(
            identifier: "ACCEPT_CONNECTION",
            title: "Accept",
            options: [.foreground]
        )

        let declineAction = UNNotificationAction(
            identifier: "DECLINE_CONNECTION",
            title: "Decline",
            options: [.destructive]
        )

        let connectionCategory = UNNotificationCategory(
            identifier: NotificationCategory.connectionRequest,
            actions: [acceptAction, declineAction],
            intentIdentifiers: [],
            options: []
        )

        // Missed Ping Category (for receivers)
        let missedPingCategory = UNNotificationCategory(
            identifier: NotificationCategory.missedPing,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        // Ping Received Category (for receivers)
        let pingReceivedCategory = UNNotificationCategory(
            identifier: NotificationCategory.pingReceived,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        // Trial Ending Category
        let subscribeAction = UNNotificationAction(
            identifier: "SUBSCRIBE_NOW",
            title: "Subscribe Now",
            options: [.foreground]
        )

        let trialEndingCategory = UNNotificationCategory(
            identifier: NotificationCategory.trialEnding,
            actions: [subscribeAction],
            intentIdentifiers: [],
            options: []
        )

        // Break Notification Category (for receivers)
        let breakCategory = UNNotificationCategory(
            identifier: NotificationCategory.breakNotification,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        // Register categories
        notificationCenter.setNotificationCategories([
            pingCategory,
            connectionCategory,
            missedPingCategory,
            pingReceivedCategory,
            trialEndingCategory,
            breakCategory
        ])
    }
}

// MARK: - Notification Service Errors

enum NotificationServiceError: LocalizedError {
    case permissionDenied
    case schedulingFailed(String)
    case registrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notification permission was denied. Please enable notifications in Settings."
        case .schedulingFailed(let message):
            return "Failed to schedule notification: \(message)"
        case .registrationFailed(let message):
            return "Failed to register for notifications: \(message)"
        }
    }
}
