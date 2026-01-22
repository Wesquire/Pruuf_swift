import Foundation

/// Represents a temporary pause in ping requirements for a sender
/// Maps to the `breaks` table in Supabase
struct Break: Codable, Identifiable, Equatable {
    /// Unique break identifier
    let id: UUID

    /// Sender taking the break
    let senderId: UUID

    /// When the break starts (DATE type in DB)
    let startDate: Date

    /// When the break ends (DATE type in DB)
    let endDate: Date

    /// When the break was created
    let createdAt: Date

    /// Current status of the break
    var status: BreakStatus

    /// Optional notes about the break
    var notes: String?

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case createdAt = "created_at"
        case status
        case notes
    }

    // MARK: - Computed Properties

    /// Whether the break is currently in effect
    var isCurrentlyActive: Bool {
        guard status == .active || status == .scheduled else { return false }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        return today >= start && today <= end
    }

    /// Duration of the break in days
    var durationDays: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: startDate, to: endDate)
        return (components.day ?? 0) + 1 // Include both start and end days
    }

    /// Human-readable duration
    var durationString: String {
        let days = durationDays
        if days == 1 {
            return "1 day"
        } else {
            return "\(days) days"
        }
    }

    /// Time remaining on the break
    var timeRemaining: TimeInterval {
        let calendar = Calendar.current
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
        return max(0, endOfDay.timeIntervalSince(Date()))
    }

    /// Human-readable time remaining
    var timeRemainingString: String {
        let remaining = timeRemaining
        if remaining <= 0 {
            return "Ended"
        }

        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600

        if days > 0 {
            return "\(days) day\(days == 1 ? "" : "s") remaining"
        } else {
            return "\(hours) hour\(hours == 1 ? "" : "s") remaining"
        }
    }

    /// Whether this break is in the future
    var isFuture: Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: startDate)
        return start > today
    }

    /// Whether this break has ended
    var hasEnded: Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: endDate)
        return today > end
    }
}

// MARK: - Break Status

/// Status of a break
/// Maps to CHECK constraint: status IN ('scheduled', 'active', 'completed', 'canceled')
enum BreakStatus: String, Codable, CaseIterable {
    /// Break is scheduled for the future
    case scheduled = "scheduled"

    /// Break is currently active
    case active = "active"

    /// Break has completed (end date passed)
    case completed = "completed"

    /// Break was canceled by the user
    case canceled = "canceled"

    var displayName: String {
        switch self {
        case .scheduled:
            return "Scheduled"
        case .active:
            return "Active"
        case .completed:
            return "Completed"
        case .canceled:
            return "Canceled"
        }
    }

    var iconName: String {
        switch self {
        case .scheduled:
            return "calendar"
        case .active:
            return "moon.fill"
        case .completed:
            return "checkmark.circle"
        case .canceled:
            return "xmark.circle"
        }
    }
}

// MARK: - Break Reason

/// Reasons for taking a break from pings
enum BreakReason: String, Codable, CaseIterable {
    /// Traveling or vacation
    case travel = "travel"

    /// Medical procedure or recovery
    case medical = "medical"

    /// Work-related (e.g., intense deadline)
    case work = "work"

    /// Personal reasons
    case personal = "personal"

    /// Other reason
    case other = "other"

    /// Display name for the reason
    var displayName: String {
        switch self {
        case .travel:
            return "Travel/Vacation"
        case .medical:
            return "Medical"
        case .work:
            return "Work"
        case .personal:
            return "Personal"
        case .other:
            return "Other"
        }
    }

    /// Icon name for the reason
    var iconName: String {
        switch self {
        case .travel:
            return "airplane"
        case .medical:
            return "cross.case.fill"
        case .work:
            return "briefcase.fill"
        case .personal:
            return "person.fill"
        case .other:
            return "ellipsis.circle.fill"
        }
    }
}

// MARK: - Break Request

/// Request model for creating a new break
struct BreakRequest: Codable {
    let senderId: UUID
    let startDate: Date
    let endDate: Date
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case senderId = "sender_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case notes
    }
}

// MARK: - Break Update Request

/// Request model for updating an existing break
struct BreakUpdateRequest: Codable {
    var endDate: Date?
    var status: BreakStatus?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case endDate = "end_date"
        case status
        case notes
    }
}
