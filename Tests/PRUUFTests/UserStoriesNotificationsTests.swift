import XCTest
@testable import PRUUF

/// Tests for Phase 8 Section 8.5 User Stories Notifications
/// US-8.1: Receive Push Notifications
/// US-8.2: Customize Notification Preferences
/// US-8.3: View Notification History
final class UserStoriesNotificationsTests: XCTestCase {

    // MARK: - US-8.1: Receive Push Notifications Tests

    /// Test that NotificationPreferences supports sound configuration
    func testSoundEnabledPreference() {
        // Default should be enabled
        let defaultPrefs = NotificationPreferences.defaults
        XCTAssertTrue(defaultPrefs.soundEnabled)

        // Can be disabled
        let disabledPrefs = NotificationPreferences(soundEnabled: false)
        XCTAssertFalse(disabledPrefs.soundEnabled)
    }

    /// Test that NotificationPreferences supports vibration configuration
    func testVibrationEnabledPreference() {
        // Default should be enabled
        let defaultPrefs = NotificationPreferences.defaults
        XCTAssertTrue(defaultPrefs.vibrationEnabled)

        // Can be disabled
        let disabledPrefs = NotificationPreferences(vibrationEnabled: false)
        XCTAssertFalse(disabledPrefs.vibrationEnabled)
    }

    /// Test that notification types have appropriate deep link destinations
    @MainActor
    func testNotificationDeepLinkDestinations() {
        let store = InAppNotificationStore.shared
        store.clearCache()

        // Ping reminder should go to sender dashboard
        let pingReminderNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Time to ping!",
            body: "Tap to let everyone know you're okay.",
            sentAt: Date(),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        let pingDestination = store.getNavigationDestination(for: pingReminderNotification)
        XCTAssertEqual(pingDestination, .senderDashboard)

        // Missed ping should navigate to sender activity or receiver dashboard
        let missedPingNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .missedPing,
            title: "Missed Ping Alert",
            body: "John missed their ping.",
            sentAt: Date(),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        let missedDestination = store.getNavigationDestination(for: missedPingNotification)
        XCTAssertEqual(missedDestination, .receiverDashboard)

        // Trial ending should go to subscription
        let trialEndingNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .trialEnding,
            title: "Trial Ending Soon",
            body: "Your free trial ends in 3 days.",
            sentAt: Date(),
            readAt: nil,
            metadata: NotificationMetadata(trialDaysRemaining: 3),
            deliveryStatus: .sent
        )
        let trialDestination = store.getNavigationDestination(for: trialEndingNotification)
        XCTAssertEqual(trialDestination, .subscription)
    }

    // MARK: - US-8.2: Customize Notification Preferences Tests

    /// Test master toggle functionality
    func testMasterToggle() {
        // All enabled by default
        var prefs = NotificationPreferences.defaults
        XCTAssertTrue(prefs.notificationsEnabled)

        // Disable master toggle
        prefs.notificationsEnabled = false

        // When master is disabled, shouldSendNotification should return false for any type
        XCTAssertFalse(prefs.shouldSendNotification(type: .pingReminder))
        XCTAssertFalse(prefs.shouldSendNotification(type: .missedPing))
        XCTAssertFalse(prefs.shouldSendNotification(type: .pingCompletedOnTime))
    }

    /// Test sender notification preferences (ping reminders, 15-min warning, deadline warning)
    func testSenderNotificationPreferences() {
        var prefs = NotificationPreferences.defaults

        // Test ping reminders toggle
        prefs.pingReminders = false
        XCTAssertFalse(prefs.shouldSendNotification(type: .pingReminder))
        prefs.pingReminders = true
        XCTAssertTrue(prefs.shouldSendNotification(type: .pingReminder))

        // Test 15-minute warning toggle
        prefs.fifteenMinuteWarning = false
        XCTAssertFalse(prefs.shouldSendNotification(type: .deadlineWarning))
        prefs.fifteenMinuteWarning = true
        XCTAssertTrue(prefs.shouldSendNotification(type: .deadlineWarning))

        // Test deadline warning toggle
        prefs.deadlineWarning = false
        XCTAssertFalse(prefs.shouldSendNotification(type: .deadlineFinal))
        prefs.deadlineWarning = true
        XCTAssertTrue(prefs.shouldSendNotification(type: .deadlineFinal))
    }

    /// Test receiver notification preferences (ping completed, missed ping alerts, connection requests)
    func testReceiverNotificationPreferences() {
        var prefs = NotificationPreferences.defaults

        // Test ping completed notifications
        prefs.pingCompletedNotifications = false
        XCTAssertFalse(prefs.shouldSendNotification(type: .pingCompletedOnTime))
        XCTAssertFalse(prefs.shouldSendNotification(type: .pingCompletedLate))
        prefs.pingCompletedNotifications = true
        XCTAssertTrue(prefs.shouldSendNotification(type: .pingCompletedOnTime))
        XCTAssertTrue(prefs.shouldSendNotification(type: .pingCompletedLate))

        // Test missed ping alerts
        prefs.missedPingAlerts = false
        XCTAssertFalse(prefs.shouldSendNotification(type: .missedPing))
        prefs.missedPingAlerts = true
        XCTAssertTrue(prefs.shouldSendNotification(type: .missedPing))

        // Test connection requests
        prefs.connectionRequests = false
        XCTAssertFalse(prefs.shouldSendNotification(type: .connectionRequest))
        prefs.connectionRequests = true
        XCTAssertTrue(prefs.shouldSendNotification(type: .connectionRequest))
    }

    /// Test per-sender muting for receivers
    func testPerSenderMuting() {
        var prefs = NotificationPreferences.defaults

        let senderId = UUID()

        // Initially not muted
        XCTAssertFalse(prefs.isSenderMuted(senderId))
        XCTAssertTrue(prefs.shouldSendNotification(type: .missedPing, senderId: senderId))

        // Mute the sender
        prefs = prefs.mutingSender(senderId)
        XCTAssertTrue(prefs.isSenderMuted(senderId))
        XCTAssertFalse(prefs.shouldSendNotification(type: .missedPing, senderId: senderId))

        // Unmute the sender
        prefs = prefs.unmutingSender(senderId)
        XCTAssertFalse(prefs.isSenderMuted(senderId))
        XCTAssertTrue(prefs.shouldSendNotification(type: .missedPing, senderId: senderId))
    }

    /// Test that changes are applied immediately (no pending state)
    func testPreferencesApplyImmediately() {
        var prefs = NotificationPreferences.defaults

        // Change should be immediately reflected
        prefs.notificationsEnabled = false
        XCTAssertFalse(prefs.notificationsEnabled)

        prefs.pingReminders = false
        XCTAssertFalse(prefs.pingReminders)

        let senderId = UUID()
        prefs = prefs.mutingSender(senderId)
        XCTAssertTrue(prefs.isSenderMuted(senderId))
    }

    // MARK: - US-8.3: View Notification History Tests

    /// Test notification time since formatting
    func testNotificationTimeSinceFormatting() {
        // Just now (< 1 minute)
        let justNowNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test",
            sentAt: Date().addingTimeInterval(-30),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertEqual(justNowNotification.timeSince, "Just now")

        // Minutes ago
        let minutesNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test",
            sentAt: Date().addingTimeInterval(-300),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertEqual(minutesNotification.timeSince, "5 min ago")

        // Hours ago
        let hoursNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test",
            sentAt: Date().addingTimeInterval(-7200),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertEqual(hoursNotification.timeSince, "2 hours ago")

        // Days ago
        let daysNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test",
            sentAt: Date().addingTimeInterval(-172800),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertEqual(daysNotification.timeSince, "2 days ago")
    }

    /// Test notification read/unread state
    func testNotificationReadState() {
        // Unread notification
        let unreadNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test",
            sentAt: Date(),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertFalse(unreadNotification.isRead)

        // Read notification
        let readNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test",
            sentAt: Date().addingTimeInterval(-60),
            readAt: Date(),
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertTrue(readNotification.isRead)
    }

    /// Test notification store initial state
    @MainActor
    func testNotificationStoreInitialState() {
        let store = InAppNotificationStore.shared
        store.clearCache()

        XCTAssertTrue(store.notifications.isEmpty)
        XCTAssertEqual(store.unreadCount, 0)
        XCTAssertFalse(store.isLoading)
    }

    /// Test that notification types have correct icons
    func testNotificationTypeIcons() {
        XCTAssertEqual(NotificationType.pingReminder.iconName, "bell.fill")
        XCTAssertEqual(NotificationType.missedPing.iconName, "exclamationmark.triangle.fill")
        XCTAssertEqual(NotificationType.pingCompletedOnTime.iconName, "checkmark.circle.fill")
        XCTAssertEqual(NotificationType.connectionRequest.iconName, "person.badge.plus")
        XCTAssertEqual(NotificationType.trialEnding.iconName, "clock.fill")
    }

    /// Test navigation to related content on tap
    @MainActor
    func testNavigateToRelatedContent() {
        let store = InAppNotificationStore.shared
        let connectionId = UUID()
        let senderId = UUID()

        // Ping completed should navigate to ping history
        let pingCompletedNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingCompletedOnTime,
            title: "Test",
            body: "Test",
            sentAt: Date(),
            readAt: nil,
            metadata: NotificationMetadata(connectionId: connectionId),
            deliveryStatus: .sent
        )
        let pingHistoryDestination = store.getNavigationDestination(for: pingCompletedNotification)
        XCTAssertEqual(pingHistoryDestination, .pingHistory(connectionId: connectionId))

        // Break started should navigate to sender activity
        let breakNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .breakStarted,
            title: "Test",
            body: "Test",
            sentAt: Date(),
            readAt: nil,
            metadata: NotificationMetadata(senderId: senderId),
            deliveryStatus: .sent
        )
        let senderActivityDestination = store.getNavigationDestination(for: breakNotification)
        XCTAssertEqual(senderActivityDestination, .senderActivity(senderId: senderId))

        // Connection request should navigate to pending connections
        let connectionRequestNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .connectionRequest,
            title: "Test",
            body: "Test",
            sentAt: Date(),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        let connectionsDestination = store.getNavigationDestination(for: connectionRequestNotification)
        XCTAssertEqual(connectionsDestination, .pendingConnections)
    }

    // MARK: - Badge Count Tests

    /// Test badge count reflects unread notifications
    @MainActor
    func testBadgeCountReflectsUnreadCount() {
        let store = InAppNotificationStore.shared
        store.clearCache()

        // Initially zero
        XCTAssertEqual(store.unreadCount, 0)
    }

    // MARK: - Notification Preferences Codable Tests

    /// Test that NotificationPreferences can be encoded and decoded properly
    func testNotificationPreferencesCodable() throws {
        let original = NotificationPreferences(
            notificationsEnabled: true,
            pingReminders: false,
            fifteenMinuteWarning: true,
            deadlineWarning: false,
            pingCompletedNotifications: true,
            missedPingAlerts: false,
            connectionRequests: true,
            mutedSenderIds: [UUID()],
            soundEnabled: false,
            vibrationEnabled: true,
            quietHoursEnabled: false,
            quietHoursStart: nil,
            quietHoursEnd: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NotificationPreferences.self, from: data)

        XCTAssertEqual(original.notificationsEnabled, decoded.notificationsEnabled)
        XCTAssertEqual(original.pingReminders, decoded.pingReminders)
        XCTAssertEqual(original.fifteenMinuteWarning, decoded.fifteenMinuteWarning)
        XCTAssertEqual(original.deadlineWarning, decoded.deadlineWarning)
        XCTAssertEqual(original.pingCompletedNotifications, decoded.pingCompletedNotifications)
        XCTAssertEqual(original.missedPingAlerts, decoded.missedPingAlerts)
        XCTAssertEqual(original.connectionRequests, decoded.connectionRequests)
        XCTAssertEqual(original.soundEnabled, decoded.soundEnabled)
        XCTAssertEqual(original.vibrationEnabled, decoded.vibrationEnabled)
        XCTAssertEqual(original.quietHoursEnabled, decoded.quietHoursEnabled)
    }
}
