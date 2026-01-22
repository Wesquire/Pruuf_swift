import XCTest
@testable import PRUUF

/// Tests for the In-App Notification system (Phase 8.4)
final class InAppNotificationTests: XCTestCase {

    // MARK: - PruufNotification Model Tests

    func testNotificationIsRead() {
        let now = Date()

        // Unread notification
        let unreadNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Ping Reminder",
            body: "Your daily check-in is due soon.",
            sentAt: now,
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
            title: "Ping Reminder",
            body: "Your daily check-in is due soon.",
            sentAt: now,
            readAt: now.addingTimeInterval(60),
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertTrue(readNotification.isRead)
    }

    func testNotificationWasDelivered() {
        let now = Date()

        let sentNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test body",
            sentAt: now,
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertTrue(sentNotification.wasDelivered)

        let failedNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test body",
            sentAt: now,
            readAt: nil,
            metadata: nil,
            deliveryStatus: .failed
        )
        XCTAssertFalse(failedNotification.wasDelivered)

        let pendingNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test body",
            sentAt: now,
            readAt: nil,
            metadata: nil,
            deliveryStatus: .pending
        )
        XCTAssertFalse(pendingNotification.wasDelivered)
    }

    func testNotificationTimeSinceJustNow() {
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test body",
            sentAt: Date().addingTimeInterval(-30), // 30 seconds ago
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertEqual(notification.timeSince, "Just now")
    }

    func testNotificationTimeSinceMinutes() {
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test body",
            sentAt: Date().addingTimeInterval(-300), // 5 minutes ago
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertEqual(notification.timeSince, "5 min ago")
    }

    func testNotificationTimeSinceHours() {
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test body",
            sentAt: Date().addingTimeInterval(-7200), // 2 hours ago
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertEqual(notification.timeSince, "2 hours ago")
    }

    func testNotificationTimeSinceOneHour() {
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test body",
            sentAt: Date().addingTimeInterval(-3600), // 1 hour ago
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertEqual(notification.timeSince, "1 hour ago")
    }

    func testNotificationTimeSinceDays() {
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test body",
            sentAt: Date().addingTimeInterval(-172800), // 2 days ago
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertEqual(notification.timeSince, "2 days ago")
    }

    func testNotificationTimeSinceOneDay() {
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test body",
            sentAt: Date().addingTimeInterval(-86400), // 1 day ago
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertEqual(notification.timeSince, "1 day ago")
    }

    // MARK: - NotificationType Tests

    func testNotificationTypeDisplayName() {
        XCTAssertEqual(NotificationType.pingReminder.displayName, "Ping Reminder")
        XCTAssertEqual(NotificationType.deadlineWarning.displayName, "Deadline Warning")
        XCTAssertEqual(NotificationType.deadlineFinal.displayName, "Final Deadline")
        XCTAssertEqual(NotificationType.missedPing.displayName, "Missed Ping")
        XCTAssertEqual(NotificationType.pingCompletedOnTime.displayName, "Ping Completed")
        XCTAssertEqual(NotificationType.pingCompletedLate.displayName, "Late Ping")
        XCTAssertEqual(NotificationType.breakStarted.displayName, "Break Started")
        XCTAssertEqual(NotificationType.connectionRequest.displayName, "Connection Request")
        XCTAssertEqual(NotificationType.paymentReminder.displayName, "Payment Reminder")
        XCTAssertEqual(NotificationType.trialEnding.displayName, "Trial Ending")
    }

    func testNotificationTypeIconName() {
        XCTAssertEqual(NotificationType.pingReminder.iconName, "bell.fill")
        XCTAssertEqual(NotificationType.deadlineWarning.iconName, "exclamationmark.circle.fill")
        XCTAssertEqual(NotificationType.deadlineFinal.iconName, "clock.badge.exclamationmark.fill")
        XCTAssertEqual(NotificationType.missedPing.iconName, "exclamationmark.triangle.fill")
        XCTAssertEqual(NotificationType.pingCompletedOnTime.iconName, "checkmark.circle.fill")
        XCTAssertEqual(NotificationType.pingCompletedLate.iconName, "clock.arrow.circlepath")
        XCTAssertEqual(NotificationType.breakStarted.iconName, "moon.fill")
        XCTAssertEqual(NotificationType.connectionRequest.iconName, "person.badge.plus")
        XCTAssertEqual(NotificationType.paymentReminder.iconName, "creditcard.fill")
        XCTAssertEqual(NotificationType.trialEnding.iconName, "clock.fill")
    }

    func testNotificationTypePriority() {
        // Highest priority notifications
        XCTAssertEqual(NotificationType.missedPing.priority, 5)
        XCTAssertEqual(NotificationType.deadlineFinal.priority, 5)

        // High priority
        XCTAssertEqual(NotificationType.deadlineWarning.priority, 4)

        // Medium priority
        XCTAssertEqual(NotificationType.pingReminder.priority, 3)
        XCTAssertEqual(NotificationType.pingCompletedOnTime.priority, 3)
        XCTAssertEqual(NotificationType.pingCompletedLate.priority, 3)

        // Lower priority
        XCTAssertEqual(NotificationType.breakStarted.priority, 2)
        XCTAssertEqual(NotificationType.connectionRequest.priority, 2)
        XCTAssertEqual(NotificationType.trialEnding.priority, 2)
        XCTAssertEqual(NotificationType.paymentReminder.priority, 1)
    }

    func testNotificationTypeIsForSender() {
        // Sender notifications
        XCTAssertTrue(NotificationType.pingReminder.isForSender)
        XCTAssertTrue(NotificationType.deadlineWarning.isForSender)
        XCTAssertTrue(NotificationType.deadlineFinal.isForSender)
        XCTAssertTrue(NotificationType.connectionRequest.isForSender)
        XCTAssertTrue(NotificationType.paymentReminder.isForSender)
        XCTAssertTrue(NotificationType.trialEnding.isForSender)

        // Receiver notifications
        XCTAssertFalse(NotificationType.missedPing.isForSender)
        XCTAssertFalse(NotificationType.pingCompletedOnTime.isForSender)
        XCTAssertFalse(NotificationType.pingCompletedLate.isForSender)
        XCTAssertFalse(NotificationType.breakStarted.isForSender)
    }

    // MARK: - DeliveryStatus Tests

    func testDeliveryStatusDisplayName() {
        XCTAssertEqual(DeliveryStatus.sent.displayName, "Sent")
        XCTAssertEqual(DeliveryStatus.failed.displayName, "Failed")
        XCTAssertEqual(DeliveryStatus.pending.displayName, "Pending")
    }

    // MARK: - NotificationMetadata Tests

    func testNotificationMetadataEncoding() throws {
        let metadata = NotificationMetadata(
            pingId: UUID(),
            connectionId: UUID(),
            senderId: UUID(),
            receiverId: UUID(),
            trialDaysRemaining: 7,
            customData: ["key": "value"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NotificationMetadata.self, from: data)

        XCTAssertEqual(metadata.pingId, decoded.pingId)
        XCTAssertEqual(metadata.connectionId, decoded.connectionId)
        XCTAssertEqual(metadata.senderId, decoded.senderId)
        XCTAssertEqual(metadata.receiverId, decoded.receiverId)
        XCTAssertEqual(metadata.trialDaysRemaining, decoded.trialDaysRemaining)
        XCTAssertEqual(metadata.customData?["key"], decoded.customData?["key"])
    }

    func testNotificationMetadataEquality() {
        let id = UUID()
        let metadata1 = NotificationMetadata(pingId: id, connectionId: nil, senderId: nil, receiverId: nil, trialDaysRemaining: nil, customData: nil)
        let metadata2 = NotificationMetadata(pingId: id, connectionId: nil, senderId: nil, receiverId: nil, trialDaysRemaining: nil, customData: nil)
        let metadata3 = NotificationMetadata(pingId: UUID(), connectionId: nil, senderId: nil, receiverId: nil, trialDaysRemaining: nil, customData: nil)

        XCTAssertEqual(metadata1, metadata2)
        XCTAssertNotEqual(metadata1, metadata3)
    }

    // MARK: - NavigationDestination Tests

    func testNavigationDestinationEquality() {
        let uuid1 = UUID()
        let uuid2 = UUID()

        XCTAssertEqual(NotificationNavigationDestination.senderDashboard, NotificationNavigationDestination.senderDashboard)
        XCTAssertEqual(NotificationNavigationDestination.receiverDashboard, NotificationNavigationDestination.receiverDashboard)
        XCTAssertEqual(NotificationNavigationDestination.pendingConnections, NotificationNavigationDestination.pendingConnections)
        XCTAssertEqual(NotificationNavigationDestination.subscription, NotificationNavigationDestination.subscription)

        XCTAssertEqual(
            NotificationNavigationDestination.senderActivity(senderId: uuid1),
            NotificationNavigationDestination.senderActivity(senderId: uuid1)
        )
        XCTAssertNotEqual(
            NotificationNavigationDestination.senderActivity(senderId: uuid1),
            NotificationNavigationDestination.senderActivity(senderId: uuid2)
        )

        XCTAssertEqual(
            NotificationNavigationDestination.pingHistory(connectionId: uuid1),
            NotificationNavigationDestination.pingHistory(connectionId: uuid1)
        )
        XCTAssertNotEqual(
            NotificationNavigationDestination.pingHistory(connectionId: uuid1),
            NotificationNavigationDestination.pingHistory(connectionId: uuid2)
        )

        // Different types should not be equal
        XCTAssertNotEqual(NotificationNavigationDestination.senderDashboard, NotificationNavigationDestination.receiverDashboard)
    }

    // MARK: - PruufNotification Equatable Tests

    func testNotificationEquality() {
        let id = UUID()
        let userId = UUID()
        let now = Date()

        let notification1 = PruufNotification(
            id: id,
            userId: userId,
            type: .pingReminder,
            title: "Test",
            body: "Body",
            sentAt: now,
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )

        let notification2 = PruufNotification(
            id: id,
            userId: userId,
            type: .pingReminder,
            title: "Test",
            body: "Body",
            sentAt: now,
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )

        let notification3 = PruufNotification(
            id: UUID(), // Different ID
            userId: userId,
            type: .pingReminder,
            title: "Test",
            body: "Body",
            sentAt: now,
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )

        XCTAssertEqual(notification1, notification2)
        XCTAssertNotEqual(notification1, notification3)
    }

    // MARK: - PruufNotification Identifiable Tests

    func testNotificationIdentifiable() {
        let id = UUID()
        let notification = PruufNotification(
            id: id,
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Body",
            sentAt: Date(),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )

        XCTAssertEqual(notification.id, id)
    }

    // MARK: - NotificationType All Cases Tests

    func testNotificationTypeAllCases() {
        // Ensure all cases are covered
        let allCases = NotificationType.allCases
        XCTAssertEqual(allCases.count, 14)
        XCTAssertTrue(allCases.contains(.pingReminder))
        XCTAssertTrue(allCases.contains(.deadlineWarning))
        XCTAssertTrue(allCases.contains(.deadlineFinal))
        XCTAssertTrue(allCases.contains(.missedPing))
        XCTAssertTrue(allCases.contains(.pingCompletedOnTime))
        XCTAssertTrue(allCases.contains(.pingCompletedLate))
        XCTAssertTrue(allCases.contains(.breakStarted))
        XCTAssertTrue(allCases.contains(.breakNotification))
        XCTAssertTrue(allCases.contains(.connectionRequest))
        XCTAssertTrue(allCases.contains(.paymentReminder))
        XCTAssertTrue(allCases.contains(.trialEnding))
        XCTAssertTrue(allCases.contains(.dataExportReady))
        XCTAssertTrue(allCases.contains(.dataExportEmailSent))
        XCTAssertTrue(allCases.contains(.pingTimeChanged))
    }

    // MARK: - NotificationType Raw Value Tests

    func testNotificationTypeRawValues() {
        XCTAssertEqual(NotificationType.pingReminder.rawValue, "ping_reminder")
        XCTAssertEqual(NotificationType.deadlineWarning.rawValue, "deadline_warning")
        XCTAssertEqual(NotificationType.deadlineFinal.rawValue, "deadline_final")
        XCTAssertEqual(NotificationType.missedPing.rawValue, "missed_ping")
        XCTAssertEqual(NotificationType.pingCompletedOnTime.rawValue, "ping_completed_ontime")
        XCTAssertEqual(NotificationType.pingCompletedLate.rawValue, "ping_completed_late")
        XCTAssertEqual(NotificationType.breakStarted.rawValue, "break_started")
        XCTAssertEqual(NotificationType.connectionRequest.rawValue, "connection_request")
        XCTAssertEqual(NotificationType.paymentReminder.rawValue, "payment_reminder")
        XCTAssertEqual(NotificationType.trialEnding.rawValue, "trial_ending")
    }

    // MARK: - DeliveryStatus Raw Value Tests

    func testDeliveryStatusRawValues() {
        XCTAssertEqual(DeliveryStatus.sent.rawValue, "sent")
        XCTAssertEqual(DeliveryStatus.failed.rawValue, "failed")
        XCTAssertEqual(DeliveryStatus.pending.rawValue, "pending")
    }

    // MARK: - Notification Codable Tests

    func testNotificationEncoding() throws {
        let now = Date()
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test Notification",
            body: "This is a test notification body.",
            sentAt: now,
            readAt: nil,
            metadata: NotificationMetadata(pingId: UUID()),
            deliveryStatus: .sent
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(notification)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PruufNotification.self, from: data)

        XCTAssertEqual(notification.id, decoded.id)
        XCTAssertEqual(notification.userId, decoded.userId)
        XCTAssertEqual(notification.type, decoded.type)
        XCTAssertEqual(notification.title, decoded.title)
        XCTAssertEqual(notification.body, decoded.body)
        XCTAssertEqual(notification.deliveryStatus, decoded.deliveryStatus)
        XCTAssertEqual(notification.metadata?.pingId, decoded.metadata?.pingId)
    }
}

// MARK: - InAppNotificationStore Tests

@MainActor
final class InAppNotificationStoreTests: XCTestCase {

    func testStoreInitialState() {
        let store = InAppNotificationStore.shared

        // Clear any existing state
        store.clearCache()

        XCTAssertTrue(store.notifications.isEmpty)
        XCTAssertEqual(store.unreadCount, 0)
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.errorMessage)
    }

    func testClearCache() {
        let store = InAppNotificationStore.shared

        // Ensure cache is cleared
        store.clearCache()

        XCTAssertTrue(store.notifications.isEmpty)
        XCTAssertEqual(store.unreadCount, 0)
        XCTAssertNil(store.errorMessage)
    }

    func testNavigationDestinationForPingReminder() {
        let store = InAppNotificationStore.shared
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Ping Reminder",
            body: "Time to ping",
            sentAt: Date(),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )

        let destination = store.getNavigationDestination(for: notification)
        XCTAssertEqual(destination, .senderDashboard)
    }

    func testNavigationDestinationForDeadlineWarning() {
        let store = InAppNotificationStore.shared
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .deadlineWarning,
            title: "Deadline Warning",
            body: "15 minutes left",
            sentAt: Date(),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )

        let destination = store.getNavigationDestination(for: notification)
        XCTAssertEqual(destination, .senderDashboard)
    }

    func testNavigationDestinationForDeadlineFinal() {
        let store = InAppNotificationStore.shared
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .deadlineFinal,
            title: "Final Deadline",
            body: "Deadline reached",
            sentAt: Date(),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )

        let destination = store.getNavigationDestination(for: notification)
        XCTAssertEqual(destination, .senderDashboard)
    }

    func testNavigationDestinationForMissedPingWithSenderId() {
        let store = InAppNotificationStore.shared
        let senderId = UUID()
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .missedPing,
            title: "Missed Ping",
            body: "A sender missed their ping",
            sentAt: Date(),
            readAt: nil,
            metadata: NotificationMetadata(pingId: nil, connectionId: nil, senderId: senderId, receiverId: nil, trialDaysRemaining: nil, customData: nil),
            deliveryStatus: .sent
        )

        let destination = store.getNavigationDestination(for: notification)
        XCTAssertEqual(destination, .senderActivity(senderId: senderId))
    }

    func testNavigationDestinationForMissedPingWithoutSenderId() {
        let store = InAppNotificationStore.shared
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .missedPing,
            title: "Missed Ping",
            body: "A sender missed their ping",
            sentAt: Date(),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )

        let destination = store.getNavigationDestination(for: notification)
        XCTAssertEqual(destination, .receiverDashboard)
    }

    func testNavigationDestinationForPingCompletedOnTimeWithConnectionId() {
        let store = InAppNotificationStore.shared
        let connectionId = UUID()
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingCompletedOnTime,
            title: "Ping Completed",
            body: "Ping was completed on time",
            sentAt: Date(),
            readAt: nil,
            metadata: NotificationMetadata(pingId: nil, connectionId: connectionId, senderId: nil, receiverId: nil, trialDaysRemaining: nil, customData: nil),
            deliveryStatus: .sent
        )

        let destination = store.getNavigationDestination(for: notification)
        XCTAssertEqual(destination, .pingHistory(connectionId: connectionId))
    }

    func testNavigationDestinationForPingCompletedLateWithConnectionId() {
        let store = InAppNotificationStore.shared
        let connectionId = UUID()
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingCompletedLate,
            title: "Late Ping",
            body: "Ping was completed late",
            sentAt: Date(),
            readAt: nil,
            metadata: NotificationMetadata(pingId: nil, connectionId: connectionId, senderId: nil, receiverId: nil, trialDaysRemaining: nil, customData: nil),
            deliveryStatus: .sent
        )

        let destination = store.getNavigationDestination(for: notification)
        XCTAssertEqual(destination, .pingHistory(connectionId: connectionId))
    }

    func testNavigationDestinationForPingCompletedWithoutConnectionId() {
        let store = InAppNotificationStore.shared
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingCompletedOnTime,
            title: "Ping Completed",
            body: "Ping was completed",
            sentAt: Date(),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )

        let destination = store.getNavigationDestination(for: notification)
        XCTAssertEqual(destination, .receiverDashboard)
    }

    func testNavigationDestinationForBreakStartedWithSenderId() {
        let store = InAppNotificationStore.shared
        let senderId = UUID()
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .breakStarted,
            title: "Break Started",
            body: "A sender started a break",
            sentAt: Date(),
            readAt: nil,
            metadata: NotificationMetadata(pingId: nil, connectionId: nil, senderId: senderId, receiverId: nil, trialDaysRemaining: nil, customData: nil),
            deliveryStatus: .sent
        )

        let destination = store.getNavigationDestination(for: notification)
        XCTAssertEqual(destination, .senderActivity(senderId: senderId))
    }

    func testNavigationDestinationForBreakStartedWithoutSenderId() {
        let store = InAppNotificationStore.shared
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .breakStarted,
            title: "Break Started",
            body: "A sender started a break",
            sentAt: Date(),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )

        let destination = store.getNavigationDestination(for: notification)
        XCTAssertEqual(destination, .receiverDashboard)
    }

    func testNavigationDestinationForConnectionRequest() {
        let store = InAppNotificationStore.shared
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .connectionRequest,
            title: "Connection Request",
            body: "Someone wants to connect",
            sentAt: Date(),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )

        let destination = store.getNavigationDestination(for: notification)
        XCTAssertEqual(destination, .pendingConnections)
    }

    func testNavigationDestinationForPaymentReminder() {
        let store = InAppNotificationStore.shared
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .paymentReminder,
            title: "Payment Reminder",
            body: "Payment is due",
            sentAt: Date(),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )

        let destination = store.getNavigationDestination(for: notification)
        XCTAssertEqual(destination, .subscription)
    }

    func testNavigationDestinationForTrialEnding() {
        let store = InAppNotificationStore.shared
        let notification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .trialEnding,
            title: "Trial Ending",
            body: "Your trial is ending soon",
            sentAt: Date(),
            readAt: nil,
            metadata: NotificationMetadata(pingId: nil, connectionId: nil, senderId: nil, receiverId: nil, trialDaysRemaining: 3, customData: nil),
            deliveryStatus: .sent
        )

        let destination = store.getNavigationDestination(for: notification)
        XCTAssertEqual(destination, .subscription)
    }
}
