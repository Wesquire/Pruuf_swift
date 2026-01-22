import Foundation
import Supabase

/// Service for managing role selection and profile creation during onboarding
/// Handles creating sender_profiles and receiver_profiles records
@MainActor
final class RoleSelectionService: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var senderProfile: SenderProfile?
    @Published private(set) var receiverProfile: ReceiverProfile?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: RoleSelectionError?

    // MARK: - Private Properties

    private let database: PostgrestClient

    // MARK: - Constants

    /// Default ping time (9:00 AM UTC - will be adjusted for user timezone)
    private static let defaultPingTime = "09:00:00"

    /// Trial period duration in days
    private static let trialDurationDays = 15

    // MARK: - Initialization

    init(database: PostgrestClient? = nil) {
        self.database = database ?? SupabaseConfig.client.schema("public")
    }

    // MARK: - Role Selection

    /// Select a role for the user and create appropriate profile
    /// - Parameters:
    ///   - role: The selected role (sender or receiver)
    ///   - userId: The user's UUID
    /// - Returns: The updated user after role selection
    func selectRole(_ role: UserRole, for userId: UUID) async throws -> PruufUser {
        guard role == .sender || role == .receiver else {
            throw RoleSelectionError.invalidRole("Initial role must be sender or receiver")
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Update user's primary role
            let updatedUser = try await updateUserPrimaryRole(userId: userId, role: role)

            // Create the appropriate profile
            if role == .sender {
                try await createSenderProfile(for: userId)
            } else {
                try await createReceiverProfile(for: userId)
            }

            return updatedUser
        } catch let roleError as RoleSelectionError {
            self.error = roleError
            throw roleError
        } catch {
            let wrappedError = RoleSelectionError.profileCreationFailed(error.localizedDescription)
            self.error = wrappedError
            throw wrappedError
        }
    }

    /// Add the other role to an existing user (EC-2.2)
    /// - Parameters:
    ///   - role: The role to add (sender or receiver)
    ///   - userId: The user's UUID
    /// - Returns: The updated user with both roles
    func addSecondRole(_ role: UserRole, for userId: UUID) async throws -> PruufUser {
        guard role == .sender || role == .receiver else {
            throw RoleSelectionError.invalidRole("Can only add sender or receiver role")
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Update user's primary role to 'both'
            let updatedUser = try await updateUserPrimaryRole(userId: userId, role: .both)

            // Create the appropriate profile
            if role == .sender {
                try await createSenderProfile(for: userId)
            } else {
                try await createReceiverProfile(for: userId)
            }

            return updatedUser
        } catch let roleError as RoleSelectionError {
            self.error = roleError
            throw roleError
        } catch {
            let wrappedError = RoleSelectionError.profileCreationFailed(error.localizedDescription)
            self.error = wrappedError
            throw wrappedError
        }
    }

    // MARK: - Profile Creation

    /// Create a sender profile for the user
    /// - Parameter userId: The user's UUID
    @discardableResult
    func createSenderProfile(for userId: UUID, pingTime: String? = nil) async throws -> SenderProfile {
        let time = pingTime ?? Self.defaultPingTime

        let request = NewSenderProfileRequest(
            userId: userId,
            pingTime: time,
            pingEnabled: true
        )

        do {
            let profile: SenderProfile = try await database
                .from("sender_profiles")
                .insert(request)
                .select()
                .single()
                .execute()
                .value

            senderProfile = profile
            return profile
        } catch {
            throw RoleSelectionError.profileCreationFailed("Failed to create sender profile: \(error.localizedDescription)")
        }
    }

    /// Create a receiver profile for the user with trial subscription
    /// - Parameter userId: The user's UUID
    @discardableResult
    func createReceiverProfile(for userId: UUID) async throws -> ReceiverProfile {
        let trialStartDate = Date()
        let trialEndDate = Calendar.current.date(
            byAdding: .day,
            value: Self.trialDurationDays,
            to: trialStartDate
        ) ?? trialStartDate

        let request = NewReceiverProfileRequest(
            userId: userId,
            subscriptionStatus: .trial,
            trialStartDate: trialStartDate,
            trialEndDate: trialEndDate
        )

        do {
            let profile: ReceiverProfile = try await database
                .from("receiver_profiles")
                .insert(request)
                .select()
                .single()
                .execute()
                .value

            receiverProfile = profile
            return profile
        } catch {
            throw RoleSelectionError.profileCreationFailed("Failed to create receiver profile: \(error.localizedDescription)")
        }
    }

    // MARK: - Profile Fetching

    /// Fetch existing sender profile for user
    /// - Parameter userId: The user's UUID
    /// - Returns: The sender profile if it exists
    func fetchSenderProfile(for userId: UUID) async throws -> SenderProfile? {
        do {
            let profile: SenderProfile = try await database
                .from("sender_profiles")
                .select()
                .eq("user_id", value: userId.uuidString)
                .single()
                .execute()
                .value

            senderProfile = profile
            return profile
        } catch let postgrestError as PostgrestError {
            if postgrestError.code == "PGRST116" {
                return nil
            }
            throw RoleSelectionError.fetchFailed(postgrestError.localizedDescription)
        } catch {
            if error.localizedDescription.contains("no rows") ||
               error.localizedDescription.contains("0 rows") {
                return nil
            }
            throw RoleSelectionError.fetchFailed(error.localizedDescription)
        }
    }

    /// Fetch existing receiver profile for user
    /// - Parameter userId: The user's UUID
    /// - Returns: The receiver profile if it exists
    func fetchReceiverProfile(for userId: UUID) async throws -> ReceiverProfile? {
        do {
            let profile: ReceiverProfile = try await database
                .from("receiver_profiles")
                .select()
                .eq("user_id", value: userId.uuidString)
                .single()
                .execute()
                .value

            receiverProfile = profile
            return profile
        } catch let postgrestError as PostgrestError {
            if postgrestError.code == "PGRST116" {
                return nil
            }
            throw RoleSelectionError.fetchFailed(postgrestError.localizedDescription)
        } catch {
            if error.localizedDescription.contains("no rows") ||
               error.localizedDescription.contains("0 rows") {
                return nil
            }
            throw RoleSelectionError.fetchFailed(error.localizedDescription)
        }
    }

    /// Check if user has a specific role profile
    /// - Parameters:
    ///   - role: The role to check
    ///   - userId: The user's UUID
    /// - Returns: True if the user has the profile for this role
    func hasProfile(for role: UserRole, userId: UUID) async throws -> Bool {
        switch role {
        case .sender:
            return try await fetchSenderProfile(for: userId) != nil
        case .receiver:
            return try await fetchReceiverProfile(for: userId) != nil
        case .both:
            let hasSender = try await fetchSenderProfile(for: userId) != nil
            let hasReceiver = try await fetchReceiverProfile(for: userId) != nil
            return hasSender && hasReceiver
        }
    }

    // MARK: - User Update

    /// Update user's primary role
    /// - Parameters:
    ///   - userId: The user's UUID
    ///   - role: The new primary role
    /// - Returns: The updated user
    private func updateUserPrimaryRole(userId: UUID, role: UserRole) async throws -> PruufUser {
        let updates = UserUpdateRequest(primaryRole: role)

        do {
            let user: PruufUser = try await database
                .from("users")
                .update(updates)
                .eq("id", value: userId.uuidString)
                .select()
                .single()
                .execute()
                .value

            return user
        } catch {
            throw RoleSelectionError.userUpdateFailed(error.localizedDescription)
        }
    }

    // MARK: - Onboarding Progress (EC-2.1)

    /// Save onboarding progress for resuming later
    /// - Parameters:
    ///   - step: The current onboarding step
    ///   - userId: The user's UUID
    func saveOnboardingProgress(step: OnboardingStep, for userId: UUID) async throws {
        let updates = UserUpdateRequest(onboardingStep: step)

        do {
            let _: PruufUser = try await database
                .from("users")
                .update(updates)
                .eq("id", value: userId.uuidString)
                .select()
                .single()
                .execute()
                .value
        } catch {
            throw RoleSelectionError.progressSaveFailed(error.localizedDescription)
        }
    }

    /// Get the onboarding step to resume from
    /// - Parameter userId: The user's UUID
    /// - Returns: The onboarding step to resume from, or roleSelection if none saved
    func getResumeStep(for userId: UUID) async throws -> OnboardingStep {
        do {
            let user: PruufUser = try await database
                .from("users")
                .select()
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value

            return user.onboardingStep ?? .roleSelection
        } catch {
            return .roleSelection
        }
    }

    // MARK: - Clear State

    /// Clear all local state
    func clearState() {
        senderProfile = nil
        receiverProfile = nil
        error = nil
    }
}

// MARK: - Role Selection Errors

enum RoleSelectionError: LocalizedError {
    case invalidRole(String)
    case profileCreationFailed(String)
    case fetchFailed(String)
    case userUpdateFailed(String)
    case progressSaveFailed(String)
    case profileAlreadyExists

    var errorDescription: String? {
        switch self {
        case .invalidRole(let message):
            return "Invalid role: \(message)"
        case .profileCreationFailed(let message):
            return "Failed to create profile: \(message)"
        case .fetchFailed(let message):
            return "Failed to fetch profile: \(message)"
        case .userUpdateFailed(let message):
            return "Failed to update user: \(message)"
        case .progressSaveFailed(let message):
            return "Failed to save progress: \(message)"
        case .profileAlreadyExists:
            return "A profile already exists for this role"
        }
    }
}
