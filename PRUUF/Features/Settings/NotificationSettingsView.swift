import SwiftUI

/// Settings view for managing notification preferences
/// Includes master toggle, sender/receiver preferences, per-sender muting, and quiet hours
struct NotificationSettingsView: View {
    @StateObject private var preferencesService = NotificationPreferencesService.shared
    @StateObject private var notificationService = NotificationService.shared
    private let pingScheduler = PingNotificationScheduler.shared

    /// The user's role determines which preference sections are shown
    var userRole: UserRole?

    /// The user's ID for loading connections
    var userId: UUID?

    @State private var showMutedSenders = false
    @State private var showQuietHoursSheet = false
    @State private var isLoadingPreferences = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            // Sender Preferences (only shown for senders)
            if userIsSender {
                senderPreferencesSection
            }

            // Receiver Preferences (only shown for receivers)
            // Note: Hidden for sender-only users per Plan 4 Requirement 10
            if userIsReceiver {
                receiverPreferencesSection
            }

            // Sound and Vibration (US-8.1)
            soundAndVibrationSection

            // Reset to Defaults
            resetSection

            // Master Toggle Section - Moved to bottom per Plan 4 Requirement 10
            masterToggleSection

            // Note: Removed per Plan 4 Requirement 10:
            // - systemPermissionSection
            // - perSenderMutingSection
            // - quietHoursSection
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadPreferences()
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .sheet(isPresented: $showMutedSenders) {
            MutedSendersView(userId: userId, userRole: userRole)
        }
        .sheet(isPresented: $showQuietHoursSheet) {
            QuietHoursSettingsView()
        }
    }

    // MARK: - User Role Helpers

    private var userIsSender: Bool {
        guard let role = userRole else { return true } // Show all if role unknown
        return role == .sender || role == .both
    }

    private var userIsReceiver: Bool {
        guard let role = userRole else { return true } // Show all if role unknown
        return role == .receiver || role == .both
    }

    // MARK: - Master Toggle Section

    private var masterToggleSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { preferencesService.preferences.notificationsEnabled },
                set: { newValue in
                    Task {
                        await updateMasterToggle(newValue)
                    }
                }
            )) {
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.blue)
                    Text("Enable Notifications")
                }
            }
            .disabled(preferencesService.isLoading)
        } header: {
            Text("Master Control")
        } footer: {
            Text("When disabled, you won't receive any notifications from Pruuf.")
        }
    }

    // MARK: - System Permission Section

    private var systemPermissionSection: some View {
        Section {
            HStack {
                Image(systemName: notificationService.isNotificationsEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(notificationService.isNotificationsEnabled ? .green : .red)

                VStack(alignment: .leading, spacing: 2) {
                    Text("System Permission")
                    Text(notificationService.isNotificationsEnabled ? "Allowed" : "Not Allowed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !notificationService.isNotificationsEnabled {
                    Button("Settings") {
                        openSystemSettings()
                    }
                    .font(.caption)
                }
            }
        } footer: {
            if !notificationService.isNotificationsEnabled {
                Text("Notifications are disabled in system settings. Tap Settings to enable them.")
            }
        }
    }

    // MARK: - Sender Preferences Section

    private var senderPreferencesSection: some View {
        Section {
            // Ping Reminders
            Toggle(isOn: Binding(
                get: { preferencesService.preferences.pingReminders },
                set: { newValue in
                    Task {
                        await updatePingReminders(newValue)
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pruuf Reminders")
                    Text("At your scheduled check-in time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .disabled(!preferencesService.preferences.notificationsEnabled || preferencesService.isLoading)

            // 15-Minute Warning
            Toggle(isOn: Binding(
                get: { preferencesService.preferences.fifteenMinuteWarning },
                set: { newValue in
                    Task {
                        await updateFifteenMinuteWarning(newValue)
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("15-Minute Warning")
                    Text("Reminder before deadline")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .disabled(!preferencesService.preferences.notificationsEnabled || preferencesService.isLoading)

            // Deadline Passed (renamed from "Deadline Warning" per Plan 4 Req 10)
            Toggle(isOn: Binding(
                get: { preferencesService.preferences.deadlineWarning },
                set: { newValue in
                    Task {
                        await updateDeadlineWarning(newValue)
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deadline Passed")
                    Text("Alert after 60-minute grace period ends")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .disabled(!preferencesService.preferences.notificationsEnabled || preferencesService.isLoading)
        } header: {
            Text("Sender Notifications")
        } footer: {
            Text("Reminders to help you complete your daily check-in on time.")
        }
    }

    // MARK: - Receiver Preferences Section

    private var receiverPreferencesSection: some View {
        Section {
            // Ping Completed
            Toggle(isOn: Binding(
                get: { preferencesService.preferences.pingCompletedNotifications },
                set: { newValue in
                    Task {
                        await updatePingCompleted(newValue)
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pruuf Completed")
                    Text("When your connections check in")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .disabled(!preferencesService.preferences.notificationsEnabled || preferencesService.isLoading)

            // Missed Ping Alerts
            Toggle(isOn: Binding(
                get: { preferencesService.preferences.missedPingAlerts },
                set: { newValue in
                    Task {
                        await updateMissedPingAlerts(newValue)
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Missed Pruuf Alerts")
                    Text("When a connection misses their check-in")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .disabled(!preferencesService.preferences.notificationsEnabled || preferencesService.isLoading)

            // Connection Requests
            Toggle(isOn: Binding(
                get: { preferencesService.preferences.connectionRequests },
                set: { newValue in
                    Task {
                        await updateConnectionRequests(newValue)
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection Requests")
                    Text("When someone wants to connect with you")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .disabled(!preferencesService.preferences.notificationsEnabled || preferencesService.isLoading)

            // Payment Reminders
            Toggle(isOn: Binding(
                get: { preferencesService.preferences.paymentReminders },
                set: { newValue in
                    Task {
                        await updatePaymentReminders(newValue)
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Payment Reminders")
                    Text("Subscription and billing updates")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .disabled(!preferencesService.preferences.notificationsEnabled || preferencesService.isLoading)
        } header: {
            Text("Receiver Notifications")
        } footer: {
            Text("Stay informed about your connections' check-ins.")
        }
    }

    // MARK: - Per-Sender Muting Section

    private var perSenderMutingSection: some View {
        Section {
            Button {
                showMutedSenders = true
            } label: {
                HStack {
                    Image(systemName: "speaker.slash.fill")
                        .foregroundColor(.orange)
                    Text("Muted Senders")
                    Spacer()
                    if let mutedCount = preferencesService.preferences.mutedSenderIds?.count, mutedCount > 0 {
                        Text("\(mutedCount)")
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.primary)
            .disabled(!preferencesService.preferences.notificationsEnabled)
        } header: {
            Text("Per-Sender Settings")
        } footer: {
            Text("Mute notifications from specific senders while keeping others active.")
        }
    }

    // MARK: - Sound and Vibration Section (US-8.1)

    private var soundAndVibrationSection: some View {
        Section {
            // Sound Toggle
            Toggle(isOn: Binding(
                get: { preferencesService.preferences.soundEnabled },
                set: { newValue in
                    Task {
                        await updateSoundEnabled(newValue)
                    }
                }
            )) {
                HStack {
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sound")
                        Text("Play sounds for notifications")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .disabled(!preferencesService.preferences.notificationsEnabled || preferencesService.isLoading)

            // Vibration Toggle
            Toggle(isOn: Binding(
                get: { preferencesService.preferences.vibrationEnabled },
                set: { newValue in
                    Task {
                        await updateVibrationEnabled(newValue)
                    }
                }
            )) {
                HStack {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .foregroundColor(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vibration")
                        Text("Vibrate for notifications")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .disabled(!preferencesService.preferences.notificationsEnabled || preferencesService.isLoading)
        } header: {
            Text("Sound & Vibration")
        } footer: {
            Text("Configure how you're alerted when notifications arrive.")
        }
    }

    // MARK: - Quiet Hours Section

    private var quietHoursSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { preferencesService.preferences.quietHoursEnabled },
                set: { newValue in
                    if newValue && preferencesService.preferences.quietHoursStart == nil {
                        showQuietHoursSheet = true
                    } else {
                        Task {
                            await updateQuietHoursEnabled(newValue)
                        }
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quiet Hours")
                    if preferencesService.preferences.quietHoursEnabled,
                       let start = preferencesService.preferences.quietHoursStart,
                       let end = preferencesService.preferences.quietHoursEnd {
                        Text("\(start) - \(end)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No notifications during specified times")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .disabled(!preferencesService.preferences.notificationsEnabled || preferencesService.isLoading)

            if preferencesService.preferences.quietHoursEnabled {
                Button {
                    showQuietHoursSheet = true
                } label: {
                    HStack {
                        Text("Edit Quiet Hours")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.primary)
            }
        } header: {
            HStack {
                Text("Quiet Hours")
                Text("Coming Soon")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .cornerRadius(4)
            }
        } footer: {
            Text("Suppress notifications during sleep or focus times. This feature will be available in a future update.")
        }
    }

    // MARK: - Reset Section

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                Task {
                    await resetToDefaults()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset to Defaults")
                }
            }
            .disabled(preferencesService.isLoading)
        }
    }

    // MARK: - Actions

    private func loadPreferences() {
        Task {
            do {
                try await preferencesService.fetchPreferences()
                isLoadingPreferences = false
            } catch {
                errorMessage = error.localizedDescription
                isLoadingPreferences = false
            }
        }
    }

    private func updateMasterToggle(_ enabled: Bool) async {
        do {
            try await preferencesService.setNotificationsEnabled(enabled)
            if enabled {
                if userIsSender, let userId {
                    await pingScheduler.rescheduleNotificationsForPendingPings(userId: userId)
                }
            } else {
                pingScheduler.cancelAllPingNotifications()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updatePingReminders(_ enabled: Bool) async {
        do {
            try await preferencesService.setPingReminders(enabled)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateFifteenMinuteWarning(_ enabled: Bool) async {
        do {
            try await preferencesService.setFifteenMinuteWarning(enabled)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateDeadlineWarning(_ enabled: Bool) async {
        do {
            try await preferencesService.setDeadlineWarning(enabled)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updatePingCompleted(_ enabled: Bool) async {
        do {
            try await preferencesService.setPingCompletedNotifications(enabled)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateMissedPingAlerts(_ enabled: Bool) async {
        do {
            try await preferencesService.setMissedPingAlerts(enabled)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateConnectionRequests(_ enabled: Bool) async {
        do {
            try await preferencesService.setConnectionRequests(enabled)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updatePaymentReminders(_ enabled: Bool) async {
        do {
            try await preferencesService.setPaymentReminders(enabled)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateQuietHoursEnabled(_ enabled: Bool) async {
        do {
            try await preferencesService.setQuietHoursEnabled(enabled)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resetToDefaults() async {
        do {
            try await preferencesService.resetToDefaults()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateSoundEnabled(_ enabled: Bool) async {
        do {
            try await preferencesService.setSoundEnabled(enabled)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateVibrationEnabled(_ enabled: Bool) async {
        do {
            try await preferencesService.setVibrationEnabled(enabled)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Muted Senders View

struct MutedSendersView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preferencesService = NotificationPreferencesService.shared
    @StateObject private var connectionService = ConnectionService.shared

    /// The user's ID for loading connections
    var userId: UUID?

    /// The user's role for loading connections
    var userRole: UserRole?

    @State private var connections: [Connection] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading connections...")
                } else if connections.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Connections")
                            .font(.headline)
                        Text("You don't have any sender connections to mute.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(connections) { connection in
                            MutedSenderRow(
                                connection: connection,
                                isMuted: preferencesService.preferences.isSenderMuted(connection.senderId)
                            ) { senderId in
                                toggleMute(senderId: senderId)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Muted Senders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadConnections()
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
        }
    }

    private func loadConnections() {
        guard let userId = userId else {
            isLoading = false
            return
        }

        Task {
            do {
                // Get connections where current user is receiver
                try await connectionService.fetchConnectionsAsReceiver(userId: userId)
                // Filter for active connections
                connections = connectionService.connections.filter { $0.status == .active }
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func toggleMute(senderId: UUID) {
        Task {
            do {
                try await preferencesService.toggleSenderMute(senderId)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct MutedSenderRow: View {
    let connection: Connection
    let isMuted: Bool
    let onToggle: (UUID) -> Void

    /// Get the sender's display name from the connection
    private var senderDisplayName: String {
        connection.sender?.displayName ?? "Unknown Sender"
    }

    /// Get the sender's initial for avatar
    private var senderInitial: String {
        senderDisplayName.prefix(1).uppercased()
    }

    var body: some View {
        HStack {
            // Avatar placeholder
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(senderInitial)
                        .font(.headline)
                        .foregroundColor(.blue)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(senderDisplayName)
                    .font(.body)
                if isMuted {
                    Text("Muted")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            Button {
                onToggle(connection.senderId)
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundColor(isMuted ? .orange : .blue)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Quiet Hours Settings View

struct QuietHoursSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preferencesService = NotificationPreferencesService.shared

    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Quiet Hours Schedule")
                } footer: {
                    Text("Notifications will be suppressed during this time period. This feature is coming soon.")
                }

                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("Quiet hours work overnight. For example, 10:00 PM to 7:00 AM will suppress notifications during the night.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Quiet Hours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveQuietHours()
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                loadCurrentSettings()
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
        }
    }

    private func loadCurrentSettings() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        if let startStr = preferencesService.preferences.quietHoursStart,
           let parsedStart = formatter.date(from: startStr) {
            // Set date components to match the parsed time
            let calendar = Calendar.current
            var components = calendar.dateComponents([.hour, .minute], from: parsedStart)
            components.year = calendar.component(.year, from: Date())
            components.month = calendar.component(.month, from: Date())
            components.day = calendar.component(.day, from: Date())
            if let date = calendar.date(from: components) {
                startTime = date
            }
        } else {
            // Default: 10 PM
            startTime = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
        }

        if let endStr = preferencesService.preferences.quietHoursEnd,
           let parsedEnd = formatter.date(from: endStr) {
            let calendar = Calendar.current
            var components = calendar.dateComponents([.hour, .minute], from: parsedEnd)
            components.year = calendar.component(.year, from: Date())
            components.month = calendar.component(.month, from: Date())
            components.day = calendar.component(.day, from: Date())
            if let date = calendar.date(from: components) {
                endTime = date
            }
        } else {
            // Default: 7 AM
            endTime = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
        }
    }

    private func saveQuietHours() {
        isSaving = true

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let startStr = formatter.string(from: startTime)
        let endStr = formatter.string(from: endTime)

        Task {
            do {
                try await preferencesService.setQuietHours(start: startStr, end: endStr)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
struct NotificationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            NotificationSettingsView(userRole: .both, userId: UUID())
        }
    }
}
#endif
