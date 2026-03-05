import Foundation

/// Represents a connection (relationship) between a sender and receiver
/// Maps to the `connections` table in Supabase
struct Connection: Codable, Identifiable, Equatable {
    /// Unique connection identifier
    let id: UUID

    /// User who sends pings (the one checking in)
    let senderId: UUID

    /// User who receives notifications (the one monitoring)
    let receiverId: UUID

    /// Current status of the connection
    var status: ConnectionStatus

    /// When the connection was created
    let createdAt: Date

    /// When the connection was last updated
    var updatedAt: Date

    /// When the connection was soft-deleted
    var deletedAt: Date?

    /// The unique code used to establish this connection
    var connectionCode: String?

    /// The receiver's user profile (populated via join)
    var receiver: PruufUser?

    /// The sender's user profile (populated via join)
    var sender: PruufUser?

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case receiverId = "receiver_id"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case connectionCode = "connection_code"
        case receiver
        case sender
    }

    // MARK: - Computed Properties

    /// Display name for the connection (sender or receiver's name based on context)
    func displayName(forUserId userId: UUID) -> String {
        if userId == senderId {
            return receiver?.displayName ?? "Unknown Receiver"
        } else {
            return sender?.displayName ?? "Unknown Sender"
        }
    }

    /// Whether the connection is active and can receive pings
    var isActive: Bool {
        status == .active
    }

    /// Whether the connection is pending acceptance
    var isPending: Bool {
        status == .pending
    }

    /// Whether the connection is paused
    var isPaused: Bool {
        status == .paused
    }
}

// MARK: - Connection Status

/// Status of a connection between two users
/// Maps to CHECK constraint: status IN ('pending', 'active', 'paused', 'deleted')
enum ConnectionStatus: String, Codable {
    /// Connection request sent, awaiting acceptance
    case pending = "pending"

    /// Connection is active and pings can be sent
    case active = "active"

    /// Connection is temporarily paused (no pings during this period)
    case paused = "paused"

    /// Connection was soft-deleted
    case deleted = "deleted"

    /// Display name for the status
    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .active:
            return "Active"
        case .paused:
            return "Paused"
        case .deleted:
            return "Deleted"
        }
    }

    /// Icon name for status
    var iconName: String {
        switch self {
        case .pending:
            return "clock.fill"
        case .active:
            return "checkmark.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .deleted:
            return "trash.fill"
        }
    }
}

// MARK: - Connection Request

/// Request model for creating a new connection using a unique code
struct ConnectionRequest: Codable {
    let receiverId: UUID
    let connectionCode: String

    enum CodingKeys: String, CodingKey {
        case receiverId = "receiver_id"
        case connectionCode = "connection_code"
    }
}

// MARK: - Connection Update Request

/// Request model for updating a connection
struct ConnectionUpdateRequest: Codable {
    var status: ConnectionStatus?

    enum CodingKeys: String, CodingKey {
        case status
    }
}

// MARK: - Unique Code

/// Represents a user's unique 5-digit code for connection establishment
/// Maps to the `unique_codes` table in Supabase
/// Both senders and receivers can generate codes for linking
struct UniqueCode: Codable, Identifiable, Equatable {
    /// Unique identifier
    let id: UUID

    /// 5-digit numeric code
    let code: String

    /// User who owns this code (sender or receiver)
    let ownerId: UUID

    /// Role of the code owner (sender or receiver)
    var ownerRole: String?

    /// When the code was created
    let createdAt: Date

    /// When the code expires (nil = never)
    var expiresAt: Date?

    /// Whether the code is currently active
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case ownerId = "owner_id"
        case ownerRole = "owner_role"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case isActive = "is_active"
    }

    /// Whether the code is currently valid (active and not expired)
    var isValid: Bool {
        guard isActive else { return false }
        if let expiresAt = expiresAt {
            return Date() < expiresAt
        }
        return true
    }
}
