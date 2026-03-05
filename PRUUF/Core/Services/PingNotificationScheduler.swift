import Foundation
import UserNotifications
import Supabase

/// Service for scheduling and managing ping-related notifications
/// Implements Section 6.3: Ping Notifications Schedule
///
/// Handles both sender notifications (reminders) and receiver notifications (completion alerts)
@MainActor
final class PingNotificationScheduler: ObservableObject {

    // MARK: - Singleton

    static let shared = PingNotificationScheduler()

    // MARK: - Private Properties

    private let notificationCenter = UNUserNotificationCenter.current()
    private let database: PostgrestClient
    private let functionsClient: FunctionsClient

    // MARK: - Notification Identifiers

    /// Prefix identifiers for different notification types
    private enum NotificationPrefix {
        static let scheduledTime = "ping_scheduled_"
        static let missedPing = "ping_missed_"
        static let receiverMissed = "receiver_missed_"
        static let receiverMissedFollowup = "receiver_missed_followup_"
    }

    // MARK: - Notification Categories

    private enum NotificationCategory {
        static let pingReminder = "PING_REMINDER"
        static let missedPingAlert = "MISSED_PING_ALERT"
        static let receiverMissedAlert = "RECEIVER_MISSED_ALERT"
        static let pingCompleted = "PING_COMPLETED"
        static let breakStarted = "BREAK_STARTED"
    }

    // MARK: - Initialization

    init(database: PostgrestClient? = nil,
         functionsClient: FunctionsClient? = nil) {
        self.database = database ?? SupabaseConfig.client.schema("public")
        self.functionsClient = functionsClient ?? SupabaseConfig.client.functions
    }

    // MARK: - Configure Notification Categories

    /// Set up all ping notification categories and actions
    func configureNotificationCategories() {
        // Ping Reminder (at scheduled time) Actions
        let confirmAction = UNNotificationAction(
            identifier: "CONFIRM_PING",
            title: "Send Pruuf",
            options: [.foreground]
        )

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_PING",
            title: "Remind in 10 min",
            options: []
        )

        let pingReminderCategory = UNNotificationCategory(
            identifier: NotificationCategory.pingReminder,
            actions: [confirmAction, snoozeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Missed Ping Alert (for sender) - No actions needed
        let missedPingCategory = UNNotificationCategory(
            identifier: NotificationCategory.missedPingAlert,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        // Ping Completed (for receivers)
        let viewDetailsAction = UNNotificationAction(
            identifier: "VIEW_DETAILS",
            title: "View Details",
            options: [.foreground]
        )

        let pingCompletedCategory = UNNotificationCategory(
            identifier: NotificationCategory.pingCompleted,
            actions: [viewDetailsAction],
            intentIdentifiers: [],
            options: []
        )

        // Receiver Missed Alert (for receivers when sender hasn't checked in)
        let receiverMissedCategory = UNNotificationCategory(
            identifier: NotificationCategory.receiverMissedAlert,
            actions: [viewDetailsAction],
            intentIdentifiers: [],
            options: []
        )

        // Break Started (for receivers)
        let breakStartedCategory = UNNotificationCategory(
            identifier: NotificationCategory.breakStarted,
            actions: [viewDetailsAction],
            intentIdentifiers: [],
            options: []
        )

        // Register all categories
        notificationCenter.setNotificationCategories([
            pingReminderCategory,
            missedPingCategory,
            receiverMissedCategory,
            pingCompletedCategory,
            breakStartedCategory
        ])

        Logger.info("Ping notification categories configured")
    }

    // MARK: - Schedule Sender Notifications

    /// Schedule all sender notifications for a ping
    /// Respects user's notification preferences per Section 8.3
    /// - Parameter ping: The ping to schedule notifications for
    func scheduleSenderNotifications(for ping: Ping) async {
        // Get user's notification preferences
        let preferences = await getNotificationPreferences(for: ping.senderId)
        let standardSound = notificationSound(for: preferences)
        let criticalSound = notificationSound(for: preferences, critical: true)

        // Check master toggle - if disabled, don't schedule any notifications
        guard preferences.notificationsEnabled else {
            Logger.info("Notifications disabled - skipping all sender notifications for ping: \(ping.id)")
            return
        }

        // 1. Schedule notification at scheduled time (if ping reminders enabled)
        if preferences.pingReminders {
            await scheduleScheduledTimeReminder(for: ping, sound: standardSound)
        }

        // 2. Schedule missed ping notification at scheduled time - always schedule for sender
        // No grace period: deadline = scheduled time, so missed notification triggers at scheduled time
        await scheduleMissedPingNotification(for: ping, sound: criticalSound)

        Logger.info("Scheduled sender notifications for ping: \(ping.id) (ping_reminders: \(preferences.pingReminders))")
    }

    /// Fetch notification preferences for a user
    /// - Parameter userId: The user's ID
    /// - Returns: NotificationPreferences (defaults if not found)
    private func getNotificationPreferences(for userId: UUID) async -> NotificationPreferences {
        do {
            struct PrefsResponse: Codable {
                let notificationPreferences: NotificationPreferences?

                enum CodingKeys: String, CodingKey {
                    case notificationPreferences = "notification_preferences"
                }
            }

            let response: [PrefsResponse] = try await database
                .from("users")
                .select("notification_preferences")
                .eq("id", value: userId.uuidString)
                .execute()
                .value

            return response.first?.notificationPreferences ?? .defaults
        } catch {
            Logger.error("Failed to fetch notification preferences: \(error.localizedDescription)")
            return .defaults
        }
    }

    /// Schedule notification at the scheduled ping time
    /// "Time to ping! Tap to let everyone know you're okay."
    private func scheduleScheduledTimeReminder(for ping: Ping, sound: UNNotificationSound?) async {
        let content = UNMutableNotificationContent()
        content.title = "Time to Send Your Pruuf!"
        content.body = "Tap to let everyone know you're okay."
        content.sound = sound
        content.categoryIdentifier = NotificationCategory.pingReminder
        content.userInfo = [
            "type": NotificationType.pingReminder.rawValue,
            "ping_id": ping.id.uuidString,
            "connection_id": ping.connectionId.uuidString
        ]

        // Schedule for the scheduled time
        guard ping.scheduledTime > Date() else {
            Logger.info("Skipping scheduled time notification - time has passed")
            return
        }

        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: ping.scheduledTime
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        let request = UNNotificationRequest(
            identifier: "\(NotificationPrefix.scheduledTime)\(ping.id.uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            Logger.info("Scheduled ping reminder for \(ping.scheduledTime)")
        } catch {
            Logger.error("Failed to schedule ping reminder: \(error.localizedDescription)")
        }
    }

    /// Schedule missed ping notification at scheduled time (deadline = scheduled time, no grace period)
    /// This is for the sender to see they missed it (receiver notifications are sent via backend)
    private func scheduleMissedPingNotification(for ping: Ping, sound: UNNotificationSound?) async {
        let content = UNMutableNotificationContent()
        content.title = "Pruuf Missed"
        content.body = "You missed your Pruuf time. You can still submit a late Pruuf."
        content.sound = sound
        content.categoryIdentifier = NotificationCategory.missedPingAlert
        content.userInfo = [
            "type": NotificationType.missedPing.rawValue,
            "ping_id": ping.id.uuidString,
            "connection_id": ping.connectionId.uuidString
        ]

        // Schedule at the scheduled time (deadline = scheduled time, no grace period)
        guard ping.scheduledTime > Date() else {
            Logger.info("Skipping missed ping notification - time has passed")
            return
        }

        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: ping.scheduledTime
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        let request = UNNotificationRequest(
            identifier: "\(NotificationPrefix.missedPing)\(ping.id.uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            Logger.info("Scheduled missed ping notification for \(ping.scheduledTime)")
        } catch {
            Logger.error("Failed to schedule missed ping notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Cancel Sender Notifications

    /// Cancel all scheduled notifications for a ping (when completed or cancelled)
    /// - Parameter pingId: The ID of the ping
    func cancelSenderNotifications(for pingId: UUID) {
        let identifiers = [
            "\(NotificationPrefix.scheduledTime)\(pingId.uuidString)",
            "\(NotificationPrefix.missedPing)\(pingId.uuidString)",
            "\(NotificationPrefix.receiverMissed)\(pingId.uuidString)",
            "\(NotificationPrefix.receiverMissedFollowup)\(pingId.uuidString)"
        ]

        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        Logger.info("Cancelled all sender notifications for ping: \(pingId)")
    }

    /// Cancel all ping-related notifications
    func cancelAllPingNotifications() {
        Task { @MainActor in
            let requests = await notificationCenter.pendingNotificationRequests()
            let pingNotificationIds = requests.filter { request in
                request.identifier.hasPrefix(NotificationPrefix.scheduledTime) ||
                request.identifier.hasPrefix(NotificationPrefix.missedPing) ||
                request.identifier.hasPrefix(NotificationPrefix.receiverMissed) ||
                request.identifier.hasPrefix(NotificationPrefix.receiverMissedFollowup)
            }.map { $0.identifier }

            notificationCenter.removePendingNotificationRequests(withIdentifiers: pingNotificationIds)
            Logger.info("Cancelled all ping notifications: \(pingNotificationIds.count) removed")
        }
    }

    // MARK: - Receiver Notifications (Sent Immediately via Push)

    /// Create notification record for receiver when ping is completed on time
    /// "[Sender Name] is okay! ✓"
    /// - Parameters:
    ///   - senderName: The name of the sender
    ///   - receiverId: The receiver's user ID
    ///   - pingId: The completed ping's ID
    ///   - connectionId: The connection ID
    func notifyReceiverPingCompletedOnTime(
        senderName: String,
        receiverId: UUID,
        pingId: UUID,
        connectionId: UUID
    ) async throws {
        let notification = PruufNotificationInsert(
            userId: receiverId,
            type: .pingCompletedOnTime,
            title: "Check-in Received",
            body: "\(senderName) is okay! ✓",
            metadata: NotificationMetadata(
                pingId: pingId,
                connectionId: connectionId
            )
        )

        try await insertNotificationRecord(notification)
        Logger.info("Created on-time completion notification for receiver: \(receiverId)")
    }

    /// Create notification record for receiver when ping is completed late
    /// "[Sender Name] pinged late at [time]"
    /// - Parameters:
    ///   - senderName: The name of the sender
    ///   - receiverId: The receiver's user ID
    ///   - pingId: The completed ping's ID
    ///   - connectionId: The connection ID
    ///   - completedAt: When the ping was completed
    func notifyReceiverPingCompletedLate(
        senderName: String,
        receiverId: UUID,
        pingId: UUID,
        connectionId: UUID,
        completedAt: Date
    ) async throws {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short

        let notification = PruufNotificationInsert(
            userId: receiverId,
            type: .pingCompletedLate,
            title: "Late Check-in Received",
            body: "\(senderName) sent a late Pruuf at \(timeFormatter.string(from: completedAt))",
            metadata: NotificationMetadata(
                pingId: pingId,
                connectionId: connectionId
            )
        )

        try await insertNotificationRecord(notification)
        Logger.info("Created late completion notification for receiver: \(receiverId)")
    }

    /// Create notification record for receiver when ping is missed (immediate, at scheduled time)
    /// "[Sender Name] hasn't sent their Pruuf yet."
    /// - Parameters:
    ///   - senderName: The name of the sender
    ///   - receiverId: The receiver's user ID
    ///   - pingId: The missed ping's ID
    ///   - connectionId: The connection ID
    ///   - lastSeen: Last time the sender was seen (optional)
    func notifyReceiverPingMissed(
        senderName: String,
        receiverId: UUID,
        pingId: UUID,
        connectionId: UUID,
        lastSeen: Date?
    ) async throws {
        let notification = PruufNotificationInsert(
            userId: receiverId,
            type: .missedPing,
            title: "Missed Check-in Alert",
            body: "\(senderName) hasn't sent their Pruuf yet.",
            metadata: NotificationMetadata(
                pingId: pingId,
                connectionId: connectionId
            )
        )

        try await insertNotificationRecord(notification)
        Logger.info("Created missed ping notification for receiver: \(receiverId)")
    }

    /// Create second notification record for receiver 60 minutes after scheduled time
    /// "[Sender Name] still hasn't sent their Pruuf. It's been 60 minutes past their check-in time."
    /// - Parameters:
    ///   - senderName: The name of the sender
    ///   - receiverId: The receiver's user ID
    ///   - pingId: The missed ping's ID
    ///   - connectionId: The connection ID
    func notifyReceiverPingMissedFollowup(
        senderName: String,
        receiverId: UUID,
        pingId: UUID,
        connectionId: UUID
    ) async throws {
        let notification = PruufNotificationInsert(
            userId: receiverId,
            type: .missedPing,
            title: "Missed Check-in Alert",
            body: "\(senderName) still hasn't sent their Pruuf. It's been 60 minutes past their check-in time.",
            metadata: NotificationMetadata(
                pingId: pingId,
                connectionId: connectionId
            )
        )

        try await insertNotificationRecord(notification)
        Logger.info("Created 60-minute followup missed ping notification for receiver: \(receiverId)")
    }

    /// Create notification record for receiver when sender starts a break
    /// "[Sender Name] is on Pruuf Pause until [date]"
    /// - Parameters:
    ///   - senderName: The name of the sender
    ///   - receiverId: The receiver's user ID
    ///   - connectionId: The connection ID
    ///   - endDate: When the break ends
    func notifyReceiverBreakStarted(
        senderName: String,
        receiverId: UUID,
        connectionId: UUID,
        endDate: Date
    ) async throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        let notification = PruufNotificationInsert(
            userId: receiverId,
            type: .breakStarted,
            title: "Pruuf Pause Started",
            body: "\(senderName) is on Pruuf Pause until \(dateFormatter.string(from: endDate))",
            metadata: NotificationMetadata(
                connectionId: connectionId
            )
        )

        try await insertNotificationRecord(notification)
        Logger.info("Created break started notification for receiver: \(receiverId)")
    }

    // MARK: - Database Operations

    /// Insert a notification record into the database
    /// The backend edge function will handle actual push notification delivery
    private func insertNotificationRecord(_ notification: PruufNotificationInsert) async throws {
        do {
            try await database
                .from("notifications")
                .insert(notification)
                .execute()
        } catch {
            Logger.error("Failed to insert notification record: \(error.localizedDescription)")
            throw PingNotificationError.databaseError(error.localizedDescription)
        }
    }

    // MARK: - Handle Notification Actions

    /// Handle notification action from user interaction
    /// - Parameters:
    ///   - actionIdentifier: The action identifier from the notification
    ///   - userInfo: Additional data from the notification
    func handleNotificationAction(_ actionIdentifier: String, userInfo: [AnyHashable: Any]) async {
        switch actionIdentifier {
        case "CONFIRM_PING":
            await handleConfirmPingAction(userInfo: userInfo)
        case "SNOOZE_PING":
            await handleSnoozePingAction(userInfo: userInfo)
        case "VIEW_DETAILS":
            // Navigation handled by AppDelegate
            Logger.info("View details action - navigation handled by AppDelegate")
        default:
            Logger.info("Unknown notification action: \(actionIdentifier)")
        }
    }

    /// Handle confirm ping action from notification
    private func handleConfirmPingAction(userInfo: [AnyHashable: Any]) async {
        guard let pingIdString = userInfo["ping_id"] as? String,
              let pingId = UUID(uuidString: pingIdString) else {
            Logger.error("Invalid ping_id in notification userInfo")
            return
        }

        // Navigation to confirm ping will be handled by AppDelegate posting a notification
        NotificationCenter.default.post(
            name: .navigateToPingConfirmation,
            object: nil,
            userInfo: ["ping_id": pingId]
        )

        Logger.info("Posted navigation to ping confirmation for: \(pingId)")
    }

    /// Handle snooze ping action - schedule reminder in 10 minutes
    private func handleSnoozePingAction(userInfo: [AnyHashable: Any]) async {
        guard let pingIdString = userInfo["ping_id"] as? String,
              let pingId = UUID(uuidString: pingIdString) else {
            Logger.error("Invalid ping_id in notification userInfo")
            return
        }

        let soundEnabled = await MainActor.run {
            NotificationPreferencesService.shared.preferences.soundEnabled
        }

        // Schedule a snooze notification for 10 minutes from now
        let content = UNMutableNotificationContent()
        content.title = "Pruuf Reminder"
        content.body = "Time to complete your check-in!"
        content.sound = soundEnabled ? .default : nil
        content.categoryIdentifier = NotificationCategory.pingReminder
        content.userInfo = userInfo

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10 * 60, repeats: false)

        let request = UNNotificationRequest(
            identifier: "ping_snooze_\(pingId.uuidString)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            Logger.info("Scheduled snooze reminder for ping: \(pingId)")
        } catch {
            Logger.error("Failed to schedule snooze reminder: \(error.localizedDescription)")
        }
    }

    // MARK: - Reschedule All Pending Pings

    /// Reschedule notifications for all pending pings (e.g., after app launch)
    /// - Parameter userId: The sender's user ID
    func rescheduleNotificationsForPendingPings(userId: UUID) async {
        do {
            let formatter = ISO8601DateFormatter()
            let pings: [Ping] = try await database
                .from("pings")
                .select()
                .eq("sender_id", value: userId.uuidString)
                .eq("status", value: PingStatus.pending.rawValue)
                .gte("deadline_time", value: formatter.string(from: Date()))
                .execute()
                .value

            // Cancel any existing notifications first
            cancelAllPingNotifications()

            // Schedule notifications for each pending ping
            for ping in pings {
                await scheduleSenderNotifications(for: ping)
            }

            Logger.info("Rescheduled notifications for \(pings.count) pending pings")
        } catch {
            Logger.error("Failed to reschedule ping notifications: \(error.localizedDescription)")
        }
    }

    // MARK: - Sound Preferences

    private func notificationSound(for preferences: NotificationPreferences, critical: Bool = false) -> UNNotificationSound? {
        guard preferences.soundEnabled else { return nil }
        return critical ? .defaultCritical : .default
    }

    // MARK: - Get Pending Notifications Count

    /// Get the count of pending ping notifications
    /// - Returns: Number of pending ping-related notifications
    func getPendingNotificationsCount() async -> Int {
        return await withCheckedContinuation { continuation in
            notificationCenter.getPendingNotificationRequests { requests in
                let count = requests.filter { request in
                    request.identifier.hasPrefix(NotificationPrefix.scheduledTime) ||
                    request.identifier.hasPrefix(NotificationPrefix.missedPing) ||
                    request.identifier.hasPrefix(NotificationPrefix.receiverMissed) ||
                    request.identifier.hasPrefix(NotificationPrefix.receiverMissedFollowup)
                }.count
                continuation.resume(returning: count)
            }
        }
    }
}

// MARK: - Notification Insert Model

/// Model for inserting notifications into the database
private struct PruufNotificationInsert: Codable {
    let userId: UUID
    let type: NotificationType
    let title: String
    let body: String
    let metadata: NotificationMetadata?
    let deliveryStatus: DeliveryStatus

    init(userId: UUID,
         type: NotificationType,
         title: String,
         body: String,
         metadata: NotificationMetadata? = nil,
         deliveryStatus: DeliveryStatus = .pending) {
        self.userId = userId
        self.type = type
        self.title = title
        self.body = body
        self.metadata = metadata
        self.deliveryStatus = deliveryStatus
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case type
        case title
        case body
        case metadata
        case deliveryStatus = "delivery_status"
    }
}

// MARK: - Ping Notification Errors

enum PingNotificationError: LocalizedError {
    case schedulingFailed(String)
    case databaseError(String)
    case invalidPingData

    var errorDescription: String? {
        switch self {
        case .schedulingFailed(let message):
            return "Failed to schedule notification: \(message)"
        case .databaseError(let message):
            return "Database error: \(message)"
        case .invalidPingData:
            return "Invalid ping data provided"
        }
    }
}

// Note: Notification.Name extensions are defined in AppDelegate.swift
// - .navigateToPingConfirmation
// - .navigateToConnectionDetails
// - .navigateToConnectionRequests
