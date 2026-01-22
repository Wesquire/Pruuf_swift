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

                            // 3. In-Person Verification Button
                            inPersonVerificationButton

                            // 4. Your Receivers Section
                            receiversSection

                            // 5. Recent Activity (7-day calendar)
                            recentActivitySection

                            // 6. Quick Actions
                            quickActionsButton
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
        .sheet(isPresented: $viewModel.showQuickActions) {
            QuickActionsSheet(
                showScheduleBreak: $showScheduleBreak,
                showChangePingTime: $showChangePingTime,
                showAddReceiver: $showAddReceiver,
                showSettings: $showSettings
            )
            .modifier(SheetHeightModifier())
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                SettingsView(authService: authService)
            }
        }
        .sheet(isPresented: $showAddReceiver) {
            AddConnectionView(authService: authService)
        }
        .sheet(isPresented: $showScheduleBreak) {
            ScheduleBreakView(authService: authService)
        }
        .sheet(isPresented: $showChangePingTime) {
            ChangePingTimePlaceholderView()
        }
        .alert("Enable Location", isPresented: $viewModel.showLocationPermissionAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Enable") {
                viewModel.requestLocationPermission()
            }
        } message: {
            Text("Location access is needed to verify your in-person check-in. This helps provide extra peace of mind to your receivers.")
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
            Text("Are you sure you want to end your break early? Your receivers will be notified, and you'll need to send your daily ping starting today.")
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

            Text("Time to Ping!")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            if !viewModel.countdownString.isEmpty {
                Text(viewModel.countdownString)
                    .font(.headline)
                    .foregroundColor(.orange)
            }

            Button {
                Task {
                    await viewModel.completePing()
                }
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("I'm Okay")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue)
                .cornerRadius(12)
            }
            .disabled(viewModel.isLoading)
            .accessibilityLabel("Tap to confirm you're okay")

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

            Text("Ping Sent!")
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

            Text("Ping Missed")
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
                Task {
                    await viewModel.completePingLate()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise.circle.fill")
                    Text("Ping Now")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.orange)
                .cornerRadius(12)
            }
            .disabled(viewModel.isLoading)
            .accessibilityLabel("Send a late ping")
        }
    }

    private var onBreakContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("On Break")
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
                Task {
                    await viewModel.completePingVoluntary()
                }
            } label: {
                HStack {
                    Image(systemName: "hand.tap.fill")
                    Text("Ping Anyway (Optional)")
                }
                .font(.subheadline)
                .foregroundColor(.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(10)
            }
            .disabled(viewModel.isLoading)
            .accessibilityLabel("Send a voluntary ping while on break")

            Button {
                showEndBreakConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                    Text("End Break Early")
                }
                .font(.headline)
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
            .disabled(viewModel.isLoading)
            .accessibilityLabel("End break early and resume pings")

            Text("You can ping voluntarily without ending your break")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - In-Person Verification Button

    private var inPersonVerificationButton: some View {
        Button {
            Task {
                await viewModel.completePingInPerson()
            }
        } label: {
            HStack(spacing: 12) {
                if viewModel.isCapturingLocation {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Image(systemName: "location.fill")
                        .font(.headline)
                }

                Text(viewModel.isCapturingLocation ? "Getting Location..." : "Verify In Person")
                    .font(.headline)
            }
            .foregroundColor(.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
        .disabled(viewModel.isLoading || viewModel.isCapturingLocation || viewModel.todayPingState == .completed)
        .opacity(viewModel.todayPingState == .completed ? 0.5 : 1.0)
        .accessibilityLabel("Verify in person with location")
    }

    // MARK: - Receivers Section

    private var receiversSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            if viewModel.receivers.isEmpty {
                emptyReceiversView
            } else {
                receiversList
            }

            addReceiverButton
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    private var emptyReceiversView: some View {
        NoReceiversEmptyState {
            showAddReceiver = true
        }
        .padding(.vertical, -16) // Adjust padding since it's inside a card
    }

    private var receiversList: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.receivers.prefix(3), id: \.id) { connection in
                ReceiverRowView(
                    connection: connection,
                    authService: authService,
                    onConnectionUpdated: {
                        await viewModel.refresh()
                    }
                )
            }

            if viewModel.receivers.count > 3 {
                Text("+ \(viewModel.receivers.count - 3) more")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private var addReceiverButton: some View {
        Button {
            showAddReceiver = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add Receiver")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(.blue)
        }
        .padding(.top, 8)
    }

    // MARK: - Recent Activity Section

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
                .foregroundColor(.primary)

            if viewModel.pingHistory.isEmpty {
                NoActivityEmptyState()
                    .padding(.vertical, -16) // Adjust padding since it's inside a card
            } else {
                PingHistoryCalendarView(history: viewModel.pingHistory)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    // MARK: - Quick Actions Button

    private var quickActionsButton: some View {
        Button {
            viewModel.showQuickActions = true
        } label: {
            HStack {
                Image(systemName: "ellipsis.circle.fill")
                Text("Quick Actions")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(.secondary)
        }
        .padding(.top, 8)
        .accessibilityLabel("Open quick actions menu")
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

// MARK: - Ping History Calendar View

struct PingHistoryCalendarView: View {
    let history: [DayPingStatus]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(history) { day in
                DayDotView(day: day)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct DayDotView: View {
    let day: DayPingStatus
    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail.toggle()
        } label: {
            VStack(spacing: 6) {
                Text(day.dayAbbreviation)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Circle()
                    .fill(day.dotColor)
                    .frame(width: 12, height: 12)

                Text(day.dayNumber)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .popover(isPresented: $showDetail) {
            VStack(spacing: 8) {
                Text(formattedDate)
                    .font(.headline)

                Text(day.status.displayName)
                    .font(.subheadline)
                    .foregroundColor(day.dotColor)
            }
            .padding()
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: day.date)
    }
}

// MARK: - Quick Actions Sheet

struct QuickActionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var showScheduleBreak: Bool
    @Binding var showChangePingTime: Bool
    @Binding var showAddReceiver: Bool
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)

            VStack(spacing: 8) {
                QuickActionButton(
                    icon: "calendar.badge.plus",
                    title: "Schedule a Break",
                    color: .purple
                ) {
                    dismiss()
                    showScheduleBreak = true
                }

                QuickActionButton(
                    icon: "clock.arrow.circlepath",
                    title: "Change Ping Time",
                    color: .blue
                ) {
                    dismiss()
                    showChangePingTime = true
                }

                QuickActionButton(
                    icon: "person.badge.plus",
                    title: "Invite Receivers",
                    color: .green
                ) {
                    dismiss()
                    showAddReceiver = true
                }

                QuickActionButton(
                    icon: "gearshape",
                    title: "Settings",
                    color: .gray
                ) {
                    dismiss()
                    showSettings = true
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                    .frame(width: 32)

                Text(title)
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
            Text("Change Ping Time - Coming Soon")
                .navigationTitle("Ping Time")
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
