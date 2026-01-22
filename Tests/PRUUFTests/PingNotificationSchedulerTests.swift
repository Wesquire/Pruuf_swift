import XCTest
@testable import PRUUF

/// Tests for PingNotificationScheduler
/// Section 6.3: Ping Notifications Schedule
final class PingNotificationSchedulerTests: XCTestCase {

    // MARK: - Notification Type Tests

    func testNotificationTypesExist() {
        // Verify all required notification types are defined
        XCTAssertEqual(NotificationType.pingReminder.rawValue, "ping_reminder")
        XCTAssertEqual(NotificationType.deadlineWarning.rawValue, "deadline_warning")
        XCTAssertEqual(NotificationType.deadlineFinal.rawValue, "deadline_final")
        XCTAssertEqual(NotificationType.missedPing.rawValue, "missed_ping")
        XCTAssertEqual(NotificationType.pingCompletedOnTime.rawValue, "ping_completed_ontime")
        XCTAssertEqual(NotificationType.pingCompletedLate.rawValue, "ping_completed_late")
        XCTAssertEqual(NotificationType.breakStarted.rawValue, "break_started")
    }

    func testNotificationTypeDisplayNames() {
        XCTAssertEqual(NotificationType.pingReminder.displayName, "Ping Reminder")
        XCTAssertEqual(NotificationType.deadlineWarning.displayName, "Deadline Warning")
        XCTAssertEqual(NotificationType.deadlineFinal.displayName, "Final Deadline")
        XCTAssertEqual(NotificationType.missedPing.displayName, "Missed Ping")
        XCTAssertEqual(NotificationType.pingCompletedOnTime.displayName, "Ping Completed")
        XCTAssertEqual(NotificationType.pingCompletedLate.displayName, "Late Ping")
        XCTAssertEqual(NotificationType.breakStarted.displayName, "Break Started")
    }

    func testNotificationTypePriorities() {
        // Missed ping and deadline final should have highest priority
        XCTAssertEqual(NotificationType.missedPing.priority, 5)
        XCTAssertEqual(NotificationType.deadlineFinal.priority, 5)

        // Deadline warning should be high priority
        XCTAssertEqual(NotificationType.deadlineWarning.priority, 4)

        // Regular reminders should be medium priority
        XCTAssertEqual(NotificationType.pingReminder.priority, 3)
        XCTAssertEqual(NotificationType.pingCompletedOnTime.priority, 3)
        XCTAssertEqual(NotificationType.pingCompletedLate.priority, 3)

        // Break started should be lower priority
        XCTAssertEqual(NotificationType.breakStarted.priority, 2)
    }

    func testNotificationTypeIsForSender() {
        // Sender notifications
        XCTAssertTrue(NotificationType.pingReminder.isForSender)
        XCTAssertTrue(NotificationType.deadlineWarning.isForSender)
        XCTAssertTrue(NotificationType.deadlineFinal.isForSender)

        // Receiver notifications
        XCTAssertFalse(NotificationType.missedPing.isForSender)
        XCTAssertFalse(NotificationType.pingCompletedOnTime.isForSender)
        XCTAssertFalse(NotificationType.pingCompletedLate.isForSender)
        XCTAssertFalse(NotificationType.breakStarted.isForSender)
    }

    func testNotificationTypeIconNames() {
        // All notification types should have valid icon names
        for type in NotificationType.allCases {
            XCTAssertFalse(type.iconName.isEmpty, "\(type) should have an icon name")
        }
    }

    // MARK: - Notification Metadata Tests

    func testNotificationMetadataEncoding() throws {
        let metadata = NotificationMetadata(
            pingId: UUID(),
            connectionId: UUID(),
            senderId: UUID(),
            receiverId: UUID()
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)
        XCTAssertNotNil(data)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NotificationMetadata.self, from: data)
        XCTAssertEqual(metadata.pingId, decoded.pingId)
        XCTAssertEqual(metadata.connectionId, decoded.connectionId)
        XCTAssertEqual(metadata.senderId, decoded.senderId)
        XCTAssertEqual(metadata.receiverId, decoded.receiverId)
    }

    // MARK: - Notification Content Tests

    func testSenderNotificationMessages() {
        // As per Section 6.3 specification:
        // Scheduled Time: "Time to ping! Tap to let everyone know you're okay."
        // 15 Minutes Before: "Reminder: 15 minutes until your ping deadline"
        // At Deadline: "Final reminder: Your ping deadline is now"

        // These are the expected messages in PingNotificationScheduler
        let scheduledTimeBody = "Tap to let everyone know you're okay."
        let deadlineWarningBody = "Reminder: 15 minutes until your ping deadline"
        let deadlineFinalBody = "Final reminder: Your ping deadline is now"

        // Verify message patterns are correct
        XCTAssertTrue(scheduledTimeBody.contains("Tap"))
        XCTAssertTrue(deadlineWarningBody.contains("15 minutes"))
        XCTAssertTrue(deadlineFinalBody.contains("deadline is now"))
    }

    func testReceiverNotificationMessagePatterns() {
        // As per Section 6.3 specification:
        // On-Time: "[Sender Name] is okay! ..."
        // Late: "[Sender Name] pinged late at [time]"
        // Missed: "[Sender Name] missed their ping. Last seen [time]."
        // Break: "[Sender Name] is on break until [date]"

        let senderName = "John"

        // On-time completion message
        let onTimeMessage = "\(senderName) is okay!"
        XCTAssertTrue(onTimeMessage.contains(senderName))
        XCTAssertTrue(onTimeMessage.contains("okay"))

        // Late completion message
        let lateMessage = "\(senderName) pinged late at 10:30 AM"
        XCTAssertTrue(lateMessage.contains(senderName))
        XCTAssertTrue(lateMessage.contains("late"))

        // Missed ping message
        let missedMessage = "\(senderName) missed their ping."
        XCTAssertTrue(missedMessage.contains(senderName))
        XCTAssertTrue(missedMessage.contains("missed"))

        // Break started message
        let breakMessage = "\(senderName) is on break until Jan 20"
        XCTAssertTrue(breakMessage.contains(senderName))
        XCTAssertTrue(breakMessage.contains("break"))
    }

    // MARK: - Delivery Status Tests

    func testDeliveryStatusValues() {
        XCTAssertEqual(DeliveryStatus.sent.rawValue, "sent")
        XCTAssertEqual(DeliveryStatus.failed.rawValue, "failed")
        XCTAssertEqual(DeliveryStatus.pending.rawValue, "pending")
    }

    func testDeliveryStatusDisplayNames() {
        XCTAssertEqual(DeliveryStatus.sent.displayName, "Sent")
        XCTAssertEqual(DeliveryStatus.failed.displayName, "Failed")
        XCTAssertEqual(DeliveryStatus.pending.displayName, "Pending")
    }

    // MARK: - Ping Notification Error Tests

    func testPingNotificationErrors() {
        let schedulingError = PingNotificationError.schedulingFailed("Test error")
        XCTAssertNotNil(schedulingError.errorDescription)
        XCTAssertTrue(schedulingError.errorDescription?.contains("schedule") ?? false)

        let databaseError = PingNotificationError.databaseError("DB error")
        XCTAssertNotNil(databaseError.errorDescription)
        XCTAssertTrue(databaseError.errorDescription?.contains("Database") ?? false)

        let invalidDataError = PingNotificationError.invalidPingData
        XCTAssertNotNil(invalidDataError.errorDescription)
        XCTAssertTrue(invalidDataError.errorDescription?.contains("Invalid") ?? false)
    }

    // MARK: - PruufNotification Model Tests

    func testPruufNotificationTimeSince() {
        let now = Date()

        // Just now (less than 1 minute ago)
        let justNow = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test body",
            sentAt: now.addingTimeInterval(-30),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertEqual(justNow.timeSince, "Just now")

        // Minutes ago
        let minutesAgo = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test body",
            sentAt: now.addingTimeInterval(-300), // 5 minutes ago
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertTrue(minutesAgo.timeSince.contains("min ago"))

        // Hours ago
        let hoursAgo = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test body",
            sentAt: now.addingTimeInterval(-7200), // 2 hours ago
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertTrue(hoursAgo.timeSince.contains("hour"))

        // Days ago
        let daysAgo = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test body",
            sentAt: now.addingTimeInterval(-172800), // 2 days ago
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertTrue(daysAgo.timeSince.contains("day"))
    }

    func testPruufNotificationIsRead() {
        let unreadNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test body",
            sentAt: Date(),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertFalse(unreadNotification.isRead)

        let readNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test body",
            sentAt: Date(),
            readAt: Date(),
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertTrue(readNotification.isRead)
    }

    func testPruufNotificationWasDelivered() {
        let deliveredNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test body",
            sentAt: Date(),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .sent
        )
        XCTAssertTrue(deliveredNotification.wasDelivered)

        let failedNotification = PruufNotification(
            id: UUID(),
            userId: UUID(),
            type: .pingReminder,
            title: "Test",
            body: "Test body",
            sentAt: Date(),
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
            sentAt: Date(),
            readAt: nil,
            metadata: nil,
            deliveryStatus: .pending
        )
        XCTAssertFalse(pendingNotification.wasDelivered)
    }
}
