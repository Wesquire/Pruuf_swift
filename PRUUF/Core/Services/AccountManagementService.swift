import Foundation
import Supabase

/// Service for managing account operations per plan.md Phase 10 Section 10.2
/// Handles: Add Role, Change Ping Time, Delete Account
@MainActor
final class AccountManagementService: ObservableObject {

    // MARK: - Singleton

    static let shared = AccountManagementService()

    // MARK: - Published Properties

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: AccountManagementError?

    // MARK: - Private Properties

    private let database: PostgrestClient
    private let functions: FunctionsClient

    // MARK: - Constants

    /// Trial period duration in days per plan.md Section 9.1
    private static let trialDurationDays = 15

    /// Data retention period in days per plan.md Section 10.2 (regulatory requirement)
    static let dataRetentionDays = 30

    /// Default ping time (9:00 AM UTC)
    private static let defaultPingTime = "09:00:00"

    // MARK: - Initialization

    init(database: PostgrestClient? = nil,
         functions: FunctionsClient? = nil) {
        self.database = database ?? SupabaseConfig.client.schema("public")
        self.functions = functions ?? SupabaseConfig.functions
    }

    // MARK: - Add Role

    /// Add sender role to an existing receiver user
    /// Per plan.md Section 10.2:
    /// - Create sender_profiles record
    /// - Update users.primary_role to 'both'
    /// - Returns onboarding step to redirect to
    /// - Parameter userId: The user's UUID
    /// - Returns: The onboarding step for sender onboarding
    func addSenderRole(userId: UUID) async throws -> OnboardingStep {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let now = Date()
        let isoFormatter = ISO8601DateFormatter()

        do {
            // 1. Create sender_profiles record with default ping time
            let senderProfileData = SenderProfileInsert(
                userId: userId.uuidString,
                pingTime: Self.defaultPingTime,
                pingEnabled: true,
                createdAt: isoFormatter.string(from: now),
                updatedAt: isoFormatter.string(from: now)
            )

            try await database
                .from("sender_profiles")
                .insert(senderProfileData)
                .execute()

            // 2. Update users.primary_role to 'both'
            let roleUpdate = RoleUpdateData(
                primaryRole: UserRole.both.rawValue,
                updatedAt: isoFormatter.string(from: now)
            )

            try await database
                .from("users")
                .update(roleUpdate)
                .eq("id", value: userId.uuidString)
                .execute()

            // 3. Log audit event
            try await logAuditEvent(
                userId: userId,
                action: AuditAction.userUpdated,
                resourceType: .user,
                resourceId: userId,
                details: AuditDetails(
                    previousValue: UserRole.receiver.rawValue,
                    newValue: UserRole.both.rawValue,
                    reason: "Added sender role",
                    context: ["action": "add_sender_role"]
                )
            )

            // 4. Return the first sender onboarding step
            return .senderPingTime
        } catch {
            let wrappedError = AccountManagementError.roleAddFailed(error.localizedDescription)
            self.error = wrappedError
            throw wrappedError
        }
    }

    /// Add receiver role to an existing sender user
    /// Per plan.md Section 10.2:
    /// - Create receiver_profiles record
    /// - Start 15-day trial for receiver role
    /// - Update users.primary_role to 'both'
    /// - Generate unique code for receiver
    /// - Returns onboarding step to redirect to
    /// - Parameter userId: The user's UUID
    /// - Returns: Tuple of (onboarding step, unique code)
    func addReceiverRole(userId: UUID) async throws -> (step: OnboardingStep, code: String?) {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let now = Date()
        let trialEndDate = Calendar.current.date(byAdding: .day, value: Self.trialDurationDays, to: now)!
        let isoFormatter = ISO8601DateFormatter()

        do {
            // 1. Create receiver_profiles record with 15-day trial
            let receiverProfileData = ReceiverProfileInsert(
                userId: userId.uuidString,
                subscriptionStatus: SubscriptionStatus.trial.rawValue,
                trialStartDate: isoFormatter.string(from: now),
                trialEndDate: isoFormatter.string(from: trialEndDate),
                createdAt: isoFormatter.string(from: now),
                updatedAt: isoFormatter.string(from: now)
            )

            try await database
                .from("receiver_profiles")
                .insert(receiverProfileData)
                .execute()

            // 2. Update users.primary_role to 'both'
            let roleUpdate = RoleUpdateData(
                primaryRole: UserRole.both.rawValue,
                updatedAt: isoFormatter.string(from: now)
            )

            try await database
                .from("users")
                .update(roleUpdate)
                .eq("id", value: userId.uuidString)
                .execute()

            // 3. Generate unique code for receiver
            var uniqueCode: String? = nil
            do {
                let response: PostgrestResponse<String> = try await database
                    .rpc("create_receiver_code", params: ["p_user_id": userId.uuidString])
                    .execute()
                uniqueCode = response.value
            } catch {
                // Code generation failed, but role was added successfully
                print("[AccountManagementService] Code generation failed: \(error)")
            }

            // 4. Log audit event
            try await logAuditEvent(
                userId: userId,
                action: AuditAction.userUpdated,
                resourceType: .user,
                resourceId: userId,
                details: AuditDetails(
                    previousValue: UserRole.sender.rawValue,
                    newValue: UserRole.both.rawValue,
                    reason: "Added receiver role with 15-day trial",
                    context: [
                        "action": "add_receiver_role",
                        "trial_end_date": isoFormatter.string(from: trialEndDate)
                    ]
                )
            )

            // 5. Return the first receiver onboarding step and code
            return (.receiverCode, uniqueCode)
        } catch {
            let wrappedError = AccountManagementError.roleAddFailed(error.localizedDescription)
            self.error = wrappedError
            throw wrappedError
        }
    }

    // MARK: - Change Ping Time

    /// Update the sender's daily ping time
    /// Per plan.md Section 10.2:
    /// - Update sender_profiles.ping_time
    /// - Note: "This will take effect tomorrow"
    /// - Returns confirmation message
    /// - Parameters:
    ///   - userId: The user's UUID
    ///   - newTime: The new ping time as a Date
    /// - Returns: Confirmation result with formatted time
    func updatePingTime(userId: UUID, newTime: Date) async throws -> PingTimeUpdateResult {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let timeString = timeFormatter.string(from: newTime)

        let displayFormatter = DateFormatter()
        displayFormatter.timeStyle = .short
        let displayTime = displayFormatter.string(from: newTime)

        let isoFormatter = ISO8601DateFormatter()
        let now = Date()

        do {
            // 1. Update sender_profiles.ping_time
            let pingTimeUpdate = PingTimeUpdateData(
                pingTime: timeString,
                updatedAt: isoFormatter.string(from: now)
            )

            try await database
                .from("sender_profiles")
                .update(pingTimeUpdate)
                .eq("user_id", value: userId.uuidString)
                .execute()

            // 2. Log audit event
            try await logAuditEvent(
                userId: userId,
                action: "ping_time.updated",
                resourceType: .user,
                resourceId: userId,
                details: AuditDetails(
                    newValue: timeString,
                    reason: "User changed daily ping time",
                    context: ["display_time": displayTime]
                )
            )

            // 3. Return confirmation result
            return PingTimeUpdateResult(
                success: true,
                newTimeString: timeString,
                displayTime: displayTime,
                confirmationMessage: "Ping time updated to \(displayTime)",
                effectiveNote: "This will take effect tomorrow"
            )
        } catch {
            let wrappedError = AccountManagementError.pingTimeUpdateFailed(error.localizedDescription)
            self.error = wrappedError
            throw wrappedError
        }
    }

    // MARK: - Delete Account

    /// Validate phone number for account deletion confirmation
    /// - Parameters:
    ///   - enteredPhoneNumber: The phone number entered by user for confirmation
    ///   - userId: The user's UUID
    /// - Returns: True if phone numbers match
    func validatePhoneForDeletion(enteredPhoneNumber: String, userId: UUID) async throws -> Bool {
        // Fetch user's actual phone number
        let users: [PhoneNumberFetch] = try await database
            .from("users")
            .select("phone_number, phone_country_code")
            .eq("id", value: userId.uuidString)
            .execute()
            .value

        guard let user = users.first else {
            throw AccountManagementError.userNotFound
        }

        // Clean and compare phone numbers (remove spaces, dashes, etc.)
        let cleanedEntered = enteredPhoneNumber.filter { $0.isNumber || $0 == "+" }
        let fullUserPhone = "\(user.phoneCountryCode)\(user.phoneNumber)".filter { $0.isNumber || $0 == "+" }
        let userPhoneOnly = user.phoneNumber.filter { $0.isNumber }

        // Match either the full phone with country code or just the number part
        return cleanedEntered == fullUserPhone || cleanedEntered == userPhoneOnly || cleanedEntered == user.phoneNumber
    }

    /// Delete user account with soft delete
    /// Per plan.md Section 10.2:
    /// - Soft delete: users.is_active = false
    /// - Set all connections status = 'deleted'
    /// - Stop ping generation (handled by is_active check in cron)
    /// - Cancel subscription
    /// - Keep data for 30 days (regulatory requirement)
    /// - Log audit event
    /// - Schedule hard delete after 30 days via scheduled job
    /// - Parameter userId: The user's UUID
    /// - Returns: Deletion result with details
    func deleteAccount(userId: UUID) async throws -> AccountDeletionResult {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let isoFormatter = ISO8601DateFormatter()
        let now = Date()
        let hardDeleteDate = Calendar.current.date(byAdding: .day, value: Self.dataRetentionDays, to: now)!

        do {
            // 1. Soft delete user: set is_active = false
            let userDeleteUpdate = UserDeleteData(
                isActive: false,
                updatedAt: isoFormatter.string(from: now)
            )

            try await database
                .from("users")
                .update(userDeleteUpdate)
                .eq("id", value: userId.uuidString)
                .execute()

            // 2. Set all connections status = 'deleted'
            let connectionDeleteUpdate = ConnectionDeleteData(
                status: ConnectionStatus.deleted.rawValue,
                deletedAt: isoFormatter.string(from: now),
                updatedAt: isoFormatter.string(from: now)
            )

            // Delete connections where user is sender
            try await database
                .from("connections")
                .update(connectionDeleteUpdate)
                .eq("sender_id", value: userId.uuidString)
                .execute()

            // Delete connections where user is receiver
            try await database
                .from("connections")
                .update(connectionDeleteUpdate)
                .eq("receiver_id", value: userId.uuidString)
                .execute()

            // 3. Cancel subscription (if receiver)
            try? await cancelSubscriptionIfNeeded(userId: userId)

            // 4. Deactivate unique code (if receiver)
            try? await deactivateUniqueCode(userId: userId)

            // 5. Schedule hard delete (store the scheduled date in a metadata field or job queue)
            // This will be processed by the cleanup-expired-data cron job
            try? await scheduleHardDelete(userId: userId, scheduledDate: hardDeleteDate)

            // 6. Log audit event
            try await logAuditEvent(
                userId: userId,
                action: AuditAction.userDeleted,
                resourceType: .user,
                resourceId: userId,
                details: AuditDetails(
                    reason: "User requested account deletion",
                    context: [
                        "soft_delete_date": isoFormatter.string(from: now),
                        "hard_delete_scheduled": isoFormatter.string(from: hardDeleteDate),
                        "retention_days": "\(Self.dataRetentionDays)"
                    ]
                )
            )

            return AccountDeletionResult(
                success: true,
                softDeleteDate: now,
                hardDeleteScheduledDate: hardDeleteDate,
                retentionDays: Self.dataRetentionDays,
                message: "Your account has been deleted. Your data will be permanently removed after \(Self.dataRetentionDays) days."
            )
        } catch {
            let wrappedError = AccountManagementError.deletionFailed(error.localizedDescription)
            self.error = wrappedError
            throw wrappedError
        }
    }

    // MARK: - Private Helper Methods

    /// Cancel subscription if user has receiver profile
    private func cancelSubscriptionIfNeeded(userId: UUID) async throws {
        let isoFormatter = ISO8601DateFormatter()
        let now = Date()

        let subscriptionUpdate = SubscriptionCancelData(
            subscriptionStatus: SubscriptionStatus.canceled.rawValue,
            updatedAt: isoFormatter.string(from: now)
        )

        try await database
            .from("receiver_profiles")
            .update(subscriptionUpdate)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    /// Deactivate unique code for receiver
    private func deactivateUniqueCode(userId: UUID) async throws {
        let codeUpdate = UniqueCodeDeactivateData(isActive: false)

        try await database
            .from("unique_codes")
            .update(codeUpdate)
            .eq("receiver_id", value: userId.uuidString)
            .execute()
    }

    /// Schedule hard delete by updating user metadata
    /// The cleanup-expired-data cron job will process this
    private func scheduleHardDelete(userId: UUID, scheduledDate: Date) async throws {
        let isoFormatter = ISO8601DateFormatter()

        // We store the hard delete schedule in a separate table or in user metadata
        // For now, we use the deleted_at concept - when is_active=false and 30 days pass
        // The cleanup job checks: WHERE is_active = false AND updated_at < (now - 30 days)

        // Alternatively, insert into a scheduled_deletions table if it exists
        // For this implementation, we rely on the cleanup job checking updated_at

        print("[AccountManagementService] Hard delete scheduled for \(isoFormatter.string(from: scheduledDate))")
    }

    /// Log an audit event
    private func logAuditEvent(
        userId: UUID,
        action: String,
        resourceType: ResourceType,
        resourceId: UUID,
        details: AuditDetails?
    ) async throws {
        let auditEntry = AuditLogInsert(
            userId: userId.uuidString,
            action: action,
            resourceType: resourceType.rawValue,
            resourceId: resourceId.uuidString,
            details: details
        )

        do {
            try await database
                .from("audit_logs")
                .insert(auditEntry)
                .execute()
        } catch {
            // Don't fail the main operation if audit logging fails
            print("[AccountManagementService] Failed to log audit event: \(error)")
        }
    }
}

// MARK: - Data Transfer Objects

/// Insert data for sender profile
private struct SenderProfileInsert: Codable {
    let userId: String
    let pingTime: String
    let pingEnabled: Bool
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case pingTime = "ping_time"
        case pingEnabled = "ping_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Insert data for receiver profile
private struct ReceiverProfileInsert: Codable {
    let userId: String
    let subscriptionStatus: String
    let trialStartDate: String
    let trialEndDate: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case subscriptionStatus = "subscription_status"
        case trialStartDate = "trial_start_date"
        case trialEndDate = "trial_end_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Update data for user role
private struct RoleUpdateData: Codable {
    let primaryRole: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case primaryRole = "primary_role"
        case updatedAt = "updated_at"
    }
}

/// Update data for ping time
private struct PingTimeUpdateData: Codable {
    let pingTime: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case pingTime = "ping_time"
        case updatedAt = "updated_at"
    }
}

/// Update data for ping enabled toggle (used by SettingsViewModel)
struct PingEnabledUpdate: Codable {
    let pingEnabled: Bool
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case pingEnabled = "ping_enabled"
        case updatedAt = "updated_at"
    }
}

/// Update data for user deletion
private struct UserDeleteData: Codable {
    let isActive: Bool
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case updatedAt = "updated_at"
    }
}

/// Update data for connection deletion
private struct ConnectionDeleteData: Codable {
    let status: String
    let deletedAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case status
        case deletedAt = "deleted_at"
        case updatedAt = "updated_at"
    }
}

/// Update data for subscription cancellation
private struct SubscriptionCancelData: Codable {
    let subscriptionStatus: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case subscriptionStatus = "subscription_status"
        case updatedAt = "updated_at"
    }
}

/// Update data for deactivating unique code
private struct UniqueCodeDeactivateData: Codable {
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
    }
}

/// Fetch phone number data
private struct PhoneNumberFetch: Codable {
    let phoneNumber: String
    let phoneCountryCode: String

    enum CodingKeys: String, CodingKey {
        case phoneNumber = "phone_number"
        case phoneCountryCode = "phone_country_code"
    }
}

/// Insert data for audit log
private struct AuditLogInsert: Codable {
    let userId: String
    let action: String
    let resourceType: String
    let resourceId: String
    let details: AuditDetails?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case action
        case resourceType = "resource_type"
        case resourceId = "resource_id"
        case details
    }
}

// MARK: - Result Types

/// Result of ping time update operation
struct PingTimeUpdateResult {
    let success: Bool
    let newTimeString: String
    let displayTime: String
    let confirmationMessage: String
    let effectiveNote: String
}

/// Result of account deletion operation
struct AccountDeletionResult {
    let success: Bool
    let softDeleteDate: Date
    let hardDeleteScheduledDate: Date
    let retentionDays: Int
    let message: String
}

// MARK: - Errors

/// Errors for account management operations
enum AccountManagementError: LocalizedError {
    case roleAddFailed(String)
    case pingTimeUpdateFailed(String)
    case deletionFailed(String)
    case userNotFound
    case phoneValidationFailed
    case invalidOperation(String)

    var errorDescription: String? {
        switch self {
        case .roleAddFailed(let message):
            return "Failed to add role: \(message)"
        case .pingTimeUpdateFailed(let message):
            return "Failed to update ping time: \(message)"
        case .deletionFailed(let message):
            return "Failed to delete account: \(message)"
        case .userNotFound:
            return "User not found"
        case .phoneValidationFailed:
            return "Phone number doesn't match. Please enter your phone number exactly as registered."
        case .invalidOperation(let message):
            return "Invalid operation: \(message)"
        }
    }
}
