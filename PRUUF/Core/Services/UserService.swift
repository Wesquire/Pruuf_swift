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

    private var database: PostgrestClient {
        SupabaseConfig.client.schema("public")
    }

    // MARK: - Initialization

    init() {
        // Database is accessed lazily via computed property to avoid thread-safety issues
    }

    // MARK: - User Operations

    /// Fetch or create a user record in the users table
    /// - Parameters:
    ///   - authId: The user's auth ID from Supabase Auth
    ///   - phoneNumber: The user's phone number
    ///   - displayName: The user's display name (for new user creation)
    /// - Returns: The fetched or newly created PruufUser
    func fetchOrCreateUser(authId: UUID, phoneNumber: String, displayName: String? = nil) async throws -> PruufUser {
        isLoading = true
        error = nil
        defer { isLoading = false }

        // Use server-side RPC that bypasses RLS to handle:
        // 1. Find by auth ID (exact match)
        // 2. Find by phone number + reassociate auth ID (re-auth scenario)
        // 3. Create new user if neither found
        do {
            return try await callFindOrCreateUserRPC(authId: authId, phoneNumber: phoneNumber, displayName: displayName)
        } catch {
            let msg = error.localizedDescription
            // Approach 3: If error is about a missing column, retry without display_name
            if msg.contains("does not exist") || msg.contains("column") {
                print("[UserService] RPC column error, retrying without display_name: \(msg)")
                do {
                    return try await callFindOrCreateUserRPC(authId: authId, phoneNumber: phoneNumber, displayName: nil)
                } catch {
                    throw UserServiceError.fetchFailed(error.localizedDescription)
                }
            }
            throw UserServiceError.fetchFailed(msg)
        }
    }

    /// Internal helper to call the find_or_create_user RPC
    private func callFindOrCreateUserRPC(authId: UUID, phoneNumber: String, displayName: String?) async throws -> PruufUser {
        var params: [String: String] = [
            "p_auth_id": authId.uuidString,
            "p_phone": phoneNumber,
            "p_timezone": TimeZone.current.identifier
        ]
        if let name = displayName {
            params["p_display_name"] = name
        }

        let users: [PruufUser] = try await database
            .rpc("find_or_create_user", params: params)
            .execute()
            .value

        guard let user = users.first else {
            throw UserServiceError.fetchFailed("RPC returned no user")
        }

        currentPruufUser = user
        return user
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
    ///   - displayName: The user's display name
    /// - Returns: The newly created PruufUser
    func createUser(authId: UUID, phoneNumber: String, phoneCountryCode: String = "+1", displayName: String? = nil) async throws -> PruufUser {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let now = Date()
        let timezone = TimeZone.current.identifier

        let newUser = NewUserRequest(
            id: authId,
            phoneNumber: phoneNumber,
            phoneCountryCode: phoneCountryCode,
            displayName: displayName,
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

        // Check cached user first
        if let user = currentPruufUser, user.timezone == currentTimezone {
            return nil
        }

        // Fetch fresh user to check timezone (handles case where currentPruufUser is nil)
        guard let user = try await fetchUser(by: userId) else {
            // User record doesn't exist yet — skip timezone sync
            return nil
        }

        if user.timezone == currentTimezone {
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
    let displayName: String?
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
        case displayName = "display_name"
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
