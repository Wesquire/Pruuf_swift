import SwiftUI
import ContactsUI
import MessageUI

// MARK: - Sender Onboarding Views
// Section 3.3: Sender Onboarding Flow

/// Namespace for sender onboarding views
enum SenderOnboardingViews {
    // Contains:
    // - SenderTutorialView
    // - PingTimeSelectionView
    // - ConnectionInvitationView
    // - SenderNotificationPermissionView
    // - SenderOnboardingCompleteView
    // - SenderOnboardingCoordinatorView
}

// MARK: - Sender Onboarding Step

/// Steps in the sender onboarding flow
enum SenderOnboardingFlowStep: Int, CaseIterable {
    case tutorial = 0
    case pingTime = 1
    case connections = 2
    case notifications = 3
    case complete = 4

    /// Map to OnboardingStep enum
    var onboardingStep: OnboardingStep {
        switch self {
        case .tutorial:
            return .senderTutorial
        case .pingTime:
            return .senderPingTime
        case .connections:
            return .senderConnections
        case .notifications:
            return .senderNotifications
        case .complete:
            return .senderComplete
        }
    }
}

// MARK: - Tutorial Slide Model

/// Model for a single tutorial slide
struct TutorialSlide: Identifiable {
    let id = UUID()
    let iconName: String
    let title: String
    let description: String
    let iconColor: Color
}

/// Tutorial slides for sender onboarding
extension TutorialSlide {
    static let senderSlides: [TutorialSlide] = [
        TutorialSlide(
            iconName: "clock.fill",
            title: "Set your daily ping time",
            description: "Choose a time each day when you'll check in. We'll remind you when it's time.",
            iconColor: .blue
        ),
        TutorialSlide(
            iconName: "hand.tap.fill",
            title: "Tap once to confirm you're okay",
            description: "It only takes a second. Just tap the big button to let everyone know you're safe.",
            iconColor: .green
        ),
        TutorialSlide(
            iconName: "person.2.fill",
            title: "Connect with people who care",
            description: "Invite friends and family to receive your pings. They'll get peace of mind knowing you're okay.",
            iconColor: .purple
        ),
        TutorialSlide(
            iconName: "calendar.badge.clock",
            title: "Take breaks when needed",
            description: "Going on vacation? Pause your pings anytime. Your connections will be notified.",
            iconColor: .orange
        )
    ]
}

// MARK: - Sender Tutorial View

/// Tutorial screen showing how PRUUF works for senders (Step 1)
struct SenderTutorialView: View {
    @State private var currentSlideIndex = 0

    /// Callback when tutorial is completed (Next/Done pressed on last slide)
    var onComplete: () -> Void

    /// Callback when tutorial is skipped
    var onSkip: () -> Void

    private let slides = TutorialSlide.senderSlides

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
            Text("How PRUUF Works for Senders")
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
                        .fill(index == currentSlideIndex ? Color.blue : Color.gray.opacity(0.3))
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
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .navigationBarHidden(true)
    }
}

/// Individual tutorial slide view
struct TutorialSlideView: View {
    let slide: TutorialSlide

    var body: some View {
        VStack(spacing: 32) {
            // Icon
            ZStack {
                Circle()
                    .fill(slide.iconColor.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: slide.iconName)
                    .font(.system(size: 50))
                    .foregroundStyle(slide.iconColor)
            }

            // Title
            Text(slide.title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            // Description
            Text(slide.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Ping Time Selection View

/// Time picker for setting daily ping time (Step 2)
struct PingTimeSelectionView: View {
    @State private var selectedTime: Date
    @State private var isProcessing = false

    /// Callback when time is selected and user continues
    var onContinue: (Date) -> Void

    /// Grace period in minutes (default 90)
    private let gracePeriodMinutes = 90

    init(defaultTime: Date? = nil, onContinue: @escaping (Date) -> Void) {
        // Default to 9:00 AM in user's local time
        let calendar = Calendar.current
        let now = Date()
        let defaultHour = 9
        let defaultMinute = 0

        if let providedTime = defaultTime {
            _selectedTime = State(initialValue: providedTime)
        } else {
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = defaultHour
            components.minute = defaultMinute
            _selectedTime = State(initialValue: calendar.date(from: components) ?? now)
        }

        self.onContinue = onContinue
    }

    /// Calculate deadline based on selected time + grace period
    private var deadlineTime: Date {
        Calendar.current.date(byAdding: .minute, value: gracePeriodMinutes, to: selectedTime) ?? selectedTime
    }

    /// Format time for display
    private var formattedSelectedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: selectedTime)
    }

    /// Format deadline time for display
    private var formattedDeadlineTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: deadlineTime)
    }

    var body: some View {
        VStack(spacing: 24) {
            // Title
            VStack(spacing: 12) {
                Text("When should we remind you to ping?")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("Choose a time you'll be awake every day")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
            .padding(.horizontal, 20)

            Spacer()

            // Time Picker (iOS native wheel picker)
            DatePicker(
                "Ping Time",
                selection: $selectedTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxHeight: 200)

            // Grace Period Explanation
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "clock.badge.checkmark")
                        .foregroundStyle(.blue)
                    Text("Grace Period")
                        .font(.subheadline.bold())
                }

                Text("You'll have until \(formattedDeadlineTime) to check in")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("(\(gracePeriodMinutes)-minute grace period)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
                isProcessing = true
                onContinue(selectedTime)
            } label: {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Continue")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
            .disabled(isProcessing)
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Connection Invitation View

/// View for inviting contacts to receive pings (Step 3)
struct ConnectionInvitationView: View {
    @EnvironmentObject private var authService: AuthService
    @StateObject private var viewModel = ConnectionInvitationViewModel()

    /// Callback when user continues (with or without invitations)
    var onContinue: (Int) -> Void

    /// Callback when user skips
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Title
            VStack(spacing: 12) {
                Text("Invite people to receive your pings")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("They'll get peace of mind knowing you're safe")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
            .padding(.horizontal, 20)

            Spacer()

            // Selected Contacts List
            if !viewModel.selectedContacts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Selected (\(viewModel.selectedContacts.count))")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(viewModel.selectedContacts) { contact in
                                SelectedContactChip(
                                    contact: contact,
                                    onRemove: {
                                        viewModel.removeContact(contact)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Select Contacts Button
            Button {
                viewModel.showingContactPicker = true
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title3)
                    Text("Select Contacts")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 2)
                )
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 20)

            Spacer()

            // Error Message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

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
                    Task {
                        await viewModel.sendInvitations()
                        onContinue(viewModel.invitationsSent)
                    }
                } label: {
                    HStack {
                        if viewModel.isProcessing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text(viewModel.selectedContacts.isEmpty ? "Continue" : "Send Invitations")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(viewModel.isProcessing)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .animation(.easeInOut, value: viewModel.selectedContacts.count)
        .sheet(isPresented: $viewModel.showingContactPicker) {
            ContactPickerView(selectedContacts: $viewModel.selectedContacts)
        }
        .sheet(isPresented: $viewModel.showingMessageCompose) {
            if let contact = viewModel.currentInviteContact {
                MessageComposeView(
                    recipients: [contact.phoneNumber],
                    body: viewModel.generateInvitationMessage(),
                    onComplete: { result in
                        viewModel.handleMessageResult(result, for: contact)
                    }
                )
            }
        }
        .onAppear {
            viewModel.senderName = authService.currentPruufUser?.displayName ?? "Someone"
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Chip showing a selected contact
struct SelectedContactChip: View {
    let contact: SelectedContact
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 32, height: 32)

                Text(contact.initials)
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            }

            // Name
            Text(contact.name)
                .font(.subheadline)
                .lineLimit(1)

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Selected Contact Model

/// Model for a selected contact
struct SelectedContact: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let phoneNumber: String
    let invitationSent: Bool

    var initials: String {
        let words = name.split(separator: " ")
        let initials = words.prefix(2).compactMap { $0.first?.uppercased() }
        return initials.joined()
    }

    static func == (lhs: SelectedContact, rhs: SelectedContact) -> Bool {
        lhs.phoneNumber == rhs.phoneNumber
    }
}

// MARK: - Connection Invitation ViewModel

/// ViewModel for managing contact invitations
@MainActor
class ConnectionInvitationViewModel: ObservableObject {
    @Published var selectedContacts: [SelectedContact] = []
    @Published var showingContactPicker = false
    @Published var showingMessageCompose = false
    @Published var currentInviteContact: SelectedContact?
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var invitationsSent = 0

    var senderName: String = "Someone"

    /// Remove a contact from selection
    func removeContact(_ contact: SelectedContact) {
        selectedContacts.removeAll { $0.id == contact.id }
    }

    /// Generate invitation message
    func generateInvitationMessage() -> String {
        // The invitation code would be generated by the backend
        // For now, use a placeholder that will be replaced when the actual system is implemented
        let inviteCode = generateTemporaryInviteCode()
        return "\(senderName) wants to send you daily pings on PRUUF to let you know they're safe. Download the app and use code \(inviteCode) to connect: https://pruuf.app/join"
    }

    /// Generate a temporary 6-digit invite code
    private func generateTemporaryInviteCode() -> String {
        let digits = "0123456789"
        return String((0..<6).map { _ in digits.randomElement()! })
    }

    /// Send invitations to all selected contacts
    func sendInvitations() async {
        guard !selectedContacts.isEmpty else { return }

        isProcessing = true
        errorMessage = nil

        // In a real implementation, this would:
        // 1. Create invitation records in the database
        // 2. Generate unique invite codes for each contact
        // 3. Open the message composer for each contact sequentially

        // For now, we'll simulate the process and count invitations
        invitationsSent = selectedContacts.count

        // Small delay to simulate processing
        try? await Task.sleep(nanoseconds: 500_000_000)

        isProcessing = false
    }

    /// Handle message compose result
    func handleMessageResult(_ result: MessageComposeResult, for contact: SelectedContact) {
        showingMessageCompose = false

        switch result {
        case .sent:
            invitationsSent += 1
            if let index = selectedContacts.firstIndex(where: { $0.id == contact.id }) {
                selectedContacts[index] = SelectedContact(
                    name: contact.name,
                    phoneNumber: contact.phoneNumber,
                    invitationSent: true
                )
            }
        case .cancelled, .failed:
            // User cancelled or failed, just continue
            break
        @unknown default:
            break
        }

        currentInviteContact = nil
    }
}

// MARK: - Contact Picker View

/// UIViewControllerRepresentable for CNContactPickerViewController
struct ContactPickerView: UIViewControllerRepresentable {
    @Binding var selectedContacts: [SelectedContact]
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPickerView

        init(_ parent: ContactPickerView) {
            self.parent = parent
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            for contact in contacts {
                guard let phoneNumber = contact.phoneNumbers.first?.value.stringValue else { continue }

                let name = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")

                // Check if already selected
                if !parent.selectedContacts.contains(where: { $0.phoneNumber == phoneNumber }) {
                    parent.selectedContacts.append(SelectedContact(
                        name: name.isEmpty ? "Unknown" : name,
                        phoneNumber: phoneNumber,
                        invitationSent: false
                    ))
                }
            }
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            // Just dismiss, contacts binding will be unchanged
        }
    }
}

// MARK: - Message Compose View

/// UIViewControllerRepresentable for MFMessageComposeViewController
struct MessageComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onComplete: (MessageComposeResult) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let parent: MessageComposeView

        init(_ parent: MessageComposeView) {
            self.parent = parent
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            parent.onComplete(result)
            parent.dismiss()
        }
    }
}

// MARK: - Sender Notification Permission View

/// View for requesting push notification permission (Step 4)
struct SenderNotificationPermissionView: View {
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
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.blue)
            }

            // Title
            Text("Stay on Track")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            // Description
            Text("Get reminders when it's time to ping")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Benefits List
            VStack(alignment: .leading, spacing: 16) {
                NotificationBenefitRow(
                    icon: "clock.fill",
                    text: "Daily reminders at your chosen time"
                )
                NotificationBenefitRow(
                    icon: "exclamationmark.triangle.fill",
                    text: "Alerts before your deadline passes"
                )
                NotificationBenefitRow(
                    icon: "person.2.fill",
                    text: "Know when someone connects with you"
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
                        .background(Color.blue)
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
                            .background(Color.blue)
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

/// Row showing a notification benefit
struct NotificationBenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Sender Onboarding Complete View

/// Final screen showing setup summary (Step 5)
struct SenderOnboardingCompleteView: View {
    let pingTime: Date
    let connectionsInvited: Int
    let notificationsEnabled: Bool

    /// Callback when user taps "Go to Dashboard"
    var onComplete: () -> Void

    /// Format time for display
    private var formattedPingTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: pingTime)
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
            Text("Your daily check-ins are ready to go")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Setup Summary
            VStack(spacing: 16) {
                SummaryRow(
                    icon: "clock.fill",
                    iconColor: .blue,
                    title: "Daily ping time",
                    value: formattedPingTime
                )

                Divider()

                SummaryRow(
                    icon: "person.2.fill",
                    iconColor: .purple,
                    title: "Invitations sent",
                    value: connectionsInvited > 0 ? "\(connectionsInvited) people" : "None yet"
                )

                Divider()

                SummaryRow(
                    icon: "bell.fill",
                    iconColor: notificationsEnabled ? .green : .orange,
                    title: "Notifications",
                    value: notificationsEnabled ? "Enabled" : "Disabled"
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
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .navigationBarHidden(true)
    }
}

/// Row showing a summary item
struct SummaryRow: View {
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

// MARK: - Sender Onboarding Coordinator View

/// Coordinates the entire sender onboarding flow
struct SenderOnboardingCoordinatorView: View {
    @EnvironmentObject private var authService: AuthService
    @StateObject private var roleService = RoleSelectionService()

    @State private var currentStep: SenderOnboardingFlowStep = .tutorial
    @State private var selectedPingTime: Date = Date()
    @State private var connectionsInvited: Int = 0
    @State private var notificationsEnabled: Bool = false

    /// Starting step (for resuming from saved progress)
    var startingStep: OnboardingStep = .senderTutorial

    /// Callback when entire sender onboarding is complete
    var onComplete: () -> Void

    var body: some View {
        Group {
            switch currentStep {
            case .tutorial:
                SenderTutorialView(
                    onComplete: { moveToStep(.pingTime) },
                    onSkip: { moveToStep(.pingTime) }
                )

            case .pingTime:
                PingTimeSelectionView(onContinue: { time in
                    selectedPingTime = time
                    Task {
                        await savePingTime(time)
                    }
                    moveToStep(.connections)
                })

            case .connections:
                ConnectionInvitationView(
                    onContinue: { count in
                        connectionsInvited = count
                        moveToStep(.notifications)
                    },
                    onSkip: {
                        connectionsInvited = 0
                        moveToStep(.notifications)
                    }
                )

            case .notifications:
                SenderNotificationPermissionView(onContinue: { enabled in
                    notificationsEnabled = enabled
                    moveToStep(.complete)
                })

            case .complete:
                SenderOnboardingCompleteView(
                    pingTime: selectedPingTime,
                    connectionsInvited: connectionsInvited,
                    notificationsEnabled: notificationsEnabled,
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
        case .senderTutorial:
            currentStep = .tutorial
        case .senderPingTime:
            currentStep = .pingTime
        case .senderConnections:
            currentStep = .connections
        case .senderNotifications:
            currentStep = .notifications
        case .senderComplete:
            currentStep = .complete
        default:
            currentStep = .tutorial
        }

        // Set default ping time to 9 AM
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 9
        components.minute = 0
        selectedPingTime = calendar.date(from: components) ?? Date()
    }

    /// Move to the next step and save progress
    private func moveToStep(_ step: SenderOnboardingFlowStep) {
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

    /// Save the selected ping time to the sender profile
    private func savePingTime(_ localTime: Date) async {
        guard let userId = authService.currentUser?.id else { return }

        // Convert local time to UTC time string (HH:MM:SS format)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: localTime)
        let utcTimeString = String(format: "%02d:%02d:00", components.hour ?? 9, components.minute ?? 0)

        do {
            // Update sender profile with the new ping time
            try await SupabaseConfig.client.schema("public")
                .from("sender_profiles")
                .update(["ping_time": utcTimeString])
                .eq("user_id", value: userId.uuidString)
                .execute()
        } catch {
            // Log error but continue - ping time can be updated later
            print("Failed to save ping time: \(error)")
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
            try await roleService.saveOnboardingProgress(step: .senderComplete, for: userId)

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
struct SenderTutorialView_Previews: PreviewProvider {
    static var previews: some View {
        SenderTutorialView(onComplete: {}, onSkip: {})
    }
}

struct PingTimeSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        PingTimeSelectionView(onContinue: { _ in })
    }
}

struct SenderOnboardingCompleteView_Previews: PreviewProvider {
    static var previews: some View {
        SenderOnboardingCompleteView(
            pingTime: Date(),
            connectionsInvited: 3,
            notificationsEnabled: true,
            onComplete: {}
        )
    }
}
#endif
