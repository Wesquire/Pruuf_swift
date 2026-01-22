import Foundation
import Supabase

/// Configuration for Supabase client
/// Handles initialization and access to Supabase services
enum SupabaseConfig {

    // MARK: - Credentials

    /// Supabase project URL
    static let projectURL = URL(string: "https://oaiteiceynliooxpeuxt.supabase.co")!

    /// Supabase anonymous public key for client-side operations
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9haXRlaWNleW5saW9veHBldXh0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg1MzA0MzEsImV4cCI6MjA4NDEwNjQzMX0.Htm_jL8JbLK2jhVlCUL0A7m6PJVY_ZuBx3FqZDZrtgk"

    // MARK: - Client Instance

    /// Shared Supabase client instance
    /// Thread-safe singleton for accessing Supabase services
    static let client: SupabaseClient = {
        let client = SupabaseClient(
            supabaseURL: projectURL,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: KeychainLocalStorage(),
                    redirectToURL: URL(string: "pruuf://auth/callback"),
                    flowType: .pkce
                ),
                global: .init(
                    headers: ["x-app-name": "PRUUF-iOS"]
                )
            )
        )
        return client
    }()

    // MARK: - Service Accessors

    /// Access to Supabase Auth service
    static var auth: AuthClient {
        client.auth
    }

    /// Access to Supabase Database (PostgREST)
    /// Note: Direct database access is deprecated. Use client.from(_:) instead.
    @available(*, deprecated, message: "Use SupabaseConfig.client.from(_:) instead")
    static var database: PostgrestClient {
        client.schema("public")
    }

    /// Access to Supabase Storage
    static var storage: SupabaseStorageClient {
        client.storage
    }

    /// Access to Supabase Realtime
    static var realtime: RealtimeClientV2 {
        client.realtimeV2
    }

    /// Access to Supabase Edge Functions
    static var functions: FunctionsClient {
        client.functions
    }
}

// MARK: - Keychain Storage for Auth Tokens

/// Custom storage implementation using Keychain for secure token storage
final class KeychainLocalStorage: AuthLocalStorage {

    private let service = "com.pruuf.ios.auth"

    func store(key: String, value: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: value
        ]

        // Delete existing item if present
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToStore(status: status)
        }
    }

    func retrieve(key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unableToRetrieve(status: status)
        }

        return result as? Data
    }

    func remove(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToRemove(status: status)
        }
    }
}

/// Keychain operation errors
enum KeychainError: Error {
    case unableToStore(status: OSStatus)
    case unableToRetrieve(status: OSStatus)
    case unableToRemove(status: OSStatus)

    var localizedDescription: String {
        switch self {
        case .unableToStore(let status):
            return "Unable to store item in Keychain. Status: \(status)"
        case .unableToRetrieve(let status):
            return "Unable to retrieve item from Keychain. Status: \(status)"
        case .unableToRemove(let status):
            return "Unable to remove item from Keychain. Status: \(status)"
        }
    }
}
