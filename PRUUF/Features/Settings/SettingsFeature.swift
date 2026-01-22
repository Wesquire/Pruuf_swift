import SwiftUI
import StoreKit

// MARK: - Settings Feature
// This module handles user settings and preferences
// Per plan.md Phase 10 Section 10.1: Settings Screen Structure

/// Settings feature namespace
enum SettingsFeature {
    // Views implemented:
    // - SettingsView - Main settings hub with all 7 sections
    //   1. Account - Phone, timezone, role, delete account
    //   2. Ping Settings (Senders) - Time picker, grace period, enable/disable, breaks
    //   3. Notifications - Master toggle, all notification types
    //   4. Subscription (Receivers) - Status, billing, subscribe, restore
    //   5. Connections - View connections, PRUUF code
    //   6. Privacy & Data - Export, delete, policies
    //   7. About - Version, support, rate, share
    // - NotificationSettingsView (Phase 8.3) - Notification preference management
}

// MARK: - Settings View Model

/// ViewModel for the main Settings screen
/// Manages user data, subscription status, and settings state
/// Enhanced per plan.md Phase 10 Section 10.2: Account Management
@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var successMessage: String?
    @Published var showSuccess = false

    // Account
    @Published var phoneNumber: String = ""
    @Published var timezone: String = ""
    @Published var userRole: UserRole?

    // Ping Settings
    @Published var pingTime: Date = Date()
    @Published var pingTimeString: String = "09:00"
    @Published var pingEnabled: Bool = true
    @Published var gracePeriod: Int = 90

    // Subscription
    @Published var subscriptionStatus: SubscriptionStatus = .trial
    @Published var trialDaysRemaining: Int?
    @Published var nextBillingDate: Date?

    // Connections
    @Published var pruufCode: String?
    @Published var activeConnectionsCount: Int = 0
    @Published var pausedConnectionsCount: Int = 0

    // Delete Account - Enhanced per Section 10.2
    @Published var showDeleteConfirmation = false
    @Published var showPhoneConfirmation = false
    @Published var showFinalDeleteConfirmation = false
    @Published var isDeletingAccount = false
    @Published var phoneNumberConfirmation: String = ""
    @Published var phoneValidationError: String?

    // Add Role - Enhanced per Section 10.2
    @Published var showAddRoleSheet = false
    @Published var isAddingRole = false
    @Published var shouldNavigateToOnboarding = false
    @Published var onboardingStepForNewRole: OnboardingStep?
    @Published var newReceiverCode: String?

    // Change Ping Time - Enhanced per Section 10.2
    @Published var showPingTimeConfirmation = false
    @Published var pingTimeUpdateNote: String = ""

    // Data Export - Enhanced per Section 10.3
    @Published var isExportingData = false
    @Published var exportResult: DataExportResult?
    @Published var showExportProgress = false
    @Published var showExportSuccess = false
    @Published var exportDownloadUrl: String?
    @Published var exportExpiresAt: Date?
    @Published var exportError: String?

    // MARK: - Services

    private let authService: AuthService
    private let subscriptionService = SubscriptionService.shared
    private let connectionService = ConnectionService.shared
    private let accountManagementService = AccountManagementService.shared
    private let dataExportService = DataExportService.shared

    // MARK: - Computed Properties

    var userId: UUID? {
        authService.currentPruufUser?.id
    }

    var isSender: Bool {
        guard let role = userRole else { return false }
        return role == .sender || role == .both
    }

    var isReceiver: Bool {
        guard let role = userRole else { return false }
        return role == .receiver || role == .both
    }

    var canAddSenderRole: Bool {
        userRole == .receiver
    }

    var canAddReceiverRole: Bool {
        userRole == .sender
    }

    var displayPhoneNumber: String {
        guard let user = authService.currentPruufUser else { return "" }
        return user.fullPhoneNumber
    }

    var displayTimezone: String {
        authService.currentPruufUser?.timezone ?? TimeZone.current.identifier
    }

    var formattedNextBillingDate: String? {
        guard let date = nextBillingDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    // MARK: - Initialization

    init(authService: AuthService) {
        self.authService = authService
        loadUserData()
    }

    // MARK: - Data Loading

    func loadUserData() {
        guard let user = authService.currentPruufUser else { return }

        phoneNumber = user.fullPhoneNumber
        timezone = user.timezone
        userRole = user.primaryRole
    }

    func loadAllData() async {
        isLoading = true
        defer { isLoading = false }

        guard let userId = userId else { return }

        // Load user data
        loadUserData()

        // Load ping settings if sender
        if isSender {
            await loadPingSettings(userId: userId)
        }

        // Load subscription info if receiver
        if isReceiver {
            await loadSubscriptionInfo(userId: userId)
            await loadPruufCode(userId: userId)
        }

        // Load connections count
        await loadConnectionsCount(userId: userId)
    }

    private func loadPingSettings(userId: UUID) async {
        do {
            let profiles: [SenderProfile] = try await SupabaseConfig.client.schema("public")
                .from("sender_profiles")
                .select()
                .eq("user_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value

            if let profile = profiles.first {
                pingEnabled = profile.pingEnabled
                pingTimeString = profile.pingTime

                // Parse time string to Date
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                if let time = formatter.date(from: profile.pingTime) {
                    pingTime = time
                }
            }
        } catch {
            print("[SettingsViewModel] Failed to load ping settings: \(error)")
        }
    }

    private func loadSubscriptionInfo(userId: UUID) async {
        do {
            let profiles: [ReceiverProfile] = try await SupabaseConfig.client.schema("public")
                .from("receiver_profiles")
                .select()
                .eq("user_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value

            if let profile = profiles.first {
                subscriptionStatus = profile.subscriptionStatus
                trialDaysRemaining = profile.trialDaysRemaining
                nextBillingDate = profile.subscriptionEndDate
            }
        } catch {
            print("[SettingsViewModel] Failed to load subscription info: \(error)")
        }
    }

    private func loadPruufCode(userId: UUID) async {
        do {
            pruufCode = try await subscriptionService.getReceiverCode(userId: userId)
        } catch {
            print("[SettingsViewModel] Failed to load PRUUF code: \(error)")
        }
    }

    private func loadConnectionsCount(userId: UUID) async {
        do {
            // Load as sender connections
            if isSender {
                let connections: [Connection] = try await SupabaseConfig.client.schema("public")
                    .from("connections")
                    .select("id, status")
                    .eq("sender_id", value: userId.uuidString)
                    .neq("status", value: ConnectionStatus.deleted.rawValue)
                    .execute()
                    .value

                activeConnectionsCount = connections.filter { $0.status == .active }.count
                pausedConnectionsCount = connections.filter { $0.status == .paused }.count
            }

            // Load as receiver connections
            if isReceiver {
                let receiverConnections: [Connection] = try await SupabaseConfig.client.schema("public")
                    .from("connections")
                    .select("id, status")
                    .eq("receiver_id", value: userId.uuidString)
                    .neq("status", value: ConnectionStatus.deleted.rawValue)
                    .execute()
                    .value

                // Add to totals if user has both roles
                if isSender {
                    activeConnectionsCount += receiverConnections.filter { $0.status == .active }.count
                    pausedConnectionsCount += receiverConnections.filter { $0.status == .paused }.count
                } else {
                    activeConnectionsCount = receiverConnections.filter { $0.status == .active }.count
                    pausedConnectionsCount = receiverConnections.filter { $0.status == .paused }.count
                }
            }
        } catch {
            print("[SettingsViewModel] Failed to load connections count: \(error)")
        }
    }

    // MARK: - Ping Settings Actions

    /// Update ping time with confirmation per Section 10.2
    /// Shows "Ping time updated to [time]" confirmation
    /// Displays note "This will take effect tomorrow"
    func updatePingTime(_ time: Date) async {
        guard let userId = userId else { return }

        do {
            let result = try await accountManagementService.updatePingTime(userId: userId, newTime: time)

            pingTime = time
            pingTimeString = result.newTimeString

            // Show confirmation message per Section 10.2
            successMessage = result.confirmationMessage
            pingTimeUpdateNote = result.effectiveNote
            showPingTimeConfirmation = true
            showSuccess = true
        } catch {
            errorMessage = "Failed to update ping time: \(error.localizedDescription)"
            showError = true
        }
    }

    func togglePingEnabled(_ enabled: Bool) async {
        guard let userId = userId else { return }

        do {
            let updateData = PingEnabledUpdate(pingEnabled: enabled, updatedAt: ISO8601DateFormatter().string(from: Date()))
            try await SupabaseConfig.client.schema("public")
                .from("sender_profiles")
                .update(updateData)
                .eq("user_id", value: userId.uuidString)
                .execute()

            pingEnabled = enabled
        } catch {
            errorMessage = "Failed to update ping status: \(error.localizedDescription)"
            showError = true
        }
    }

    // MARK: - Role Actions (Enhanced per Section 10.2)

    /// Add sender role to existing receiver
    /// Per Section 10.2:
    /// - Creates sender_profiles record
    /// - Updates users.primary_role to 'both'
    /// - Redirects to role-specific onboarding
    func addSenderRole() async {
        guard let userId = userId else { return }
        isAddingRole = true
        defer { isAddingRole = false }

        do {
            // Use AccountManagementService for proper role addition
            let onboardingStep = try await accountManagementService.addSenderRole(userId: userId)

            userRole = .both
            showAddRoleSheet = false

            // Set up navigation to role-specific onboarding
            onboardingStepForNewRole = onboardingStep
            shouldNavigateToOnboarding = true

            successMessage = "Sender role added! Let's set up your daily ping time."
            showSuccess = true
        } catch {
            errorMessage = "Failed to add sender role: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Add receiver role to existing sender
    /// Per Section 10.2:
    /// - Creates receiver_profiles record
    /// - Starts 15-day trial for receiver role
    /// - Updates users.primary_role to 'both'
    /// - Generates unique code
    /// - Redirects to role-specific onboarding
    func addReceiverRole() async {
        guard let userId = userId else { return }
        isAddingRole = true
        defer { isAddingRole = false }

        do {
            // Use AccountManagementService for proper role addition with trial
            let (onboardingStep, uniqueCode) = try await accountManagementService.addReceiverRole(userId: userId)

            userRole = .both
            newReceiverCode = uniqueCode
            showAddRoleSheet = false

            // Set up navigation to role-specific onboarding
            onboardingStepForNewRole = onboardingStep
            shouldNavigateToOnboarding = true

            successMessage = "Receiver role added! Your 15-day free trial has started."
            showSuccess = true
        } catch {
            errorMessage = "Failed to add receiver role: \(error.localizedDescription)"
            showError = true
        }
    }

    // MARK: - Delete Account (Enhanced per Section 10.2)

    /// Validate phone number for deletion confirmation
    /// Per Section 10.2: Require phone number entry to confirm
    func validatePhoneForDeletion() async -> Bool {
        guard let userId = userId else { return false }

        do {
            let isValid = try await accountManagementService.validatePhoneForDeletion(
                enteredPhoneNumber: phoneNumberConfirmation,
                userId: userId
            )

            if !isValid {
                phoneValidationError = "Phone number doesn't match. Please enter your registered phone number."
            } else {
                phoneValidationError = nil
            }

            return isValid
        } catch {
            phoneValidationError = "Failed to validate phone number: \(error.localizedDescription)"
            return false
        }
    }

    /// Initiate deletion flow with phone confirmation
    func initiateAccountDeletion() {
        phoneNumberConfirmation = ""
        phoneValidationError = nil
        showPhoneConfirmation = true
    }

    /// Delete account with full Section 10.2 requirements
    /// - Soft delete with users.is_active = false
    /// - Set all connections status = 'deleted'
    /// - Stop ping generation
    /// - Cancel subscription
    /// - Keep data for 30 days (regulatory requirement)
    /// - Log audit event
    /// - Sign out user
    /// - Schedule hard delete after 30 days via scheduled job
    func deleteAccount() async {
        guard let userId = userId else { return }
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            // Perform full account deletion via service
            let result = try await accountManagementService.deleteAccount(userId: userId)

            // Sign out user
            try await authService.signOut()

            // Show confirmation (will be visible briefly before sign out redirects)
            print("[SettingsViewModel] Account deleted: \(result.message)")
        } catch {
            errorMessage = "Failed to delete account: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Reset deletion state
    func cancelDeletion() {
        showDeleteConfirmation = false
        showPhoneConfirmation = false
        showFinalDeleteConfirmation = false
        phoneNumberConfirmation = ""
        phoneValidationError = nil
    }

    // MARK: - Subscription Actions

    func restorePurchases() async {
        guard let userId = userId else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try await subscriptionService.restorePurchases(userId: userId)
            await loadSubscriptionInfo(userId: userId)
        } catch {
            errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
            showError = true
        }
    }

    // MARK: - Data Export (GDPR)
    // Enhanced per plan.md Phase 10 Section 10.3
    // - Generate ZIP file with all user data
    // - Upload to Storage with 7-day expiration
    // - Deliver via download link or email
    // - Send notification when ready

    /// Request a full GDPR-compliant data export
    /// Calls Edge Function to generate ZIP file with all user data
    /// - Returns: URL for sharing (temporary local file with download link info)
    func exportUserData() async -> URL? {
        guard let userId = userId else { return nil }

        isExportingData = true
        showExportProgress = true
        exportError = nil
        defer { isExportingData = false }

        do {
            let result = try await dataExportService.requestExport(userId: userId)
            exportResult = result

            if result.success {
                exportDownloadUrl = result.downloadUrl
                exportExpiresAt = result.expiresAt
                showExportProgress = false
                showExportSuccess = true

                // If we have a download URL, create a local file for sharing
                if let downloadUrl = result.downloadUrl {
                    // Create a temp file with download instructions
                    let exportInfo = """
                    PRUUF Data Export
                    =================

                    Your data export is ready for download.

                    Download URL:
                    \(downloadUrl)

                    This link will expire in 7 days.

                    File size: \(result.fileSizeBytes != nil ? ByteCountFormatter.string(fromByteCount: Int64(result.fileSizeBytes!), countStyle: .file) : "Unknown")

                    To download:
                    1. Open the URL above in your browser
                    2. Your ZIP file will download automatically

                    The export includes:
                    - Your profile information (JSON)
                    - All connections (JSON)
                    - Complete ping history (CSV)
                    - All notifications (CSV)
                    - Break history (JSON)
                    - Payment transactions (CSV)

                    For questions, contact support@pruuf.com
                    """

                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("pruuf_export_info_\(Date().timeIntervalSince1970).txt")
                    try exportInfo.write(to: tempURL, atomically: true, encoding: .utf8)
                    return tempURL
                }
            } else {
                exportError = result.message ?? "Export failed"
                showExportProgress = false
            }

            return nil

        } catch {
            print("[SettingsViewModel] Data export failed: \(error)")
            exportError = error.localizedDescription
            showExportProgress = false
            errorMessage = "Failed to export data: \(error.localizedDescription)"
            showError = true
            return nil
        }
    }

    /// Open the export download URL in Safari
    func openExportDownloadUrl() {
        guard let urlString = exportDownloadUrl,
              let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Export Progress Sheet

/// View shown during data export processing
/// Per plan.md Section 10.3: Process within 48 hours
struct DataExportProgressView: View {
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()

                if viewModel.isExportingData {
                    // Loading state
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()

                    Text("Generating Your Data Export")
                        .font(.headline)

                    Text("This may take a moment. We're gathering all your data including profile, connections, pings, notifications, breaks, and payment history.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                } else if viewModel.showExportSuccess, let downloadUrl = viewModel.exportDownloadUrl {
                    // Success state
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                        .padding()

                    Text("Export Ready!")
                        .font(.headline)

                    if let expiresAt = viewModel.exportExpiresAt {
                        let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 7
                        Text("Your download link expires in \(daysRemaining) days")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 12) {
                        Button {
                            viewModel.openExportDownloadUrl()
                        } label: {
                            Label("Download ZIP File", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)

                        Button {
                            UIPasteboard.general.string = downloadUrl
                        } label: {
                            Label("Copy Download Link", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal)
                    }
                    .padding(.top)

                } else if let error = viewModel.exportError {
                    // Error state
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                        .padding()

                    Text("Export Failed")
                        .font(.headline)

                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Try Again") {
                        Task {
                            _ = await viewModel.exportUserData()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Data Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                        viewModel.showExportSuccess = false
                        viewModel.exportError = nil
                    }
                }
            }
        }
    }
}

// MARK: - Main Settings View

/// Main settings hub for the app
/// Per plan.md Phase 10 Section 10.1: Complete Settings Screen Structure
struct SettingsView: View {
    @EnvironmentObject private var authService: AuthService
    @StateObject private var viewModel: SettingsViewModel
    @StateObject private var storeKitManager = StoreKitManager.shared

    // Navigation state
    @State private var showNotificationSettings = false
    @State private var showBreaksList = false
    @State private var showConnectionsList = false
    @State private var showScheduleBreak = false
    @State private var showSubscriptionManagement = false
    @State private var showExportSheet = false
    @State private var exportURL: URL?
    @State private var showPingTimePicker = false
    @State private var showExportProgressSheet = false

    init(authService: AuthService) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(authService: authService))
    }

    var body: some View {
        List {
            // 1. Account Section
            accountSection

            // 2. Ping Settings (Senders only)
            if viewModel.isSender {
                pingSettingsSection
            }

            // 3. Notifications Section
            notificationsSection

            // 4. Subscription (Receivers only)
            if viewModel.isReceiver {
                subscriptionSection
            }

            // 5. Connections Section
            connectionsSection

            // 6. Privacy & Data Section
            privacyDataSection

            // 7. About Section
            aboutSection

            // Sign Out
            signOutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadAllData()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
        .sheet(isPresented: $showNotificationSettings) {
            NavigationView {
                NotificationSettingsView(userRole: viewModel.userRole, userId: viewModel.userId)
            }
        }
        .sheet(isPresented: $showBreaksList) {
            BreaksListView(authService: authService)
        }
        .sheet(isPresented: $viewModel.showAddRoleSheet) {
            addRoleSheet
        }
        .sheet(isPresented: $showSubscriptionManagement) {
            if let userId = viewModel.userId {
                NavigationView {
                    SubscriptionManagementView(userId: userId)
                }
            }
        }
        .sheet(isPresented: $showPingTimePicker) {
            pingTimePickerSheet
        }
        // Success alert for ping time update
        .alert("Success", isPresented: $viewModel.showSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            VStack {
                Text(viewModel.successMessage ?? "Operation completed successfully")
                if !viewModel.pingTimeUpdateNote.isEmpty {
                    Text(viewModel.pingTimeUpdateNote)
                        .font(.caption)
                }
            }
        }
        // Step 1: Initial delete confirmation dialog
        .confirmationDialog(
            "Delete Account",
            isPresented: $viewModel.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete My Account", role: .destructive) {
                // Proceed to phone number confirmation per Section 10.2
                viewModel.initiateAccountDeletion()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDeletion()
            }
        } message: {
            Text("This will permanently delete your account and all associated data. Your data will be kept for 30 days before permanent deletion.")
        }
        // Step 2: Phone number confirmation sheet per Section 10.2
        .sheet(isPresented: $viewModel.showPhoneConfirmation) {
            phoneConfirmationSheet
        }
        // Step 3: Final confirmation alert
        .alert("Final Confirmation", isPresented: $viewModel.showFinalDeleteConfirmation) {
            Button("Yes, Delete Everything", role: .destructive) {
                Task {
                    await viewModel.deleteAccount()
                }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDeletion()
            }
        } message: {
            Text("All your data, connections, and ping history will be permanently deleted after 30 days. You will be signed out immediately.")
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(isPresented: $showExportProgressSheet) {
            DataExportProgressView(isPresented: $showExportProgressSheet, viewModel: viewModel)
        }
    }

    // MARK: - Section 1: Account

    private var accountSection: some View {
        Section {
            // Phone Number (read-only)
            HStack {
                Label("Phone Number", systemImage: "phone.fill")
                    .foregroundColor(.primary)
                Spacer()
                Text(viewModel.displayPhoneNumber)
                    .foregroundColor(.secondary)
            }

            // Timezone (auto-detected, read-only)
            HStack {
                Label("Timezone", systemImage: "clock.fill")
                    .foregroundColor(.primary)
                Spacer()
                Text(timezoneDisplayName)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Role
            HStack {
                Label("Role", systemImage: roleIconName)
                    .foregroundColor(.primary)
                Spacer()
                Text(roleDisplayName)
                    .foregroundColor(.secondary)
            }

            // Add Role Button
            if viewModel.canAddSenderRole {
                Button {
                    viewModel.showAddRoleSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                        Text("Add Sender Role")
                            .foregroundColor(.blue)
                    }
                }
            } else if viewModel.canAddReceiverRole {
                Button {
                    viewModel.showAddRoleSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                        Text("Add Receiver Role")
                            .foregroundColor(.blue)
                    }
                }
            }

            // Delete Account (danger zone)
            Button(role: .destructive) {
                viewModel.showDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("Delete Account")
                }
            }
        } header: {
            Text("Account")
        }
    }

    private var timezoneDisplayName: String {
        let tz = TimeZone(identifier: viewModel.displayTimezone) ?? TimeZone.current
        return tz.localizedName(for: .standard, locale: .current) ?? viewModel.displayTimezone
    }

    private var roleIconName: String {
        switch viewModel.userRole {
        case .sender: return "arrow.up.circle.fill"
        case .receiver: return "arrow.down.circle.fill"
        case .both: return "arrow.up.arrow.down.circle.fill"
        case nil: return "person.circle.fill"
        }
    }

    private var roleDisplayName: String {
        switch viewModel.userRole {
        case .sender: return "Sender"
        case .receiver: return "Receiver"
        case .both: return "Sender & Receiver"
        case nil: return "Not Set"
        }
    }

    // MARK: - Section 2: Ping Settings (Senders Only)

    private var pingSettingsSection: some View {
        Section {
            // Daily ping time (time picker)
            Button {
                showPingTimePicker = true
            } label: {
                HStack {
                    Label("Daily Ping Time", systemImage: "alarm.fill")
                        .foregroundColor(.primary)
                    Spacer()
                    Text(formattedPingTime)
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Grace period (read-only)
            HStack {
                Label("Grace Period", systemImage: "timer")
                    .foregroundColor(.primary)
                Spacer()
                Text("\(viewModel.gracePeriod) minutes")
                    .foregroundColor(.secondary)
            }

            // Enable/disable pings (master toggle)
            Toggle(isOn: Binding(
                get: { viewModel.pingEnabled },
                set: { newValue in
                    Task {
                        await viewModel.togglePingEnabled(newValue)
                    }
                }
            )) {
                Label("Enable Pings", systemImage: "bell.badge.fill")
            }

            // Schedule a Break
            Button {
                showBreaksList = true
            } label: {
                HStack {
                    Label("Schedule a Break", systemImage: "calendar.badge.clock")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Ping Settings")
        } footer: {
            Text("Grace period is the extra time you have after your scheduled ping time to complete your check-in.")
        }
    }

    private var formattedPingTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: viewModel.pingTime)
    }

    // MARK: - Section 3: Notifications

    private var notificationsSection: some View {
        Section {
            // Master toggle
            NavigationLink {
                NotificationSettingsView(userRole: viewModel.userRole, userId: viewModel.userId)
            } label: {
                Label("Notification Settings", systemImage: "bell.fill")
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Manage ping reminders, alerts, and notification preferences.")
        }
    }

    // MARK: - Section 4: Subscription (Receivers Only)

    private var subscriptionSection: some View {
        Section {
            // Current status
            HStack {
                Label("Status", systemImage: "creditcard.fill")
                    .foregroundColor(.primary)
                Spacer()
                statusBadge
            }

            // Trial days remaining (if in trial)
            if viewModel.subscriptionStatus == .trial, let days = viewModel.trialDaysRemaining {
                HStack {
                    Label("Trial Ends", systemImage: "calendar")
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(days) days remaining")
                        .foregroundColor(.orange)
                }
            }

            // Next billing date (if active)
            if viewModel.subscriptionStatus == .active, let date = viewModel.formattedNextBillingDate {
                HStack {
                    Label("Next Billing", systemImage: "calendar.circle")
                        .foregroundColor(.primary)
                    Spacer()
                    Text(date)
                        .foregroundColor(.secondary)
                }
            }

            // Subscribe Now or Manage Subscription
            if viewModel.subscriptionStatus == .trial || viewModel.subscriptionStatus == .expired {
                Button {
                    showSubscriptionManagement = true
                } label: {
                    HStack {
                        Image(systemName: "star.circle.fill")
                            .foregroundColor(.purple)
                        Text("Subscribe Now")
                            .foregroundColor(.purple)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if viewModel.subscriptionStatus == .active {
                Button {
                    showSubscriptionManagement = true
                } label: {
                    HStack {
                        Label("Manage Subscription", systemImage: "gearshape.fill")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Restore Purchases
            Button {
                Task {
                    await viewModel.restorePurchases()
                }
            } label: {
                HStack {
                    Label("Restore Purchases", systemImage: "arrow.clockwise.circle.fill")
                        .foregroundColor(.primary)
                    if viewModel.isLoading {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.isLoading)
        } header: {
            Text("Subscription")
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        let (text, color) = subscriptionStatusInfo
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(4)
    }

    private var subscriptionStatusInfo: (String, Color) {
        switch viewModel.subscriptionStatus {
        case .trial:
            return ("Trial", .blue)
        case .active:
            return ("Active", .green)
        case .pastDue:
            return ("Past Due", .orange)
        case .canceled:
            return ("Canceled", .red)
        case .expired:
            return ("Expired", .gray)
        }
    }

    // MARK: - Section 5: Connections

    private var connectionsSection: some View {
        Section {
            // View all connections
            NavigationLink {
                // TODO: Navigate to full connections list
                ConnectionsListPlaceholder()
            } label: {
                HStack {
                    Label("View All Connections", systemImage: "person.2.fill")
                    Spacer()
                    if viewModel.activeConnectionsCount > 0 {
                        Text("\(viewModel.activeConnectionsCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                    }
                }
            }

            // Manage active/paused connections
            if viewModel.pausedConnectionsCount > 0 {
                HStack {
                    Label("Paused Connections", systemImage: "pause.circle.fill")
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(viewModel.pausedConnectionsCount)")
                        .foregroundColor(.orange)
                }
            }

            // Your PRUUF Code (receivers only)
            if viewModel.isReceiver {
                HStack {
                    Label("Your PRUUF Code", systemImage: "qrcode")
                        .foregroundColor(.primary)
                    Spacer()
                    if let code = viewModel.pruufCode {
                        Text(code)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    } else {
                        Text("Loading...")
                            .foregroundColor(.secondary)
                    }
                }
                .contextMenu {
                    if let code = viewModel.pruufCode {
                        Button {
                            UIPasteboard.general.string = code
                        } label: {
                            Label("Copy Code", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
        } header: {
            Text("Connections")
        }
    }

    // MARK: - Section 6: Privacy & Data
    // Enhanced per plan.md Phase 10 Section 10.3: Data Export GDPR

    private var privacyDataSection: some View {
        Section {
            // Export my data (GDPR compliance)
            // Per plan.md Section 10.3:
            // - Provide "Export My Data" button in Privacy and Data section
            // - Generate ZIP file with all user data
            // - Deliver via email or download link
            Button {
                showExportProgressSheet = true
                Task {
                    exportURL = await viewModel.exportUserData()
                    if exportURL != nil {
                        showExportSheet = true
                    }
                }
            } label: {
                HStack {
                    Label("Export My Data", systemImage: "square.and.arrow.up")
                        .foregroundColor(.primary)
                    Spacer()
                    if viewModel.isExportingData {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .disabled(viewModel.isExportingData)

            // Delete my data
            Button(role: .destructive) {
                viewModel.showDeleteConfirmation = true
            } label: {
                Label("Delete My Data", systemImage: "trash")
            }

            // Privacy policy link
            Button {
                if let url = URL(string: "https://pruuf.com/privacy") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Terms of service link
            Button {
                if let url = URL(string: "https://pruuf.com/terms") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Label("Terms of Service", systemImage: "doc.text.fill")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Privacy & Data")
        } footer: {
            Text("Export includes your profile, connections, ping history, notifications, breaks, and payment transactions in machine-readable formats (JSON/CSV).")
                .font(.caption)
        }
    }

    // MARK: - Section 7: About

    private var aboutSection: some View {
        Section {
            // App version
            HStack {
                Label("Version", systemImage: "info.circle.fill")
                    .foregroundColor(.primary)
                Spacer()
                Text(Bundle.main.appVersion)
                    .foregroundColor(.secondary)
            }

            // Build number
            HStack {
                Label("Build", systemImage: "hammer.fill")
                    .foregroundColor(.primary)
                Spacer()
                Text(Bundle.main.buildNumber)
                    .foregroundColor(.secondary)
            }

            // Contact Support
            Button {
                if let url = URL(string: "mailto:support@pruuf.com?subject=PRUUF%20Support%20Request") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Label("Contact Support", systemImage: "envelope.fill")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Rate PRUUF
            Button {
                requestAppStoreReview()
            } label: {
                HStack {
                    Label("Rate PRUUF", systemImage: "star.fill")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Share with Friends
            Button {
                shareApp()
            } label: {
                HStack {
                    Label("Share with Friends", systemImage: "square.and.arrow.up")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Sign Out Section

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                Task {
                    try? await authService.signOut()
                }
            } label: {
                HStack {
                    Spacer()
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    Spacer()
                }
            }
        }
    }

    // MARK: - Sheets

    private var addRoleSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: viewModel.canAddSenderRole ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.top, 40)

                // Title
                Text(viewModel.canAddSenderRole ? "Add Sender Role" : "Add Receiver Role")
                    .font(.title)
                    .fontWeight(.bold)

                // Description
                Text(viewModel.canAddSenderRole
                     ? "Start checking in daily to let your loved ones know you're okay."
                     : "Get peace of mind by receiving daily check-ins from your loved ones.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if !viewModel.canAddSenderRole {
                    // Receiver pricing info
                    Text("Includes a 15-day free trial, then $2.99/month")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // Add button
                Button {
                    Task {
                        if viewModel.canAddSenderRole {
                            await viewModel.addSenderRole()
                        } else {
                            await viewModel.addReceiverRole()
                        }
                    }
                } label: {
                    HStack {
                        if viewModel.isAddingRole {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(viewModel.canAddSenderRole ? "Add Sender Role" : "Start Free Trial")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .disabled(viewModel.isAddingRole)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.showAddRoleSheet = false
                    }
                }
            }
        }
    }

    /// Ping time picker sheet with iOS wheel picker per Section 10.2
    private var pingTimePickerSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Set Daily Ping Time")
                    .font(.headline)
                    .padding(.top)

                // iOS wheel time picker per Section 10.2
                DatePicker(
                    "Ping Time",
                    selection: Binding(
                        get: { viewModel.pingTime },
                        set: { newTime in
                            viewModel.pingTime = newTime
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()

                Text("You'll be reminded to check in at this time each day.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Note per Section 10.2: "This will take effect tomorrow"
                Text("Changes will take effect tomorrow")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.horizontal)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showPingTimePicker = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await viewModel.updatePingTime(viewModel.pingTime)
                            showPingTimePicker = false
                        }
                    }
                    .font(.headline)
                }
            }
        }
    }

    /// Phone number confirmation sheet for account deletion per Section 10.2
    /// Requires phone number entry to confirm deletion
    private var phoneConfirmationSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Warning icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                    .padding(.top, 40)

                // Title
                Text("Confirm Account Deletion")
                    .font(.title2)
                    .fontWeight(.bold)

                // Description
                Text("To confirm deletion, please enter your phone number exactly as registered.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Phone number entry field
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Enter your phone number", text: $viewModel.phoneNumberConfirmation)
                        .keyboardType(.phonePad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal, 24)

                    if let error = viewModel.phoneValidationError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, 24)
                    }
                }

                // Data retention notice per Section 10.2
                VStack(spacing: 4) {
                    Text("Your data will be kept for 30 days")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("(regulatory requirement)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 32)

                Spacer()

                // Confirm button
                Button {
                    Task {
                        let isValid = await viewModel.validatePhoneForDeletion()
                        if isValid {
                            viewModel.showPhoneConfirmation = false
                            viewModel.showFinalDeleteConfirmation = true
                        }
                    }
                } label: {
                    HStack {
                        if viewModel.isDeletingAccount {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Confirm Deletion")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.red)
                    .cornerRadius(12)
                }
                .disabled(viewModel.phoneNumberConfirmation.isEmpty || viewModel.isDeletingAccount)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.cancelDeletion()
                    }
                }
            }
        }
    }

    // MARK: - Helper Functions

    private func requestAppStoreReview() {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    private func shareApp() {
        let shareText = "Check out PRUUF - a simple way to let loved ones know you're okay with daily check-ins. Download it here: https://apps.apple.com/app/pruuf"
        let activityController = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityController, animated: true)
        }
    }
}

// MARK: - Helper Views

/// Placeholder for connections list view
struct ConnectionsListPlaceholder: View {
    var body: some View {
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
}

/// Share sheet for exporting data
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Bundle Extension

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - Preview Provider

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SettingsView(authService: AuthService())
        }
    }
}
#endif
