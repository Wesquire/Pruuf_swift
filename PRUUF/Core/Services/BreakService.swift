import Foundation
import Supabase

/// Service for managing breaks (planned pauses in ping requirements)
/// Handles break scheduling, status transitions, and notifications
@MainActor
final class BreakService: ObservableObject {

    // MARK: - Singleton

    static let shared = BreakService()

    // MARK: - Published Properties

    @Published private(set) var activeBreak: Break?
    @Published private(set) var scheduledBreaks: [Break] = []
    @Published private(set) var breakHistory: [Break] = []
    @Published private(set) var isLoading: Bool = false

    // MARK: - Private Properties

    private let database: PostgrestClient

    // MARK: - Initialization

    init(database: PostgrestClient? = nil) {
        self.database = database ?? SupabaseConfig.client.schema("public")
    }

    // MARK: - Schedule Break

    /// Schedule a new break for the sender
    /// - Parameters:
    ///   - senderId: The sender's user ID
    ///   - startDate: When the break starts
    ///   - endDate: When the break ends
    ///   - notes: Optional notes about the break
    /// - Returns: The created break record
    @discardableResult
    func scheduleBreak(
        senderId: UUID,
        startDate: Date,
        endDate: Date,
        notes: String?
    ) async throws -> Break {
        isLoading = true
        defer { isLoading = false }

        // Validate dates
        let validationResult = validateBreakDates(startDate: startDate, endDate: endDate)
        guard validationResult.isValid else {
            throw BreakServiceError.invalidDates(validationResult.message)
        }

        // EC-7.1: Check for overlapping breaks
        let hasOverlap = try await hasOverlappingBreak(
            senderId: senderId,
            startDate: startDate,
            endDate: endDate
        )
        if hasOverlap {
            throw BreakServiceError.overlappingBreak
        }

        // Determine initial status based on start date
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDay = calendar.startOfDay(for: startDate)
        // EC-7.2: Break starts today → Immediately set status='active'
        let initialStatus: BreakStatus = startDay <= today ? .active : .scheduled

        // Format dates for database (date only, no time)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: endDate)

        // Create the break record
        let breakData: [String: String?] = [
            "sender_id": senderId.uuidString,
            "start_date": startDateString,
            "end_date": endDateString,
            "status": initialStatus.rawValue,
            "notes": notes
        ]

        let createdBreaks: [Break] = try await database
            .from("breaks")
            .insert(breakData)
            .select()
            .execute()
            .value

        guard let createdBreak = createdBreaks.first else {
            throw BreakServiceError.creationFailed("No break returned from database")
        }

        // Update local state
        if initialStatus == .active {
            activeBreak = createdBreak
            // EC-7.2: Break starts today → today's ping becomes 'on_break'
            try await markTodaysPingsAsOnBreak(senderId: senderId)
        } else {
            scheduledBreaks.insert(createdBreak, at: 0)
        }

        // Note: Notifications are sent automatically via database trigger (on_break_created)

        return createdBreak
    }

    // MARK: - EC-7.2: Mark Today's Pings as On Break

    /// Mark all pending pings for today as 'on_break' when a break starts today
    /// - Parameter senderId: The sender's user ID
    private func markTodaysPingsAsOnBreak(senderId: UUID) async throws {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!

        let formatter = ISO8601DateFormatter()

        // Update all pending pings for today to 'on_break' status
        try await database
            .from("pings")
            .update([
                "status": PingStatus.onBreak.rawValue,
                "completion_method": CompletionMethod.autoBreak.rawValue
            ])
            .eq("sender_id", value: senderId.uuidString)
            .eq("status", value: PingStatus.pending.rawValue)
            .gte("scheduled_time", value: formatter.string(from: todayStart))
            .lt("scheduled_time", value: formatter.string(from: todayEnd))
            .execute()
    }

    // MARK: - Cancel Break

    /// Cancel a scheduled or active break
    /// - Parameters:
    ///   - breakId: The break's unique ID
    ///   - senderId: The sender's user ID (for notification purposes)
    func cancelBreak(breakId: UUID, senderId: UUID) async throws {
        isLoading = true
        defer { isLoading = false }

        // Update the break status to canceled
        try await database
            .from("breaks")
            .update(["status": BreakStatus.canceled.rawValue])
            .eq("id", value: breakId.uuidString)
            .execute()

        // Revert future pings from 'on_break' status to 'pending'
        // This ensures the sender will need to ping for upcoming days
        try await revertFuturePingsToPending(senderId: senderId)

        // Update local state
        if activeBreak?.id == breakId {
            activeBreak = nil
        }
        scheduledBreaks.removeAll { $0.id == breakId }

        // Note: Notifications are sent automatically via database trigger (on_break_status_changed)
    }

    /// Revert future pings with 'on_break' status back to 'pending'
    /// Called when a break is canceled to resume normal ping requirements
    ///
    /// EC-7.3: If break ends today, tomorrow's ping reverts to 'pending'
    /// Note: Normal break end transitions are handled by the generate_daily_pings function.
    /// When generate_daily_pings runs for a new day, it checks isSenderOnBreak() which
    /// uses date range comparison. If the break ended yesterday, today is outside the range,
    /// so the new ping is created with status='pending' automatically.
    /// This method is for immediate reversion when a break is canceled early.
    private func revertFuturePingsToPending(senderId: UUID) async throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = ISO8601DateFormatter()

        // Update all future pings that were set to 'on_break' back to 'pending'
        try await database
            .from("pings")
            .update(["status": PingStatus.pending.rawValue])
            .eq("sender_id", value: senderId.uuidString)
            .eq("status", value: PingStatus.onBreak.rawValue)
            .gte("scheduled_time", value: formatter.string(from: today))
            .execute()
    }

    // MARK: - End Break Early

    /// End an active break early (today becomes the end date)
    /// - Parameters:
    ///   - breakId: The break's unique ID
    ///   - senderId: The sender's user ID
    func endBreakEarly(breakId: UUID, senderId: UUID) async throws {
        isLoading = true
        defer { isLoading = false }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: Date())

        // Update break to end today and mark as canceled
        try await database
            .from("breaks")
            .update([
                "status": BreakStatus.canceled.rawValue,
                "end_date": todayString
            ])
            .eq("id", value: breakId.uuidString)
            .execute()

        // Revert future pings from 'on_break' status to 'pending'
        // This ensures the sender will need to ping starting today
        try await revertFuturePingsToPending(senderId: senderId)

        // Update local state
        activeBreak = nil

        // Note: Notifications are sent automatically via database trigger (on_break_status_changed)
    }

    // MARK: - Fetch Breaks

    /// Fetch the current active break for a sender
    func fetchActiveBreak(senderId: UUID) async throws {
        let today = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: today)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: startOfDay)

        let breaks: [Break] = try await database
            .from("breaks")
            .select()
            .eq("sender_id", value: senderId.uuidString)
            .lte("start_date", value: todayString)
            .gte("end_date", value: todayString)
            .in("status", values: [BreakStatus.scheduled.rawValue, BreakStatus.active.rawValue])
            .limit(1)
            .execute()
            .value

        activeBreak = breaks.first
    }

    /// Fetch all scheduled (future) breaks for a sender
    func fetchScheduledBreaks(senderId: UUID) async throws {
        let today = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: today)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: startOfDay)

        let breaks: [Break] = try await database
            .from("breaks")
            .select()
            .eq("sender_id", value: senderId.uuidString)
            .gt("start_date", value: todayString)
            .eq("status", value: BreakStatus.scheduled.rawValue)
            .order("start_date", ascending: true)
            .execute()
            .value

        scheduledBreaks = breaks
    }

    /// Fetch break history for a sender
    func fetchBreakHistory(senderId: UUID, limit: Int? = nil) async throws {
        var query = database
            .from("breaks")
            .select()
            .eq("sender_id", value: senderId.uuidString)
            .in("status", values: [BreakStatus.completed.rawValue, BreakStatus.canceled.rawValue])
            .order("start_date", ascending: false)

        if let limit = limit {
            query = query.limit(limit)
        }

        let breaks: [Break] = try await query
            .execute()
            .value

        breakHistory = breaks
    }

    /// Fetch all breaks (active, scheduled, and recent history) for a sender
    func fetchAllBreaks(senderId: UUID) async throws {
        isLoading = true
        defer { isLoading = false }

        async let activeTask: () = fetchActiveBreak(senderId: senderId)
        async let scheduledTask: () = fetchScheduledBreaks(senderId: senderId)
        async let historyTask: () = fetchBreakHistory(senderId: senderId)

        _ = try await (activeTask, scheduledTask, historyTask)
    }

    // MARK: - Validation

    /// Validate break dates
    /// - Parameters:
    ///   - startDate: The proposed start date
    ///   - endDate: The proposed end date
    /// - Returns: Validation result with message if invalid
    func validateBreakDates(startDate: Date, endDate: Date) -> BreakValidationResult {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)

        // Start date must be today or in the future
        if startDay < today {
            return BreakValidationResult(
                isValid: false,
                message: "Start date cannot be in the past",
                warning: nil
            )
        }

        // End date must be on or after start date
        if endDay < startDay {
            return BreakValidationResult(
                isValid: false,
                message: "End date must be on or after start date",
                warning: nil
            )
        }

        // Check for long duration warning (EC-7.5)
        let daysBetween = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        var warning: String? = nil
        if daysBetween > 365 {
            warning = "Breaks longer than 1 year may affect your account"
        }

        return BreakValidationResult(isValid: true, message: nil, warning: warning)
    }

    // MARK: - EC-7.1: Check for Overlapping Breaks

    /// Check if a proposed break overlaps with any existing active or scheduled breaks
    /// - Parameters:
    ///   - senderId: The sender's user ID
    ///   - startDate: The proposed start date
    ///   - endDate: The proposed end date
    ///   - excludeBreakId: Optional break ID to exclude (for editing existing breaks)
    /// - Returns: True if there is an overlap, false otherwise
    func hasOverlappingBreak(
        senderId: UUID,
        startDate: Date,
        endDate: Date,
        excludeBreakId: UUID? = nil
    ) async throws -> Bool {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: endDate)

        // Query for existing breaks that overlap with the proposed dates
        // Two date ranges [A, B] and [C, D] overlap if A <= D and C <= B
        var query = database
            .from("breaks")
            .select("id")
            .eq("sender_id", value: senderId.uuidString)
            .in("status", values: [BreakStatus.scheduled.rawValue, BreakStatus.active.rawValue])
            .lte("start_date", value: endDateString)
            .gte("end_date", value: startDateString)

        // Exclude specific break if provided (for editing)
        if let excludeId = excludeBreakId {
            query = query.neq("id", value: excludeId.uuidString)
        }

        let overlappingBreaks: [Break] = try await query
            .execute()
            .value

        return !overlappingBreaks.isEmpty
    }

    // MARK: - EC-7.5: Check Break Duration Warning

    /// Check if a break duration exceeds 1 year and return a warning
    /// - Parameters:
    ///   - startDate: The proposed start date
    ///   - endDate: The proposed end date
    /// - Returns: A warning message if break is longer than 1 year, nil otherwise
    func checkBreakDurationWarning(startDate: Date, endDate: Date) -> String? {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)

        // Check if break is longer than 365 days
        let daysBetween = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        if daysBetween > 365 {
            return "Breaks longer than 1 year may affect your account"
        }

        return nil
    }

    // MARK: - Notifications
    // Note: Break notifications are sent automatically via database triggers:
    // - on_break_created: Notifies receivers when a break is scheduled/started
    // - on_break_status_changed: Notifies receivers when break status changes
    // See migration 013_breaks_notifications.sql for implementation details
}

// MARK: - Supporting Types

/// Result of break date validation
struct BreakValidationResult {
    let isValid: Bool
    let message: String?
    /// EC-7.5: Warning message for long breaks (> 1 year)
    let warning: String?

    init(isValid: Bool, message: String?, warning: String? = nil) {
        self.isValid = isValid
        self.message = message
        self.warning = warning
    }
}

/// Errors that can occur in BreakService
enum BreakServiceError: LocalizedError {
    case invalidDates(String?)
    case creationFailed(String)
    case notFound
    case unauthorized
    case overlappingBreak
    case breakTooLong

    var errorDescription: String? {
        switch self {
        case .invalidDates(let message):
            return message ?? "Invalid dates"
        case .creationFailed(let message):
            return "Failed to create break: \(message)"
        case .notFound:
            return "Break not found"
        case .unauthorized:
            return "You are not authorized to modify this break"
        case .overlappingBreak:
            return "You already have a break during this period"
        case .breakTooLong:
            return "Breaks longer than 1 year may affect your account"
        }
    }
}
