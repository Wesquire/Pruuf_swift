import SwiftUI

// MARK: - Onboarding Feature

/// Onboarding feature namespace containing views and view models
/// for the user onboarding flow including role selection
enum OnboardingFeature {
    // Views:
    // - RoleSelectionView (Section 3.2)
    // - SenderOnboardingFlow (Section 3.3 - implemented in SenderOnboardingViews.swift)
    // - ReceiverOnboardingFlow (Section 3.4 - placeholder)
    // - OnboardingCoordinatorView
}

// MARK: - Onboarding State

/// Current state of the onboarding flow
enum OnboardingState: Equatable {
    case roleSelection
    case senderOnboarding(step: OnboardingStep)
    case receiverOnboarding(step: OnboardingStep)
    case addSecondRole(currentRole: UserRole)
    case complete
}

// MARK: - Role Selection View

/// Main role selection screen - "How will you use PRUUF?"
/// User selects either Sender or Receiver role
struct RoleSelectionView: View {
    @EnvironmentObject private var authService: AuthService
    @StateObject private var roleService = RoleSelectionService()

    @State private var selectedRole: UserRole?
    @State private var showContinue: Bool = false
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String?

    /// Callback when role selection is complete
    var onRoleSelected: ((UserRole) -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Text("How will you use PRUUF?")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text("You can always add the other role later")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)

            Spacer()

            // Role Selection Cards
            VStack(spacing: 16) {
                // Sender Card
                RoleSelectionCard(
                    role: .sender,
                    isSelected: selectedRole == .sender,
                    onSelect: { selectRole(.sender) }
                )

                // Receiver Card
                RoleSelectionCard(
                    role: .receiver,
                    isSelected: selectedRole == .receiver,
                    onSelect: { selectRole(.receiver) }
                )
            }
            .padding(.horizontal, 20)

            Spacer()

            // Error Message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Continue Button
            if showContinue {
                Button {
                    Task {
                        await confirmSelection()
                    }
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
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer()
                .frame(height: 40)
        }
        .animation(.easeInOut(duration: 0.25), value: showContinue)
        .animation(.easeInOut(duration: 0.25), value: selectedRole)
    }

    // MARK: - Private Methods

    private func selectRole(_ role: UserRole) {
        withAnimation {
            if selectedRole == role {
                // Deselect if tapping same card
                selectedRole = nil
                showContinue = false
            } else {
                selectedRole = role
                showContinue = true
            }
        }
        errorMessage = nil

        // Light haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func confirmSelection() async {
        guard let role = selectedRole else { return }
        guard let userId = authService.currentUser?.id else {
            errorMessage = "User not found. Please try again."
            return
        }

        isProcessing = true
        errorMessage = nil

        do {
            // Get the phone number from auth service for user creation if needed
            let phoneNumber = authService.currentPruufUser?.phoneNumber ?? authService.pendingVerificationPhone

            // Save the role selection to database
            _ = try await roleService.selectRole(role, for: userId, phoneNumber: phoneNumber)

            // Save onboarding progress (EC-2.1)
            try await roleService.saveOnboardingProgress(step: .roleSelection, for: userId)

            // Proceed directly to the appropriate onboarding flow
            isProcessing = false
            finalizeSelection()
        } catch {
            isProcessing = false
            errorMessage = "Failed to save selection. Please try again."
        }
    }

    private func finalizeSelection() {
        guard let role = selectedRole else { return }
        onRoleSelected?(role)
    }
}

// MARK: - Role Selection Card

/// Card component for displaying a role option
struct RoleSelectionCard: View {
    let role: UserRole
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    // Role Icon
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.blue : Color(.systemGray5))
                            .frame(width: 56, height: 56)

                        Image(systemName: role.iconName)
                            .font(.system(size: 24))
                            .foregroundStyle(isSelected ? .white : .blue)
                    }

                    Spacer()

                    // Pricing Tag
                    Text(role.pricingTag)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(role == .sender ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                        )
                        .foregroundStyle(role == .sender ? .green : .blue)
                }

                // Title
                Text(role.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)

                // Description
                Text(role.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? Color.blue.opacity(0.2) : Color.clear, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Onboarding Coordinator View

/// Coordinates the entire onboarding flow based on user's role and progress
struct OnboardingCoordinatorView: View {
    @EnvironmentObject private var authService: AuthService
    @StateObject private var roleService = RoleSelectionService()

    @State private var currentState: OnboardingState = .roleSelection
    @State private var isLoadingResume: Bool = true

    var body: some View {
        NavigationView {
            Group {
                if isLoadingResume {
                    // Loading state while checking for resume point
                    OnboardingLoadingView()
                } else {
                    switch currentState {
                    case .roleSelection:
                        RoleSelectionView(onRoleSelected: handleRoleSelected)

                    case .senderOnboarding(let step):
                        // Sender Onboarding Flow (Section 3.3)
                        SenderOnboardingCoordinatorView(
                            startingStep: step,
                            onComplete: handleOnboardingComplete
                        )

                    case .receiverOnboarding(let step):
                        // Receiver Onboarding Flow (Section 3.4 / US-1.4)
                        ReceiverOnboardingCoordinatorView(
                            startingStep: step,
                            onComplete: handleOnboardingComplete
                        )

                    case .addSecondRole:
                        // Handled via alert in RoleSelectionView
                        EmptyView()

                    case .complete:
                        OnboardingCompleteView()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .task {
            await checkResumePoint()
        }
    }

    // MARK: - Private Methods

    /// Check if user should resume from a previous onboarding step (EC-2.1)
    private func checkResumePoint() async {
        // Wait briefly for auth state to stabilize after navigation transition
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        guard let userId = authService.currentUser?.id else {
            // No user ID yet - default to role selection
            print("OnboardingCoordinator: No user ID available, defaulting to role selection")
            currentState = .roleSelection
            isLoadingResume = false
            return
        }

        do {
            let resumeStep = try await roleService.getResumeStep(for: userId)

            // Determine the state based on the resume step
            if resumeStep == .roleSelection {
                currentState = .roleSelection
            } else if resumeStep.isSenderStep {
                currentState = .senderOnboarding(step: resumeStep)
            } else if resumeStep.isReceiverStep {
                currentState = .receiverOnboarding(step: resumeStep)
            } else {
                currentState = .roleSelection
            }
        } catch {
            // Default to role selection if we can't determine resume point
            print("OnboardingCoordinator: Error getting resume step: \(error.localizedDescription)")
            currentState = .roleSelection
        }

        isLoadingResume = false
    }

    /// Handle when user selects a role
    private func handleRoleSelected(_ role: UserRole) {
        withAnimation {
            if role == .sender || authService.currentPruufUser?.primaryRole == .both {
                currentState = .senderOnboarding(step: .senderTutorial)
            } else {
                currentState = .receiverOnboarding(step: .receiverTutorial)
            }
        }
    }

    /// Handle when onboarding flow completes
    private func handleOnboardingComplete() {
        Task {
            do {
                try await authService.completeOnboarding()
            } catch {
                // Log error but continue - user can retry if needed
                print("Failed to mark onboarding complete: \(error)")
            }
        }
    }
}

// MARK: - Onboarding Loading View

/// Loading view shown while checking resume point
struct OnboardingLoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)

            Text("Loading your progress...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sender Onboarding (Section 3.3)
// Full implementation available in SenderOnboardingViews.swift
// - SenderTutorialView: Tutorial slides explaining how PRUUF works
// - PingTimeSelectionView: iOS wheel picker for setting daily ping time
// - ConnectionInvitationView: Contact picker with share/invitation
// - SenderNotificationPermissionView: Push notification permission request
// - SenderOnboardingCompleteView: Setup summary and completion
// - SenderOnboardingCoordinatorView: Coordinates the entire flow

// MARK: - Receiver Onboarding (Section 3.4 / US-1.4)
// Full implementation available in ReceiverOnboardingViews.swift
// - ReceiverTutorialView: Tutorial slides explaining how PRUUF works for receivers
// - UniqueCodeView: 6-digit unique code display with copy/share functionality
// - SenderCodeEntryView: Optional entry of sender's code to connect
// - SubscriptionInfoView: Explains 15-day free trial and $2.99/month pricing
// - ReceiverNotificationPermissionView: Push notification permission request
// - ReceiverOnboardingCompleteView: Setup summary and completion
// - ReceiverOnboardingCoordinatorView: Coordinates the entire flow

// MARK: - Onboarding Complete View

/// Shown when onboarding is fully complete
struct OnboardingCompleteView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 100))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.largeTitle.bold())

            Text("Welcome to PRUUF")
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()

            ProgressView()
                .progressViewStyle(.circular)

            Text("Redirecting to dashboard...")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
                .frame(height: 60)
        }
    }
}
