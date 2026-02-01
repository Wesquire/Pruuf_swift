import Foundation
import Supabase

/// Service for managing connection invitations
/// Handles creating invitation codes and tracking invitation status
@MainActor
final class InvitationService: ObservableObject {

    // MARK: - Singleton

    static let shared = InvitationService()

    // MARK: - Published Properties

    @Published private(set) var pendingInvitations: [ConnectionInvitation] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: InvitationServiceError?

    // MARK: - Private Properties

    private let database: PostgrestClient

    // MARK: - Constants

    /// Length of invitation codes
    private static let codeLength = 6

    /// Invitation code expiration in days
    private static let codeExpirationDays = 7

    // MARK: - Initialization

    init(database: PostgrestClient? = nil) {
        self.database = database ?? SupabaseConfig.client.schema("public")
    }

    // MARK: - Generate Invitation Code

    /// Generate a unique 6-digit invitation code
    /// - Returns: A unique 6-digit code
    func generateInvitationCode() -> String {
        let digits = "0123456789"
        return String((0..<Self.codeLength).map { _ in digits.randomElement()! })
    }

    // MARK: - Create Invitation

    /// Create a new invitation for a contact
    /// - Parameters:
    ///   - senderId: The ID of the user sending the invitation
    ///   - recipientPhoneNumber: The phone number of the recipient
    ///   - recipientName: The name of the recipient (from contacts)
    /// - Returns: The created invitation
    func createInvitation(
        senderId: UUID,
        recipientPhoneNumber: String,
        recipientName: String
    ) async throws -> ConnectionInvitation {
        isLoading = true
        error = nil
        defer { isLoading = false }

        // Generate a unique code
        let code = generateInvitationCode()

        // Calculate expiration date
        let expiresAt = Calendar.current.date(
            byAdding: .day,
            value: Self.codeExpirationDays,
            to: Date()
        ) ?? Date()

        let request = NewInvitationRequest(
            senderId: senderId,
            invitationCode: code,
            recipientPhoneNumber: recipientPhoneNumber,
            recipientName: recipientName,
            status: .pending,
            expiresAt: expiresAt
        )

        do {
            let invitation: ConnectionInvitation = try await database
                .from("connection_invitations")
                .insert(request)
                .select()
                .single()
                .execute()
                .value

            pendingInvitations.append(invitation)
            return invitation
        } catch {
            let serviceError = InvitationServiceError.createFailed(error.localizedDescription)
            self.error = serviceError
            throw serviceError
        }
    }

    // MARK: - Fetch Pending Invitations

    /// Fetch all pending invitations for a sender
    /// - Parameter senderId: The sender's user ID
    func fetchPendingInvitations(senderId: UUID) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            let invitations: [ConnectionInvitation] = try await database
                .from("connection_invitations")
                .select()
                .eq("sender_id", value: senderId.uuidString)
                .eq("status", value: InvitationStatus.pending.rawValue)
                .order("created_at", ascending: false)
                .execute()
                .value

            pendingInvitations = invitations
        } catch {
            let serviceError = InvitationServiceError.fetchFailed(error.localizedDescription)
            self.error = serviceError
            throw serviceError
        }
    }

    // MARK: - Validate Invitation Code

    /// Validate an invitation code and return the invitation if valid
    /// - Parameter code: The 6-digit invitation code
    /// - Returns: The invitation if valid and not expired
    func validateInvitationCode(_ code: String) async throws -> ConnectionInvitation {
        isLoading = true
        defer { isLoading = false }

        do {
            let invitations: [ConnectionInvitation] = try await database
                .from("connection_invitations")
                .select("*, sender:sender_id(id, phone_number, display_name, avatar_url)")
                .eq("invitation_code", value: code)
                .eq("status", value: InvitationStatus.pending.rawValue)
                .execute()
                .value

            guard let invitation = invitations.first else {
                throw InvitationServiceError.invalidCode
            }

            // Check if expired
            if let expiresAt = invitation.expiresAt, Date() > expiresAt {
                throw InvitationServiceError.codeExpired
            }

            return invitation
        } catch let invitationError as InvitationServiceError {
            self.error = invitationError
            throw invitationError
        } catch {
            let serviceError = InvitationServiceError.fetchFailed(error.localizedDescription)
            self.error = serviceError
            throw serviceError
        }
    }

    // MARK: - Accept Invitation

    /// Accept an invitation and create the connection
    /// - Parameters:
    ///   - invitationId: The invitation ID
    ///   - receiverId: The receiver's user ID
    /// - Returns: The created connection
    func acceptInvitation(invitationId: UUID, receiverId: UUID) async throws -> Connection {
        isLoading = true
        defer { isLoading = false }

        do {
            // Update invitation status
            let _: ConnectionInvitation = try await database
                .from("connection_invitations")
                .update(["status": InvitationStatus.accepted.rawValue])
                .eq("id", value: invitationId.uuidString)
                .select()
                .single()
                .execute()
                .value

            // Get the invitation to find the sender
            let invitation: ConnectionInvitation = try await database
                .from("connection_invitations")
                .select()
                .eq("id", value: invitationId.uuidString)
                .single()
                .execute()
                .value

            // Create the connection
            let connection: Connection = try await database
                .from("connections")
                .insert([
                    "sender_id": invitation.senderId.uuidString,
                    "receiver_id": receiverId.uuidString,
                    "status": ConnectionStatus.active.rawValue,
                    "connection_code": invitation.invitationCode
                ])
                .select()
                .single()
                .execute()
                .value

            // Remove from pending
            pendingInvitations.removeAll { $0.id == invitationId }

            return connection
        } catch let invitationError as InvitationServiceError {
            self.error = invitationError
            throw invitationError
        } catch {
            let serviceError = InvitationServiceError.acceptFailed(error.localizedDescription)
            self.error = serviceError
            throw serviceError
        }
    }

    // MARK: - Cancel Invitation

    /// Cancel a pending invitation
    /// - Parameter invitationId: The invitation ID to cancel
    func cancelInvitation(invitationId: UUID) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await database
                .from("connection_invitations")
                .update(["status": InvitationStatus.cancelled.rawValue])
                .eq("id", value: invitationId.uuidString)
                .execute()

            pendingInvitations.removeAll { $0.id == invitationId }
        } catch {
            let serviceError = InvitationServiceError.cancelFailed(error.localizedDescription)
            self.error = serviceError
            throw serviceError
        }
    }

    // MARK: - Nudge Receiver (Requirement 3)

    /// Send a reminder/nudge to a pending receiver
    /// Rate limited to once per 24 hours per receiver
    /// - Parameters:
    ///   - invitationId: The invitation ID to nudge
    /// - Returns: The invitation if nudge is allowed, nil if rate limited
    func nudgeReceiver(invitationId: UUID) async throws -> ConnectionInvitation? {
        isLoading = true
        defer { isLoading = false }

        do {
            // Fetch the invitation to check last nudge time
            let invitations: [ConnectionInvitation] = try await database
                .from("connection_invitations")
                .select()
                .eq("id", value: invitationId.uuidString)
                .eq("status", value: InvitationStatus.pending.rawValue)
                .execute()
                .value

            guard let invitation = invitations.first else {
                throw InvitationServiceError.invalidCode
            }

            // Check rate limiting - max 1 nudge per 24 hours
            if let lastNudge = invitation.lastNudgeAt {
                let hoursSinceLastNudge = Date().timeIntervalSince(lastNudge) / 3600
                if hoursSinceLastNudge < 24 {
                    throw InvitationServiceError.nudgeRateLimited(hoursRemaining: Int(24 - hoursSinceLastNudge))
                }
            }

            // Update the last_nudge_at timestamp
            let updatedInvitation: ConnectionInvitation = try await database
                .from("connection_invitations")
                .update(["last_nudge_at": ISO8601DateFormatter().string(from: Date())])
                .eq("id", value: invitationId.uuidString)
                .select()
                .single()
                .execute()
                .value

            return updatedInvitation

        } catch let invitationError as InvitationServiceError {
            self.error = invitationError
            throw invitationError
        } catch {
            let serviceError = InvitationServiceError.nudgeFailed(error.localizedDescription)
            self.error = serviceError
            throw serviceError
        }
    }

    /// Generate a nudge/reminder message
    /// - Parameters:
    ///   - senderName: The name of the sender
    ///   - code: The invitation code
    /// - Returns: The formatted reminder message
    func generateNudgeMessage(senderName: String, code: String) -> String {
        return "Reminder: \(senderName) is waiting for you to accept their PRUUF invitation. Use code \(code) in the PRUUF app to connect: https://pruuf.app/join"
    }

    // MARK: - Generate Invitation Message

    /// Generate the invitation message (for sharing via Messages or other apps)
    /// - Parameters:
    ///   - senderName: The name of the sender
    ///   - code: The invitation code
    /// - Returns: The formatted invitation message
    func generateInvitationMessage(senderName: String, code: String) -> String {
        return "\(senderName) wants to send you daily Pruufs on PRUUF to let you know they're safe. Download the app and use code \(code) to connect: https://pruuf.app/join"
    }

    // MARK: - Clear Data

    /// Clear all local data
    func clearData() {
        pendingInvitations = []
        error = nil
    }
}

// MARK: - Connection Invitation Model

/// Represents a pending connection invitation
struct ConnectionInvitation: Codable, Identifiable, Equatable {
    let id: UUID
    let senderId: UUID
    let invitationCode: String
    let recipientPhoneNumber: String
    let recipientName: String?
    var status: InvitationStatus
    let expiresAt: Date?
    let createdAt: Date
    var updatedAt: Date

    /// Last time a nudge/reminder was sent (for rate limiting)
    var lastNudgeAt: Date?

    /// The sender's user profile (populated via join)
    var sender: PruufUser?

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case invitationCode = "invitation_code"
        case recipientPhoneNumber = "recipient_phone_number"
        case recipientName = "recipient_name"
        case status
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastNudgeAt = "last_nudge_at"
        case sender
    }

    /// Check if invitation is expired
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }

    /// Days until expiration
    var daysUntilExpiration: Int? {
        guard let expiresAt = expiresAt else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
        return max(0, days)
    }
}

// MARK: - Invitation Status

/// Status of a connection invitation
enum InvitationStatus: String, Codable {
    case pending = "pending"
    case accepted = "accepted"
    case declined = "declined"
    case cancelled = "cancelled"
    case expired = "expired"
}

// MARK: - New Invitation Request

/// Request model for creating a new invitation
struct NewInvitationRequest: Codable {
    let senderId: UUID
    let invitationCode: String
    let recipientPhoneNumber: String
    let recipientName: String
    let status: InvitationStatus
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case senderId = "sender_id"
        case invitationCode = "invitation_code"
        case recipientPhoneNumber = "recipient_phone_number"
        case recipientName = "recipient_name"
        case status
        case expiresAt = "expires_at"
    }
}

// MARK: - Invitation Service Errors

enum InvitationServiceError: LocalizedError {
    case createFailed(String)
    case fetchFailed(String)
    case invalidCode
    case codeExpired
    case acceptFailed(String)
    case cancelFailed(String)
    case nudgeFailed(String)
    case nudgeRateLimited(hoursRemaining: Int)

    var errorDescription: String? {
        switch self {
        case .createFailed(let message):
            return "Failed to create invitation: \(message)"
        case .fetchFailed(let message):
            return "Failed to fetch invitations: \(message)"
        case .invalidCode:
            return "Invalid invitation code. Please check and try again."
        case .codeExpired:
            return "This invitation code has expired. Please ask for a new code."
        case .acceptFailed(let message):
            return "Failed to accept invitation: \(message)"
        case .cancelFailed(let message):
            return "Failed to cancel invitation: \(message)"
        case .nudgeFailed(let message):
            return "Failed to send reminder: \(message)"
        case .nudgeRateLimited(let hoursRemaining):
            return "You can send another reminder in \(hoursRemaining) hour(s)."
        }
    }
}
