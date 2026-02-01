import SwiftUI

// MARK: - Sender Dashboard View

/// Main dashboard view for senders
/// Shows ping status, receivers, recent activity, and quick actions
struct SenderDashboardView: View {
    @StateObject private var viewModel: SenderDashboardViewModel
    @EnvironmentObject private var authService: AuthService
    @State private var showSettings = false
    @State private var showAddReceiver = false
    @State private var showScheduleBreak = false
    @State private var showChangePingTime = false
    @State private var showEndBreakConfirmation = false
    @State private var showNotificationCenter = false
    @State private var showOkConfirmation = false
    @State private var showLateOkConfirmation = false
    @State private var showVoluntaryOkConfirmation = false
    @State private var showAllReceivers = false
    @State private var isSettingsExpanded = true
    @State private var showReceiverCodeEntry = false

    init(authService: AuthService) {
        _viewModel = StateObject(wrappedValue: SenderDashboardViewModel(authService: authService))
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Main content
                if viewModel.hasNetworkError {
                    // Network error state
                    NetworkErrorEmptyState {
                        Task {
                            await viewModel.retryAfterError()
                        }
                    }
                    .padding()
                } else if viewModel.isInitialLoad && viewModel.isLoading {
                    // Full screen loading for initial load
                    FullScreenLoadingView(message: "Loading your dashboard...")
                } else {
                    // Main dashboard content
                    ScrollView {
                        VStack(spacing: 24) {
                            // 1. Header Section
                            headerSection

                            // 2. Today's Ping Status Card
                            todayPingCard

                            // 3. Your Receivers Section
                            receiversSection

                            // 4. Settings Section (collapsible, default open)
                            settingsSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                    .refreshable {
                        await viewModel.refresh()
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .onAppear {
            Task {
                await viewModel.loadDashboardData()
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                SettingsView(authService: authService)
            }
        }
        .sheet(isPresented: $showAddReceiver) {
            InviteReceiversFlowView(authService: authService)
                .environmentObject(authService)
        }
        .sheet(isPresented: $showScheduleBreak) {
            ScheduleBreakView(authService: authService)
        }
        .sheet(isPresented: $showChangePingTime) {
            ChangePingTimePlaceholderView()
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .alert("End Break Early?", isPresented: $showEndBreakConfirmation) {
            Button("Keep Break", role: .cancel) { }
            Button("End Break", role: .destructive) {
                Task {
                    await viewModel.endBreakEarly()
                }
            }
        } message: {
            Text("Are you sure you want to end your break early? Your receivers will be notified, and you'll need to send your daily Pruuf starting today.")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.userName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text(viewModel.currentTimeString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Notification bell with badge
            NotificationBellButton(showNotificationCenter: $showNotificationCenter)
                .padding(.trailing, 12)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 4)
        .sheet(isPresented: $showNotificationCenter) {
            NotificationCenterView()
        }
    }

    // MARK: - Today's Ping Card

    private var todayPingCard: some View {
        VStack(spacing: 16) {
            switch viewModel.todayPingState {
            case .pending:
                pendingPingContent
            case .completed:
                completedPingContent
            case .missed:
                missedPingContent
            case .onBreak:
                onBreakContent
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private var pendingPingContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            VStack(spacing: 8) {
                Text("Time to Send Your Pruuf!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text("Tap the Pruuf Ping button to let your receivers know that you're ok")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !viewModel.countdownString.isEmpty {
                Text(viewModel.countdownString)
                    .font(.headline)
                    .foregroundColor(.orange)
            }

            Button {
                showOkConfirmation = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                    Text("I'm Okay")
                        .font(.system(size: 28, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color.blue)
                .cornerRadius(20)
            }
            .disabled(viewModel.isLoading)
            .accessibilityLabel("Tap to confirm you're okay")
            .confirmationDialog(
                "Send Your Pruuf?",
                isPresented: $showOkConfirmation,
                titleVisibility: .visible
            ) {
                Button("Yes, I'm Okay") {
                    Task {
                        await viewModel.completePing()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will notify your receivers that you are safe.")
            }

            Text("Tap to let everyone know you're safe")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var completedPingContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Pruuf Sent!")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            if let ping = viewModel.todayPing, let completedAt = ping.completedAt {
                let formatter = DateFormatter()
                let _ = formatter.dateFormat = "h:mm a"
                Text("Completed at \(formatter.string(from: completedAt))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("See you tomorrow")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var missedPingContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("Pruuf Missed")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            if let ping = viewModel.todayPing {
                let formatter = DateFormatter()
                let _ = formatter.dateFormat = "h:mm a"
                Text("Deadline was \(formatter.string(from: ping.deadlineTime))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Button {
                showLateOkConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise.circle.fill")
                    Text("Send Pruuf Now")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.orange)
                .cornerRadius(12)
            }
            .disabled(viewModel.isLoading)
            .accessibilityLabel("Send a late Pruuf")
            .confirmationDialog(
                "Send Late Pruuf?",
                isPresented: $showLateOkConfirmation,
                titleVisibility: .visible
            ) {
                Button("Yes, Send Pruuf Now") {
                    Task {
                        await viewModel.completePingLate()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will notify your receivers that you are safe, even though you missed the deadline.")
            }
        }
    }

    private var onBreakContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("On Pruuf Pause")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            if let activeBreak = viewModel.currentBreak {
                let formatter = DateFormatter()
                let _ = formatter.dateFormat = "MMM d"
                Text("Until \(formatter.string(from: activeBreak.endDate))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Section 7.1: Optional voluntary ping completion during breaks
            // "allow optional voluntary completion"
            Button {
                showVoluntaryOkConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "hand.tap.fill")
                    Text("Send Pruuf Anyway (Optional)")
                }
                .font(.subheadline)
                .foregroundColor(.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(10)
            }
            .disabled(viewModel.isLoading)
            .accessibilityLabel("Send a voluntary Pruuf while on Pruuf Pause")
            .confirmationDialog(
                "Send Voluntary Pruuf?",
                isPresented: $showVoluntaryOkConfirmation,
                titleVisibility: .visible
            ) {
                Button("Yes, Send Pruuf") {
                    Task {
                        await viewModel.completePingVoluntary()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will notify your receivers that you are safe. Your Pruuf Pause will continue.")
            }

            Button {
                showEndBreakConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                    Text("End Pruuf Pause Early")
                }
                .font(.headline)
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
            .disabled(viewModel.isLoading)
            .accessibilityLabel("End break early and resume Pruufs")

            Text("You can send a Pruuf voluntarily without ending your break")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Receivers Section

    private var receiversSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Your Receivers")
                    .font(.headline)
                    .foregroundColor(.primary)

                if viewModel.activeReceiversCount > 0 {
                    Text("\(viewModel.activeReceiversCount)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .cornerRadius(10)
                }

                Spacer()
            }

            // Action Buttons
            VStack(spacing: 12) {
                // View Receivers Button
                NavigationLink {
                    ConnectionsPlaceholderView()
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "person.2.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                            .frame(width: 32)

                        Text("See My Receivers")
                            .font(.body)
                            .foregroundColor(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }

                // Invite Receivers Button
                Button {
                    showAddReceiver = true
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "paperplane.fill")
                            .font(.title3)
                            .foregroundColor(.green)
                            .frame(width: 32)

                        Text("Invite Receivers")
                            .font(.body)
                            .foregroundColor(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
            }

            // I received a code section
            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Did someone share their code with you?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button {
                    showReceiverCodeEntry = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard")
                            .font(.subheadline)
                        Text("I received a code")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.purple)
                }
            }

            // Sender Code Badge (Plan 4 Req 2)
            if viewModel.senderInvitationCode != nil {
                Divider()
                    .padding(.vertical, 4)

                SenderCodeBadge(code: viewModel.senderInvitationCode)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .sheet(isPresented: $showReceiverCodeEntry) {
            ReceiverCodeEntryView(authService: authService)
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(
                isExpanded: $isSettingsExpanded,
                content: {
                    VStack(spacing: 12) {
                        // Change Pruuf Time
                        Button {
                            showChangePingTime = true
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.title3)
                                    .foregroundColor(.blue)
                                    .frame(width: 32)

                                Text("Change Pruuf Time")
                                    .font(.body)
                                    .foregroundColor(.primary)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                        }

                        // Schedule a Pruuf Pause
                        Button {
                            showScheduleBreak = true
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.title3)
                                    .foregroundColor(.purple)
                                    .frame(width: 32)

                                Text("Schedule a Pruuf Pause")
                                    .font(.body)
                                    .foregroundColor(.primary)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.top, 8)
                },
                label: {
                    Text("Settings")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
            )
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Receiver Row View

struct ReceiverRowView: View {
    let connection: Connection
    let authService: AuthService
    let onConnectionUpdated: () async -> Void

    @State private var showManageSheet = false
    @State private var showHistorySheet = false
    @StateObject private var connectionManager = ConnectionManagementViewModel()

    init(connection: Connection, authService: AuthService, onConnectionUpdated: @escaping () async -> Void = {}) {
        self.connection = connection
        self.authService = authService
        self.onConnectionUpdated = onConnectionUpdated
    }

    var body: some View {
        Button {
            showManageSheet = true
        } label: {
            HStack(spacing: 12) {
                // Avatar circle
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(initials)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)

                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Options indicator
                Image(systemName: "ellipsis")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showManageSheet) {
            SenderConnectionActionsSheet(
                connection: connection,
                authService: authService,
                onPause: {
                    _ = await connectionManager.pauseConnection(connection.id)
                    await onConnectionUpdated()
                },
                onResume: {
                    _ = await connectionManager.resumeConnection(connection.id)
                    await onConnectionUpdated()
                },
                onRemove: {
                    _ = await connectionManager.removeConnection(connection.id)
                    await onConnectionUpdated()
                },
                onViewHistory: {
                    showHistorySheet = true
                }
            )
        }
        .sheet(isPresented: $showHistorySheet) {
            PingHistoryView(
                connectionId: connection.id,
                displayName: displayName,
                userId: authService.currentPruufUser?.id ?? UUID()
            )
        }
    }

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
            return .yellow
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
            return "Deleted"
        }
    }
}


// MARK: - Placeholder Views

struct SettingsPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Text("Settings - Coming Soon")
                .navigationTitle("Settings")
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

struct AddReceiverPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Text("Add Receiver - Coming Soon")
                .navigationTitle("Add Receiver")
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

struct ChangePingTimePlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Text("Change Pruuf Time - Coming Soon")
                .navigationTitle("Pruuf Time")
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

// MARK: - Sheet Height Modifier (iOS 15 Compatibility)

/// ViewModifier to handle sheet height across iOS versions
struct SheetHeightModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.presentationDetents([.height(280)])
        } else {
            content
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SenderDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        SenderDashboardView(authService: AuthService())
    }
}
#endif
