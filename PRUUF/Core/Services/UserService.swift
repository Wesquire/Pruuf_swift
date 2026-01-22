import Foundation
import Supabase

/// Service for managing user records in the Supabase `users` table
/// Handles CRUD operations for PruufUser entities
@MainActor
final class UserService: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var currentPruufUser: PruufUser?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: UserServiceError?

    // MARK: - Private Properties

    private let database: PostgrestClient

    // MARK: - Initialization

    nonisolated init(database: PostgrestClient? = nil) {
        self.database = database ?? SupabaseConfig.client.schema("public")
    }

    // MARK: - User Operations

    /// Fetch or create a user record in the users table
    /// - Parameters:
    ///   - authId: The user's auth ID from Supabase Auth
    ///   - phoneNumber: The user's phone number
    /// - Returns: The fetched or newly created PruufUser
    func fetchOrCreateUser(authId: UUID, phoneNumber: String) async throws -> PruufUser {
        isLoading = true
        error = nil
        defer { isLoading = false }

        // First, try to fetch existing user
        if let existingUser = try await fetchUser(by: authId) {
            currentPruufUser = existingUser
            return existingUser
        }

        // User doesn't exist, create new one
        let newUser = try await createUser(authId: authId, phoneNumber: phoneNumber)
        currentPruufUser = newUser
        return newUser
    }

    /// Fetch a user by their ID
    /// - Parameter id: The user's UUID
    /// - Returns: The PruufUser if found, nil otherwise
    func fetchUser(by id: UUID) async throws -> PruufUser? {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response: PruufUser = try await database
                .from("users")
                .select()
                .eq("id", value: id.uuidString)
                .single()
                .execute()
                .value

            return response
        } catch let postgrestError as PostgrestError {
            // PGRST116 is "no rows found" - not an error, just means user doesn't exist yet
            if postgrestError.code == "PGRST116" {
                return nil
            }
            throw UserServiceError.fetchFailed(postgrestError.localizedDescription)
        } catch {
            // Check if it's a "no rows" scenario with different error type
            if error.localizedDescription.contains("no rows") ||
               error.localizedDescription.contains("0 rows") {
                return nil
            }
            throw UserServiceError.fetchFailed(error.localizedDescription)
        }
    }

    /// Create a new user in the database
    /// - Parameters:
    ///   - authId: The user's auth ID from Supabase Auth
    ///   - phoneNumber: The user's phone number (without country code)
    ///   - phoneCountryCode: The country code (default: "+1")
    /// - Returns: The newly created PruufUser
    func createUser(authId: UUID, phoneNumber: String, phoneCountryCode: String = "+1") async throws -> PruufUser {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let now = Date()
        let timezone = TimeZone.current.identifier

        let newUser = NewUserRequest(
            id: authId,
            phoneNumber: phoneNumber,
            phoneCountryCode: phoneCountryCode,
            timezone: timezone,
            isActive: true,
            hasCompletedOnboarding: false,
            notificationPreferences: .defaults,
            createdAt: now,
            updatedAt: now
        )

        do {
            let response: PruufUser = try await database
                .from("users")
                .insert(newUser)
                .select()
                .single()
                .execute()
                .value

            return response
        } catch {
            throw UserServiceError.createFailed(error.localizedDescription)
        }
    }

    /// Update an existing user's profile
    /// - Parameters:
    ///   - userId: The user's UUID
    ///   - updates: The fields to update
    /// - Returns: The updated PruufUser
    func updateUser(userId: UUID, updates: UserUpdateRequest) async throws -> PruufUser {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response: PruufUser = try await database
                .from("users")
                .update(updates)
                .eq("id", value: userId.uuidString)
                .select()
                .single()
                .execute()
                .value

            currentPruufUser = response
            return response
        } catch {
            throw UserServiceError.updateFailed(error.localizedDescription)
        }
    }

    /// Mark user as having completed onboarding
    /// - Parameter userId: The user's UUID
    /// - Returns: The updated PruufUser
    func completeOnboarding(for userId: UUID) async throws -> PruufUser {
        let updates = UserUpdateRequest(hasCompletedOnboarding: true)
        return try await updateUser(userId: userId, updates: updates)
    }

    /// Check if user has completed onboarding
    /// - Parameter userId: The user's UUID
    /// - Returns: True if onboarding is complete, false otherwise
    func hasCompletedOnboarding(userId: UUID) async throws -> Bool {
        guard let user = try await fetchUser(by: userId) else {
            return false
        }
        return user.hasCompletedOnboarding
    }

    /// Clear the current user (on sign out)
    func clearCurrentUser() {
        currentPruufUser = nil
        error = nil
    }

    // MARK: - Role Selection

    /// Update user's primary role
    /// - Parameters:
    ///   - userId: The user's UUID
    ///   - role: The new primary role
    /// - Returns: The updated PruufUser
    func updatePrimaryRole(userId: UUID, role: UserRole) async throws -> PruufUser {
        let updates = UserUpdateRequest(primaryRole: role)
        return try await updateUser(userId: userId, updates: updates)
    }

    /// Save onboarding progress step
    /// - Parameters:
    ///   - userId: The user's UUID
    ///   - step: The current onboarding step
    /// - Returns: The updated PruufUser
    func saveOnboardingStep(userId: UUID, step: OnboardingStep) async throws -> PruufUser {
        let updates = UserUpdateRequest(onboardingStep: step)
        return try await updateUser(userId: userId, updates: updates)
    }

    // MARK: - Timezone Management

    /// Update user's timezone based on current device timezone
    /// Phase 6.1: "9 AM local" means 9 AM wherever sender currently is
    /// This should be called when the app becomes active to support sender travel
    /// - Parameter userId: The user's UUID
    /// - Returns: The updated PruufUser if timezone changed, nil if no change needed
    @discardableResult
    func syncTimezoneIfNeeded(userId: UUID) async throws -> PruufUser? {
        let currentTimezone = TimeZone.current.identifier

        // Check if we need to update
        if let user = currentPruufUser, user.timezone == currentTimezone {
            // No change needed
            return nil
        }

        // Timezone has changed, update it
        let updates = UserUpdateRequest(timezone: currentTimezone)
        return try await updateUser(userId: userId, updates: updates)
    }

    /// Get the user's current onboarding step for resuming
    /// - Parameter userId: The user's UUID
    /// - Returns: The onboarding step to resume from
    func getOnboardingStep(userId: UUID) async throws -> OnboardingStep? {
        guard let user = try await fetchUser(by: userId) else {
            return nil
        }
        return user.onboardingStep
    }
}

// MARK: - New User Request

/// Request model for creating a new user
private struct NewUserRequest: Codable {
    let id: UUID
    let phoneNumber: String
    let phoneCountryCode: String
    let timezone: String
    let isActive: Bool
    let hasCompletedOnboarding: Bool
    let notificationPreferences: NotificationPreferences
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case phoneNumber = "phone_number"
        case phoneCountryCode = "phone_country_code"
        case timezone
        case isActive = "is_active"
        case hasCompletedOnboarding = "has_completed_onboarding"
        case notificationPreferences = "notification_preferences"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - UserService Errors

enum UserServiceError: LocalizedError {
    case fetchFailed(String)
    case createFailed(String)
    case updateFailed(String)
    case userNotFound
    case invalidData

    var errorDescription: String? {
        switch self {
        case .fetchFailed(let message):
            return "Failed to fetch user: \(message)"
        case .createFailed(let message):
            return "Failed to create user: \(message)"
        case .updateFailed(let message):
            return "Failed to update user: \(message)"
        case .userNotFound:
            return "User not found"
        case .invalidData:
            return "Invalid user data"
        }
    }
}
