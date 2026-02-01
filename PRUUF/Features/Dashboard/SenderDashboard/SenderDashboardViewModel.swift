import Foundation
import SwiftUI
import CoreLocation
import Supabase

/// ViewModel for the Sender Dashboard
/// Manages state for ping status, receivers, breaks, and history
@MainActor
final class SenderDashboardViewModel: NSObject, ObservableObject {

    // MARK: - Published Properties

    /// Current today's ping state
    @Published private(set) var todayPingState: TodayPingState = .pending

    /// Today's ping if one exists
    @Published private(set) var todayPing: Ping?

    /// Current active break if any
    @Published private(set) var currentBreak: Break?

    /// List of receivers (connections where user is sender)
    @Published private(set) var receivers: [Connection] = []

    /// Last 7 days of ping history
    @Published private(set) var pingHistory: [DayPingStatus] = []

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

    /// Whether location permission is needed
    @Published var showLocationPermissionAlert: Bool = false

    /// Whether location is being captured
    @Published var isCapturingLocation: Bool = false

    /// Current time display
    @Published private(set) var currentTimeString: String = ""

    /// Countdown remaining for pending ping
    @Published private(set) var countdownString: String = ""

    /// Sender's daily ping time
    @Published private(set) var pingTimeString: String = ""

    /// Sender's unique invitation code (Plan 4 Req 2)
    @Published private(set) var senderInvitationCode: String?

    // MARK: - Private Properties

    private let pingService: PingService
    private let connectionService: ConnectionService
    private let authService: AuthService
    private let database: PostgrestClient
    private let locationManager: CLLocationManager
    private var countdownTimer: Timer?
    private var timeUpdateTimer: Timer?
    private var capturedLocation: CLLocation?
    private var locationCompletion: ((CLLocation?) -> Void)?

    /// Tracks the last known calendar day for midnight reset detection
    /// When day changes, dashboard data is reloaded to reset the "I'm OK" window
    private var lastKnownDay: Date?

    // MARK: - Computed Properties

    /// Current user's ID
    var userId: UUID? {
        authService.currentPruufUser?.id
    }

    /// User's display name
    var userName: String {
        authService.currentPruufUser?.displayName ?? "Me"
    }

    /// Number of active receivers
    var activeReceiversCount: Int {
        receivers.filter { $0.status == .active }.count
    }

    /// Whether user has any receivers
    var hasReceivers: Bool {
        !receivers.isEmpty
    }

    // MARK: - Initialization

    init(
        pingService: PingService? = nil,
        connectionService: ConnectionService? = nil,
        authService: AuthService,
        database: PostgrestClient? = nil
    ) {
        self.pingService = pingService ?? PingService.shared
        self.connectionService = connectionService ?? ConnectionService.shared
        self.authService = authService
        self.database = database ?? SupabaseConfig.client.schema("public")
        self.locationManager = CLLocationManager()

        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest

        setupTimers()
    }

    deinit {
        countdownTimer?.invalidate()
        timeUpdateTimer?.invalidate()
    }

    // MARK: - Timer Setup

    private func setupTimers() {
        // Update current time every second
        updateCurrentTime()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCurrentTime()
                self?.updateCountdown()
                self?.checkForDayChange()
            }
        }
    }

    private func updateCurrentTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        currentTimeString = formatter.string(from: Date())
    }

    private func updateCountdown() {
        guard case .pending = todayPingState,
              let ping = todayPing else {
            countdownString = ""
            return
        }

        countdownString = ping.timeRemainingString
    }

    /// Check if the calendar day has changed (midnight reset)
    /// If day changed, reload dashboard data to reset the "I'm OK" window
    /// Only pings in the current calendar day satisfy the daily Pruuf requirement
    private func checkForDayChange() {
        let calendar = Calendar.current
        let currentDay = calendar.startOfDay(for: Date())

        // If we have a lastKnownDay and it's different from currentDay, day has changed
        if let lastDay = lastKnownDay, lastDay != currentDay {
            Logger.info("[Midnight Reset] Day changed from \(lastDay) to \(currentDay), reloading dashboard")

            // Day has changed - reload dashboard to reset the "I'm OK" window
            Task {
                await loadDashboardData()
            }
        }

        // Update lastKnownDay (this also handles initial setup)
        lastKnownDay = currentDay
    }

    // MARK: - Data Loading

    /// Load all dashboard data
    func loadDashboardData() async {
        guard let userId = userId else { return }

        isLoading = true
        hasNetworkError = false

        do {
            // Load data in parallel
            async let connectionsTask: () = loadReceivers(userId: userId)
            async let pingStatusTask: () = loadTodayPingStatus(userId: userId)
            async let breakTask: () = loadCurrentBreak(userId: userId)
            async let historyTask: () = loadPingHistory(userId: userId)
            async let pingTimeTask: () = loadSenderPingTime(userId: userId)
            async let invitationCodeTask: () = loadSenderInvitationCode(userId: userId)

            _ = try await (connectionsTask, pingStatusTask, breakTask, historyTask, pingTimeTask, invitationCodeTask)

            // Determine today's ping state
            determineTodayPingState()

            // Set lastKnownDay for midnight reset detection
            lastKnownDay = Calendar.current.startOfDay(for: Date())

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

    /// Load receivers (connections where user is sender)
    private func loadReceivers(userId: UUID) async throws {
        try await connectionService.fetchConnectionsAsSender(userId: userId)
        receivers = connectionService.connections
    }

    /// Load today's ping status
    private func loadTodayPingStatus(userId: UUID) async throws {
        // Get today's ping from the pings table
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let formatter = ISO8601DateFormatter()

        let pings: [Ping] = try await database
            .from("pings")
            .select()
            .eq("sender_id", value: userId.uuidString)
            .gte("scheduled_time", value: formatter.string(from: startOfDay))
            .lt("scheduled_time", value: formatter.string(from: endOfDay))
            .limit(1)
            .execute()
            .value

        todayPing = pings.first
    }

    /// Load current active break
    private func loadCurrentBreak(userId: UUID) async throws {
        let today = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: today)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: startOfDay)

        let breaks: [Break] = try await database
            .from("breaks")
            .select()
            .eq("sender_id", value: userId.uuidString)
            .lte("start_date", value: todayString)
            .gte("end_date", value: todayString)
            .in("status", values: [BreakStatus.scheduled.rawValue, BreakStatus.active.rawValue])
            .limit(1)
            .execute()
            .value

        currentBreak = breaks.first
    }

    /// Load last 7 days of ping history
    private func loadPingHistory(userId: UUID) async throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: today)!

        let formatter = ISO8601DateFormatter()

        let pings: [Ping] = try await database
            .from("pings")
            .select("id, scheduled_time, status, completed_at")
            .eq("sender_id", value: userId.uuidString)
            .gte("scheduled_time", value: formatter.string(from: sevenDaysAgo))
            .order("scheduled_time", ascending: true)
            .execute()
            .value

        // Create day status for each of the last 7 days
        var history: [DayPingStatus] = []
        for i in 0..<7 {
            let date = calendar.date(byAdding: .day, value: i - 6, to: today)!
            let dayPings = pings.filter { ping in
                calendar.isDate(ping.scheduledTime, inSameDayAs: date)
            }

            let status: PingStatus
            if let ping = dayPings.first {
                status = ping.status
            } else {
                // No ping for this day - mark as pending if no data
                status = .pending
            }

            history.append(DayPingStatus(date: date, status: status))
        }

        pingHistory = history
    }

    /// Load sender's configured ping time
    private func loadSenderPingTime(userId: UUID) async throws {
        let profiles: [SenderProfile] = try await database
            .from("sender_profiles")
            .select()
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value

        if let profile = profiles.first {
            // Parse the ping time (stored as HH:MM:SS in UTC)
            let timeComponents = profile.pingTime.split(separator: ":")
            if timeComponents.count >= 2,
               let hour = Int(timeComponents[0]),
               let minute = Int(timeComponents[1]) {

                var components = DateComponents()
                components.hour = hour
                components.minute = minute

                let calendar = Calendar.current
                if let date = calendar.date(from: components) {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "h:mm a"
                    pingTimeString = formatter.string(from: date)
                }
            }
        }
    }

    /// Load sender's invitation code (Plan 4 Req 2)
    private func loadSenderInvitationCode(userId: UUID) async throws {
        let profiles: [SenderProfile] = try await database
            .from("sender_profiles")
            .select("invitation_code")
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value

        if let profile = profiles.first {
            senderInvitationCode = profile.invitationCode
        }
    }

    /// Determine today's ping state based on loaded data
    private func determineTodayPingState() {
        // Check if on break first
        if let activeBreak = currentBreak, activeBreak.isCurrentlyActive {
            todayPingState = .onBreak
            return
        }

        // Check today's ping status
        guard let ping = todayPing else {
            // No ping exists for today yet - show pending
            todayPingState = .pending
            return
        }

        switch ping.status {
        case .completed:
            todayPingState = .completed
        case .missed:
            todayPingState = .missed
        case .onBreak:
            todayPingState = .onBreak
        case .pending:
            if ping.isWithinWindow {
                todayPingState = .pending
            } else {
                todayPingState = .missed
            }
        }
    }

    // MARK: - Ping Actions

    /// Complete today's ping with tap method
    func completePing() async {
        guard let ping = todayPing else {
            // If no ping exists, create one and complete it
            await completePingWithoutExistingRecord()
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await pingService.completePing(pingId: ping.id, method: .tap)

            // Update local state
            todayPingState = .completed

            // Trigger haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Reload data to update history
            await loadDashboardData()
        } catch {
            errorMessage = "Failed to complete ping: \(error.localizedDescription)"
        }
    }

    /// Complete ping when no ping record exists yet
    private func completePingWithoutExistingRecord() async {
        isLoading = true
        defer { isLoading = false }

        guard let userId = userId else { return }

        do {
            // Call the complete_ping RPC function
            _ = try await database
                .rpc("complete_ping", params: [
                    "p_sender_id": userId.uuidString,
                    "p_method": CompletionMethod.tap.rawValue,
                    "p_location": nil as String?,
                    "p_notes": nil as String?
                ])
                .execute()

            // Update local state
            todayPingState = .completed

            // Trigger haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Reload data
            await loadDashboardData()
        } catch {
            // Fallback - just update the state
            todayPingState = .completed
            errorMessage = nil
        }
    }

    /// Complete ping with in-person verification (location)
    func completePingInPerson() async {
        // Check location permission
        let status = locationManager.authorizationStatus

        switch status {
        case .notDetermined:
            showLocationPermissionAlert = true
            return
        case .denied, .restricted:
            errorMessage = "Location permission is required for in-person verification. Please enable it in Settings."
            return
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            break
        }

        isCapturingLocation = true

        // Request location update
        locationManager.requestLocation()
    }

    /// Request location permission
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Complete ping with captured location
    private func completePingWithLocation(_ location: CLLocation) async {
        isCapturingLocation = false

        guard let ping = todayPing else {
            await completePingInPersonWithoutRecord(location: location)
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Update the ping with location verification
            let locationData: [String: Any] = [
                "lat": location.coordinate.latitude,
                "lon": location.coordinate.longitude,
                "accuracy": location.horizontalAccuracy
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: locationData)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            try await database
                .from("pings")
                .update([
                    "completed_at": ISO8601DateFormatter().string(from: Date()),
                    "completion_method": CompletionMethod.inPerson.rawValue,
                    "status": PingStatus.completed.rawValue,
                    "verification_location": jsonString
                ])
                .eq("id", value: ping.id.uuidString)
                .execute()

            todayPingState = .completed

            // Trigger haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            await loadDashboardData()
        } catch {
            errorMessage = "Failed to verify location: \(error.localizedDescription)"
        }
    }

    /// Complete ping in person without existing record
    private func completePingInPersonWithoutRecord(location: CLLocation) async {
        isLoading = true
        defer { isLoading = false }

        guard let userId = userId else { return }

        do {
            let locationData: [String: Any] = [
                "lat": location.coordinate.latitude,
                "lon": location.coordinate.longitude,
                "accuracy": location.horizontalAccuracy
            ]
            let jsonData = try JSONSerialization.data(withJSONObject: locationData)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            let _: [String: String] = try await database
                .rpc("complete_ping", params: [
                    "p_sender_id": userId.uuidString,
                    "p_method": CompletionMethod.inPerson.rawValue,
                    "p_location": jsonString,
                    "p_notes": nil as String?
                ])
                .execute()
                .value

            todayPingState = .completed

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            await loadDashboardData()
        } catch {
            todayPingState = .completed
            errorMessage = nil
        }
    }

    /// Complete a late ping (when missed but user still wants to send)
    func completePingLate() async {
        await completePing()
    }

    /// Complete a voluntary ping while on break
    /// Section 7.1: "allow optional voluntary completion"
    /// This allows senders to ping during their break period without ending the break
    func completePingVoluntary() async {
        guard let ping = todayPing else {
            // Create a voluntary ping if none exists
            await completePingWithoutExistingRecord()
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Update the ping to completed status but keep it voluntary
            try await database
                .from("pings")
                .update([
                    "completed_at": ISO8601DateFormatter().string(from: Date()),
                    "completion_method": CompletionMethod.tap.rawValue,
                    "status": PingStatus.completed.rawValue,
                    "notes": "Voluntary ping during break"
                ])
                .eq("id", value: ping.id.uuidString)
                .execute()

            // Update local state - show completed but keep the break
            todayPingState = .completed

            // Trigger haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Reload data to update history (break status remains unchanged)
            await loadDashboardData()
        } catch {
            errorMessage = "Failed to complete voluntary ping: \(error.localizedDescription)"
        }
    }

    // MARK: - Break Actions

    /// End the current break early
    func endBreakEarly() async {
        guard let activeBreak = currentBreak else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try await database
                .from("breaks")
                .update([
                    "status": BreakStatus.canceled.rawValue,
                    "end_date": DateFormatter.dateOnly.string(from: Date())
                ])
                .eq("id", value: activeBreak.id.uuidString)
                .execute()

            currentBreak = nil
            todayPingState = .pending

            await loadDashboardData()
        } catch {
            errorMessage = "Failed to end break: \(error.localizedDescription)"
        }
    }

    // MARK: - Refresh

    /// Refresh all dashboard data
    func refresh() async {
        await loadDashboardData()
    }
}

// MARK: - CLLocationManagerDelegate

extension SenderDashboardViewModel: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            await completePingWithLocation(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            isCapturingLocation = false
            errorMessage = "Failed to get location: \(error.localizedDescription)"
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                showLocationPermissionAlert = false
            }
        }
    }
}

// MARK: - Today Ping State

/// Represents the current state of today's ping
enum TodayPingState: Equatable {
    case pending
    case completed
    case missed
    case onBreak
}

// MARK: - Day Ping Status

/// Status of a ping for a specific day (for calendar display)
struct DayPingStatus: Identifiable {
    let id = UUID()
    let date: Date
    let status: PingStatus

    /// Color for the status dot
    var dotColor: Color {
        switch status {
        case .completed:
            return .green
        case .missed:
            return .red
        case .onBreak:
            return .gray
        case .pending:
            return .yellow
        }
    }

    /// Day of week abbreviation
    var dayAbbreviation: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    /// Day number
    var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}

// MARK: - Date Formatter Extension

extension DateFormatter {
    static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
