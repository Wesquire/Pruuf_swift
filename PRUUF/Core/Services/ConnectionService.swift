import Foundation
import Supabase

/// Service for managing connections between senders and receivers
/// Handles connection requests, updates, and queries
@MainActor
final class ConnectionService: ObservableObject {

    // MARK: - Singleton

    static let shared = ConnectionService()

    // MARK: - Published Properties

    @Published private(set) var connections: [Connection] = []
    @Published private(set) var pendingConnections: [Connection] = []
    @Published private(set) var isLoading: Bool = false

    // MARK: - Private Properties

    private let database: PostgrestClient
    private let functions: FunctionsClient

    // MARK: - Initialization

    init(database: PostgrestClient? = nil,
         functions: FunctionsClient? = nil) {
        self.database = database ?? SupabaseConfig.client.schema("public")
        self.functions = functions ?? SupabaseConfig.functions
    }

    // MARK: - Fetch Connections (as Sender)

    /// Fetch all connections where the user is the sender
    func fetchConnectionsAsSender(userId: UUID) async throws {
        isLoading = true
        defer { isLoading = false }

        let connections: [Connection] = try await database
            .from("connections")
            .select("*, receiver:receiver_id(id, phone_number, phone_country_code, timezone)")
            .eq("sender_id", value: userId.uuidString)
            .neq("status", value: ConnectionStatus.deleted.rawValue)
            .order("created_at", ascending: false)
            .execute()
            .value

        self.connections = connections
    }

    // MARK: - Fetch Connections (as Receiver)

    /// Fetch all connections where the user is the receiver
    func fetchConnectionsAsReceiver(userId: UUID) async throws {
        isLoading = true
        defer { isLoading = false }

        let connections: [Connection] = try await database
            .from("connections")
            .select("*, sender:sender_id(id, phone_number, phone_country_code, timezone)")
            .eq("receiver_id", value: userId.uuidString)
            .neq("status", value: ConnectionStatus.deleted.rawValue)
            .order("created_at", ascending: false)
            .execute()
            .value

        self.connections = connections
    }

    // MARK: - Fetch Pending Connections

    /// Fetch pending connection requests for the current user (as receiver)
    func fetchPendingConnections(userId: UUID) async throws {
        isLoading = true
        defer { isLoading = false }

        let pending: [Connection] = try await database
            .from("connections")
            .select("*, sender:sender_id(id, phone_number, phone_country_code, timezone)")
            .eq("receiver_id", value: userId.uuidString)
            .eq("status", value: ConnectionStatus.pending.rawValue)
            .order("created_at", ascending: false)
            .execute()
            .value

        self.pendingConnections = pending
    }

    // MARK: - Create Connection via Code

    /// Create a connection using a receiver's unique code
    /// - Parameters:
    ///   - senderId: The sender's user ID
    ///   - code: The receiver's unique 6-digit code
    /// - Returns: The created connection
    @discardableResult
    func createConnection(senderId: UUID, withCode code: String) async throws -> Connection {
        isLoading = true
        defer { isLoading = false }

        // Look up the unique code to find the receiver
        let codes: [UniqueCode] = try await database
            .from("unique_codes")
            .select("*, receiver:receiver_id(id, phone_number, phone_country_code, timezone)")
            .eq("code", value: code)
            .eq("is_active", value: true)
            .execute()
            .value

        guard let uniqueCode = codes.first else {
            throw ConnectionServiceError.invalidCode
        }

        // Check if connection already exists
        let existingConnections: [Connection] = try await database
            .from("connections")
            .select()
            .eq("sender_id", value: senderId.uuidString)
            .eq("receiver_id", value: uniqueCode.receiverId.uuidString)
            .execute()
            .value

        if let existing = existingConnections.first {
            if existing.status == .deleted {
                // Reactivate the connection
                return try await updateConnectionStatus(connectionId: existing.id, status: .active)
            } else {
                throw ConnectionServiceError.connectionAlreadyExists
            }
        }

        // Prevent self-connection
        if senderId == uniqueCode.receiverId {
            throw ConnectionServiceError.cannotConnectToSelf
        }

        // Create new connection
        let newConnection: Connection = try await database
            .from("connections")
            .insert([
                "sender_id": senderId.uuidString,
                "receiver_id": uniqueCode.receiverId.uuidString,
                "status": ConnectionStatus.active.rawValue,
                "connection_code": code
            ])
            .select("*, receiver:receiver_id(id, phone_number, phone_country_code, timezone)")
            .single()
            .execute()
            .value

        // Add to local state
        connections.insert(newConnection, at: 0)

        return newConnection
    }

    // MARK: - Create Connection via Edge Function

    /// Create a connection using the validate-connection-code edge function
    /// This method provides an alternative that uses server-side validation and
    /// handles all edge cases (EC-5.1 through EC-5.4) atomically on the server
    /// - Parameters:
    ///   - senderId: The sender's user ID
    ///   - code: The receiver's unique 6-digit code
    /// - Returns: The created connection
    @discardableResult
    func createConnectionViaEdgeFunction(senderId: UUID, withCode code: String) async throws -> Connection {
        isLoading = true
        defer { isLoading = false }

        struct ValidateConnectionRequest: Encodable {
            let code: String
            let connectingUserId: String
            let role: String
        }

        struct ValidateConnectionResponse: Decodable {
            let success: Bool
            let connection: Connection?
            let error: String?
            let errorCode: String?
        }

        let request = ValidateConnectionRequest(
            code: code,
            connectingUserId: senderId.uuidString,
            role: "sender"
        )

        do {
            let response: ValidateConnectionResponse = try await functions
                .invoke("validate-connection-code", options: FunctionInvokeOptions(body: request))

            if response.success, let connection = response.connection {
                // Add to local state
                connections.insert(connection, at: 0)
                return connection
            } else {
                // Map error codes to ConnectionServiceError
                let errorCode = response.errorCode ?? "UNKNOWN"
                switch errorCode {
                case "INVALID_CODE", "INVALID_CODE_FORMAT":
                    throw ConnectionServiceError.invalidCode
                case "SELF_CONNECTION":
                    throw ConnectionServiceError.cannotConnectToSelf
                case "DUPLICATE_CONNECTION":
                    throw ConnectionServiceError.connectionAlreadyExists
                default:
                    throw ConnectionServiceError.updateFailed(response.error ?? "Unknown error")
                }
            }
        } catch let error as ConnectionServiceError {
            throw error
        } catch {
            throw ConnectionServiceError.updateFailed(error.localizedDescription)
        }
    }

    // MARK: - Accept Connection

    /// Accept a pending connection request (as receiver)
    /// - Parameter connectionId: The ID of the connection to accept
    @discardableResult
    func acceptConnection(connectionId: UUID) async throws -> Connection {
        let connection = try await updateConnectionStatus(connectionId: connectionId, status: .active)

        // Remove from pending
        pendingConnections.removeAll { $0.id == connectionId }

        return connection
    }

    // MARK: - Pause Connection

    /// Pause a connection temporarily
    /// - Parameter connectionId: The ID of the connection to pause
    @discardableResult
    func pauseConnection(connectionId: UUID) async throws -> Connection {
        return try await updateConnectionStatus(connectionId: connectionId, status: .paused)
    }

    // MARK: - Resume Connection

    /// Resume a paused connection
    /// - Parameter connectionId: The ID of the connection to resume
    @discardableResult
    func resumeConnection(connectionId: UUID) async throws -> Connection {
        return try await updateConnectionStatus(connectionId: connectionId, status: .active)
    }

    // MARK: - Delete Connection

    /// Soft delete a connection
    /// - Parameter connectionId: The ID of the connection to delete
    func deleteConnection(connectionId: UUID) async throws {
        isLoading = true
        defer { isLoading = false }

        try await database
            .from("connections")
            .update([
                "status": ConnectionStatus.deleted.rawValue,
                "deleted_at": ISO8601DateFormatter().string(from: Date()),
                "updated_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: connectionId.uuidString)
            .execute()

        // Remove from local state
        connections.removeAll { $0.id == connectionId }
    }

    // MARK: - Update Connection Status

    @discardableResult
    private func updateConnectionStatus(connectionId: UUID, status: ConnectionStatus) async throws -> Connection {
        isLoading = true
        defer { isLoading = false }

        let updateData: [String: String] = [
            "status": status.rawValue,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]

        let connection: Connection = try await database
            .from("connections")
            .update(updateData)
            .eq("id", value: connectionId.uuidString)
            .select("*, receiver:receiver_id(id, phone_number, phone_country_code, timezone), sender:sender_id(id, phone_number, phone_country_code, timezone)")
            .single()
            .execute()
            .value

        // Update local state
        if let index = connections.firstIndex(where: { $0.id == connectionId }) {
            connections[index] = connection
        }

        return connection
    }

    // MARK: - Get Active Connections Count

    /// Get the count of active connections
    var activeConnectionsCount: Int {
        connections.filter { $0.status == .active }.count
    }

    // MARK: - Refresh Connections

    /// Refresh all connection data for a user
    func refreshConnections(userId: UUID, role: UserRole?) async {
        do {
            if role == .sender || role == .both {
                try await fetchConnectionsAsSender(userId: userId)
            }
            if role == .receiver || role == .both {
                try await fetchConnectionsAsReceiver(userId: userId)
                try await fetchPendingConnections(userId: userId)
            }
        } catch {
            // Silently fail on refresh
        }
    }

    // MARK: - Clear Data

    /// Clear all local connection data
    func clearData() {
        connections = []
        pendingConnections = []
    }
}

// MARK: - Connection Service Errors

enum ConnectionServiceError: LocalizedError {
    case userNotFound
    case invalidCode
    case connectionAlreadyExists
    case connectionNotFound
    case cannotConnectToSelf
    case connectionLimitReached
    case updateFailed(String)

    var errorDescription: String? {
        switch self {
        case .userNotFound:
            return "User not found. Make sure they have a PRUUF account."
        case .invalidCode:
            return "Invalid connection code. Please check and try again."
        case .connectionAlreadyExists:
            return "You already have a connection with this user"
        case .connectionNotFound:
            return "Connection not found"
        case .cannotConnectToSelf:
            return "You cannot connect with yourself"
        case .connectionLimitReached:
            return "You have reached your connection limit. Upgrade to add more."
        case .updateFailed(let message):
            return "Failed to update connection: \(message)"
        }
    }
}
