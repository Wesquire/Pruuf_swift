import Foundation
import Supabase
import CoreLocation

/// Service for managing pings (check-ins)
/// Handles ping generation, confirmation, and history
/// Phase 6 Section 6.2: Ping Completion Methods
@MainActor
final class PingService: ObservableObject {

    // MARK: - Singleton

    static let shared = PingService()

    // MARK: - Published Properties

    @Published private(set) var activePings: [Ping] = []
    @Published private(set) var pingHistory: [PingHistoryItem] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var currentStreak: Int = 0
    @Published private(set) var todaysPingStatus: TodaysPingStatus?

    // MARK: - Private Properties

    private let database: PostgrestClient
    private let functionsClient: FunctionsClient

    // MARK: - Initialization

    init(database: PostgrestClient? = nil,
         functionsClient: FunctionsClient? = nil) {
        self.database = database ?? SupabaseConfig.client.schema("public")
        self.functionsClient = functionsClient ?? SupabaseConfig.client.functions
    }

    // MARK: - Fetch Active Pings

    /// Fetch all active (pending) pings for the current user
    func fetchActivePings(userId: UUID) async throws {
        isLoading = true
        defer { isLoading = false }

        let pings: [Ping] = try await database
            .from("pings")
            .select()
            .eq("sender_id", value: userId.uuidString)
            .eq("status", value: PingStatus.pending.rawValue)
            .gte("deadline_time", value: ISO8601DateFormatter().string(from: Date()))
            .order("deadline_time", ascending: true)
            .execute()
            .value

        self.activePings = pings
    }

    // MARK: - Complete All Pending Pings (Tap to Ping)

    /// Complete all pending pings for today with a single tap
    /// Method 1: Tap to Ping - Simple button press completion
    /// - Parameter userId: The sender's user ID
    /// - Returns: Completion result with counts
    @discardableResult
    func completeAllPendingPings(userId: UUID) async throws -> PingCompletionResult {
        isLoading = true
        defer { isLoading = false }

        // Create typed request body for edge function
        let requestBody = CompletePingRequest(
            senderId: userId.uuidString,
            method: "tap",
            location: nil
        )

        // Use the generic invoke that returns the decoded type directly
        let result: PingCompletionResponse = try await functionsClient.invoke(
            "complete-ping",
            options: FunctionInvokeOptions(body: requestBody)
        )

        if !result.success {
            throw PingServiceError.confirmationFailed(result.error ?? "Unknown error")
        }

        // Clear active pings from local state
        activePings.removeAll()

        // Update streak
        await refreshStreak(userId: userId)

        return PingCompletionResult(
            completedCount: result.completedCount,
            onTimeCount: result.onTimeCount,
            lateCount: result.lateCount,
            method: .tap,
            completedAt: result.completedAt ?? Date()
        )
    }

    // MARK: - Complete Ping with In-Person Verification

    /// Complete ping with in-person GPS verification
    /// Method 2: In-Person Verification - Includes location data
    /// - Parameters:
    ///   - userId: The sender's user ID
    ///   - location: The GPS coordinates for verification
    /// - Returns: Completion result with counts
    @discardableResult
    func completePingInPerson(userId: UUID, location: CLLocation) async throws -> PingCompletionResult {
        isLoading = true
        defer { isLoading = false }

        let locationData = LocationData(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy
        )

        let requestBody = CompletePingRequest(
            senderId: userId.uuidString,
            method: "in_person",
            location: locationData
        )

        // Use the generic invoke that returns the decoded type directly
        let result: PingCompletionResponse = try await functionsClient.invoke(
            "complete-ping",
            options: FunctionInvokeOptions(body: requestBody)
        )

        if !result.success {
            throw PingServiceError.confirmationFailed(result.error ?? "Unknown error")
        }

        // Clear active pings from local state
        activePings.removeAll()

        // Update streak
        await refreshStreak(userId: userId)

        return PingCompletionResult(
            completedCount: result.completedCount,
            onTimeCount: result.onTimeCount,
            lateCount: result.lateCount,
            method: .inPerson,
            completedAt: result.completedAt ?? Date(),
            hasLocationVerification: true
        )
    }

    // MARK: - Complete Single Ping

    /// Complete a specific ping (check-in)
    /// - Parameters:
    ///   - pingId: The ID of the ping to complete
    ///   - method: How the ping was completed (tap, in_person, etc.)
    /// - Returns: The updated ping
    @discardableResult
    func completePing(pingId: UUID, method: CompletionMethod = .tap) async throws -> Ping {
        isLoading = true
        defer { isLoading = false }

        let now = Date()

        let updatedPing: Ping = try await database
            .from("pings")
            .update([
                "completed_at": ISO8601DateFormatter().string(from: now),
                "completion_method": method.rawValue,
                "status": PingStatus.completed.rawValue
            ])
            .eq("id", value: pingId.uuidString)
            .select()
            .single()
            .execute()
            .value

        // Update local state
        if let index = activePings.firstIndex(where: { $0.id == pingId }) {
            activePings.remove(at: index)
        }

        return updatedPing
    }

    // MARK: - Late Ping Submission

    /// Submit a late ping after the deadline has passed
    /// Method 3: Late Ping - Still counts toward streak
    /// - Parameter userId: The sender's user ID
    /// - Returns: Completion result marked as late
    @discardableResult
    func submitLatePing(userId: UUID) async throws -> PingCompletionResult {
        // Late pings use the same mechanism as regular pings
        // The edge function determines if it's late based on deadline
        return try await completeAllPendingPings(userId: userId)
    }

    // MARK: - Check Today's Ping Status

    /// Get the current status of today's pings
    /// - Parameter userId: The sender's user ID
    /// - Returns: Today's ping status including pending count and deadline info
    func checkTodaysPingStatus(userId: UUID) async throws -> TodaysPingStatus {
        isLoading = true
        defer { isLoading = false }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!

        let formatter = ISO8601DateFormatter()

        // Fetch today's pings for this user
        let pings: [Ping] = try await database
            .from("pings")
            .select()
            .eq("sender_id", value: userId.uuidString)
            .gte("scheduled_time", value: formatter.string(from: todayStart))
            .lt("scheduled_time", value: formatter.string(from: todayEnd))
            .execute()
            .value

        let pendingPings = pings.filter { $0.status == .pending }
        let completedPings = pings.filter { $0.status == .completed }
        let missedPings = pings.filter { $0.status == .missed }
        let onBreakPings = pings.filter { $0.status == .onBreak }

        // Find earliest deadline among pending pings
        let earliestDeadline = pendingPings.map { $0.deadlineTime }.min()

        // Check if any pending pings are late
        let isLate = pendingPings.contains { $0.deadlineTime < Date() }

        let status = TodaysPingStatus(
            hasPendingPings: !pendingPings.isEmpty,
            isLate: isLate,
            pendingCount: pendingPings.count,
            completedCount: completedPings.count,
            missedCount: missedPings.count,
            onBreakCount: onBreakPings.count,
            totalCount: pings.count,
            earliestDeadline: earliestDeadline
        )

        self.todaysPingStatus = status
        return status
    }

    // MARK: - Refresh Streak

    /// Refresh the current streak count
    /// - Parameter userId: The user's ID
    func refreshStreak(userId: UUID) async {
        do {
            currentStreak = try await calculateStreak(userId: userId)
        } catch {
            print("Failed to refresh streak: \(error)")
        }
    }

    // MARK: - Fetch Ping History

    /// Fetch ping history for a user
    /// - Parameters:
    ///   - userId: The user's ID
    ///   - limit: Maximum number of items to fetch
    ///   - offset: Number of items to skip (for pagination)
    func fetchPingHistory(userId: UUID, limit: Int = 30, offset: Int = 0) async throws {
        isLoading = true
        defer { isLoading = false }

        let history: [PingHistoryItem] = try await database
            .from("pings")
            .select("id, scheduled_time, status, completed_at")
            .eq("sender_id", value: userId.uuidString)
            .order("scheduled_time", ascending: false)
            .range(from: offset, to: offset + limit - 1)
            .execute()
            .value

        if offset == 0 {
            self.pingHistory = history
        } else {
            self.pingHistory.append(contentsOf: history)
        }
    }

    // MARK: - Fetch Pings for Connection

    /// Fetch pings associated with a specific connection
    /// - Parameters:
    ///   - connectionId: The connection's ID
    ///   - limit: Maximum number of items to fetch
    func fetchPingsForConnection(connectionId: UUID, limit: Int = 30) async throws -> [Ping] {
        let pings: [Ping] = try await database
            .from("pings")
            .select()
            .eq("connection_id", value: connectionId.uuidString)
            .order("scheduled_time", ascending: false)
            .limit(limit)
            .execute()
            .value

        return pings
    }

    // MARK: - Get Ping Statistics

    /// Get ping statistics for a user
    /// - Parameter userId: The user's ID
    /// - Returns: Tuple of (total pings, completed count, missed count)
    func getPingStatistics(userId: UUID) async throws -> (total: Int, completed: Int, missed: Int) {
        // Get completed count
        let completedPings: [Ping] = try await database
            .from("pings")
            .select()
            .eq("sender_id", value: userId.uuidString)
            .eq("status", value: PingStatus.completed.rawValue)
            .execute()
            .value

        // Get missed count
        let missedPings: [Ping] = try await database
            .from("pings")
            .select()
            .eq("sender_id", value: userId.uuidString)
            .eq("status", value: PingStatus.missed.rawValue)
            .execute()
            .value

        let total = completedPings.count + missedPings.count
        return (total: total, completed: completedPings.count, missed: missedPings.count)
    }

    // MARK: - Calculate Streak

    /// Calculate the current consecutive ping completion streak
    /// Phase 6 Section 6.4: Ping Streak Calculation Rules:
    ///   - Consecutive days of completed pings
    ///   - Breaks do NOT break the streak (counted as completed)
    ///   - Missed pings reset streak to 0
    ///   - Late pings count toward streak (they have status 'completed')
    /// - Parameter userId: The user's ID
    /// - Parameter receiverId: Optional specific receiver to calculate streak for
    /// - Returns: Number of consecutive days with completed or on_break pings
    func calculateStreak(userId: UUID, receiverId: UUID? = nil) async throws -> Int {
        // Fetch all pings ordered by date descending
        let recentPings: [Ping]

        if let receiverId = receiverId {
            // Query for specific receiver
            recentPings = try await database
                .from("pings")
                .select("scheduled_time, status")
                .eq("sender_id", value: userId.uuidString)
                .eq("receiver_id", value: receiverId.uuidString)
                .order("scheduled_time", ascending: false)
                .limit(730) // Max 2 years
                .execute()
                .value
        } else {
            // Query for all receivers
            recentPings = try await database
                .from("pings")
                .select("scheduled_time, status")
                .eq("sender_id", value: userId.uuidString)
                .order("scheduled_time", ascending: false)
                .limit(730) // Max 2 years
                .execute()
                .value
        }

        if recentPings.isEmpty {
            return 0
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Group pings by date and determine best status for each day
        var pingsByDate: [Date: PingStatus] = [:]

        for ping in recentPings {
            let pingDate = calendar.startOfDay(for: ping.scheduledTime)
            let existingStatus = pingsByDate[pingDate]

            // Priority: completed > on_break > pending > missed
            if existingStatus == nil {
                pingsByDate[pingDate] = ping.status
            } else if ping.status == .completed {
                pingsByDate[pingDate] = .completed
            } else if ping.status == .onBreak && existingStatus != .completed {
                pingsByDate[pingDate] = .onBreak
            }
            // pending and missed don't override better statuses
        }

        // Check today's status first
        if let todayStatus = pingsByDate[today] {
            if todayStatus == .missed {
                return 0 // Missed ping resets streak to 0
            }
        }

        var streak = 0
        var hasStartedCounting = false

        // If today is completed or on_break, count it
        if let todayStatus = pingsByDate[today] {
            if todayStatus == .completed || todayStatus == .onBreak {
                streak = 1
                hasStartedCounting = true
            }
        }

        // Go backwards from yesterday
        var currentDate = calendar.date(byAdding: .day, value: -1, to: today)!
        let twoYearsAgo = calendar.date(byAdding: .year, value: -2, to: today)!

        while currentDate >= twoYearsAgo {
            guard let status = pingsByDate[currentDate] else {
                // No ping for this date
                if hasStartedCounting {
                    // We were counting and hit a gap - streak ends
                    break
                }
                // Haven't started counting yet, keep going back
                currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
                continue
            }

            switch status {
            case .missed:
                // Missed ping breaks the streak
                return streak
            case .completed, .onBreak:
                // These count toward streak
                streak += 1
                hasStartedCounting = true
            case .pending:
                // Pending shouldn't exist for past days, but treat as break if it does
                if hasStartedCounting {
                    return streak
                }
            }

            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
        }

        return streak
    }

    // MARK: - Clear Active Pings

    /// Clear the local active pings cache
    func clearActivePings() {
        activePings = []
    }

    // MARK: - Clear History

    /// Clear the local ping history cache
    func clearHistory() {
        pingHistory = []
    }
}

// MARK: - Ping Service Errors

enum PingServiceError: LocalizedError {
    case pingNotFound
    case pingAlreadyConfirmed
    case pingExpired
    case confirmationFailed(String)
    case noPendingPings
    case locationRequired
    case locationPermissionDenied

    var errorDescription: String? {
        switch self {
        case .pingNotFound:
            return "Ping not found"
        case .pingAlreadyConfirmed:
            return "This ping has already been confirmed"
        case .pingExpired:
            return "This ping has expired and can no longer be confirmed"
        case .confirmationFailed(let message):
            return "Failed to confirm ping: \(message)"
        case .noPendingPings:
            return "No pending pings to complete"
        case .locationRequired:
            return "Location is required for in-person verification"
        case .locationPermissionDenied:
            return "Location permission is required for in-person verification"
        }
    }
}

// MARK: - Ping Completion Response (from Edge Function)

struct PingCompletionResponse: Codable {
    let success: Bool
    let completedCount: Int
    let onTimeCount: Int
    let lateCount: Int
    let method: String
    let completedAt: Date?
    let receiversNotified: Int?
    let hasLocationVerification: Bool?
    let pingIds: [UUID]?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case completedCount = "completed_count"
        case onTimeCount = "on_time_count"
        case lateCount = "late_count"
        case method
        case completedAt = "completed_at"
        case receiversNotified = "receivers_notified"
        case hasLocationVerification = "has_location_verification"
        case pingIds = "ping_ids"
        case error
    }
}

// MARK: - Ping Completion Result

struct PingCompletionResult {
    let completedCount: Int
    let onTimeCount: Int
    let lateCount: Int
    let method: CompletionMethod
    let completedAt: Date
    let hasLocationVerification: Bool

    init(completedCount: Int,
         onTimeCount: Int,
         lateCount: Int,
         method: CompletionMethod,
         completedAt: Date,
         hasLocationVerification: Bool = false) {
        self.completedCount = completedCount
        self.onTimeCount = onTimeCount
        self.lateCount = lateCount
        self.method = method
        self.completedAt = completedAt
        self.hasLocationVerification = hasLocationVerification
    }

    /// Whether any pings were completed late
    var hasLatePings: Bool {
        lateCount > 0
    }

    /// Whether all pings were on time
    var allOnTime: Bool {
        lateCount == 0 && completedCount > 0
    }

    /// User-friendly completion message
    var completionMessage: String {
        if completedCount == 0 {
            return "No pings to complete"
        }

        var message = "You're all checked in!"

        if hasLatePings {
            message = "Checked in late"
        }

        if hasLocationVerification {
            message += " (verified in person)"
        }

        return message
    }
}

// MARK: - Today's Ping Status

struct TodaysPingStatus {
    let hasPendingPings: Bool
    let isLate: Bool
    let pendingCount: Int
    let completedCount: Int
    let missedCount: Int
    let onBreakCount: Int
    let totalCount: Int
    let earliestDeadline: Date?

    /// Time remaining until the earliest deadline
    var timeRemaining: TimeInterval {
        guard let deadline = earliestDeadline else { return 0 }
        return max(0, deadline.timeIntervalSince(Date()))
    }

    /// Whether all pings for today are complete
    var allCompleted: Bool {
        pendingCount == 0 && completedCount > 0
    }

    /// Human-readable time remaining
    var timeRemainingString: String {
        let remaining = timeRemaining
        if remaining <= 0 {
            return "Deadline passed"
        }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        } else if minutes > 0 {
            return "\(minutes) minutes remaining"
        } else {
            return "Less than a minute"
        }
    }

    /// Status description for display
    var statusDescription: String {
        if allCompleted {
            return "All checked in!"
        } else if isLate {
            return "Ping overdue - tap now"
        } else if hasPendingPings {
            return "Waiting for check-in"
        } else if onBreakCount > 0 {
            return "On break"
        } else {
            return "No pings today"
        }
    }

    /// Button text based on status
    var actionButtonText: String {
        if allCompleted {
            return "Completed"
        } else if isLate {
            return "Ping Now"
        } else if hasPendingPings {
            return "I'm Okay"
        } else {
            return "No Action Needed"
        }
    }

    /// Whether the action button should be enabled
    var isActionEnabled: Bool {
        hasPendingPings && !allCompleted
    }
}

// MARK: - Complete Ping Request (for Edge Function)

struct CompletePingRequest: Codable {
    let senderId: String
    let method: String
    let location: LocationData?

    enum CodingKeys: String, CodingKey {
        case senderId = "sender_id"
        case method
        case location
    }
}

// MARK: - Location Data (for In-Person Verification)

struct LocationData: Codable {
    let lat: Double
    let lon: Double
    let accuracy: Double
}
