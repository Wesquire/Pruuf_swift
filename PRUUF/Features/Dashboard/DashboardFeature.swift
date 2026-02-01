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
/// Simplified to show only sender dashboard (Their Pruufs tab removed per Requirement 11)
struct DualRoleDashboardView: View {
    let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    var body: some View {
        // Simplified to single view - only showing sender dashboard
        // Receiver features accessible via separate tab or navigation if needed
        SenderDashboardView(authService: authService)
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
                    benefitRow(icon: "bell.fill", text: "Real-time Pruuf notifications")
                    benefitRow(icon: "exclamationmark.triangle.fill", text: "Missed Pruuf alerts")
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
                    Text("Receivers")
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
                    displayName: "Pruuf History",
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

                Text("View detailed Pruuf history and status for this sender.")
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

// MARK: - Receivers Tab View

/// Receivers tab view showing list of all receivers with status badges
/// Requirement 8: Connections/Receivers Page Redesign
struct ConnectionsPlaceholderView: View {
    @EnvironmentObject private var authService: AuthService
    @StateObject private var connectionService = ConnectionService.shared
    @State private var showAddReceiver = false
    @State private var showManageSheet = false
    @State private var selectedConnection: Connection?
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Requirement 9: Collapsible Connection ID
    @State private var senderInvitationCode: String?
    @State private var isConnectionIdExpanded = false
    @State private var showCodeCopied = false

    // Requirement 3: Nudge/Reminder functionality
    @State private var showNudgeSMSComposer = false
    @State private var pendingNudgeConnection: Connection?

    var body: some View {
        NavigationView {
            Group {
                if isLoading && connectionService.connections.isEmpty {
                    ProgressView("Loading receivers...")
                } else if connectionService.connections.isEmpty {
                    emptyStateView
                } else {
                    receiversListView
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Receivers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddReceiver = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .task {
            await loadReceivers()
            await loadSenderInvitationCode()
        }
        .sheet(isPresented: $showAddReceiver) {
            AddConnectionView(authService: authService)
        }
        .onChange(of: showAddReceiver) { isShowing in
            if !isShowing {
                Task {
                    await loadReceivers()
                }
            }
        }
        .sheet(isPresented: $showManageSheet) {
            if let connection = selectedConnection {
                SenderConnectionActionsSheet(
                    connection: connection,
                    authService: authService,
                    onPause: {
                        await pauseConnection(connection.id)
                    },
                    onResume: {
                        await resumeConnection(connection.id)
                    },
                    onRemove: {
                        await removeConnection(connection.id)
                    },
                    onViewHistory: {
                        // History handled in sheet
                    }
                )
            }
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        // Requirement 3: SMS Composer for Nudge
        .sheet(isPresented: $showNudgeSMSComposer) {
            if let connection = pendingNudgeConnection,
               let phoneNumber = connection.receiver?.phoneNumber,
               SMSComposerView.canSendText {
                SMSComposerView(
                    isPresented: $showNudgeSMSComposer,
                    recipients: [phoneNumber],
                    messageBody: generateNudgeMessage(for: connection),
                    onComplete: { success in
                        if success {
                            errorMessage = "Reminder sent to \(connection.receiver?.displayName ?? "receiver")"
                        }
                        pendingNudgeConnection = nil
                    }
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "person.2.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Receivers")
                .font(.title2)
                .fontWeight(.bold)

            Text("Add receivers to send them your daily Pruuf.\nThey'll be notified when you check in.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showAddReceiver = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Receiver")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.blue)
                .cornerRadius(12)
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Receivers List

    private var receiversListView: some View {
        VStack(spacing: 0) {
            List {
                // Receivers section
                ForEach(connectionService.connections) { connection in
                    ReceiverListRowView(
                        connection: connection,
                        onSendReminder: connection.status == .pending ? {
                            sendReminder(for: connection)
                        } : nil
                    )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedConnection = connection
                            showManageSheet = true
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    await removeConnection(connection.id)
                                }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }

                // Requirement 9: Collapsible "My Connection ID" section
                if senderInvitationCode != nil {
                    Section {
                        connectionIdSection
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await loadReceivers()
            }

            // Add Receiver Button at bottom
            addReceiverFooter
        }
        .overlay(
            // Toast for copied confirmation
            Group {
                if showCodeCopied {
                    VStack {
                        Spacer()
                        Text("Code copied!")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(8)
                            .padding(.bottom, 100)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showCodeCopied)
        )
    }

    // MARK: - Connection ID Section (Requirement 9)

    private var connectionIdSection: some View {
        DisclosureGroup(
            isExpanded: $isConnectionIdExpanded,
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    // Code display
                    if let code = senderInvitationCode {
                        HStack {
                            Text(code)
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                                .tracking(4)

                            Spacer()

                            Button {
                                UIPasteboard.general.string = code
                                showCodeCopied = true
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)

                                // Hide toast after 2 seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showCodeCopied = false
                                }
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.title3)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    // Explanatory text
                    Text("Share this code with people who want to receive your daily Pruuf. They'll enter it in their app to connect with you.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            },
            label: {
                HStack(spacing: 12) {
                    Image(systemName: "qrcode")
                        .font(.title3)
                        .foregroundColor(.purple)

                    Text("My Connection ID")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                }
            }
        )
        .tint(.purple)
    }

    // MARK: - Add Receiver Footer

    private var addReceiverFooter: some View {
        Button {
            showAddReceiver = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                Text("Add Receiver")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.systemBackground))
        }
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .top
        )
    }

    // MARK: - Data Loading

    private func loadReceivers() async {
        guard let userId = authService.currentPruufUser?.id else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try await connectionService.fetchConnectionsAsSender(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Load the sender's invitation code from sender_profiles table
    private func loadSenderInvitationCode() async {
        guard let userId = authService.currentPruufUser?.id else { return }

        struct SenderProfileCode: Codable {
            let invitationCode: String?

            enum CodingKeys: String, CodingKey {
                case invitationCode = "invitation_code"
            }
        }

        do {
            let profiles: [SenderProfileCode] = try await SupabaseConfig.client.schema("public")
                .from("sender_profiles")
                .select("invitation_code")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            if let profile = profiles.first, let code = profile.invitationCode {
                senderInvitationCode = code
            }
        } catch {
            // Silently fail - code will just not be displayed
            print("Failed to load sender invitation code: \(error)")
        }
    }

    // MARK: - Connection Actions

    private func pauseConnection(_ connectionId: UUID) async {
        do {
            _ = try await connectionService.pauseConnection(connectionId: connectionId)
            await loadReceivers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resumeConnection(_ connectionId: UUID) async {
        do {
            _ = try await connectionService.resumeConnection(connectionId: connectionId)
            await loadReceivers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeConnection(_ connectionId: UUID) async {
        do {
            try await connectionService.deleteConnection(connectionId: connectionId)
            await loadReceivers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendReminder(for connection: Connection) {
        // Requirement 3: Trigger SMS composer for nudge
        guard let phoneNumber = connection.receiver?.phoneNumber, !phoneNumber.isEmpty else {
            errorMessage = "No phone number available for this receiver"
            return
        }

        // Check if SMS is available
        if SMSComposerView.canSendText {
            pendingNudgeConnection = connection
            showNudgeSMSComposer = true
        } else {
            errorMessage = "SMS is not available on this device"
        }
    }

    /// Generate the nudge message for a connection
    private func generateNudgeMessage(for connection: Connection) -> String {
        let senderName = authService.currentPruufUser?.displayName ?? "Someone"
        let code = senderInvitationCode ?? "------"
        return InvitationService.shared.generateNudgeMessage(senderName: senderName, code: code)
    }
}

// MARK: - Receiver List Row View

/// Row view for the receivers list with status badge
struct ReceiverListRowView: View {
    let connection: Connection
    var onSendReminder: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Avatar circle with initials
            Circle()
                .fill(statusColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(initials)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(statusColor)
                )

            // Name and status
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                // Status badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Reminder button for pending connections
            if connection.status == .pending, let onSendReminder = onSendReminder {
                Button {
                    onSendReminder()
                } label: {
                    Text("Remind")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Chevron indicator
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Computed Properties

    private var displayName: String {
        connection.receiver?.displayName ?? connection.receiver?.phoneNumber ?? "Unknown"
    }

    private var initials: String {
        if let name = connection.receiver?.displayName, !name.isEmpty {
            let words = name.split(separator: " ")
            let initials = words.prefix(2).compactMap { $0.first?.uppercased() }
            return initials.joined()
        }
        return "?"
    }

    private var statusColor: Color {
        switch connection.status {
        case .active:
            return .green
        case .paused:
            return .gray
        case .pending:
            return .orange
        case .deleted:
            return .red
        }
    }

    private var statusText: String {
        switch connection.status {
        case .active:
            return "Active"
        case .paused:
            return "Paused"
        case .pending:
            return "Pending"
        case .deleted:
            return "Removed"
        }
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
