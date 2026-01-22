import Foundation

/// Represents a notification sent to a user
/// Maps to the `notifications` table in Supabase
struct PruufNotification: Codable, Identifiable, Equatable {
    /// Unique notification identifier
    let id: UUID

    /// User who received this notification
    let userId: UUID

    /// Type of notification
    let type: NotificationType

    /// Notification title
    let title: String

    /// Notification body text
    let body: String

    /// When the notification was sent
    let sentAt: Date

    /// When the notification was read (nil if unread)
    var readAt: Date?

    /// Additional metadata (ping_id, connection_id, etc.)
    var metadata: NotificationMetadata?

    /// Delivery status of the notification
    var deliveryStatus: DeliveryStatus

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type
        case title
        case body
        case sentAt = "sent_at"
        case readAt = "read_at"
        case metadata
        case deliveryStatus = "delivery_status"
    }

    // MARK: - Computed Properties

    /// Whether the notification has been read
    var isRead: Bool {
        readAt != nil
    }

    /// Whether the notification was successfully delivered
    var wasDelivered: Bool {
        deliveryStatus == .sent
    }

    /// Time since notification was sent
    var timeSince: String {
        let interval = Date().timeIntervalSince(sentAt)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
}

// MARK: - Notification Type

/// Types of notifications that can be sent
/// Maps to CHECK constraint: type IN ('ping_reminder', 'deadline_warning', 'missed_ping', 'connection_request', 'payment_reminder', 'trial_ending', 'break_notification', 'data_export_ready', 'data_export_email_sent')
enum NotificationType: String, Codable, CaseIterable {
    /// Reminder to complete daily ping (at scheduled time)
    case pingReminder = "ping_reminder"

    /// Warning that ping deadline is approaching (15 min before)
    case deadlineWarning = "deadline_warning"

    /// Final reminder at the deadline itself
    case deadlineFinal = "deadline_final"

    /// Alert that a ping was missed (5 min after deadline)
    case missedPing = "missed_ping"

    /// Notification to receivers when ping completed on time
    case pingCompletedOnTime = "ping_completed_ontime"

    /// Notification to receivers when ping completed late
    case pingCompletedLate = "ping_completed_late"

    /// Notification to receivers when sender starts a break
    case breakStarted = "break_started"

    /// Break notification (scheduled, started, ended)
    case breakNotification = "break_notification"

    /// New connection request received
    case connectionRequest = "connection_request"

    /// Payment-related reminder
    case paymentReminder = "payment_reminder"

    /// Trial period ending soon
    case trialEnding = "trial_ending"

    /// GDPR data export is ready for download (Phase 10 Section 10.3)
    case dataExportReady = "data_export_ready"

    /// GDPR data export link sent via email (Phase 10 Section 10.3)
    case dataExportEmailSent = "data_export_email_sent"

    /// Notification to receivers when sender changes their ping time (Phase 10 Section 10.4 US-10.1)
    case pingTimeChanged = "ping_time_changed"

    /// Display name for the type
    var displayName: String {
        switch self {
        case .pingReminder:
            return "Ping Reminder"
        case .deadlineWarning:
            return "Deadline Warning"
        case .deadlineFinal:
            return "Final Deadline"
        case .missedPing:
            return "Missed Ping"
        case .pingCompletedOnTime:
            return "Ping Completed"
        case .pingCompletedLate:
            return "Late Ping"
        case .breakStarted:
            return "Break Started"
        case .breakNotification:
            return "Break Notification"
        case .connectionRequest:
            return "Connection Request"
        case .paymentReminder:
            return "Payment Reminder"
        case .trialEnding:
            return "Trial Ending"
        case .dataExportReady:
            return "Data Export Ready"
        case .dataExportEmailSent:
            return "Data Export Sent"
        case .pingTimeChanged:
            return "Ping Time Changed"
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .pingReminder:
            return "bell.fill"
        case .deadlineWarning:
            return "exclamationmark.circle.fill"
        case .deadlineFinal:
            return "clock.badge.exclamationmark.fill"
        case .missedPing:
            return "exclamationmark.triangle.fill"
        case .pingCompletedOnTime:
            return "checkmark.circle.fill"
        case .pingCompletedLate:
            return "clock.arrow.circlepath"
        case .breakStarted:
            return "moon.fill"
        case .breakNotification:
            return "calendar.badge.clock"
        case .connectionRequest:
            return "person.badge.plus"
        case .paymentReminder:
            return "creditcard.fill"
        case .trialEnding:
            return "clock.fill"
        case .dataExportReady:
            return "square.and.arrow.down.fill"
        case .dataExportEmailSent:
            return "envelope.fill"
        case .pingTimeChanged:
            return "clock.arrow.2.circlepath"
        }
    }

    /// Priority level (higher = more important)
    var priority: Int {
        switch self {
        case .missedPing:
            return 5
        case .deadlineFinal:
            return 5
        case .deadlineWarning:
            return 4
        case .pingReminder:
            return 3
        case .pingCompletedOnTime:
            return 3
        case .pingCompletedLate:
            return 3
        case .breakStarted:
            return 2
        case .breakNotification:
            return 2
        case .connectionRequest:
            return 2
        case .trialEnding:
            return 2
        case .dataExportReady:
            return 2
        case .dataExportEmailSent:
            return 1
        case .paymentReminder:
            return 1
        case .pingTimeChanged:
            return 2
        }
    }

    /// Whether this notification type is for senders (vs receivers)
    var isForSender: Bool {
        switch self {
        case .pingReminder, .deadlineWarning, .deadlineFinal:
            return true
        case .missedPing, .pingCompletedOnTime, .pingCompletedLate, .breakStarted, .breakNotification, .pingTimeChanged:
            return false // These go to receivers
        case .connectionRequest, .paymentReminder, .trialEnding:
            return true // These go to the user who needs to take action
        case .dataExportReady, .dataExportEmailSent:
            return true // Data export notifications go to the requesting user
        }
    }
}

// MARK: - Delivery Status

/// Delivery status of a notification
/// Maps to CHECK constraint: delivery_status IN ('sent', 'failed', 'pending')
enum DeliveryStatus: String, Codable {
    /// Successfully sent
    case sent = "sent"

    /// Failed to deliver
    case failed = "failed"

    /// Pending delivery
    case pending = "pending"

    var displayName: String {
        switch self {
        case .sent:
            return "Sent"
        case .failed:
            return "Failed"
        case .pending:
            return "Pending"
        }
    }
}

// MARK: - Notification Metadata

/// Additional context for notifications
struct NotificationMetadata: Codable, Equatable {
    /// Related ping ID
    var pingId: UUID?

    /// Related connection ID
    var connectionId: UUID?

    /// Related sender ID
    var senderId: UUID?

    /// Related receiver ID
    var receiverId: UUID?

    /// Days remaining in trial
    var trialDaysRemaining: Int?

    /// Additional custom data
    var customData: [String: String]?

    enum CodingKeys: String, CodingKey {
        case pingId = "ping_id"
        case connectionId = "connection_id"
        case senderId = "sender_id"
        case receiverId = "receiver_id"
        case trialDaysRemaining = "trial_days_remaining"
        case customData = "custom_data"
    }
}
