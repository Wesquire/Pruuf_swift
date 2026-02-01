import SwiftUI

// MARK: - Receiver Dashboard View

/// Main dashboard view for receivers
/// Shows senders, unique code, subscription status, and activity history
struct ReceiverDashboardView: View {
    @StateObject private var viewModel: ReceiverDashboardViewModel
    @EnvironmentObject private var authService: AuthService
    @State private var showSettings = false
    @State private var showConnectSender = false
    @State private var showManageSubscription = false
    @State private var showShareSheet = false
    @State private var showCodeInfo = false
    @State private var showNotificationCenter = false

    init(authService: AuthService) {
        _viewModel = StateObject(wrappedValue: ReceiverDashboardViewModel(authService: authService))
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

                            // Section 9.5: Subscription Status Banner on App Launch
                            // Shows "Subscription Expired" or "Payment Failed" banners
                            subscriptionStatusBanner

                            // 2. Your PRUUF Code Card
                            pruufCodeCard

                            // 3. Your Senders Section
                            sendersSection

                            // 4. Subscription Status Card
                            subscriptionStatusCard

                            // 5. Recent Activity
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
            ReceiverQuickActionsSheet(
                showConnectSender: $showConnectSender,
                showManageSubscription: $showManageSubscription,
                showSettings: $showSettings,
                shareCode: viewModel.shareCode
            )
            .modifier(ReceiverSheetHeightModifier())
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                SettingsView(authService: authService)
            }
        }
        .sheet(isPresented: $showConnectSender) {
            ConnectToSenderView(authService: authService)
        }
        .sheet(isPresented: $showManageSubscription) {
            ManageSubscriptionPlaceholderView()
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewControllerRepresentable(activityItems: [viewModel.shareCode()])
        }
        .alert("How to Use Your Code", isPresented: $showCodeInfo) {
            Button("Got it!", role: .cancel) { }
        } message: {
            Text("Share this 6-digit code with people who want to send you daily check-ins. They'll enter this code in their PRUUF app to connect with you.")
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

            // Subscription status badge
            if !viewModel.subscriptionBadgeText.isEmpty {
                Text(viewModel.subscriptionBadgeText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(viewModel.subscriptionBadgeColor)
                    .cornerRadius(12)
            }

            // Notification bell with badge
            NotificationBellButton(showNotificationCenter: $showNotificationCenter)
                .padding(.leading, 8)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel("Settings")
            .padding(.leading, 8)
        }
        .padding(.horizontal, 4)
        .sheet(isPresented: $showNotificationCenter) {
            NotificationCenterView()
        }
    }

    // MARK: - Section 9.5: Subscription Status Banner

    /// Per plan.md Section 9.5: Check subscription status on app launch
    /// - If expired -> Show "Subscription Expired" banner
    /// - If past_due -> Show "Payment Failed - Update Payment Method"
    @ViewBuilder
    private var subscriptionStatusBanner: some View {
        if let profile = viewModel.receiverProfile {
            switch profile.subscriptionStatus {
            case .expired:
                SubscriptionExpiredBannerView(
                    onSubscribe: {
                        showManageSubscription = true
                    }
                )

            case .pastDue:
                PaymentFailedBannerView(
                    gracePeriodDaysRemaining: nil, // Will be calculated from updated_at
                    onUpdatePayment: {
                        showManageSubscription = true
                    }
                )

            case .trial, .active, .canceled:
                EmptyView()
            }
        }
    }

    // MARK: - PRUUF Code Card

    private var pruufCodeCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Your PRUUF Code")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button {
                    showCodeInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                .accessibilityLabel("How to use your code")
            }

            // Large code display
            Text(viewModel.uniqueCode)
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                .kerning(8)
                .padding(.vertical, 8)

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    viewModel.copyCode()
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                            .font(.subheadline)
                        Text("Copy")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                }
                .accessibilityLabel("Copy code to clipboard")

                Button {
                    showShareSheet = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline)
                        Text("Share")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                }
                .accessibilityLabel("Share code")
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    // MARK: - Senders Section

    private var sendersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Senders")
                    .font(.headline)
                    .foregroundColor(.primary)

                if viewModel.activeSendersCount > 0 {
                    Text("\(viewModel.activeSendersCount)")
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

            if viewModel.senders.isEmpty {
                emptySendersView
            } else {
                sendersList
            }

            connectToSenderButton
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    private var emptySendersView: some View {
        NoSendersEmptyState(
            uniqueCode: viewModel.uniqueCode,
            onCopyCode: {
                viewModel.copyCode()
            },
            onShareCode: {
                showShareSheet = true
            }
        )
        .padding(.vertical, -16) // Adjust padding since it's inside a card
    }

    private var sendersList: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.senders) { sender in
                SenderCardView(
                    sender: sender,
                    authService: authService,
                    onConnectionUpdated: {
                        await viewModel.refresh()
                    }
                )
            }
        }
    }

    private var connectToSenderButton: some View {
        Button {
            showConnectSender = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Connect to Sender")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(.blue)
        }
        .padding(.top, 8)
    }

    // MARK: - Subscription Status Card

    private var subscriptionStatusCard: some View {
        Group {
            if let profile = viewModel.receiverProfile {
                switch profile.subscriptionStatus {
                case .trial:
                    trialStatusCard(profile: profile)
                case .active:
                    activeSubscriptionCard(profile: profile)
                case .pastDue, .expired:
                    expiredSubscriptionCard(profile: profile)
                case .canceled:
                    canceledSubscriptionCard(profile: profile)
                }
            }
        }
    }

    private func trialStatusCard(profile: ReceiverProfile) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "clock.fill")
                    .font(.title2)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Trial ends in \(profile.trialDaysRemaining ?? 0) day\((profile.trialDaysRemaining ?? 0) == 1 ? "" : "s")")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Subscribe to keep your peace of mind")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Button {
                showManageSubscription = true
            } label: {
                Text("Subscribe Now")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    private func activeSubscriptionCard(profile: ReceiverProfile) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("$2.99/month")
                    .font(.headline)
                    .foregroundColor(.primary)

                if let nextBilling = profile.subscriptionEndDate {
                    let formatter = DateFormatter()
                    let _ = formatter.dateFormat = "MMM d, yyyy"
                    Text("Next billing: \(formatter.string(from: nextBilling))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                showManageSubscription = true
            } label: {
                Text("Manage")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    /// Per plan.md Section 9.2: User sees "Subscribe to Continue" banner when expired
    /// Access to history remains (read-only)
    private func expiredSubscriptionCard(profile: ReceiverProfile) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(.red)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Subscribe to Continue")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Your trial has ended. Subscribe to continue receiving Pruufs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Button {
                showManageSubscription = true
            } label: {
                Text("Subscribe Now")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
        }
        .padding(16)
        .background(Color.red.opacity(0.1))
        .cornerRadius(16)
    }

    private func canceledSubscriptionCard(profile: ReceiverProfile) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Subscription canceled")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Resubscribe to continue receiving Pruufs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Button {
                showManageSubscription = true
            } label: {
                Text("Resubscribe")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .cornerRadius(12)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    // MARK: - Recent Activity Section

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                // Filter menu
                if viewModel.senders.count > 1 {
                    Menu {
                        Button {
                            viewModel.selectedSenderFilter = nil
                        } label: {
                            HStack {
                                Text("All Senders")
                                if viewModel.selectedSenderFilter == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        Divider()

                        ForEach(viewModel.senders) { sender in
                            Button {
                                viewModel.selectedSenderFilter = sender.connection.senderId
                            } label: {
                                HStack {
                                    Text(sender.senderName)
                                    if viewModel.selectedSenderFilter == sender.connection.senderId {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Filter")
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
            }

            if viewModel.filteredActivity.isEmpty {
                emptyActivityView
            } else {
                activityTimeline
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    private var emptyActivityView: some View {
        NoActivityEmptyState()
            .padding(.vertical, -16) // Adjust padding since it's inside a card
    }

    private var activityTimeline: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.filteredActivity.prefix(10)) { activity in
                ActivityTimelineRow(activity: activity)

                if activity.id != viewModel.filteredActivity.prefix(10).last?.id {
                    Divider()
                        .padding(.leading, 44)
                }
            }
        }
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

// MARK: - Sender Card View

struct SenderCardView: View {
    let sender: SenderWithPingStatus
    let authService: AuthService
    let onConnectionUpdated: () async -> Void

    @State private var showManageSheet = false
    @State private var showHistorySheet = false
    @StateObject private var connectionManager = ConnectionManagementViewModel()

    init(sender: SenderWithPingStatus, authService: AuthService, onConnectionUpdated: @escaping () async -> Void = {}) {
        self.sender = sender
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
                    .fill(sender.pingStatus.color.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(sender.initials)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(sender.pingStatus.color)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(sender.senderName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    HStack(spacing: 4) {
                        Image(systemName: sender.pingStatus.iconName)
                            .font(.caption)
                            .foregroundColor(sender.pingStatus.color)

                        Text(sender.pingStatus.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        if let countdown = sender.pingStatus.countdownString {
                            Text(countdown)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    // Ping streak
                    if sender.streak > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)

                            Text("\(sender.streak) day\(sender.streak == 1 ? "" : "s") in a row")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Options indicator
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showManageSheet) {
            ReceiverConnectionActionsSheet(
                sender: sender,
                authService: authService,
                onPauseNotifications: {
                    guard let receiverId = authService.currentPruufUser?.id else { return }
                    _ = await connectionManager.pauseNotificationsForSender(
                        sender.connection.senderId,
                        receiverId: receiverId
                    )
                },
                onResumeNotifications: {
                    guard let receiverId = authService.currentPruufUser?.id else { return }
                    _ = await connectionManager.resumeNotificationsForSender(
                        sender.connection.senderId,
                        receiverId: receiverId
                    )
                },
                onRemove: {
                    _ = await connectionManager.removeConnection(sender.connection.id)
                    await onConnectionUpdated()
                },
                onViewHistory: {
                    showHistorySheet = true
                }
            )
        }
        .sheet(isPresented: $showHistorySheet) {
            PingHistoryView(
                connectionId: sender.connection.id,
                displayName: sender.senderName,
                userId: authService.currentPruufUser?.id ?? UUID()
            )
        }
    }
}

// MARK: - Activity Timeline Row

struct ActivityTimelineRow: View {
    let activity: ActivityItem

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(activity.status == .completed ? Color.green : Color.red)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.senderName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    Text(activity.formattedTimestamp)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let method = activity.method {
                        Text("(\(method.displayName))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Text(activity.status.displayName)
                .font(.caption)
                .foregroundColor(activity.status == .completed ? .green : .red)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Receiver Quick Actions Sheet

struct ReceiverQuickActionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var showConnectSender: Bool
    @Binding var showManageSubscription: Bool
    @Binding var showSettings: Bool
    let shareCode: () -> String

    @State private var showShareSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)

            VStack(spacing: 8) {
                ReceiverQuickActionButton(
                    icon: "square.and.arrow.up",
                    title: "Share My Code",
                    color: .blue
                ) {
                    dismiss()
                    showShareSheet = true
                }

                ReceiverQuickActionButton(
                    icon: "person.badge.plus",
                    title: "Connect to Sender",
                    color: .green
                ) {
                    dismiss()
                    showConnectSender = true
                }

                ReceiverQuickActionButton(
                    icon: "creditcard",
                    title: "Manage Subscription",
                    color: .purple
                ) {
                    dismiss()
                    showManageSubscription = true
                }

                ReceiverQuickActionButton(
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
        .sheet(isPresented: $showShareSheet) {
            ActivityViewControllerRepresentable(activityItems: [shareCode()])
        }
    }
}

struct ReceiverQuickActionButton: View {
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

struct ReceiverSettingsPlaceholderView: View {
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

struct ConnectToSenderPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Text("Connect to Sender - Coming Soon")
                .navigationTitle("Connect")
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

struct ManageSubscriptionPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Text("Manage Subscription - Coming Soon")
                .navigationTitle("Subscription")
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

// MARK: - Activity View Controller

struct ActivityViewControllerRepresentable: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Sheet Height Modifier (iOS 15 Compatibility)

struct ReceiverSheetHeightModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.presentationDetents([.height(300)])
        } else {
            content
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ReceiverDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        ReceiverDashboardView(authService: AuthService())
    }
}
#endif
