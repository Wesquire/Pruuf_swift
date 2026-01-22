import SwiftUI
import UIKit

// MARK: - Receiver Onboarding Views
// Section 3.4: Receiver Onboarding Flow (US-1.4)

/// Namespace for receiver onboarding views
enum ReceiverOnboardingViews {
    // Contains:
    // - ReceiverTutorialView
    // - UniqueCodeView
    // - SenderCodeEntryView
    // - SubscriptionInfoView
    // - ReceiverNotificationPermissionView
    // - ReceiverOnboardingCompleteView
    // - ReceiverOnboardingCoordinatorView
}

// MARK: - Receiver Onboarding Step

/// Steps in the receiver onboarding flow
enum ReceiverOnboardingFlowStep: Int, CaseIterable {
    case tutorial = 0
    case uniqueCode = 1
    case senderCodeEntry = 2
    case subscriptionInfo = 3
    case notifications = 4
    case complete = 5

    /// Map to OnboardingStep enum
    var onboardingStep: OnboardingStep {
        switch self {
        case .tutorial:
            return .receiverTutorial
        case .uniqueCode, .senderCodeEntry:
            return .receiverCode
        case .subscriptionInfo:
            return .receiverSubscription
        case .notifications:
            return .receiverNotifications
        case .complete:
            return .receiverComplete
        }
    }
}

// MARK: - Tutorial Slides for Receiver

extension TutorialSlide {
    static let receiverSlides: [TutorialSlide] = [
        TutorialSlide(
            iconName: "heart.fill",
            title: "Get daily pings from loved ones",
            description: "Receive a simple daily check-in from people you care about, letting you know they're safe.",
            iconColor: .pink
        ),
        TutorialSlide(
            iconName: "checkmark.shield.fill",
            title: "Know they're safe and sound",
            description: "Each ping confirms your loved one is okay. Peace of mind, delivered daily.",
            iconColor: .green
        ),
        TutorialSlide(
            iconName: "exclamationmark.triangle.fill",
            title: "Get notified if they miss a ping",
            description: "If someone doesn't check in by their deadline, you'll receive an alert so you can reach out.",
            iconColor: .orange
        ),
        TutorialSlide(
            iconName: "number.circle.fill",
            title: "Connect using their unique code",
            description: "Enter your sender's 6-digit code to connect, or share your code so they can find you.",
            iconColor: .blue
        )
    ]
}

// MARK: - Receiver Tutorial View

/// Tutorial screen showing how PRUUF works for receivers (Step 1)
struct ReceiverTutorialView: View {
    @State private var currentSlideIndex = 0

    /// Callback when tutorial is completed
    var onComplete: () -> Void

    /// Callback when tutorial is skipped
    var onSkip: () -> Void

    private let slides = TutorialSlide.receiverSlides

    var body: some View {
        VStack(spacing: 0) {
            // Skip Button (top right)
            HStack {
                Spacer()
                Button("Skip") {
                    onSkip()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.trailing, 20)
                .padding(.top, 10)
            }

            // Title
            Text("How PRUUF Works for Receivers")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.top, 20)
                .padding(.horizontal, 20)

            Spacer()

            // Slide Content
            TabView(selection: $currentSlideIndex) {
                ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                    TutorialSlideView(slide: slide)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentSlideIndex)

            // Page Indicator
            HStack(spacing: 8) {
                ForEach(0..<slides.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentSlideIndex ? Color.pink : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut, value: currentSlideIndex)
                }
            }
            .padding(.top, 20)

            Spacer()

            // Next/Done Button
            Button {
                if currentSlideIndex < slides.count - 1 {
                    withAnimation {
                        currentSlideIndex += 1
                    }
                } else {
                    onComplete()
                }
            } label: {
                Text(currentSlideIndex < slides.count - 1 ? "Next" : "Done")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.pink)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Unique Code View

/// Displays the receiver's unique 6-digit code with copy/share functionality (Step 2)
struct UniqueCodeView: View {
    @EnvironmentObject private var authService: AuthService
    @StateObject private var viewModel = UniqueCodeViewModel()
    @State private var showCopiedAlert = false

    /// Callback when user continues
    var onContinue: (String) -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Title
            VStack(spacing: 12) {
                Text("Your PRUUF Code")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text("Share this code with senders who want to check in with you")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
            .padding(.horizontal, 20)

            Spacer()

            // Code Display
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else if let code = viewModel.uniqueCode {
                VStack(spacing: 20) {
                    // Large code display
                    HStack(spacing: 12) {
                        ForEach(Array(code.enumerated()), id: \.offset) { _, digit in
                            Text(String(digit))
                                .font(.system(size: 40, weight: .bold, design: .monospaced))
                                .frame(width: 48, height: 56)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                        }
                    }

                    // Copy and Share buttons
                    HStack(spacing: 16) {
                        Button {
                            copyCode(code)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy")
                            }
                            .font(.subheadline.bold())
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.15))
                            )
                            .foregroundStyle(.blue)
                        }

                        Button {
                            shareCode(code)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share")
                            }
                            .font(.subheadline.bold())
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(Color.pink.opacity(0.15))
                            )
                            .foregroundStyle(.pink)
                        }
                    }
                }
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.orange)

                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Retry") {
                        Task {
                            await viewModel.generateCode(for: authService.currentUser?.id)
                        }
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
                }
                .padding(.horizontal, 40)
            }

            Spacer()

            // Info Card
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("How it works")
                        .font(.subheadline.bold())
                }

                Text("Senders will use this code to connect with you. Once connected, you'll receive their daily check-in pings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
            .padding(.horizontal, 20)

            Spacer()

            // Continue Button
            Button {
                if let code = viewModel.uniqueCode {
                    onContinue(code)
                }
            } label: {
                Text("Continue")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(viewModel.uniqueCode != nil ? Color.pink : Color.gray)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .disabled(viewModel.uniqueCode == nil)
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .onAppear {
            Task {
                await viewModel.generateCode(for: authService.currentUser?.id)
            }
        }
        .alert("Copied!", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your code has been copied to the clipboard.")
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Private Methods

    private func copyCode(_ code: String) {
        UIPasteboard.general.string = code
        showCopiedAlert = true

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func shareCode(_ code: String) {
        let shareText = "Connect with me on PRUUF! Use my code: \(code)\n\nDownload PRUUF: https://pruuf.app/join"

        let activityController = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityController, animated: true)
        }
    }
}

// MARK: - Unique Code ViewModel

/// ViewModel for generating and managing unique codes
/// Uses the create_receiver_code() database function for code generation
@MainActor
class UniqueCodeViewModel: ObservableObject {
    @Published var uniqueCode: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let supabaseClient = SupabaseConfig.client

    /// Generate or fetch existing unique code for the user via create_receiver_code() database function
    func generateCode(for userId: UUID?) async {
        guard let userId = userId else {
            errorMessage = "User not found"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // Call the create_receiver_code() database function via RPC
            // This function either returns existing code or generates a new unique 6-digit code
            let code: String = try await supabaseClient
                .rpc("create_receiver_code", params: ["p_user_id": userId.uuidString])
                .execute()
                .value

            uniqueCode = code
        } catch {
            // Log detailed error for debugging
            print("Failed to generate code via create_receiver_code(): \(error)")
            errorMessage = "Failed to generate code. Please try again."
        }

        isLoading = false
    }
}

// MARK: - Sender Code Entry View

/// Optional screen for entering a sender's code to connect (Step 3)
struct SenderCodeEntryView: View {
    @EnvironmentObject private var authService: AuthService
    @State private var senderCode: String = ""
    @State private var isValidating: Bool = false
    @State private var errorMessage: String?
    @State private var connectionSuccess: Bool = false
    @State private var connectedSenderName: String?
    @FocusState private var isCodeFieldFocused: Bool

    /// Callback when user continues (with or without entering a code)
    var onContinue: (Bool) -> Void

    /// Callback when user skips
    var onSkip: () -> Void

    private let codeLength = 6
    private let database = SupabaseConfig.client.schema("public")

    var body: some View {
        VStack(spacing: 24) {
            // Title
            VStack(spacing: 12) {
                Text("Do you have a sender's code?")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("If someone invited you, enter their code to connect")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
            .padding(.horizontal, 20)

            Spacer()

            // Code Entry
            VStack(spacing: 20) {
                // Code input boxes
                HStack(spacing: 12) {
                    ForEach(0..<codeLength, id: \.self) { index in
                        SenderCodeDigitBox(
                            digit: getDigit(at: index),
                            isActive: index == senderCode.count && isCodeFieldFocused
                        )
                    }
                }
                .onTapGesture {
                    isCodeFieldFocused = true
                }

                // Hidden text field for input
                TextField("", text: $senderCode)
                    .keyboardType(.numberPad)
                    .focused($isCodeFieldFocused)
                    .opacity(0)
                    .frame(height: 0)
                    .onChange(of: senderCode) { newValue in
                        let filtered = String(newValue.filter { $0.isNumber }.prefix(codeLength))
                        if filtered != newValue {
                            senderCode = filtered
                        }

                        // Auto-validate when 6 digits entered
                        if senderCode.count == codeLength {
                            Task {
                                await validateCode()
                            }
                        }
                    }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                // Success message
                if connectionSuccess {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Connected to \(connectedSenderName ?? "Sender")!")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            // Info Card
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                    Text("Don't have a code yet?")
                        .font(.subheadline.bold())
                }

                Text("No worries! You can add senders later from the Connections tab. Just ask them for their 6-digit code when you're ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
            .padding(.horizontal, 20)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                // Skip for Now
                Button {
                    onSkip()
                } label: {
                    Text("Skip for Now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Continue Button
                Button {
                    if connectionSuccess || senderCode.isEmpty {
                        onContinue(connectionSuccess)
                    } else {
                        Task {
                            await validateCode()
                        }
                    }
                } label: {
                    HStack {
                        if isValidating {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text(connectionSuccess ? "Continue" : (senderCode.count == codeLength ? "Connect" : "Continue"))
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.pink)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(isValidating)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .onAppear {
            isCodeFieldFocused = true
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Private Methods

    private func getDigit(at index: Int) -> String {
        guard index < senderCode.count else { return "" }
        let stringIndex = senderCode.index(senderCode.startIndex, offsetBy: index)
        return String(senderCode[stringIndex])
    }

    private func validateCode() async {
        guard senderCode.count == codeLength else { return }
        guard let receiverId = authService.currentUser?.id else {
            errorMessage = "User session not found"
            return
        }

        isValidating = true
        errorMessage = nil

        do {
            // Step 1: Lookup the code in unique_codes table to find the sender
            struct SenderCodeLookup: Codable {
                let senderId: UUID

                enum CodingKeys: String, CodingKey {
                    case senderId = "sender_id"
                }
            }

            // Look up the sender_profiles table for this code
            // Note: Senders have invitation codes in sender_profiles
            struct SenderProfileLookup: Codable {
                let id: UUID
                let userId: UUID
                let displayName: String?

                enum CodingKeys: String, CodingKey {
                    case id
                    case userId = "user_id"
                    case displayName = "display_name"
                }
            }

            // Query sender_profiles for the invitation code
            let senderProfiles: [SenderProfileLookup] = try await database
                .from("sender_profiles")
                .select("id, user_id, display_name")
                .eq("invitation_code", value: senderCode)
                .eq("is_active", value: true)
                .execute()
                .value

            guard let senderProfile = senderProfiles.first else {
                errorMessage = "Invalid code. Please check and try again."
                isValidating = false
                return
            }

            let senderId = senderProfile.userId
            connectedSenderName = senderProfile.displayName ?? "Sender"

            // Step 2: Check if connection already exists
            struct ConnectionCheck: Codable {
                let id: UUID
            }

            let existingConnections: [ConnectionCheck] = try await database
                .from("connections")
                .select("id")
                .eq("sender_id", value: senderId.uuidString)
                .eq("receiver_id", value: receiverId.uuidString)
                .neq("status", value: "deleted")
                .execute()
                .value

            if !existingConnections.isEmpty {
                errorMessage = "You're already connected to this sender."
                isValidating = false
                return
            }

            // Step 3: Create connection record
            struct NewConnection: Codable {
                let senderId: UUID
                let receiverId: UUID
                let status: String
                let connectionCode: String

                enum CodingKeys: String, CodingKey {
                    case senderId = "sender_id"
                    case receiverId = "receiver_id"
                    case status
                    case connectionCode = "connection_code"
                }
            }

            let newConnection = NewConnection(
                senderId: senderId,
                receiverId: receiverId,
                status: "active",
                connectionCode: senderCode
            )

            try await database
                .from("connections")
                .insert(newConnection)
                .execute()

            // Success!
            connectionSuccess = true
            isValidating = false

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Auto-continue after brief delay
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            onContinue(true)

        } catch {
            print("Connection error: \(error)")
            errorMessage = "Failed to connect. Please try again."
            isValidating = false
        }
    }
}

/// Individual digit box for sender code entry
struct SenderCodeDigitBox: View {
    let digit: String
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.pink : Color(.systemGray4), lineWidth: isActive ? 2 : 1)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
                .frame(width: 48, height: 56)

            Text(digit)
                .font(.title)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Subscription Info View

/// Explains the subscription model (Step 4)
struct SubscriptionInfoView: View {
    /// Callback when user continues
    var onContinue: () -> Void

    /// Trial days remaining (default 15)
    private let trialDays = 15

    /// Monthly price
    private let monthlyPrice = "$2.99"

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.pink.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.pink)
            }

            // Title (as per plan: "15 Days Free, Then $2.99/Month")
            VStack(spacing: 8) {
                Text("15 Days Free, Then \(monthlyPrice)/Month")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Benefits List (matching plan exactly)
            VStack(alignment: .leading, spacing: 16) {
                SubscriptionBenefitRow(
                    icon: "infinity.circle.fill",
                    title: "Unlimited sender connections",
                    description: "Connect with as many senders as you need"
                )

                Divider()

                SubscriptionBenefitRow(
                    icon: "bell.badge.fill",
                    title: "Real-time ping notifications",
                    description: "Get notified instantly when senders check in"
                )

                Divider()

                SubscriptionBenefitRow(
                    icon: "heart.fill",
                    title: "Peace of mind 24/7",
                    description: "Know your loved ones are safe every day"
                )

                Divider()

                SubscriptionBenefitRow(
                    icon: "xmark.circle.fill",
                    title: "Cancel anytime",
                    description: "No commitment, cancel whenever you want"
                )
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
            )
            .padding(.horizontal, 20)

            Spacer()

            // "Your free trial starts now" message
            HStack(spacing: 8) {
                Image(systemName: "gift.fill")
                    .foregroundStyle(.green)
                Text("Your free trial starts now")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.green.opacity(0.15))
            )

            // Fine Print (Payment required after trial expires)
            Text("Payment required after trial expires. Cancel anytime before then.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Continue Button
            Button {
                onContinue()
            } label: {
                Text("Continue")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.pink)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Row showing a subscription benefit
struct SubscriptionBenefitRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.pink)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Receiver Notification Permission View

/// View for requesting push notification permission (Step 5)
struct ReceiverNotificationPermissionView: View {
    @StateObject private var notificationService = NotificationService.shared
    @State private var isRequesting = false
    @State private var permissionGranted: Bool?

    /// Callback when user continues
    var onContinue: (Bool) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.pink.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.pink)
            }

            // Title
            Text("Never Miss a Ping")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            // Description (as per plan: "Get notified when senders ping you")
            Text("Get notified when senders ping you")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Benefits List
            VStack(alignment: .leading, spacing: 16) {
                ReceiverNotificationBenefitRow(
                    icon: "checkmark.circle.fill",
                    text: "Instant ping confirmations",
                    color: .green
                )
                ReceiverNotificationBenefitRow(
                    icon: "exclamationmark.triangle.fill",
                    text: "Missed ping alerts",
                    color: .orange
                )
                ReceiverNotificationBenefitRow(
                    icon: "calendar.badge.clock",
                    text: "Break schedule updates",
                    color: .blue
                )
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
            .padding(.horizontal, 20)

            Spacer()

            // Permission Result
            if let granted = permissionGranted {
                HStack(spacing: 8) {
                    Image(systemName: granted ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(granted ? .green : .orange)
                    Text(granted ? "Notifications enabled" : "Notifications disabled")
                        .font(.subheadline)
                        .foregroundStyle(granted ? .green : .orange)
                }
                .padding(.bottom, 8)
            }

            // Buttons
            VStack(spacing: 12) {
                // Enable Notifications Button
                if permissionGranted == nil {
                    Button {
                        Task {
                            await requestNotificationPermission()
                        }
                    } label: {
                        HStack {
                            if isRequesting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            } else {
                                Text("Enable Notifications")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.pink)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isRequesting)
                } else {
                    // Continue Button
                    Button {
                        onContinue(permissionGranted ?? false)
                    } label: {
                        Text("Continue")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.pink)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                }

                // Skip option (only if permission not yet requested)
                if permissionGranted == nil {
                    Button {
                        onContinue(false)
                    } label: {
                        Text("Not Now")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func requestNotificationPermission() async {
        isRequesting = true
        let granted = await notificationService.requestPermission()
        isRequesting = false
        permissionGranted = granted

        // Auto-continue after a brief delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        onContinue(granted)
    }
}

/// Row showing a notification benefit for receivers
struct ReceiverNotificationBenefitRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Receiver Onboarding Complete View

/// Final screen showing setup summary (Step 6)
struct ReceiverOnboardingCompleteView: View {
    let uniqueCode: String
    let connectionCount: Int
    let notificationsEnabled: Bool
    let trialEndDate: Date

    /// Callback when user taps "Go to Dashboard"
    var onComplete: () -> Void

    /// Date formatter for trial end date
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Success Icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
            }

            // Title
            Text("You're all set!")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            // Subtitle
            Text("You're ready to receive pings from your loved ones")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            // Setup Summary (as per plan)
            VStack(spacing: 16) {
                // Your code: [6-digit code]
                ReceiverSummaryRow(
                    icon: "number.circle.fill",
                    iconColor: .blue,
                    title: "Your code",
                    value: uniqueCode
                )

                Divider()

                // Trial ends: [Date]
                ReceiverSummaryRow(
                    icon: "calendar",
                    iconColor: .pink,
                    title: "Trial ends",
                    value: dateFormatter.string(from: trialEndDate)
                )

                Divider()

                // Connections: [Number]
                ReceiverSummaryRow(
                    icon: "person.2.fill",
                    iconColor: .purple,
                    title: "Connections",
                    value: connectionCount > 0 ? "\(connectionCount)" : "0"
                )
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
            )
            .padding(.horizontal, 20)

            Spacer()

            // Go to Dashboard Button
            Button {
                onComplete()
            } label: {
                Text("Go to Dashboard")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.pink)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .navigationBarHidden(true)
    }
}

/// Row showing a summary item for receiver
struct ReceiverSummaryRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .frame(width: 24)

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Receiver Onboarding Coordinator View

/// Coordinates the entire receiver onboarding flow
struct ReceiverOnboardingCoordinatorView: View {
    @EnvironmentObject private var authService: AuthService
    @StateObject private var roleService = RoleSelectionService()

    @State private var currentStep: ReceiverOnboardingFlowStep = .tutorial
    @State private var uniqueCode: String = ""
    @State private var connectionCount: Int = 0
    @State private var notificationsEnabled: Bool = false

    /// Starting step (for resuming from saved progress)
    var startingStep: OnboardingStep = .receiverTutorial

    /// Callback when entire receiver onboarding is complete
    var onComplete: () -> Void

    /// Calculate trial end date (15 days from now)
    private var trialEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 15, to: Date()) ?? Date()
    }

    var body: some View {
        Group {
            switch currentStep {
            case .tutorial:
                ReceiverTutorialView(
                    onComplete: { moveToStep(.uniqueCode) },
                    onSkip: { moveToStep(.uniqueCode) }
                )

            case .uniqueCode:
                UniqueCodeView(onContinue: { code in
                    uniqueCode = code
                    moveToStep(.senderCodeEntry)
                })

            case .senderCodeEntry:
                SenderCodeEntryView(
                    onContinue: { connected in
                        if connected {
                            connectionCount += 1
                        }
                        moveToStep(.subscriptionInfo)
                    },
                    onSkip: {
                        moveToStep(.subscriptionInfo)
                    }
                )

            case .subscriptionInfo:
                SubscriptionInfoView(onContinue: {
                    moveToStep(.notifications)
                })

            case .notifications:
                ReceiverNotificationPermissionView(onContinue: { enabled in
                    notificationsEnabled = enabled
                    moveToStep(.complete)
                })

            case .complete:
                ReceiverOnboardingCompleteView(
                    uniqueCode: uniqueCode,
                    connectionCount: connectionCount,
                    notificationsEnabled: notificationsEnabled,
                    trialEndDate: trialEndDate,
                    onComplete: {
                        Task {
                            await completeOnboarding()
                        }
                    }
                )
            }
        }
        .onAppear {
            initializeStep()
        }
    }

    // MARK: - Private Methods

    /// Initialize the step based on starting step
    private func initializeStep() {
        switch startingStep {
        case .receiverTutorial:
            currentStep = .tutorial
        case .receiverCode:
            currentStep = .uniqueCode
        case .receiverSubscription:
            currentStep = .subscriptionInfo
        case .receiverNotifications:
            currentStep = .notifications
        case .receiverComplete:
            currentStep = .complete
        default:
            currentStep = .tutorial
        }
    }

    /// Move to the next step and save progress
    private func moveToStep(_ step: ReceiverOnboardingFlowStep) {
        withAnimation {
            currentStep = step
        }

        // Save progress
        Task {
            await saveProgress(step.onboardingStep)
        }
    }

    /// Save onboarding progress
    private func saveProgress(_ step: OnboardingStep) async {
        guard let userId = authService.currentUser?.id else { return }

        do {
            try await roleService.saveOnboardingProgress(step: step, for: userId)
        } catch {
            // Log error but continue - non-critical
            print("Failed to save onboarding progress: \(error)")
        }
    }

    /// Complete onboarding and set has_completed_onboarding = true
    private func completeOnboarding() async {
        guard let userId = authService.currentUser?.id else {
            onComplete()
            return
        }

        do {
            // Mark onboarding step as complete
            try await roleService.saveOnboardingProgress(step: .receiverComplete, for: userId)

            // Set has_completed_onboarding = true
            try await authService.completeOnboarding()
        } catch {
            print("Failed to complete onboarding: \(error)")
        }

        onComplete()
    }
}

// MARK: - Previews

#if DEBUG
struct ReceiverTutorialView_Previews: PreviewProvider {
    static var previews: some View {
        ReceiverTutorialView(onComplete: {}, onSkip: {})
    }
}

struct UniqueCodeView_Previews: PreviewProvider {
    static var previews: some View {
        UniqueCodeView(onContinue: { _ in })
    }
}

struct SubscriptionInfoView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionInfoView(onContinue: {})
    }
}

struct ReceiverOnboardingCompleteView_Previews: PreviewProvider {
    static var previews: some View {
        ReceiverOnboardingCompleteView(
            uniqueCode: "123456",
            connectionCount: 1,
            notificationsEnabled: true,
            trialEndDate: Calendar.current.date(byAdding: .day, value: 15, to: Date()) ?? Date(),
            onComplete: {}
        )
    }
}
#endif
