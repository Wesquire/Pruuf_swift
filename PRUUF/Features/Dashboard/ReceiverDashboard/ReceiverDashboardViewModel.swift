import Foundation
import SwiftUI
import Supabase

/// ViewModel for the Receiver Dashboard
/// Manages state for senders, unique code, subscription status, and activity history
@MainActor
final class ReceiverDashboardViewModel: ObservableObject {

    // MARK: - Published Properties

    /// List of senders (connections where user is receiver)
    @Published private(set) var senders: [SenderWithPingStatus] = []

    /// Receiver's unique 6-digit code
    @Published private(set) var uniqueCode: String = ""

    /// Receiver's subscription profile
    @Published private(set) var receiverProfile: ReceiverProfile?

    /// Recent activity items (last 7 days)
    @Published private(set) var recentActivity: [ActivityItem] = []

    /// Whether data is loading
    @Published private(set) var isLoading: Bool = false

    /// Whether this is the initial load (for showing full screen loading)
    @Published private(set) var isInitialLoad: Bool = true

    /// Whether there is a network error
    @Published private(set) var hasNetworkError: Bool = false

    /// Error message to display
    @Published var errorMessage: String?

    /// Whether to show the quick actions sheet
    @Published var showQuickActions: Bool = false

    /// Filter for recent activity by sender
    @Published var selectedSenderFilter: UUID? = nil

    /// Current time display
    @Published private(set) var currentTimeString: String = ""

    // MARK: - Private Properties

    private let connectionService: ConnectionService
    private let authService: AuthService
    private let database: PostgrestClient
    private var timeUpdateTimer: Timer?

    // MARK: - Computed Properties

    /// Current user's ID
    var userId: UUID? {
        authService.currentPruufUser?.id
    }

    /// User's display name
    var userName: String {
        authService.currentPruufUser?.displayName ?? "Me"
    }

    /// Number of active senders
    var activeSendersCount: Int {
        senders.filter { $0.connection.status == .active }.count
    }

    /// Whether user has any senders
    var hasSenders: Bool {
        !senders.isEmpty
    }

    /// Subscription status badge text
    var subscriptionBadgeText: String {
        guard let profile = receiverProfile else { return "" }

        switch profile.subscriptionStatus {
        case .trial:
            if let days = profile.trialDaysRemaining {
                return "Trial: \(days) day\(days == 1 ? "" : "s") left"
            }
            return "Trial"
        case .active:
            return "Active"
        case .pastDue:
            return "Past Due"
        case .canceled:
            return "Canceled"
        case .expired:
            return "Expired"
        }
    }

    /// Subscription badge color
    var subscriptionBadgeColor: Color {
        guard let profile = receiverProfile else { return .gray }

        switch profile.subscriptionStatus {
        case .trial:
            return .blue
        case .active:
            return .green
        case .pastDue, .expired:
            return .red
        case .canceled:
            return .orange
        }
    }

    /// Days remaining in trial (for subscription card)
    var trialDaysRemaining: Int? {
        receiverProfile?.trialDaysRemaining
    }

    /// Next billing date (for active subscriptions)
    var nextBillingDate: Date? {
        guard receiverProfile?.subscriptionStatus == .active else { return nil }
        return receiverProfile?.subscriptionEndDate
    }

    /// Filtered activity based on selected sender
    var filteredActivity: [ActivityItem] {
        if let senderId = selectedSenderFilter {
            return recentActivity.filter { $0.senderId == senderId }
        }
        return recentActivity
    }

    // MARK: - Initialization

    init(
        connectionService: ConnectionService? = nil,
        authService: AuthService,
        database: PostgrestClient? = nil
    ) {
        self.connectionService = connectionService ?? ConnectionService.shared
        self.authService = authService
        self.database = database ?? SupabaseConfig.client.schema("public")

        setupTimers()
    }

    deinit {
        timeUpdateTimer?.invalidate()
    }

    // MARK: - Timer Setup

    private func setupTimers() {
        updateCurrentTime()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCurrentTime()
            }
        }
    }

    private func updateCurrentTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        currentTimeString = formatter.string(from: Date())
    }

    // MARK: - Data Loading

    /// Load all dashboard data
    func loadDashboardData() async {
        guard let userId = userId else { return }

        isLoading = true
        hasNetworkError = false

        do {
            // Load data in parallel
            async let sendersTask: () = loadSenders(userId: userId)
            async let codeTask: () = loadUniqueCode(userId: userId)
            async let profileTask: () = loadReceiverProfile(userId: userId)
            async let activityTask: () = loadRecentActivity(userId: userId)

            _ = try await (sendersTask, codeTask, profileTask, activityTask)

            // Mark initial load complete
            isInitialLoad = false

        } catch {
            // Check for network-related errors
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                hasNetworkError = true
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    /// Retry loading after network error
    func retryAfterError() async {
        hasNetworkError = false
        errorMessage = nil
        await loadDashboardData()
    }

    /// Load senders (connections where user is receiver) with ping status
    private func loadSenders(userId: UUID) async throws {
        // Fetch connections where user is receiver
        let connections: [Connection] = try await database
            .from("connections")
            .select("""
                id, sender_id, receiver_id, status, created_at, updated_at, deleted_at, connection_code,
                sender:users!connections_sender_id_fkey(id, phone_number, phone_country_code, display_name)
            """)
            .eq("receiver_id", value: userId.uuidString)
            .neq("status", value: ConnectionStatus.deleted.rawValue)
            .order("created_at", ascending: false)
            .execute()
            .value

        // For each sender, get their current ping status
        var sendersWithStatus: [SenderWithPingStatus] = []

        for connection in connections {
            let pingStatus = try await loadSenderPingStatus(
                senderId: connection.senderId,
                connectionId: connection.id
            )

            let streak = try await loadPingStreak(senderId: connection.senderId)

            sendersWithStatus.append(SenderWithPingStatus(
                connection: connection,
                pingStatus: pingStatus,
                streak: streak
            ))
        }

        senders = sendersWithStatus
    }

    /// Load ping status for a specific sender
    private func loadSenderPingStatus(senderId: UUID, connectionId: UUID) async throws -> SenderPingStatus {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let formatter = ISO8601DateFormatter()

        // Check if sender is on break
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

        if let activeBreak = breaks.first {
            return .onBreak(until: activeBreak.endDate)
        }

        // Get today's ping
        let pings: [Ping] = try await database
            .from("pings")
            .select()
            .eq("sender_id", value: senderId.uuidString)
            .gte("scheduled_time", value: formatter.string(from: startOfDay))
            .lt("scheduled_time", value: formatter.string(from: endOfDay))
            .limit(1)
            .execute()
            .value

        if let ping = pings.first {
            switch ping.status {
            case .completed:
                return .completed(at: ping.completedAt ?? Date())
            case .missed:
                return .missed(lastSeen: ping.scheduledTime)
            case .pending:
                return .expected(by: ping.deadlineTime)
            case .onBreak:
                return .onBreak(until: Date())
            }
        }

        // No ping record for today - check sender's ping time
        let profiles: [SenderProfile] = try await database
            .from("sender_profiles")
            .select()
            .eq("user_id", value: senderId.uuidString)
            .limit(1)
            .execute()
            .value

        if let profile = profiles.first {
            // Parse ping time and create expected deadline
            let timeComponents = profile.pingTime.split(separator: ":")
            if timeComponents.count >= 2,
               let hour = Int(timeComponents[0]),
               let minute = Int(timeComponents[1]) {

                var components = calendar.dateComponents([.year, .month, .day], from: Date())
                components.hour = hour
                components.minute = minute

                if let pingTime = calendar.date(from: components) {
                    // Add 90-minute grace period
                    let deadline = calendar.date(byAdding: .minute, value: 90, to: pingTime) ?? pingTime

                    if Date() > deadline {
                        return .missed(lastSeen: pingTime)
                    } else {
                        return .expected(by: deadline)
                    }
                }
            }
        }

        return .expected(by: Date())
    }

    /// Load ping streak for a sender
    /// Phase 6 Section 6.4: Ping Streak Calculation Rules:
    ///   - Consecutive days of completed pings
    ///   - Breaks do NOT break the streak (counted as completed)
    ///   - Missed pings reset streak to 0
    ///   - Late pings count toward streak (they have status 'completed')
    private func loadPingStreak(senderId: UUID) async throws -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Get all pings for this sender, ordered by date descending
        // Include both completed and on_break pings for streak calculation
        let pings: [Ping] = try await database
            .from("pings")
            .select("scheduled_time, status")
            .eq("sender_id", value: senderId.uuidString)
            .order("scheduled_time", ascending: false)
            .limit(730) // Max 2 years
            .execute()
            .value

        if pings.isEmpty {
            return 0
        }

        // Group pings by date and determine best status for each day
        var pingsByDate: [Date: PingStatus] = [:]

        for ping in pings {
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

    /// Load receiver's unique code
    private func loadUniqueCode(userId: UUID) async throws {
        let codes: [UniqueCode] = try await database
            .from("unique_codes")
            .select()
            .eq("receiver_id", value: userId.uuidString)
            .eq("is_active", value: true)
            .limit(1)
            .execute()
            .value

        if let code = codes.first {
            uniqueCode = code.code
        } else {
            // Generate a new code if none exists
            uniqueCode = try await generateNewCode(userId: userId)
        }
    }

    /// Generate a new unique code for the receiver
    private func generateNewCode(userId: UUID) async throws -> String {
        let result: [UniqueCode] = try await database
            .rpc("create_receiver_code", params: ["p_receiver_id": userId.uuidString])
            .execute()
            .value

        return result.first?.code ?? ""
    }

    /// Load receiver's subscription profile
    private func loadReceiverProfile(userId: UUID) async throws {
        let profiles: [ReceiverProfile] = try await database
            .from("receiver_profiles")
            .select()
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value

        receiverProfile = profiles.first
    }

    /// Load recent activity (last 7 days of pings)
    private func loadRecentActivity(userId: UUID) async throws {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday)!

        let formatter = ISO8601DateFormatter()

        // Get pings for all senders where user is receiver
        let pings: [Ping] = try await database
            .from("pings")
            .select("""
                id, sender_id, scheduled_time, completed_at, status, completion_method,
                sender:users!pings_sender_id_fkey(id, display_name, phone_number)
            """)
            .eq("receiver_id", value: userId.uuidString)
            .gte("scheduled_time", value: formatter.string(from: sevenDaysAgo))
            .order("scheduled_time", ascending: false)
            .execute()
            .value

        recentActivity = pings.map { ping in
            // Get sender name from the senders list
            let senderName = senders.first { $0.connection.senderId == ping.senderId }?
                .connection.sender?.displayName ?? "Unknown"

            return ActivityItem(
                id: ping.id,
                senderId: ping.senderId,
                senderName: senderName,
                timestamp: ping.completedAt ?? ping.scheduledTime,
                status: ping.status,
                method: ping.completionMethod
            )
        }
    }

    // MARK: - Actions

    /// Copy unique code to clipboard
    func copyCode() {
        UIPasteboard.general.string = uniqueCode

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Share unique code
    func shareCode() -> String {
        return "Connect with me on PRUUF! My code is: \(uniqueCode)\n\nDownload the app: https://pruuf.app/join"
    }

    /// Refresh all dashboard data
    func refresh() async {
        await loadDashboardData()
    }
}

// MARK: - Sender Ping Status

/// Represents the current ping status of a sender from receiver's perspective
enum SenderPingStatus: Equatable {
    /// Sender has completed their ping today
    case completed(at: Date)

    /// Sender's ping is expected by a certain time
    case expected(by: Date)

    /// Sender missed their ping
    case missed(lastSeen: Date)

    /// Sender is currently on break
    case onBreak(until: Date)

    /// Icon name for the status
    var iconName: String {
        switch self {
        case .completed:
            return "checkmark.circle.fill"
        case .expected:
            return "clock.fill"
        case .missed:
            return "exclamationmark.triangle.fill"
        case .onBreak:
            return "calendar"
        }
    }

    /// Color for the status
    var color: Color {
        switch self {
        case .completed:
            return .green
        case .expected:
            return .yellow
        case .missed:
            return .red
        case .onBreak:
            return .gray
        }
    }

    /// Status message
    var statusMessage: String {
        let formatter = DateFormatter()

        switch self {
        case .completed(let time):
            formatter.dateFormat = "h:mm a"
            return "Pinged today at \(formatter.string(from: time))"
        case .expected(let deadline):
            formatter.dateFormat = "h:mm a"
            return "Ping expected by \(formatter.string(from: deadline))"
        case .missed(let lastSeen):
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return "Missed ping - Last seen \(formatter.string(from: lastSeen))"
        case .onBreak(let until):
            formatter.dateFormat = "MMM d"
            return "On break until \(formatter.string(from: until))"
        }
    }

    /// Countdown string for expected status
    var countdownString: String? {
        guard case .expected(let deadline) = self else { return nil }

        let remaining = deadline.timeIntervalSince(Date())
        if remaining <= 0 { return nil }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        if hours > 0 {
            return "(\(hours)h \(minutes)m)"
        } else {
            return "(\(minutes)m)"
        }
    }
}

// MARK: - Sender With Ping Status

/// Combines a connection with the sender's current ping status
struct SenderWithPingStatus: Identifiable {
    let connection: Connection
    let pingStatus: SenderPingStatus
    let streak: Int

    var id: UUID { connection.id }

    /// Sender's display name
    var senderName: String {
        connection.sender?.displayName ?? connection.sender?.phoneNumber ?? "Unknown"
    }

    /// Sender's initials for avatar
    var initials: String {
        if let name = connection.sender?.displayName, !name.isEmpty {
            let words = name.split(separator: " ")
            let initials = words.prefix(2).compactMap { $0.first?.uppercased() }
            return initials.joined()
        }
        return "?"
    }
}

// MARK: - Activity Item

/// Represents a single activity entry in the timeline
struct ActivityItem: Identifiable {
    let id: UUID
    let senderId: UUID
    let senderName: String
    let timestamp: Date
    let status: PingStatus
    let method: CompletionMethod?

    /// Formatted timestamp
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: timestamp)
    }

    /// Relative time since activity
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
