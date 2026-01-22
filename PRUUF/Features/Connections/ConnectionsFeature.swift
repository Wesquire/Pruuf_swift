import SwiftUI
import UIKit

// MARK: - Connections Feature
// This module handles connection management (adding, viewing, managing connections)

/// Connections feature namespace
enum ConnectionsFeature {}

// MARK: - Add Connection View (Sender connects to Receiver)

/// View for senders to connect to receivers using a 6-digit code
/// Flow:
/// 1. Sender taps "+ Add Receiver" from dashboard
/// 2. Show "Connect to Receiver" screen
/// 3. Input options: Manual entry, paste from clipboard
/// 4. Validate code, create connection, show success/error
struct AddConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AddConnectionViewModel
    @FocusState private var isCodeFieldFocused: Bool

    init(authService: AuthService) {
        _viewModel = StateObject(wrappedValue: AddConnectionViewModel(authService: authService))
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if viewModel.connectionState == .success {
                    successView
                } else {
                    mainContent
                }
            }
            .navigationTitle("Connect to Receiver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            viewModel.checkClipboardForCode()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isCodeFieldFocused = true
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "person.badge.plus.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Enter Receiver's Code")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text("Ask them for their 6-digit PRUUF code")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)

            // Code Entry Field
            codeEntrySection

            // Clipboard Button (if code detected)
            if viewModel.clipboardCode != nil {
                clipboardButton
            }

            // Connect Button
            connectButton

            // QR Code Hint (future enhancement)
            qrCodeHint

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Code Entry Section

    private var codeEntrySection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    digitBox(at: index)
                }
            }

            // Hidden TextField for input
            TextField("", text: $viewModel.code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isCodeFieldFocused)
                .opacity(0.01)
                .frame(width: 1, height: 1)
                .onChange(of: viewModel.code) { newValue in
                    // Limit to 6 digits
                    if newValue.count > 6 {
                        viewModel.code = String(newValue.prefix(6))
                    }
                    // Filter non-numeric characters
                    viewModel.code = newValue.filter { $0.isNumber }
                }

            if viewModel.connectionState == .invalidCode {
                Text("Invalid code. Please check and try again.")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
        }
        .onTapGesture {
            isCodeFieldFocused = true
        }
    }

    // MARK: - Digit Box

    private func digitBox(at index: Int) -> some View {
        let digit = viewModel.digitAt(index: index)
        let isActive = viewModel.code.count == index

        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)

            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isActive ? Color.blue : (digit.isEmpty ? Color.gray.opacity(0.3) : Color.blue.opacity(0.5)),
                    lineWidth: isActive ? 2 : 1
                )

            Text(digit)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .frame(width: 48, height: 60)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }

    // MARK: - Clipboard Button

    private var clipboardButton: some View {
        Button {
            viewModel.pasteFromClipboard()
            isCodeFieldFocused = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                    .font(.subheadline)
                Text("Paste code from clipboard")
                    .font(.subheadline)
            }
            .foregroundColor(.blue)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(20)
        }
    }

    // MARK: - Connect Button

    private var connectButton: some View {
        Button {
            Task {
                isCodeFieldFocused = false
                await viewModel.connect()
            }
        } label: {
            HStack {
                if viewModel.connectionState == .connecting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .padding(.trailing, 8)
                }

                Text(viewModel.connectionState == .connecting ? "Connecting..." : "Connect")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(viewModel.canConnect ? Color.blue : Color.gray)
            .cornerRadius(12)
        }
        .disabled(!viewModel.canConnect)
    }

    // MARK: - QR Code Hint

    private var qrCodeHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "qrcode")
                .font(.subheadline)
            Text("QR code scanning coming soon")
                .font(.caption)
        }
        .foregroundColor(.secondary.opacity(0.7))
        .padding(.top, 16)
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Success Animation
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
            }

            VStack(spacing: 12) {
                Text("Connected!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                if let receiverName = viewModel.connectedReceiverName {
                    Text("Connected to \(receiverName)")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                Text("They will be notified that you're now sending them pings.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Add Connection View Model

/// ViewModel for managing the add connection flow
@MainActor
class AddConnectionViewModel: ObservableObject {
    // MARK: - State

    enum ConnectionState {
        case idle
        case connecting
        case success
        case invalidCode
        case error
    }

    // MARK: - Published Properties

    @Published var code: String = ""
    @Published var connectionState: ConnectionState = .idle
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var clipboardCode: String?
    @Published var connectedReceiverName: String?

    // MARK: - Private Properties

    private let authService: AuthService
    private let connectionService: ConnectionService
    private let notificationService: NotificationService

    // MARK: - Computed Properties

    var canConnect: Bool {
        code.count == 6 && connectionState != .connecting
    }

    // MARK: - Initialization

    init(authService: AuthService,
         connectionService: ConnectionService? = nil,
         notificationService: NotificationService? = nil) {
        self.authService = authService
        self.connectionService = connectionService ?? ConnectionService.shared
        self.notificationService = notificationService ?? NotificationService.shared
    }

    // MARK: - Public Methods

    /// Get digit at specific index for display
    func digitAt(index: Int) -> String {
        guard index < code.count else { return "" }
        let codeIndex = code.index(code.startIndex, offsetBy: index)
        return String(code[codeIndex])
    }

    /// Check clipboard for a 6-digit code
    func checkClipboardForCode() {
        guard let clipboardString = UIPasteboard.general.string else { return }

        // Clean the clipboard content
        let cleaned = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it's a 6-digit code
        if cleaned.count == 6, cleaned.allSatisfy({ $0.isNumber }) {
            clipboardCode = cleaned
        }
    }

    /// Paste code from clipboard
    func pasteFromClipboard() {
        if let clipboardCode = clipboardCode {
            code = clipboardCode
            self.clipboardCode = nil
        }
    }

    /// Connect to receiver using entered code
    func connect() async {
        guard canConnect else { return }
        guard let userId = authService.currentUser?.id else {
            showError(message: "Please sign in to connect with others.")
            return
        }

        connectionState = .connecting

        do {
            // Use ConnectionService to create connection
            let connection = try await connectionService.createConnection(senderId: userId, withCode: code)

            // Get receiver name for success message
            connectedReceiverName = connection.receiver?.displayName ?? "Receiver"

            // Create today's ping for this connection if not yet pinged
            try await createTodayPingIfNeeded(for: connection)

            // Send notification to receiver
            await sendConnectionNotification(to: connection.receiverId, senderName: authService.currentPruufUser?.displayName ?? "Someone")

            // Haptic feedback for success
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            connectionState = .success

        } catch let error as ConnectionServiceError {
            handleConnectionError(error)
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    /// Clear error state
    func clearError() {
        showError = false
        errorMessage = ""
        if connectionState == .error || connectionState == .invalidCode {
            connectionState = .idle
        }
    }

    // MARK: - Private Methods

    // Helper structs for Supabase queries
    private struct SenderProfilePingTime: Codable {
        let pingTime: String

        enum CodingKeys: String, CodingKey {
            case pingTime = "ping_time"
        }
    }

    private struct UserDeviceToken: Codable {
        let deviceToken: String?

        enum CodingKeys: String, CodingKey {
            case deviceToken = "device_token"
        }
    }

    private struct NewPingRequest: Codable {
        let connectionId: String
        let senderId: String
        let receiverId: String
        let scheduledTime: String
        let deadlineTime: String
        let status: String

        enum CodingKeys: String, CodingKey {
            case connectionId = "connection_id"
            case senderId = "sender_id"
            case receiverId = "receiver_id"
            case scheduledTime = "scheduled_time"
            case deadlineTime = "deadline_time"
            case status
        }
    }

    private struct NewNotificationRequest: Codable {
        let userId: String
        let type: String
        let title: String
        let body: String
        let sentAt: String
        let deliveryStatus: String

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case type
            case title
            case body
            case sentAt = "sent_at"
            case deliveryStatus = "delivery_status"
        }
    }

    /// Create today's ping for a new connection if sender hasn't pinged yet
    private func createTodayPingIfNeeded(for connection: Connection) async throws {
        guard let userId = authService.currentUser?.id else { return }

        let database = SupabaseConfig.client.schema("public")
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        // Check if there's already a ping for this connection today
        let existingPings: [Ping] = try await database
            .from("pings")
            .select()
            .eq("connection_id", value: connection.id.uuidString)
            .gte("scheduled_time", value: ISO8601DateFormatter().string(from: today))
            .lt("scheduled_time", value: ISO8601DateFormatter().string(from: tomorrow))
            .execute()
            .value

        guard existingPings.isEmpty else { return }

        // Get sender's ping time from sender_profiles
        let senderProfiles: [SenderProfilePingTime] = try await database
            .from("sender_profiles")
            .select("ping_time")
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value

        guard let senderProfile = senderProfiles.first else {
            return
        }

        let pingTimeString = senderProfile.pingTime

        // Parse ping time (stored as TIME in database, e.g., "09:00:00")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        dateFormatter.timeZone = TimeZone.current

        guard let pingTimeComponents = dateFormatter.date(from: pingTimeString) else {
            return
        }

        // Create scheduled time for today
        var scheduledComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: pingTimeComponents)
        scheduledComponents.hour = timeComponents.hour
        scheduledComponents.minute = timeComponents.minute
        scheduledComponents.second = timeComponents.second

        guard let scheduledTime = calendar.date(from: scheduledComponents) else {
            return
        }

        // Only create ping if scheduled time is in the future (or within deadline window)
        // Grace period is 90 minutes
        let deadlineTime = scheduledTime.addingTimeInterval(90 * 60)

        // Only create if deadline is in the future
        guard deadlineTime > Date() else { return }

        // Create the ping
        let newPing = NewPingRequest(
            connectionId: connection.id.uuidString,
            senderId: connection.senderId.uuidString,
            receiverId: connection.receiverId.uuidString,
            scheduledTime: ISO8601DateFormatter().string(from: scheduledTime),
            deadlineTime: ISO8601DateFormatter().string(from: deadlineTime),
            status: PingStatus.pending.rawValue
        )

        try await database
            .from("pings")
            .insert(newPing)
            .execute()
    }

    /// Send notification to receiver about new connection
    private func sendConnectionNotification(to receiverId: UUID, senderName: String) async {
        let database = SupabaseConfig.client.schema("public")

        do {
            // Get receiver's device token
            let users: [UserDeviceToken] = try await database
                .from("users")
                .select("device_token")
                .eq("id", value: receiverId.uuidString)
                .execute()
                .value

            guard let user = users.first,
                  let deviceToken = user.deviceToken,
                  !deviceToken.isEmpty else {
                return
            }

            // Create notification record
            let notification = NewNotificationRequest(
                userId: receiverId.uuidString,
                type: "connection_request",
                title: "New Connection",
                body: "\(senderName) is now sending you pings",
                sentAt: ISO8601DateFormatter().string(from: Date()),
                deliveryStatus: "sent"
            )

            try await database
                .from("notifications")
                .insert(notification)
                .execute()
        } catch {
            // Silently fail - notification is not critical
        }

        // Note: Actual push notification sending would be done by edge function
        // using the device token. This creates the record for tracking.
    }

    /// Handle connection service errors
    private func handleConnectionError(_ error: ConnectionServiceError) {
        switch error {
        case .invalidCode:
            connectionState = .invalidCode
            // Haptic feedback for error
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

        case .cannotConnectToSelf:
            showError(message: "You cannot connect to your own code.")

        case .connectionAlreadyExists:
            showError(message: "You're already connected to this user.")

        default:
            showError(message: error.localizedDescription)
        }
    }

    /// Show error alert
    private func showError(message: String) {
        connectionState = .error
        errorMessage = message
        showError = true

        // Haptic feedback for error
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
}

// MARK: - Receiver Connect to Sender View

/// View for receivers to connect to senders using their code
/// Used during onboarding and from the receiver dashboard
struct ConnectToSenderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ConnectToSenderViewModel
    @FocusState private var isCodeFieldFocused: Bool
    let onSuccess: ((Connection) -> Void)?

    init(authService: AuthService, onSuccess: ((Connection) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: ConnectToSenderViewModel(authService: authService))
        self.onSuccess = onSuccess
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if viewModel.connectionState == .success {
                    successView
                } else {
                    mainContent
                }
            }
            .navigationTitle("Connect to Sender")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            viewModel.checkClipboardForCode()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isCodeFieldFocused = true
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.pink)

                Text("Enter Sender's Code")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text("If someone invited you to receive their pings, enter their code")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)

            // Code Entry Field
            codeEntrySection

            // Clipboard Button
            if viewModel.clipboardCode != nil {
                clipboardButton
            }

            // Connect Button
            connectButton

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Code Entry Section

    private var codeEntrySection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    digitBox(at: index)
                }
            }

            TextField("", text: $viewModel.code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isCodeFieldFocused)
                .opacity(0.01)
                .frame(width: 1, height: 1)
                .onChange(of: viewModel.code) { newValue in
                    if newValue.count > 6 {
                        viewModel.code = String(newValue.prefix(6))
                    }
                    viewModel.code = newValue.filter { $0.isNumber }
                }

            if viewModel.connectionState == .invalidCode {
                Text("Invalid code. Please check and try again.")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
        }
        .onTapGesture {
            isCodeFieldFocused = true
        }
    }

    private func digitBox(at index: Int) -> some View {
        let digit = viewModel.digitAt(index: index)
        let isActive = viewModel.code.count == index

        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)

            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isActive ? Color.pink : (digit.isEmpty ? Color.gray.opacity(0.3) : Color.pink.opacity(0.5)),
                    lineWidth: isActive ? 2 : 1
                )

            Text(digit)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .frame(width: 48, height: 60)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }

    private var clipboardButton: some View {
        Button {
            viewModel.pasteFromClipboard()
            isCodeFieldFocused = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                    .font(.subheadline)
                Text("Paste code from clipboard")
                    .font(.subheadline)
            }
            .foregroundColor(.pink)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(Color.pink.opacity(0.1))
            .cornerRadius(20)
        }
    }

    private var connectButton: some View {
        Button {
            Task {
                isCodeFieldFocused = false
                await viewModel.connect()
            }
        } label: {
            HStack {
                if viewModel.connectionState == .connecting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .padding(.trailing, 8)
                }

                Text(viewModel.connectionState == .connecting ? "Connecting..." : "Connect")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(viewModel.canConnect ? Color.pink : Color.gray)
            .cornerRadius(12)
        }
        .disabled(!viewModel.canConnect)
    }

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
            }

            VStack(spacing: 12) {
                Text("Connected!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                if let senderName = viewModel.connectedSenderName {
                    Text("Connected to \(senderName)")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                Text("You'll receive their daily pings and know when they're okay.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button {
                if let connection = viewModel.createdConnection {
                    onSuccess?(connection)
                }
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.pink)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Connect To Sender View Model

@MainActor
class ConnectToSenderViewModel: ObservableObject {

    enum ConnectionState {
        case idle
        case connecting
        case success
        case invalidCode
        case error
    }

    @Published var code: String = ""
    @Published var connectionState: ConnectionState = .idle
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var clipboardCode: String?
    @Published var connectedSenderName: String?
    @Published var createdConnection: Connection?

    private let authService: AuthService

    var canConnect: Bool {
        code.count == 6 && connectionState != .connecting
    }

    init(authService: AuthService) {
        self.authService = authService
    }

    func digitAt(index: Int) -> String {
        guard index < code.count else { return "" }
        let codeIndex = code.index(code.startIndex, offsetBy: index)
        return String(code[codeIndex])
    }

    func checkClipboardForCode() {
        guard let clipboardString = UIPasteboard.general.string else { return }
        let cleaned = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count == 6, cleaned.allSatisfy({ $0.isNumber }) {
            clipboardCode = cleaned
        }
    }

    func pasteFromClipboard() {
        if let clipboardCode = clipboardCode {
            code = clipboardCode
            self.clipboardCode = nil
        }
    }

    // Helper structs for Supabase queries
    private struct SenderProfileUserId: Codable {
        let userId: UUID

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
        }
    }

    private struct ConnectionStatusUpdate: Codable {
        let status: String
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case status
            case updatedAt = "updated_at"
        }
    }

    private struct NewConnectionRequest: Codable {
        let senderId: String
        let receiverId: String
        let status: String
        let connectionCode: String

        enum CodingKeys: String, CodingKey {
            case senderId = "sender_id"
            case receiverId = "receiver_id"
            case status
            case connectionCode = "connection_code"
        }
    }

    func connect() async {
        guard canConnect else { return }
        guard let userId = authService.currentUser?.id else {
            showError(message: "Please sign in to connect.")
            return
        }

        connectionState = .connecting

        do {
            let database = SupabaseConfig.client.schema("public")

            // Look up sender by their invitation code (stored in sender_profiles)
            let senderProfiles: [SenderProfileUserId] = try await database
                .from("sender_profiles")
                .select("user_id")
                .eq("invitation_code", value: code)
                .execute()
                .value

            guard let senderProfile = senderProfiles.first else {
                connectionState = .invalidCode
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
                return
            }

            let senderId = senderProfile.userId

            // EC-5.1: Self-connection check
            if senderId == userId {
                showError(message: "You cannot connect to your own code.")
                return
            }

            // Check for existing connection
            let existingConnections: [Connection] = try await database
                .from("connections")
                .select()
                .eq("sender_id", value: senderId.uuidString)
                .eq("receiver_id", value: userId.uuidString)
                .execute()
                .value

            var connection: Connection

            if let existing = existingConnections.first {
                if existing.status == .deleted {
                    // EC-5.3: Reactivate deleted connection
                    let update = ConnectionStatusUpdate(
                        status: ConnectionStatus.active.rawValue,
                        updatedAt: ISO8601DateFormatter().string(from: Date())
                    )

                    connection = try await database
                        .from("connections")
                        .update(update)
                        .eq("id", value: existing.id.uuidString)
                        .select("*, sender:sender_id(id, phone_number, phone_country_code, timezone)")
                        .single()
                        .execute()
                        .value
                } else {
                    // EC-5.2: Already connected
                    showError(message: "You're already connected to this sender.")
                    return
                }
            } else {
                // Create new connection
                let newConnection = NewConnectionRequest(
                    senderId: senderId.uuidString,
                    receiverId: userId.uuidString,
                    status: ConnectionStatus.active.rawValue,
                    connectionCode: code
                )

                connection = try await database
                    .from("connections")
                    .insert(newConnection)
                    .select("*, sender:sender_id(id, phone_number, phone_country_code, timezone)")
                    .single()
                    .execute()
                    .value
            }

            connectedSenderName = connection.sender?.displayName ?? "Sender"
            createdConnection = connection
            connectionState = .success

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

        } catch {
            showError(message: error.localizedDescription)
        }
    }

    func clearError() {
        showError = false
        errorMessage = ""
        if connectionState == .error || connectionState == .invalidCode {
            connectionState = .idle
        }
    }

    private func showError(message: String) {
        connectionState = .error
        errorMessage = message
        showError = true

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
}

// MARK: - Preview

#if DEBUG
struct ConnectionsFeature_Previews: PreviewProvider {
    static var previews: some View {
        AddConnectionView(authService: AuthService())
        ConnectToSenderView(authService: AuthService())
    }
}
#endif
