import SwiftUI
import Charts

// MARK: - Admin Dashboard Main View

/// Main admin dashboard view with navigation to all admin features
/// Requires iOS 16+ for Charts and NavigationStack
@available(iOS 16.0, *)
public struct AdminDashboardView: View {
    @StateObject private var adminService = AdminService.shared
    @State private var selectedSection: AdminSection = .overview
    @State private var showingError = false

    public var body: some View {
        NavigationStack {
            Group {
                if adminService.isLoading && adminService.userMetrics == nil {
                    ProgressView("Loading dashboard...")
                } else {
                    TabView(selection: $selectedSection) {
                        AdminOverviewSection()
                            .tabItem {
                                Label("Overview", systemImage: "chart.pie.fill")
                            }
                            .tag(AdminSection.overview)

                        AdminUserManagementSection()
                            .tabItem {
                                Label("Users", systemImage: "person.3.fill")
                            }
                            .tag(AdminSection.users)

                        AdminConnectionsSection()
                            .tabItem {
                                Label("Connections", systemImage: "link")
                            }
                            .tag(AdminSection.connections)

                        AdminPingsSection()
                            .tabItem {
                                Label("Pings", systemImage: "bell.fill")
                            }
                            .tag(AdminSection.pings)

                        AdminSubscriptionsSection()
                            .tabItem {
                                Label("Revenue", systemImage: "dollarsign.circle.fill")
                            }
                            .tag(AdminSection.subscriptions)

                        AdminSystemHealthSection()
                            .tabItem {
                                Label("Health", systemImage: "heart.text.square.fill")
                            }
                            .tag(AdminSection.systemHealth)

                        AdminOperationsSection()
                            .tabItem {
                                Label("Ops", systemImage: "gearshape.2.fill")
                            }
                            .tag(AdminSection.operations)
                    }
                }
            }
            .navigationTitle("Admin Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await refreshAllData()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(adminService.error?.localizedDescription ?? "An error occurred")
            }
            .task {
                await refreshAllData()
            }
        }
    }

    private func refreshAllData() async {
        do {
            try await adminService.fetchUserMetrics()
            try await adminService.fetchConnectionAnalytics()
            try await adminService.fetchPingAnalytics()
            try await adminService.fetchSubscriptionMetrics()
            try await adminService.fetchSystemHealth()
        } catch {
            adminService.error = error
            showingError = true
        }
    }
}

enum AdminSection: String, CaseIterable {
    case overview
    case users
    case connections
    case pings
    case subscriptions
    case systemHealth
    case operations
}

// MARK: - Overview Section

@available(iOS 16.0, *)
struct AdminOverviewSection: View {
    @ObservedObject private var adminService = AdminService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Quick Stats Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    QuickStatCard(
                        title: "Total Users",
                        value: "\(adminService.userMetrics?.totalUsers ?? 0)",
                        icon: "person.3.fill",
                        color: .blue
                    )

                    QuickStatCard(
                        title: "Active (7d)",
                        value: "\(adminService.userMetrics?.activeUsersLast7Days ?? 0)",
                        icon: "person.fill.checkmark",
                        color: .green
                    )

                    QuickStatCard(
                        title: "Active Connections",
                        value: "\(adminService.connectionAnalytics?.activeConnections ?? 0)",
                        icon: "link",
                        color: .purple
                    )

                    QuickStatCard(
                        title: "MRR",
                        value: formatCurrency(adminService.subscriptionMetrics?.monthlyRecurringRevenue ?? 0),
                        icon: "dollarsign.circle.fill",
                        color: .orange
                    )

                    QuickStatCard(
                        title: "Pings Today",
                        value: "\(adminService.pingAnalytics?.totalPingsToday ?? 0)",
                        icon: "bell.fill",
                        color: .cyan
                    )

                    QuickStatCard(
                        title: "System Health",
                        value: adminService.systemHealth?.healthStatus ?? "Unknown",
                        icon: healthStatusIcon,
                        color: healthStatusColor
                    )
                }
                .padding(.horizontal)

                // Ping Completion Chart
                if let pingAnalytics = adminService.pingAnalytics {
                    AdminChartCard(title: "Ping Completion Rates") {
                        if #available(iOS 17.0, *) {
                            PingCompletionPieChart(analytics: pingAnalytics)
                                .frame(height: 200)
                        } else {
                            Text("Pie chart requires iOS 17+")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Subscription Status
                if let subMetrics = adminService.subscriptionMetrics {
                    AdminChartCard(title: "Subscription Status") {
                        SubscriptionStatusChart(metrics: subMetrics)
                            .frame(height: 200)
                    }
                }
            }
            .padding(.vertical)
        }
    }

    private var healthStatusIcon: String {
        switch adminService.systemHealth?.healthStatus {
        case "healthy": return "checkmark.circle.fill"
        case "degraded": return "exclamationmark.triangle.fill"
        case "critical": return "xmark.circle.fill"
        default: return "questionmark.circle.fill"
        }
    }

    private var healthStatusColor: Color {
        switch adminService.systemHealth?.healthStatus {
        case "healthy": return .green
        case "degraded": return .orange
        case "critical": return .red
        default: return .gray
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}

// MARK: - User Management Section

@available(iOS 16.0, *)
struct AdminUserManagementSection: View {
    @ObservedObject private var adminService = AdminService.shared
    @State private var searchText = ""
    @State private var selectedUser: UserDetails?
    @State private var showingUserDetail = false
    @State private var showingDeactivateAlert = false
    @State private var deactivationReason = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // User Metrics Summary
                if let metrics = adminService.userMetrics {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            MetricPill(label: "Total", value: "\(metrics.totalUsers)", color: .blue)
                            MetricPill(label: "Active (7d)", value: "\(metrics.activeUsersLast7Days)", color: .green)
                            MetricPill(label: "Active (30d)", value: "\(metrics.activeUsersLast30Days)", color: .teal)
                            MetricPill(label: "Today", value: "+\(metrics.newSignupsToday)", color: .orange)
                            MetricPill(label: "This Week", value: "+\(metrics.newSignupsThisWeek)", color: .purple)
                            MetricPill(label: "This Month", value: "+\(metrics.newSignupsThisMonth)", color: .pink)
                        }
                        .padding(.horizontal)
                    }
                }

                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search by phone number", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            Task {
                                try? await adminService.searchUsersByPhone(searchText)
                            }
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            adminService.searchedUsers = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)

                // Search Results / User List
                List {
                    if !adminService.searchedUsers.isEmpty {
                        Section("Search Results") {
                            ForEach(adminService.searchedUsers) { user in
                                UserListRow(user: user)
                                    .onTapGesture {
                                        selectedUser = user
                                        showingUserDetail = true
                                    }
                            }
                        }
                    } else if searchText.isEmpty {
                        Section("User Breakdown") {
                            if let metrics = adminService.userMetrics {
                                UserBreakdownRow(label: "Senders", count: metrics.senderCount, icon: "arrow.up.circle.fill", color: .blue)
                                UserBreakdownRow(label: "Receivers", count: metrics.receiverCount, icon: "arrow.down.circle.fill", color: .green)
                                UserBreakdownRow(label: "Both Roles", count: metrics.bothRoleCount, icon: "arrow.up.arrow.down.circle.fill", color: .purple)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("User Management")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingUserDetail) {
                if let user = selectedUser {
                    UserDetailSheet(user: user)
                }
            }
        }
    }
}

@available(iOS 16.0, *)
struct UserListRow: View {
    let user: UserDetails

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(user.phoneNumber)
                    .font(.headline)
                Text(user.primaryRole ?? "No role")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(
                    text: user.isActive ? "Active" : "Inactive",
                    color: user.isActive ? .green : .red
                )
                if let status = user.subscriptionStatus {
                    StatusBadge(
                        text: status.capitalized,
                        color: subscriptionStatusColor(status)
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func subscriptionStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "active": return .green
        case "trial": return .blue
        case "past_due": return .orange
        case "canceled", "expired": return .red
        default: return .gray
        }
    }
}

@available(iOS 16.0, *)
struct UserBreakdownRow: View {
    let label: String
    let count: Int
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)
            Text(label)
            Spacer()
            Text("\(count)")
                .font(.headline)
                .foregroundColor(color)
        }
    }
}

@available(iOS 16.0, *)
struct UserDetailSheet: View {
    let user: UserDetails
    @ObservedObject private var adminService = AdminService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeactivateAlert = false
    @State private var showingSubscriptionSheet = false
    @State private var showingImpersonateAlert = false
    @State private var deactivationReason = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Basic Info") {
                    LabeledContent("Phone", value: user.phoneNumber)
                    LabeledContent("Country Code", value: user.phoneCountryCode)
                    LabeledContent("Role", value: user.primaryRole ?? "None")
                    LabeledContent("Timezone", value: user.timezone)
                    LabeledContent("Onboarding", value: user.hasCompletedOnboarding ? "Complete" : "Incomplete")
                }

                Section("Activity") {
                    LabeledContent("Created", value: user.createdAt.formatted())
                    if let lastSeen = user.lastSeenAt {
                        LabeledContent("Last Seen", value: lastSeen.formatted())
                    }
                    LabeledContent("Connections", value: "\(user.connectionCount)")
                    LabeledContent("Total Pings", value: "\(user.pingCount)")
                    LabeledContent("Completion Rate", value: String(format: "%.1f%%", user.completionRate * 100))
                }

                if let status = user.subscriptionStatus {
                    Section("Subscription") {
                        LabeledContent("Status", value: status.capitalized)
                        if let trialEnd = user.trialEndDate {
                            LabeledContent("Trial Ends", value: trialEnd.formatted())
                        }
                    }
                }

                Section("Actions") {
                    Button {
                        showingImpersonateAlert = true
                    } label: {
                        Label("Impersonate User", systemImage: "person.fill.viewfinder")
                    }

                    Button {
                        showingSubscriptionSheet = true
                    } label: {
                        Label("Update Subscription", systemImage: "creditcard.fill")
                    }

                    Button(role: user.isActive ? .destructive : .none) {
                        if user.isActive {
                            showingDeactivateAlert = true
                        } else {
                            Task {
                                try? await adminService.reactivateUser(userId: user.id)
                                dismiss()
                            }
                        }
                    } label: {
                        Label(
                            user.isActive ? "Deactivate Account" : "Reactivate Account",
                            systemImage: user.isActive ? "xmark.circle.fill" : "checkmark.circle.fill"
                        )
                    }
                }
            }
            .navigationTitle("User Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Deactivate User", isPresented: $showingDeactivateAlert) {
                TextField("Reason", text: $deactivationReason)
                Button("Cancel", role: .cancel) {}
                Button("Deactivate", role: .destructive) {
                    Task {
                        try? await adminService.deactivateUser(userId: user.id, reason: deactivationReason)
                        dismiss()
                    }
                }
            } message: {
                Text("Enter a reason for deactivating this account.")
            }
            .alert("Impersonate User", isPresented: $showingImpersonateAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Impersonate") {
                    Task {
                        let session = try? await adminService.impersonateUser(userId: user.id)
                        // Handle impersonation session
                        print("Impersonation session: \(String(describing: session))")
                    }
                }
            } message: {
                Text("This will create a temporary session as this user for debugging purposes. All actions will be logged.")
            }
            .sheet(isPresented: $showingSubscriptionSheet) {
                SubscriptionUpdateSheet(user: user)
            }
        }
    }
}

@available(iOS 16.0, *)
struct SubscriptionUpdateSheet: View {
    let user: UserDetails
    @ObservedObject private var adminService = AdminService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStatus = "active"
    @State private var endDate = Date().addingTimeInterval(30 * 24 * 60 * 60)

    let statusOptions = ["trial", "active", "past_due", "canceled", "expired"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Status") {
                    LabeledContent("Status", value: user.subscriptionStatus ?? "None")
                }

                Section("Update To") {
                    Picker("New Status", selection: $selectedStatus) {
                        ForEach(statusOptions, id: \.self) { status in
                            Text(status.capitalized).tag(status)
                        }
                    }

                    if selectedStatus == "active" || selectedStatus == "trial" {
                        DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Update Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            try? await adminService.updateUserSubscription(
                                userId: user.id,
                                status: selectedStatus,
                                endDate: selectedStatus == "active" || selectedStatus == "trial" ? endDate : nil
                            )
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Connections Section

@available(iOS 16.0, *)
struct AdminConnectionsSection: View {
    @ObservedObject private var adminService = AdminService.shared
    @State private var connectionGrowth: [ConnectionGrowthPoint] = []
    @State private var topUsers: [TopUserByConnections] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Connection Stats
                if let analytics = adminService.connectionAnalytics {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        QuickStatCard(
                            title: "Total",
                            value: "\(analytics.totalConnections)",
                            icon: "link",
                            color: .blue
                        )
                        QuickStatCard(
                            title: "Active",
                            value: "\(analytics.activeConnections)",
                            icon: "link.circle.fill",
                            color: .green
                        )
                        QuickStatCard(
                            title: "Paused",
                            value: "\(analytics.pausedConnections)",
                            icon: "pause.circle.fill",
                            color: .orange
                        )
                        QuickStatCard(
                            title: "Avg/User",
                            value: String(format: "%.1f", analytics.averageConnectionsPerUser),
                            icon: "person.fill",
                            color: .purple
                        )
                    }
                    .padding(.horizontal)

                    // Growth Stats
                    HStack(spacing: 16) {
                        GrowthCard(
                            title: "This Month",
                            value: analytics.connectionGrowthThisMonth,
                            percentage: analytics.growthPercentage
                        )
                        GrowthCard(
                            title: "Last Month",
                            value: analytics.connectionGrowthLastMonth,
                            percentage: nil
                        )
                    }
                    .padding(.horizontal)
                }

                // Connection Growth Chart
                if !connectionGrowth.isEmpty {
                    AdminChartCard(title: "Connection Growth (30 Days)") {
                        ConnectionGrowthChart(data: connectionGrowth)
                            .frame(height: 200)
                    }
                }

                // Top Users by Connection Count
                if !topUsers.isEmpty {
                    AdminChartCard(title: "Top Users by Connections") {
                        VStack(spacing: 8) {
                            ForEach(topUsers.prefix(10)) { user in
                                HStack {
                                    Text(user.phoneNumber)
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(user.connectionCount)")
                                        .font(.headline)
                                        .foregroundColor(.blue)
                                }
                                .padding(.horizontal)
                                Divider()
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(.vertical)
        }
        .task {
            do {
                connectionGrowth = try await adminService.getConnectionGrowth(days: 30)
                topUsers = try await adminService.getTopUsersByConnections(limit: 10)
            } catch {
                print("Error loading connection data: \(error)")
            }
        }
    }
}

// MARK: - Pings Section

@available(iOS 16.0, *)
struct AdminPingsSection: View {
    @ObservedObject private var adminService = AdminService.shared
    @State private var streakDistribution: [StreakDistribution] = []
    @State private var missedAlerts: [MissedPingAlert] = []
    @State private var breakStats: BreakUsageStats?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Ping Stats
                if let analytics = adminService.pingAnalytics {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        CompactStatCard(title: "Today", value: "\(analytics.totalPingsToday)", color: .blue)
                        CompactStatCard(title: "This Week", value: "\(analytics.totalPingsThisWeek)", color: .green)
                        CompactStatCard(title: "This Month", value: "\(analytics.totalPingsThisMonth)", color: .purple)
                    }
                    .padding(.horizontal)

                    // Completion Rates
                    AdminChartCard(title: "Completion Rates") {
                        VStack(spacing: 12) {
                            CompletionRateRow(
                                label: "On Time",
                                count: analytics.onTimeCount,
                                percentage: analytics.completionRateOnTime,
                                color: .green
                            )
                            CompletionRateRow(
                                label: "Late",
                                count: analytics.lateCount,
                                percentage: analytics.completionRateLate,
                                color: .orange
                            )
                            CompletionRateRow(
                                label: "Missed",
                                count: analytics.missedCount,
                                percentage: analytics.missedRate,
                                color: .red
                            )
                            CompletionRateRow(
                                label: "On Break",
                                count: analytics.onBreakCount,
                                percentage: 0,
                                color: .gray
                            )
                        }
                        .padding()
                    }

                    // Additional Metrics
                    HStack(spacing: 16) {
                        MetricCard(
                            title: "Avg Completion Time",
                            value: String(format: "%.0f min", analytics.averageCompletionTimeMinutes),
                            icon: "clock.fill"
                        )
                        MetricCard(
                            title: "Longest Streak",
                            value: "\(analytics.longestStreak) days",
                            icon: "flame.fill"
                        )
                        MetricCard(
                            title: "Avg Streak",
                            value: String(format: "%.1f days", analytics.averageStreak),
                            icon: "chart.line.uptrend.xyaxis"
                        )
                    }
                    .padding(.horizontal)
                }

                // Streak Distribution
                if !streakDistribution.isEmpty {
                    AdminChartCard(title: "Streak Distribution") {
                        StreakDistributionChart(data: streakDistribution)
                            .frame(height: 200)
                    }
                }

                // Missed Ping Alerts
                if !missedAlerts.isEmpty {
                    AdminChartCard(title: "Recent Missed Pings") {
                        VStack(spacing: 8) {
                            ForEach(missedAlerts.prefix(10)) { alert in
                                MissedPingAlertRow(alert: alert)
                                Divider()
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                // Break Usage
                if let breaks = breakStats {
                    AdminChartCard(title: "Break Usage Statistics") {
                        VStack(spacing: 12) {
                            LabeledContent("Active Breaks", value: "\(breaks.activeBreaks)")
                            LabeledContent("Scheduled Breaks", value: "\(breaks.scheduledBreaks)")
                            LabeledContent("Completed This Month", value: "\(breaks.completedBreaksThisMonth)")
                            LabeledContent("Avg Duration", value: String(format: "%.1f days", breaks.averageBreakDurationDays))
                            LabeledContent("Users on Break", value: "\(breaks.usersWithActiveBreaks)")
                        }
                        .padding()
                    }
                }
            }
            .padding(.vertical)
        }
        .task {
            do {
                streakDistribution = try await adminService.getPingStreaksDistribution()
                missedAlerts = try await adminService.getMissedPingAlerts(limit: 50)
                breakStats = try await adminService.getBreakUsageStats()
            } catch {
                print("Error loading ping data: \(error)")
            }
        }
    }
}

@available(iOS 16.0, *)
struct CompletionRateRow: View {
    let label: String
    let count: Int
    let percentage: Double
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
            Spacer()
            Text("\(count)")
                .font(.headline)
            Text(String(format: "(%.1f%%)", percentage * 100))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

@available(iOS 16.0, *)
struct MissedPingAlertRow: View {
    let alert: MissedPingAlert

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(alert.senderPhone)
                    .font(.headline)
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                Text(alert.receiverPhone)
                    .font(.headline)
            }
            HStack {
                Text("Missed at: \(alert.missedAt.formatted())")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if alert.consecutiveMisses > 1 {
                    Text("\(alert.consecutiveMisses) in a row")
                        .font(.caption)
                        .foregroundColor(.red)
                        .fontWeight(.bold)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Subscriptions Section

@available(iOS 16.0, *)
struct AdminSubscriptionsSection: View {
    @ObservedObject private var adminService = AdminService.shared
    @State private var paymentFailures: [PaymentFailure] = []
    @State private var refunds: [RefundChargeback] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Revenue Metrics
                if let metrics = adminService.subscriptionMetrics {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        RevenueCard(
                            title: "MRR",
                            value: metrics.monthlyRecurringRevenue,
                            icon: "dollarsign.circle.fill",
                            color: .green
                        )
                        RevenueCard(
                            title: "ARPU",
                            value: metrics.averageRevenuePerUser,
                            icon: "person.fill",
                            color: .blue
                        )
                        RevenueCard(
                            title: "LTV",
                            value: metrics.lifetimeValue,
                            icon: "chart.line.uptrend.xyaxis",
                            color: .purple
                        )
                    }
                    .padding(.horizontal)

                    // Subscription Status Breakdown
                    AdminChartCard(title: "Subscription Status") {
                        VStack(spacing: 12) {
                            SubscriptionStatusRow(label: "Active", count: metrics.activeSubscriptions, color: .green)
                            SubscriptionStatusRow(label: "Trial", count: metrics.trialUsers, color: .blue)
                            SubscriptionStatusRow(label: "Past Due", count: metrics.pastDueSubscriptions, color: .orange)
                            SubscriptionStatusRow(label: "Canceled", count: metrics.canceledSubscriptions, color: .red)
                            SubscriptionStatusRow(label: "Expired", count: metrics.expiredSubscriptions, color: .gray)
                        }
                        .padding()
                    }

                    // Conversion & Churn
                    HStack(spacing: 16) {
                        PercentageCard(
                            title: "Trial Conversion",
                            percentage: metrics.trialConversionRate,
                            isGood: metrics.trialConversionRate > 0.1
                        )
                        PercentageCard(
                            title: "Churn Rate",
                            percentage: metrics.churnRate,
                            isGood: metrics.churnRate < 0.05
                        )
                    }
                    .padding(.horizontal)

                    // Issues This Month
                    AdminChartCard(title: "Issues This Month") {
                        VStack(spacing: 12) {
                            LabeledContent("Payment Failures") {
                                Text("\(metrics.paymentFailuresThisMonth)")
                                    .foregroundColor(metrics.paymentFailuresThisMonth > 0 ? .red : .green)
                            }
                            LabeledContent("Refunds") {
                                Text("\(metrics.refundsThisMonth)")
                                    .foregroundColor(metrics.refundsThisMonth > 0 ? .orange : .green)
                            }
                            LabeledContent("Chargebacks") {
                                Text("\(metrics.chargebacksThisMonth)")
                                    .foregroundColor(metrics.chargebacksThisMonth > 0 ? .red : .green)
                            }
                        }
                        .padding()
                    }
                }

                // Payment Failures List
                if !paymentFailures.isEmpty {
                    AdminChartCard(title: "Recent Payment Failures") {
                        VStack(spacing: 8) {
                            ForEach(paymentFailures.prefix(10)) { failure in
                                PaymentFailureRow(failure: failure)
                                Divider()
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                // Refunds & Chargebacks List
                if !refunds.isEmpty {
                    AdminChartCard(title: "Recent Refunds & Chargebacks") {
                        VStack(spacing: 8) {
                            ForEach(refunds.prefix(10)) { refund in
                                RefundRow(refund: refund)
                                Divider()
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(.vertical)
        }
        .task {
            do {
                paymentFailures = try await adminService.getPaymentFailures(limit: 50)
                refunds = try await adminService.getRefundsAndChargebacks(limit: 50)
            } catch {
                print("Error loading subscription data: \(error)")
            }
        }
    }
}

@available(iOS 16.0, *)
struct SubscriptionStatusRow: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
            Spacer()
            Text("\(count)")
                .font(.headline)
        }
    }
}

@available(iOS 16.0, *)
struct PaymentFailureRow: View {
    let failure: PaymentFailure

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(failure.phoneNumber)
                    .font(.headline)
                Spacer()
                Text(formatCurrency(failure.amount))
                    .foregroundColor(.red)
            }
            Text(failure.failureReason)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                Text(failure.failedAt.formatted())
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if failure.retryCount > 0 {
                    Text("Retries: \(failure.retryCount)")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.horizontal)
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}

@available(iOS 16.0, *)
struct RefundRow: View {
    let refund: RefundChargeback

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(refund.phoneNumber)
                    .font(.headline)
                Spacer()
                StatusBadge(
                    text: refund.type.capitalized,
                    color: refund.type == "chargeback" ? .red : .orange
                )
            }
            Text(refund.reason)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                Text(formatCurrency(refund.amount))
                    .font(.subheadline)
                    .foregroundColor(.red)
                Spacer()
                Text(refund.processedAt.formatted())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}

// MARK: - System Health Section

@available(iOS 16.0, *)
struct AdminSystemHealthSection: View {
    @ObservedObject private var adminService = AdminService.shared
    @State private var edgeFunctionMetrics: [EdgeFunctionMetric] = []
    @State private var cronJobStats: [CronJobStat] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Overall Health Status
                if let health = adminService.systemHealth {
                    HealthStatusBanner(health: health)
                        .padding(.horizontal)

                    // Key Metrics
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        HealthMetricCard(
                            title: "DB Pool Usage",
                            value: String(format: "%.1f%%", health.databaseConnectionPoolUsage * 100),
                            status: health.databaseConnectionPoolUsage < 0.8 ? .good : .warning
                        )
                        HealthMetricCard(
                            title: "Avg Query Time",
                            value: String(format: "%.0f ms", health.averageQueryTimeMs),
                            status: health.averageQueryTimeMs < 100 ? .good : .warning
                        )
                        HealthMetricCard(
                            title: "API Error Rate",
                            value: String(format: "%.2f%%", health.apiErrorRateLast24h * 100),
                            status: health.apiErrorRateLast24h < 0.01 ? .good : .critical
                        )
                        HealthMetricCard(
                            title: "Push Delivery",
                            value: String(format: "%.1f%%", health.pushNotificationDeliveryRate * 100),
                            status: health.pushNotificationDeliveryRate > 0.95 ? .good : .warning
                        )
                        HealthMetricCard(
                            title: "Cron Success",
                            value: String(format: "%.1f%%", health.cronJobSuccessRate * 100),
                            status: health.cronJobSuccessRate > 0.99 ? .good : .warning
                        )
                        HealthMetricCard(
                            title: "Storage",
                            value: health.storageUsageFormatted,
                            status: .good
                        )
                    }
                    .padding(.horizontal)

                    // Additional Info
                    AdminChartCard(title: "System Info") {
                        VStack(spacing: 12) {
                            LabeledContent("Active Sessions", value: "\(health.activeUserSessions)")
                            LabeledContent("Pending Pings", value: "\(health.pendingPings)")
                        }
                        .padding()
                    }
                }

                // Edge Function Metrics
                if !edgeFunctionMetrics.isEmpty {
                    AdminChartCard(title: "Edge Function Performance") {
                        VStack(spacing: 8) {
                            ForEach(edgeFunctionMetrics) { metric in
                                EdgeFunctionRow(metric: metric)
                                Divider()
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                // Cron Job Stats
                if !cronJobStats.isEmpty {
                    AdminChartCard(title: "Cron Job Status") {
                        VStack(spacing: 8) {
                            ForEach(cronJobStats) { stat in
                                CronJobRow(stat: stat)
                                Divider()
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(.vertical)
        }
        .task {
            do {
                edgeFunctionMetrics = try await adminService.getEdgeFunctionMetrics()
                cronJobStats = try await adminService.getCronJobStats()
            } catch {
                print("Error loading system health data: \(error)")
            }
        }
    }
}

@available(iOS 16.0, *)
struct HealthStatusBanner: View {
    let health: SystemHealth

    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .font(.title)
                .foregroundColor(statusColor)
            VStack(alignment: .leading) {
                Text("System Status")
                    .font(.headline)
                Text(health.healthStatus.capitalized)
                    .font(.subheadline)
                    .foregroundColor(statusColor)
            }
            Spacer()
        }
        .padding()
        .background(statusColor.opacity(0.1))
        .cornerRadius(12)
    }

    private var statusIcon: String {
        switch health.healthStatus {
        case "healthy": return "checkmark.shield.fill"
        case "degraded": return "exclamationmark.shield.fill"
        case "critical": return "xmark.shield.fill"
        default: return "questionmark.shield.fill"
        }
    }

    private var statusColor: Color {
        switch health.healthStatus {
        case "healthy": return .green
        case "degraded": return .orange
        case "critical": return .red
        default: return .gray
        }
    }
}

enum HealthStatus {
    case good, warning, critical
}

@available(iOS 16.0, *)
struct HealthMetricCard: View {
    let title: String
    let value: String
    let status: HealthStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var statusColor: Color {
        switch status {
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

@available(iOS 16.0, *)
struct EdgeFunctionRow: View {
    let metric: EdgeFunctionMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(metric.functionName)
                    .font(.headline)
                Spacer()
                Text("\(metric.invocationsLast24h) calls")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack {
                Text(String(format: "Avg: %.0f ms", metric.averageExecutionTimeMs))
                    .font(.caption)
                Text("P95: \(String(format: "%.0f ms", metric.p95ExecutionTimeMs))")
                    .font(.caption)
                Spacer()
                Text(String(format: "%.2f%% errors", metric.errorRate * 100))
                    .font(.caption)
                    .foregroundColor(metric.errorRate > 0.01 ? .red : .green)
            }
            .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
}

@available(iOS 16.0, *)
struct CronJobRow: View {
    let stat: CronJobStat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stat.jobName)
                    .font(.headline)
                Spacer()
                StatusBadge(
                    text: stat.lastRunStatus.capitalized,
                    color: stat.lastRunStatus == "success" ? .green : .red
                )
            }
            HStack {
                if let lastRun = stat.lastRunAt {
                    Text("Last: \(lastRun.formatted())")
                        .font(.caption)
                }
                Spacer()
                Text("\(stat.successCount)/\(stat.successCount + stat.failureCount) success")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
}

// MARK: - Operations Section

@available(iOS 16.0, *)
struct AdminOperationsSection: View {
    @ObservedObject private var adminService = AdminService.shared
    @State private var auditLogs: [AuditLogEntry] = []
    @State private var showingManualPing = false
    @State private var showingTestNotification = false
    @State private var showingCancelSubscription = false
    @State private var showingRefund = false
    @State private var showingExport = false

    // Form states
    @State private var targetUserId = ""
    @State private var connectionId = ""
    @State private var notificationTitle = ""
    @State private var notificationBody = ""
    @State private var cancellationReason = ""
    @State private var refundTransactionId = ""
    @State private var refundAmount = ""
    @State private var refundReason = ""
    @State private var selectedReportType: ReportType = .users
    @State private var selectedExportFormat: ExportFormat = .csv

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Quick Actions
                AdminChartCard(title: "Operations") {
                    VStack(spacing: 12) {
                        OperationButton(
                            title: "Generate Manual Ping",
                            icon: "bell.badge.fill",
                            color: .blue
                        ) {
                            showingManualPing = true
                        }

                        OperationButton(
                            title: "Send Test Notification",
                            icon: "paperplane.fill",
                            color: .green
                        ) {
                            showingTestNotification = true
                        }

                        OperationButton(
                            title: "Cancel Subscription",
                            icon: "xmark.circle.fill",
                            color: .orange
                        ) {
                            showingCancelSubscription = true
                        }

                        OperationButton(
                            title: "Issue Refund",
                            icon: "arrow.uturn.backward.circle.fill",
                            color: .red
                        ) {
                            showingRefund = true
                        }

                        OperationButton(
                            title: "Export Report",
                            icon: "square.and.arrow.up.fill",
                            color: .purple
                        ) {
                            showingExport = true
                        }
                    }
                    .padding()
                }

                // Audit Logs
                AdminChartCard(title: "Recent Audit Logs") {
                    VStack(spacing: 8) {
                        ForEach(auditLogs.prefix(20)) { log in
                            AuditLogRow(log: log)
                            Divider()
                        }

                        if auditLogs.isEmpty {
                            Text("No audit logs found")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.vertical)
        }
        .task {
            do {
                auditLogs = try await adminService.getAuditLogs(limit: 100)
            } catch {
                print("Error loading audit logs: \(error)")
            }
        }
        .sheet(isPresented: $showingManualPing) {
            ManualPingSheet(connectionId: $connectionId, adminService: adminService)
        }
        .sheet(isPresented: $showingTestNotification) {
            TestNotificationSheet(
                targetUserId: $targetUserId,
                title: $notificationTitle,
                notificationBody: $notificationBody,
                adminService: adminService
            )
        }
        .sheet(isPresented: $showingCancelSubscription) {
            CancelSubscriptionSheet(
                targetUserId: $targetUserId,
                reason: $cancellationReason,
                adminService: adminService
            )
        }
        .sheet(isPresented: $showingRefund) {
            RefundSheet(
                transactionId: $refundTransactionId,
                amount: $refundAmount,
                reason: $refundReason,
                adminService: adminService
            )
        }
        .sheet(isPresented: $showingExport) {
            ExportSheet(
                reportType: $selectedReportType,
                exportFormat: $selectedExportFormat,
                adminService: adminService
            )
        }
    }
}

@available(iOS 16.0, *)
struct OperationButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 30)
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }
}

@available(iOS 16.0, *)
struct AuditLogRow: View {
    let log: AuditLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(log.action.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.headline)
                Spacer()
                Text(log.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("By: \(log.adminEmail ?? "Unknown")")
                    .font(.caption)
                if let resourceId = log.resourceId {
                    Text("Resource: \(resourceId.uuidString.prefix(8))...")
                        .font(.caption)
                }
            }
            .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
}

// MARK: - Operation Sheets

@available(iOS 16.0, *)
struct ManualPingSheet: View {
    @Binding var connectionId: String
    let adminService: AdminService
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    @State private var resultMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection ID") {
                    TextField("Enter connection UUID", text: $connectionId)
                }

                if !resultMessage.isEmpty {
                    Section {
                        Text(resultMessage)
                            .foregroundColor(resultMessage.contains("Success") ? .green : .red)
                    }
                }
            }
            .navigationTitle("Generate Manual Ping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Generate") {
                        Task {
                            isProcessing = true
                            do {
                                guard let uuid = UUID(uuidString: connectionId) else {
                                    resultMessage = "Invalid UUID format"
                                    isProcessing = false
                                    return
                                }
                                try await adminService.generateManualPing(connectionId: uuid)
                                resultMessage = "Success! Ping generated."
                            } catch {
                                resultMessage = "Error: \(error.localizedDescription)"
                            }
                            isProcessing = false
                        }
                    }
                    .disabled(connectionId.isEmpty || isProcessing)
                }
            }
        }
    }
}

@available(iOS 16.0, *)
struct TestNotificationSheet: View {
    @Binding var targetUserId: String
    @Binding var title: String
    @Binding var notificationBody: String
    let adminService: AdminService
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    @State private var resultMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Target User") {
                    TextField("User UUID", text: $targetUserId)
                }

                Section("Notification Content") {
                    TextField("Title", text: $title)
                    TextField("Body", text: $notificationBody)
                }

                if !resultMessage.isEmpty {
                    Section {
                        Text(resultMessage)
                            .foregroundColor(resultMessage.contains("Success") ? .green : .red)
                    }
                }
            }
            .navigationTitle("Send Test Notification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        Task {
                            isProcessing = true
                            do {
                                guard let uuid = UUID(uuidString: targetUserId) else {
                                    resultMessage = "Invalid UUID format"
                                    isProcessing = false
                                    return
                                }
                                try await adminService.sendTestNotification(userId: uuid, title: title, body: notificationBody)
                                resultMessage = "Success! Notification sent."
                            } catch {
                                resultMessage = "Error: \(error.localizedDescription)"
                            }
                            isProcessing = false
                        }
                    }
                    .disabled(targetUserId.isEmpty || title.isEmpty || notificationBody.isEmpty || isProcessing)
                }
            }
        }
    }
}

@available(iOS 16.0, *)
struct CancelSubscriptionSheet: View {
    @Binding var targetUserId: String
    @Binding var reason: String
    let adminService: AdminService
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    @State private var resultMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Target User") {
                    TextField("User UUID", text: $targetUserId)
                }

                Section("Cancellation Reason") {
                    TextField("Reason", text: $reason)
                }

                if !resultMessage.isEmpty {
                    Section {
                        Text(resultMessage)
                            .foregroundColor(resultMessage.contains("Success") ? .green : .red)
                    }
                }
            }
            .navigationTitle("Cancel Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Confirm") {
                        Task {
                            isProcessing = true
                            do {
                                guard let uuid = UUID(uuidString: targetUserId) else {
                                    resultMessage = "Invalid UUID format"
                                    isProcessing = false
                                    return
                                }
                                try await adminService.cancelSubscription(userId: uuid, reason: reason)
                                resultMessage = "Success! Subscription canceled."
                            } catch {
                                resultMessage = "Error: \(error.localizedDescription)"
                            }
                            isProcessing = false
                        }
                    }
                    .disabled(targetUserId.isEmpty || reason.isEmpty || isProcessing)
                }
            }
        }
    }
}

@available(iOS 16.0, *)
struct RefundSheet: View {
    @Binding var transactionId: String
    @Binding var amount: String
    @Binding var reason: String
    let adminService: AdminService
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    @State private var resultMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    TextField("Transaction UUID", text: $transactionId)
                }

                Section("Refund Details") {
                    TextField("Amount (e.g., 2.99)", text: $amount)
                        .keyboardType(.decimalPad)
                    TextField("Reason", text: $reason)
                }

                if !resultMessage.isEmpty {
                    Section {
                        Text(resultMessage)
                            .foregroundColor(resultMessage.contains("Success") ? .green : .red)
                    }
                }
            }
            .navigationTitle("Issue Refund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refund") {
                        Task {
                            isProcessing = true
                            do {
                                guard let uuid = UUID(uuidString: transactionId),
                                      let decimalAmount = Decimal(string: amount) else {
                                    resultMessage = "Invalid input format"
                                    isProcessing = false
                                    return
                                }
                                try await adminService.issueRefund(transactionId: uuid, amount: decimalAmount, reason: reason)
                                resultMessage = "Success! Refund issued."
                            } catch {
                                resultMessage = "Error: \(error.localizedDescription)"
                            }
                            isProcessing = false
                        }
                    }
                    .disabled(transactionId.isEmpty || amount.isEmpty || reason.isEmpty || isProcessing)
                }
            }
        }
    }
}

@available(iOS 16.0, *)
struct ExportSheet: View {
    @Binding var reportType: ReportType
    @Binding var exportFormat: ExportFormat
    let adminService: AdminService
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    @State private var exportUrl: URL?
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Report Type") {
                    Picker("Type", selection: $reportType) {
                        ForEach(ReportType.allCases, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                }

                Section("Format") {
                    Picker("Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue.uppercased()).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let url = exportUrl {
                    Section {
                        Link("Download Report", destination: url)
                            .foregroundColor(.blue)
                    }
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Export Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Export") {
                        Task {
                            isProcessing = true
                            do {
                                exportUrl = try await adminService.exportReport(reportType: reportType, format: exportFormat)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            isProcessing = false
                        }
                    }
                    .disabled(isProcessing)
                }
            }
        }
    }
}

// MARK: - Reusable Components

@available(iOS 16.0, *)
struct QuickStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

@available(iOS 16.0, *)
struct CompactStatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

@available(iOS 16.0, *)
struct MetricPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(20)
    }
}

@available(iOS 16.0, *)
struct MetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

@available(iOS 16.0, *)
struct GrowthCard: View {
    let title: String
    let value: Int
    let percentage: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(alignment: .bottom) {
                Text("+\(value)")
                    .font(.title2)
                    .fontWeight(.bold)
                if let pct = percentage {
                    Text(String(format: "%.1f%%", pct))
                        .font(.caption)
                        .foregroundColor(pct >= 0 ? .green : .red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

@available(iOS 16.0, *)
struct RevenueCard: View {
    let title: String
    let value: Decimal
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            Text(formatCurrency(value))
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}

@available(iOS 16.0, *)
struct PercentageCard: View {
    let title: String
    let percentage: Double
    let isGood: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(format: "%.1f%%", percentage * 100))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(isGood ? .green : .red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

@available(iOS 16.0, *)
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .cornerRadius(8)
    }
}

struct AdminChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)
            content
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }
}

// MARK: - Charts

@available(iOS 17.0, *)
struct PingCompletionPieChart: View {
    let analytics: PingAnalytics

    var body: some View {
        Chart {
            SectorMark(angle: .value("On Time", analytics.onTimeCount), innerRadius: .ratio(0.5))
                .foregroundStyle(.green)
            SectorMark(angle: .value("Late", analytics.lateCount), innerRadius: .ratio(0.5))
                .foregroundStyle(.orange)
            SectorMark(angle: .value("Missed", analytics.missedCount), innerRadius: .ratio(0.5))
                .foregroundStyle(.red)
        }
    }
}

@available(iOS 16.0, *)
struct SubscriptionStatusChart: View {
    let metrics: SubscriptionMetrics

    var body: some View {
        Chart {
            BarMark(x: .value("Status", "Active"), y: .value("Count", metrics.activeSubscriptions))
                .foregroundStyle(.green)
            BarMark(x: .value("Status", "Trial"), y: .value("Count", metrics.trialUsers))
                .foregroundStyle(.blue)
            BarMark(x: .value("Status", "Past Due"), y: .value("Count", metrics.pastDueSubscriptions))
                .foregroundStyle(.orange)
            BarMark(x: .value("Status", "Canceled"), y: .value("Count", metrics.canceledSubscriptions))
                .foregroundStyle(.red)
            BarMark(x: .value("Status", "Expired"), y: .value("Count", metrics.expiredSubscriptions))
                .foregroundStyle(.gray)
        }
    }
}

@available(iOS 16.0, *)
@available(iOS 16.0, *)
struct ConnectionGrowthChart: View {
    let data: [ConnectionGrowthPoint]

    var body: some View {
        Chart(data) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Total", point.cumulativeTotal)
            )
            .foregroundStyle(.blue)
            AreaMark(
                x: .value("Date", point.date),
                y: .value("Total", point.cumulativeTotal)
            )
            .foregroundStyle(.blue.opacity(0.1))
        }
    }
}

@available(iOS 16.0, *)
@available(iOS 16.0, *)
struct StreakDistributionChart: View {
    let data: [StreakDistribution]

    var body: some View {
        Chart(data) { item in
            BarMark(
                x: .value("Range", item.streakRange),
                y: .value("Users", item.userCount)
            )
            .foregroundStyle(.blue.gradient)
        }
    }
}

// MARK: - Preview

@available(iOS 16.0, *)
#Preview {
    AdminDashboardView()
}
