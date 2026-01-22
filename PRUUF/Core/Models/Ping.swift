import Foundation

/// Represents a daily ping/check-in that must be confirmed
/// Maps to the `pings` table in Supabase
struct Ping: Codable, Identifiable, Equatable {
    /// Unique ping identifier
    let id: UUID

    /// Connection this ping is associated with
    let connectionId: UUID

    /// User who needs to confirm this ping (sender)
    let senderId: UUID

    /// User who monitors this ping (receiver)
    let receiverId: UUID

    /// When the ping is scheduled for
    let scheduledTime: Date

    /// Deadline for confirming the ping (scheduled_time + grace period)
    let deadlineTime: Date

    /// When the ping was completed (nil if not yet completed)
    var completedAt: Date?

    /// How the ping was completed
    var completionMethod: CompletionMethod?

    /// Current status of the ping
    var status: PingStatus

    /// When the ping was created
    let createdAt: Date

    /// GPS location if in-person verification was used
    var verificationLocation: VerificationLocation?

    /// Optional notes about this ping
    var notes: String?

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case connectionId = "connection_id"
        case senderId = "sender_id"
        case receiverId = "receiver_id"
        case scheduledTime = "scheduled_time"
        case deadlineTime = "deadline_time"
        case completedAt = "completed_at"
        case completionMethod = "completion_method"
        case status
        case createdAt = "created_at"
        case verificationLocation = "verification_location"
        case notes
    }

    // MARK: - Computed Properties

    /// Whether the ping is still within the confirmation window
    var isWithinWindow: Bool {
        Date() < deadlineTime
    }

    /// Whether the ping has been completed
    var isCompleted: Bool {
        completedAt != nil
    }

    /// Whether the ping was missed (deadline passed without confirmation)
    var isMissed: Bool {
        status == .missed || (!isCompleted && !isWithinWindow)
    }

    /// Time remaining until deadline (returns 0 if past)
    var timeRemaining: TimeInterval {
        max(0, deadlineTime.timeIntervalSince(Date()))
    }

    /// Human-readable time remaining
    var timeRemainingString: String {
        let remaining = timeRemaining
        if remaining <= 0 {
            return "Expired"
        }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        } else {
            return "\(minutes)m remaining"
        }
    }

    /// Grace period duration
    var gracePeriod: TimeInterval {
        deadlineTime.timeIntervalSince(scheduledTime)
    }
}

// MARK: - Completion Method

/// How a ping was completed
/// Maps to CHECK constraint: completion_method IN ('tap', 'in_person', 'auto_break')
enum CompletionMethod: String, Codable {
    /// Simple tap/button press
    case tap = "tap"

    /// In-person verification with location
    case inPerson = "in_person"

    /// Automatically marked as on break
    case autoBreak = "auto_break"

    var displayName: String {
        switch self {
        case .tap:
            return "Tapped"
        case .inPerson:
            return "In Person"
        case .autoBreak:
            return "On Break"
        }
    }
}

// MARK: - Verification Location

/// GPS location data for in-person verification
struct VerificationLocation: Codable, Equatable {
    let lat: Double
    let lon: Double
    let accuracy: Double?
}

// MARK: - Ping Status

/// Status of a ping
/// Maps to CHECK constraint: status IN ('pending', 'completed', 'missed', 'on_break')
enum PingStatus: String, Codable {
    /// Ping is active and awaiting completion
    case pending = "pending"

    /// Ping was completed within the window
    case completed = "completed"

    /// Ping deadline passed without completion
    case missed = "missed"

    /// Ping was automatically marked due to an active break
    case onBreak = "on_break"

    /// Display name for the status
    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .completed:
            return "Completed"
        case .missed:
            return "Missed"
        case .onBreak:
            return "On Break"
        }
    }

    /// Icon name for the status
    var iconName: String {
        switch self {
        case .pending:
            return "clock.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .missed:
            return "exclamationmark.triangle.fill"
        case .onBreak:
            return "moon.fill"
        }
    }

    /// Whether this is a successful outcome
    var isSuccess: Bool {
        switch self {
        case .completed, .onBreak:
            return true
        case .pending, .missed:
            return false
        }
    }
}

// MARK: - Ping Schedule

/// Configuration for when pings should be generated
struct PingSchedule: Codable, Identifiable, Equatable {
    /// Unique schedule identifier
    let id: UUID

    /// User this schedule belongs to
    let userId: UUID

    /// Connection this schedule applies to (if specific to one connection)
    let connectionId: UUID?

    /// Time of day for the ping (in user's timezone)
    var pingTime: Date

    /// Duration in minutes of the confirmation window
    var windowMinutes: Int

    /// Days of the week when pings are active (1 = Sunday, 7 = Saturday)
    var activeDays: [Int]

    /// Whether this schedule is currently active
    var isActive: Bool

    /// When the schedule was created
    let createdAt: Date

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case connectionId = "connection_id"
        case pingTime = "ping_time"
        case windowMinutes = "window_minutes"
        case activeDays = "active_days"
        case isActive = "is_active"
        case createdAt = "created_at"
    }

    // MARK: - Computed Properties

    /// Whether a ping should be generated today
    var isActiveToday: Bool {
        guard isActive else { return false }
        let weekday = Calendar.current.component(.weekday, from: Date())
        return activeDays.contains(weekday)
    }
}

// MARK: - Ping History Item

/// Summary of ping history for display
struct PingHistoryItem: Codable, Identifiable {
    let id: UUID
    let scheduledTime: Date
    let status: PingStatus
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case scheduledTime = "scheduled_time"
        case status
        case completedAt = "completed_at"
    }

    /// Date of the ping (for display)
    var date: Date {
        scheduledTime
    }
}
