import SwiftUI
import UIKit
import MessageUI
import Supabase

// MARK: - Connection Management Views

/// Views and view models for managing connections between senders and receivers
/// Section 5.2: Managing Connections

// MARK: - Connection Action Sheet (Sender Perspective)

/// Action sheet for managing a receiver connection (from sender's perspective)
struct SenderConnectionActionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let connection: Connection
    let authService: AuthService
    let onPause: () async -> Void
    let onResume: () async -> Void
    let onRemove: () async -> Void
    let onViewHistory: () -> Void

    @State private var showPauseConfirmation = false
    @State private var showRemoveConfirmation = false
    @State private var showContactOptions = false
    @State private var isProcessing = false

    var body: some View {
        NavigationView {
            List {
                // Connection Info Section
                Section {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(statusColor.opacity(0.2))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Text(initials)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(statusColor)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(receiverName)
                                .font(.headline)
                                .foregroundColor(.primary)

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 8, height: 8)
                                Text(connection.status.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                // Actions Section
                Section {
                    // Pause/Resume Connection
                    if connection.status == .active {
                        Button {
                            showPauseConfirmation = true
                        } label: {
                            Label {
                                Text("Pause Connection")
                            } icon: {
                                Image(systemName: "pause.circle.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                        .disabled(isProcessing)
                    } else if connection.status == .paused {
                        Button {
                            Task {
                                isProcessing = true
                                await onResume()
                                isProcessing = false
                                dismiss()
                            }
                        } label: {
                            Label {
                                Text("Resume Connection")
                            } icon: {
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .disabled(isProcessing)
                    }

                    // Contact Receiver
                    Button {
                        showContactOptions = true
                    } label: {
                        Label {
                            Text("Contact Receiver")
                        } icon: {
                            Image(systemName: "message.fill")
                                .foregroundColor(.blue)
                        }
                    }

                    // View History
                    Button {
                        dismiss()
                        onViewHistory()
                    } label: {
                        Label {
                            Text("View Pruuf History")
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.purple)
                        }
                    }
                }

                // Danger Zone
                Section {
                    Button(role: .destructive) {
                        showRemoveConfirmation = true
                    } label: {
                        Label {
                            Text("Remove Connection")
                        } icon: {
                            Image(systemName: "trash.fill")
                                .foregroundColor(.red)
                        }
                    }
                    .disabled(isProcessing)
                }
            }
            .navigationTitle("Manage Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .confirmationDialog("Pause Connection?", isPresented: $showPauseConfirmation, titleVisibility: .visible) {
            Button("Pause") {
                Task {
                    isProcessing = true
                    await onPause()
                    isProcessing = false
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Pausing will stop sending Pruufs to \(receiverName). You can resume at any time.")
        }
        .confirmationDialog("Remove Connection?", isPresented: $showRemoveConfirmation, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    isProcessing = true
                    await onRemove()
                    isProcessing = false
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove \(receiverName) from your receivers list. They will no longer receive your Pruufs.")
        }
        .sheet(isPresented: $showContactOptions) {
            ContactOptionsSheet(
                phoneNumber: connection.receiver?.fullPhoneNumber ?? "",
                displayName: receiverName
            )
        }
    }

    // MARK: - Computed Properties

    private var receiverName: String {
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
        case .active: return .green
        case .paused: return .gray
        case .pending: return .yellow
        case .deleted: return .red
        }
    }
}

// MARK: - Connection Action Sheet (Receiver Perspective)

/// Action sheet for managing a sender connection (from receiver's perspective)
struct ReceiverConnectionActionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sender: SenderWithPingStatus
    let authService: AuthService
    let onPauseNotifications: () async -> Void
    let onResumeNotifications: () async -> Void
    let onRemove: () async -> Void
    let onViewHistory: () -> Void

    @State private var showPauseConfirmation = false
    @State private var showRemoveConfirmation = false
    @State private var showContactOptions = false
    @State private var isProcessing = false
    @State private var notificationsPaused = false

    var body: some View {
        NavigationView {
            List {
                // Connection Info Section
                Section {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(sender.pingStatus.color.opacity(0.2))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Text(sender.initials)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(sender.pingStatus.color)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(sender.senderName)
                                .font(.headline)
                                .foregroundColor(.primary)

                            HStack(spacing: 4) {
                                Image(systemName: sender.pingStatus.iconName)
                                    .font(.caption)
                                    .foregroundColor(sender.pingStatus.color)
                                Text(sender.pingStatus.statusMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            if sender.streak > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "flame.fill")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                    Text("\(sender.streak) day streak")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                // Actions Section
                Section {
                    // Pause/Resume Notifications
                    if !notificationsPaused {
                        Button {
                            showPauseConfirmation = true
                        } label: {
                            Label {
                                Text("Pause Notifications")
                            } icon: {
                                Image(systemName: "bell.slash.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                        .disabled(isProcessing)
                    } else {
                        Button {
                            Task {
                                isProcessing = true
                                await onResumeNotifications()
                                notificationsPaused = false
                                isProcessing = false
                            }
                        } label: {
                            Label {
                                Text("Resume Notifications")
                            } icon: {
                                Image(systemName: "bell.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .disabled(isProcessing)
                    }

                    // Contact Sender
                    Button {
                        showContactOptions = true
                    } label: {
                        Label {
                            Text("Contact Sender")
                        } icon: {
                            Image(systemName: "message.fill")
                                .foregroundColor(.blue)
                        }
                    }

                    // View History
                    Button {
                        dismiss()
                        onViewHistory()
                    } label: {
                        Label {
                            Text("View Pruuf History")
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.purple)
                        }
                    }
                }

                // Danger Zone
                Section {
                    Button(role: .destructive) {
                        showRemoveConfirmation = true
                    } label: {
                        Label {
                            Text("Remove Connection")
                        } icon: {
                            Image(systemName: "trash.fill")
                                .foregroundColor(.red)
                        }
                    }
                    .disabled(isProcessing)
                }
            }
            .navigationTitle("Manage Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .confirmationDialog("Pause Notifications?", isPresented: $showPauseConfirmation, titleVisibility: .visible) {
            Button("Pause") {
                Task {
                    isProcessing = true
                    await onPauseNotifications()
                    notificationsPaused = true
                    isProcessing = false
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You'll stop receiving notifications from \(sender.senderName). You can still see their Pruufs in the app.")
        }
        .confirmationDialog("Remove Connection?", isPresented: $showRemoveConfirmation, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    isProcessing = true
                    await onRemove()
                    isProcessing = false
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove \(sender.senderName) from your senders list. You will no longer receive their Pruufs.")
        }
        .sheet(isPresented: $showContactOptions) {
            ContactOptionsSheet(
                phoneNumber: sender.connection.sender?.fullPhoneNumber ?? "",
                displayName: sender.senderName
            )
        }
    }
}

// MARK: - Contact Options Sheet

/// Sheet for selecting contact method (Messages or Phone Call)
struct ContactOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let phoneNumber: String
    let displayName: String

    @State private var showMessageComposer = false
    @State private var showCallConfirmation = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button {
                        showMessageComposer = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Send Message")
                                    .foregroundColor(.primary)
                                Text(phoneNumber)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "message.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .disabled(!MFMessageComposeViewController.canSendText())

                    Button {
                        showCallConfirmation = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Call")
                                    .foregroundColor(.primary)
                                Text(phoneNumber)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "phone.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Contact \(displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showMessageComposer) {
            MessageComposerView(recipients: [phoneNumber]) { result in
                showMessageComposer = false
                if result == .sent {
                    dismiss()
                }
            }
        }
        .confirmationDialog("Call \(displayName)?", isPresented: $showCallConfirmation, titleVisibility: .visible) {
            Button("Call") {
                makePhoneCall()
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Call \(phoneNumber)")
        }
    }

    private func makePhoneCall() {
        let cleanedNumber = phoneNumber.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")

        if let url = URL(string: "tel://\(cleanedNumber)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Message Composer View

/// UIViewControllerRepresentable for MFMessageComposeViewController
struct MessageComposerView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onComplete: (MessageComposeResult) -> Void

    init(recipients: [String], body: String = "", onComplete: @escaping (MessageComposeResult) -> Void) {
        self.recipients = recipients
        self.body = body
        self.onComplete = onComplete
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onComplete: (MessageComposeResult) -> Void

        init(onComplete: @escaping (MessageComposeResult) -> Void) {
            self.onComplete = onComplete
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true) {
                self.onComplete(result)
            }
        }
    }
}

// MARK: - Ping History View

/// View displaying ping history for a specific connection
struct PingHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let connectionId: UUID
    let displayName: String
    let userId: UUID

    @StateObject private var viewModel: PingHistoryViewModel

    init(connectionId: UUID, displayName: String, userId: UUID) {
        self.connectionId = connectionId
        self.displayName = displayName
        self.userId = userId
        _viewModel = StateObject(wrappedValue: PingHistoryViewModel(connectionId: connectionId))
    }

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading && viewModel.pingHistory.isEmpty {
                    ProgressView("Loading history...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.pingHistory.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("No Pruuf history yet")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Pruufs will appear here once they start coming in.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    List {
                        ForEach(viewModel.groupedHistory.keys.sorted().reversed(), id: \.self) { date in
                            Section(header: Text(viewModel.formatSectionDate(date))) {
                                ForEach(viewModel.groupedHistory[date] ?? []) { ping in
                                    PingHistoryRowView(ping: ping)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History: \(displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.loadHistory()
        }
    }
}

// MARK: - Ping History Row View

struct PingHistoryRowView: View {
    let ping: Ping

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Circle()
                .fill(statusColor.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: statusIcon)
                        .font(.subheadline)
                        .foregroundColor(statusColor)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(statusText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    Text(formattedTime)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let method = ping.completionMethod {
                        Text("(\(method.displayName))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch ping.status {
        case .completed: return .green
        case .missed: return .red
        case .pending: return .yellow
        case .onBreak: return .gray
        }
    }

    private var statusIcon: String {
        switch ping.status {
        case .completed: return "checkmark.circle.fill"
        case .missed: return "exclamationmark.triangle.fill"
        case .pending: return "clock.fill"
        case .onBreak: return "calendar"
        }
    }

    private var statusText: String {
        switch ping.status {
        case .completed:
            return "Pruuf completed"
        case .missed:
            return "Pruuf missed"
        case .pending:
            return "Pruuf pending"
        case .onBreak:
            return "On Pruuf Pause"
        }
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        if let completedAt = ping.completedAt {
            return "at \(formatter.string(from: completedAt))"
        } else {
            return "scheduled \(formatter.string(from: ping.scheduledTime))"
        }
    }
}

// MARK: - Ping History ViewModel

@MainActor
class PingHistoryViewModel: ObservableObject {
    @Published var pingHistory: [Ping] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let connectionId: UUID
    private let database = SupabaseConfig.client.schema("public")

    init(connectionId: UUID) {
        self.connectionId = connectionId
    }

    /// Load ping history for the connection
    func loadHistory() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let pings: [Ping] = try await database
                .from("pings")
                .select()
                .eq("connection_id", value: connectionId.uuidString)
                .order("scheduled_time", ascending: false)
                .limit(100)
                .execute()
                .value

            pingHistory = pings
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Group history by date
    var groupedHistory: [Date: [Ping]] {
        let calendar = Calendar.current
        return Dictionary(grouping: pingHistory) { ping in
            calendar.startOfDay(for: ping.scheduledTime)
        }
    }

    /// Format section date header
    func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Connection Management ViewModel

/// ViewModel for managing connection actions
@MainActor
class ConnectionManagementViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var errorMessage: String?

    private let connectionService: ConnectionService
    private let database: PostgrestClient

    init(connectionService: ConnectionService? = nil) {
        self.connectionService = connectionService ?? ConnectionService.shared
        self.database = SupabaseConfig.client.schema("public")
    }

    /// Pause a connection (Sender action)
    func pauseConnection(_ connectionId: UUID) async -> Bool {
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await connectionService.pauseConnection(connectionId: connectionId)

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            return true
        } catch {
            errorMessage = error.localizedDescription

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            return false
        }
    }

    /// Resume a paused connection (Sender action)
    func resumeConnection(_ connectionId: UUID) async -> Bool {
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await connectionService.resumeConnection(connectionId: connectionId)

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            return true
        } catch {
            errorMessage = error.localizedDescription

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            return false
        }
    }

    /// Remove a connection (Sender or Receiver action)
    func removeConnection(_ connectionId: UUID) async -> Bool {
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await connectionService.deleteConnection(connectionId: connectionId)

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            return true
        } catch {
            errorMessage = error.localizedDescription

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            return false
        }
    }

    /// Pause notifications for a sender (Receiver action)
    /// This mutes notifications for a specific sender without affecting the connection
    func pauseNotificationsForSender(_ senderId: UUID, receiverId: UUID) async -> Bool {
        isProcessing = true
        defer { isProcessing = false }

        do {
            // Get current notification preferences
            let users: [PruufUser] = try await database
                .from("users")
                .select("notification_preferences")
                .eq("id", value: receiverId.uuidString)
                .limit(1)
                .execute()
                .value

            var preferences = users.first?.notificationPreferences ?? NotificationPreferences()

            // Add sender to muted list
            if preferences.mutedSenderIds == nil {
                preferences.mutedSenderIds = []
            }
            if !preferences.mutedSenderIds!.contains(senderId) {
                preferences.mutedSenderIds!.append(senderId)
            }

            // Update preferences
            try await database
                .from("users")
                .update(["notification_preferences": preferences])
                .eq("id", value: receiverId.uuidString)
                .execute()

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            return true
        } catch {
            errorMessage = error.localizedDescription

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            return false
        }
    }

    /// Resume notifications for a sender (Receiver action)
    func resumeNotificationsForSender(_ senderId: UUID, receiverId: UUID) async -> Bool {
        isProcessing = true
        defer { isProcessing = false }

        do {
            // Get current notification preferences
            let users: [PruufUser] = try await database
                .from("users")
                .select("notification_preferences")
                .eq("id", value: receiverId.uuidString)
                .limit(1)
                .execute()
                .value

            var preferences = users.first?.notificationPreferences ?? NotificationPreferences()

            // Remove sender from muted list
            if let index = preferences.mutedSenderIds?.firstIndex(of: senderId) {
                preferences.mutedSenderIds?.remove(at: index)
            }

            // Update preferences
            try await database
                .from("users")
                .update(["notification_preferences": preferences])
                .eq("id", value: receiverId.uuidString)
                .execute()

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            return true
        } catch {
            errorMessage = error.localizedDescription

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            return false
        }
    }

    /// Check if notifications are paused for a sender
    func isNotificationsPaused(senderId: UUID, preferences: NotificationPreferences?) -> Bool {
        guard let mutedIds = preferences?.mutedSenderIds else { return false }
        return mutedIds.contains(senderId)
    }
}

// MARK: - Preview

#if DEBUG
struct ConnectionManagementView_Previews: PreviewProvider {
    static var previews: some View {
        ContactOptionsSheet(
            phoneNumber: "+1 (555) 123-4567",
            displayName: "John Doe"
        )
    }
}
#endif
