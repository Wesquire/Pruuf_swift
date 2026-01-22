import SwiftUI
import Supabase
import Combine

// MARK: - Dashboard Feature

/// Dashboard feature namespace
/// Contains all dashboard-related views and view models
enum DashboardFeature {
    // Views:
    // - SenderDashboardView (implemented)
    // - ReceiverDashboardView (Phase 4.2)
    // - DualRoleDashboardView (Phase 4.3)
}

// MARK: - Main Dashboard Coordinator

/// Coordinates between different dashboard views based on user role
struct DashboardCoordinatorView: View {
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        Group {
            if let role = authService.currentPruufUser?.primaryRole {
                switch role {
                case .sender:
                    SenderDashboardView(authService: authService)
                case .receiver:
                    ReceiverDashboardView(authService: authService)
                case .both:
                    DualRoleDashboardView(authService: authService)
                }
            } else {
                // Default to sender dashboard if role not set
                SenderDashboardView(authService: authService)
            }
        }
    }
}

// MARK: - Dual Role Dashboard View

/// Dashboard for users with both sender and receiver roles (Phase 4.3)
/// Uses tab navigation to switch between sender and receiver views
struct DualRoleDashboardView: View {
    let authService: AuthService
    @StateObject private var viewModel: DualRoleDashboardViewModel
    @State private var selectedTab: DualRoleTab = .myPings

    init(authService: AuthService) {
        self.authService = authService
        self._viewModel = StateObject(wrappedValue: DualRoleDashboardViewModel(authService: authService))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar at top
            tabBar

            // Content area
            Group {
                switch selectedTab {
                case .myPings:
                    SenderDashboardView(authService: authService)
                case .theirPings:
                    ReceiverDashboardView(authService: authService)
                }
            }
        }
        .task {
            await viewModel.loadBadgeCounts()
        }
        .alert("Subscription Required", isPresented: $viewModel.showSubscriptionAlert) {
            Button("Subscribe") {
                viewModel.showSubscriptionSheet = true
            }
            Button("Cancel", role: .cancel) {
                selectedTab = .myPings
            }
        } message: {
            Text("You need an active subscription to view your senders. Subscribe now to get peace of mind knowing your loved ones are safe.")
        }
        .sheet(isPresented: $viewModel.showSubscriptionSheet) {
            SubscriptionRequiredSheet(onSubscribe: {
                viewModel.showSubscriptionSheet = false
            }, onCancel: {
                viewModel.showSubscriptionSheet = false
                selectedTab = .myPings
            })
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == .theirPings {
                viewModel.checkSubscriptionRequirement()
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(for: .myPings)
            tabButton(for: .theirPings)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }

    private func tabButton(for tab: DualRoleTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        } label: {
            HStack(spacing: 6) {
                Text(tab.title)
                    .font(.subheadline)
                    .fontWeight(selectedTab == tab ? .semibold : .regular)

                // Badge for notifications
                if let badgeCount = badgeCount(for: tab), badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor(for: tab))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTab == tab ? Color.blue : Color.clear)
            )
            .foregroundColor(selectedTab == tab ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func badgeCount(for tab: DualRoleTab) -> Int? {
        switch tab {
        case .myPings:
            return viewModel.senderPendingCount > 0 ? viewModel.senderPendingCount : nil
        case .theirPings:
            return viewModel.receiverAlertCount > 0 ? viewModel.receiverAlertCount : nil
        }
    }

    private func badgeColor(for tab: DualRoleTab) -> Color {
        switch tab {
        case .myPings:
            // Yellow for pending action (need to ping)
            return .orange
        case .theirPings:
            // Red for missed pings from senders
            return .red
        }
    }
}

// MARK: - Dual Role Tab

/// Tab options for dual role dashboard
enum DualRoleTab: Int, CaseIterable {
    case myPings = 0
    case theirPings = 1

    var title: String {
        switch self {
        case .myPings:
            return "My Pings"
        case .theirPings:
            return "Their Pings"
        }
    }

    var iconName: String {
        switch self {
        case .myPings:
            return "arrow.up.circle.fill"
        case .theirPings:
            return "arrow.down.circle.fill"
        }
    }
}

// MARK: - Dual Role Dashboard ViewModel

/// ViewModel for the Dual Role Dashboard
/// Manages badge counts and subscription status
@MainActor
final class DualRoleDashboardViewModel: ObservableObject {

    // MARK: - Published Properties

    /// Number of pending actions for sender (e.g., ping not sent today)
    @Published private(set) var senderPendingCount: Int = 0

    /// Number of alerts for receiver (e.g., missed pings from senders)
    @Published private(set) var receiverAlertCount: Int = 0

    /// Whether subscription alert should be shown
    @Published var showSubscriptionAlert: Bool = false

    /// Whether subscription sheet should be shown
    @Published var showSubscriptionSheet: Bool = false

    // MARK: - Private Properties

    private let authService: AuthService
    private let database: PostgrestClient

    // MARK: - Computed Properties

    /// Current user's ID
    var userId: UUID? {
        authService.currentPruufUser?.id
    }

    // MARK: - Initialization

    init(
        authService: AuthService,
        database: PostgrestClient? = nil
    ) {
        self.authService = authService
        self.database = database ?? SupabaseConfig.client.schema("public")
    }

    // MARK: - Data Loading

    /// Load badge counts for both tabs
    func loadBadgeCounts() async {
        guard let userId = userId else { return }

        do {
            async let senderBadge = loadSenderPendingCount(userId: userId)
            async let receiverBadge = loadReceiverAlertCount(userId: userId)

            let (senderCount, receiverCount) = try await (senderBadge, receiverBadge)

            senderPendingCount = senderCount
            receiverAlertCount = receiverCount
        } catch {
            // Silently handle errors for badge counts
            print("Failed to load badge counts: \(error)")
        }
    }

    /// Load sender pending count (1 if today's ping not sent)
    private func loadSenderPendingCount(userId: UUID) async throws -> Int {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let formatter = ISO8601DateFormatter()

        // Check if there's a completed ping for today
        let pings: [Ping] = try await database
            .from("pings")
            .select("id, status")
            .eq("sender_id", value: userId.uuidString)
            .gte("scheduled_time", value: formatter.string(from: startOfDay))
            .lt("scheduled_time", value: formatter.string(from: endOfDay))
            .eq("status", value: PingStatus.completed.rawValue)
            .limit(1)
            .execute()
            .value

        // If no completed ping, check if sender is on break
        if pings.isEmpty {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let todayString = dateFormatter.string(from: startOfDay)

            let breaks: [Break] = try await database
                .from("breaks")
                .select("id")
                .eq("sender_id", value: userId.uuidString)
                .lte("start_date", value: todayString)
                .gte("end_date", value: todayString)
                .in("status", values: [BreakStatus.scheduled.rawValue, BreakStatus.active.rawValue])
                .limit(1)
                .execute()
                .value

            // If on break, no badge needed
            if !breaks.isEmpty {
                return 0
            }

            // Not completed and not on break = pending action needed
            return 1
        }

        return 0
    }

    /// Load receiver alert count (number of missed pings from senders today)
    private func loadReceiverAlertCount(userId: UUID) async throws -> Int {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let formatter = ISO8601DateFormatter()

        // Get all active connections where user is receiver
        let connections: [Connection] = try await database
            .from("connections")
            .select("sender_id")
            .eq("receiver_id", value: userId.uuidString)
            .eq("status", value: ConnectionStatus.active.rawValue)
            .execute()
            .value

        guard !connections.isEmpty else { return 0 }

        let senderIds = connections.map { $0.senderId.uuidString }

        // Count missed pings from connected senders today
        let missedPings: [Ping] = try await database
            .from("pings")
            .select("id")
            .in("sender_id", values: senderIds)
            .gte("scheduled_time", value: formatter.string(from: startOfDay))
            .lt("scheduled_time", value: formatter.string(from: endOfDay))
            .eq("status", value: PingStatus.missed.rawValue)
            .execute()
            .value

        return missedPings.count
    }

    // MARK: - Subscription Logic

    /// Check if subscription is required to access receiver dashboard
    func checkSubscriptionRequirement() {
        guard let userId = userId else { return }

        Task {
            do {
                // Check if user has any receiver connections
                let connections: [Connection] = try await database
                    .from("connections")
                    .select("id")
                    .eq("receiver_id", value: userId.uuidString)
                    .neq("status", value: ConnectionStatus.deleted.rawValue)
                    .limit(1)
                    .execute()
                    .value

                // If user has receiver connections, check subscription status
                if !connections.isEmpty {
                    let profiles: [ReceiverProfile] = try await database
                        .from("receiver_profiles")
                        .select()
                        .eq("user_id", value: userId.uuidString)
                        .limit(1)
                        .execute()
                        .value

                    if let profile = profiles.first {
                        // Check subscription status
                        let hasValidSubscription = profile.subscriptionStatus == .active ||
                            profile.subscriptionStatus == .trial

                        if !hasValidSubscription {
                            showSubscriptionAlert = true
                        }
                    } else {
                        // No receiver profile = no trial started
                        showSubscriptionAlert = true
                    }
                }
                // If no receiver connections, no subscription required (free to browse empty dashboard)
            } catch {
                print("Failed to check subscription: \(error)")
            }
        }
    }
}

// MARK: - Subscription Required Sheet

/// Sheet shown when subscription is required to access receiver features
struct SubscriptionRequiredSheet: View {
    let onSubscribe: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                    .padding(.top, 40)

                // Title
                Text("Get Peace of Mind")
                    .font(.title)
                    .fontWeight(.bold)

                // Description
                Text("Subscribe to view your senders and get notified when they check in.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Benefits
                VStack(alignment: .leading, spacing: 12) {
                    benefitRow(icon: "person.2.fill", text: "Unlimited sender connections")
                    benefitRow(icon: "bell.fill", text: "Real-time ping notifications")
                    benefitRow(icon: "exclamationmark.triangle.fill", text: "Missed ping alerts")
                    benefitRow(icon: "shield.fill", text: "Peace of mind 24/7")
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)

                Spacer()

                // Price
                VStack(spacing: 4) {
                    Text("$2.99/month")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Cancel anytime")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Subscribe button
                Button {
                    onSubscribe()
                } label: {
                    Text("Subscribe Now")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 24)

                // Cancel button
                Button {
                    onCancel()
                } label: {
                    Text("Maybe Later")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.blue)
                .frame(width: 24)

            Text(text)
                .font(.body)
        }
    }
}

// MARK: - Main Tab View

/// Main tab view for authenticated users
/// Handles navigation from in-app notifications via NotificationCenter observer
struct MainTabView: View {
    @EnvironmentObject private var authService: AuthService
    @State private var selectedTab = 0

    // MARK: - Notification Navigation State

    /// Navigation destination requested by notification tap
    @State private var notificationDestination: NotificationNavigationDestination?

    /// Whether to show sender activity sheet
    @State private var showSenderActivity = false
    @State private var senderActivityId: UUID?

    /// Whether to show ping history sheet
    @State private var showPingHistory = false
    @State private var pingHistoryConnectionId: UUID?

    /// Whether to show pending connections
    @State private var showPendingConnections = false

    /// Whether to show subscription management
    @State private var showSubscription = false

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardCoordinatorView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(0)

            ConnectionsPlaceholderView()
                .tabItem {
                    Image(systemName: "person.2.fill")
                    Text("Connections")
                }
                .tag(1)

            SettingsTabPlaceholderView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(2)
        }
        .onReceive(NotificationCenter.default.publisher(for: InAppNotificationStore.navigateToNotificationDestination)) { notification in
            handleNotificationNavigation(notification)
        }
        .sheet(isPresented: $showSenderActivity) {
            if let senderId = senderActivityId {
                SenderActivitySheetView(senderId: senderId)
            }
        }
        .sheet(isPresented: $showPingHistory) {
            if let connectionId = pingHistoryConnectionId,
               let userId = authService.currentPruufUser?.id {
                PingHistoryView(
                    connectionId: connectionId,
                    displayName: "Ping History",
                    userId: userId
                )
            }
        }
        .sheet(isPresented: $showPendingConnections) {
            PendingConnectionsSheetView()
        }
        .sheet(isPresented: $showSubscription) {
            ManageSubscriptionPlaceholderView()
        }
    }

    // MARK: - Notification Navigation Handler

    /// Handle navigation notification from in-app notification tap
    /// - Parameter notification: The navigation notification
    private func handleNotificationNavigation(_ notification: Foundation.Notification) {
        guard let userInfo = notification.userInfo,
              let destination = userInfo["destination"] as? NotificationNavigationDestination else {
            return
        }

        // Process destination
        switch destination {
        case .senderDashboard:
            // Navigate to sender dashboard (Home tab, sender view)
            selectedTab = 0
            // If dual role, need to signal sender tab selection

        case .receiverDashboard:
            // Navigate to receiver dashboard (Home tab, receiver view)
            selectedTab = 0
            // If dual role, need to signal receiver tab selection

        case .senderActivity(let senderId):
            // Navigate to sender activity view
            selectedTab = 0
            senderActivityId = senderId
            showSenderActivity = true

        case .pingHistory(let connectionId):
            // Navigate to ping history for a connection
            pingHistoryConnectionId = connectionId
            showPingHistory = true

        case .pendingConnections:
            // Navigate to connections tab and show pending
            selectedTab = 1
            showPendingConnections = true

        case .subscription:
            // Show subscription management
            showSubscription = true

        case .settings:
            // Navigate to settings tab
            selectedTab = 2
        }
    }
}

// MARK: - Sender Activity Sheet View

/// Sheet view for displaying a specific sender's activity
/// Shown when navigating from a missed ping notification
struct SenderActivitySheetView: View {
    let senderId: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Sender Activity")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Sender ID: \(senderId.uuidString.prefix(8))...")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("View detailed ping history and status for this sender.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .navigationTitle("Sender Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Pending Connections Sheet View

/// Sheet view for displaying pending connection requests
/// Shown when navigating from a connection request notification
struct PendingConnectionsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Pending Connections")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("View and manage your pending connection requests.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .navigationTitle("Pending Connections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Tab Placeholder Views

struct ConnectionsPlaceholderView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Connections")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Manage your connections here")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .navigationTitle("Connections")
        }
        .navigationViewStyle(.stack)
    }
}

/// Settings tab view that wraps the full SettingsView
/// Updated for Phase 10 Section 10.1: Complete Settings Screen Structure
struct SettingsTabPlaceholderView: View {
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        NavigationView {
            SettingsView(authService: authService)
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Preview

#if DEBUG
struct DashboardFeature_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(AuthService())
    }
}
#endif
