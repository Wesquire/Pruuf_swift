import Foundation

/// Application-wide configuration settings
/// Manages environment-specific configurations and app constants
enum Config {

    // MARK: - Supabase Configuration

    /// Supabase project URL
    static let supabaseURL = "https://oaiteiceynliooxpeuxt.supabase.co"

    /// Supabase anonymous public key for client-side operations
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9haXRlaWNleW5saW9veHBldXh0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg1MzA0MzEsImV4cCI6MjA4NDEwNjQzMX0.Htm_jL8JbLK2jhVlCUL0A7m6PJVY_ZuBx3FqZDZrtgk"

    // MARK: - Environment

    /// Current application environment
    static let environment: Environment = {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }()

    /// Application environment types
    enum Environment {
        case development
        case staging
        case production

        /// Display name for the environment
        var displayName: String {
            switch self {
            case .development:
                return "Development"
            case .staging:
                return "Staging"
            case .production:
                return "Production"
            }
        }

        /// Whether verbose logging is enabled
        var isLoggingEnabled: Bool {
            switch self {
            case .development, .staging:
                return true
            case .production:
                return false
            }
        }

        /// Whether analytics should be sent
        var isAnalyticsEnabled: Bool {
            switch self {
            case .development:
                return false
            case .staging, .production:
                return true
            }
        }
    }

    // MARK: - App Configuration

    /// Bundle identifier for the app
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.pruuf.ios"
    }

    /// App version string
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Build number
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// Full version string (e.g., "1.0.0 (42)")
    static var fullVersionString: String {
        "\(appVersion) (\(buildNumber))"
    }

    // MARK: - API Configuration

    /// API timeout interval in seconds
    static let apiTimeoutInterval: TimeInterval = 30.0

    /// Maximum retry attempts for failed requests
    static let maxRetryAttempts: Int = 3

    /// Retry delay in seconds
    static let retryDelay: TimeInterval = 1.0

    // MARK: - Push Notification Configuration

    /// APNs environment
    static var apnsEnvironment: String {
        environment == .production ? "production" : "development"
    }

    // MARK: - Feature Flags

    /// Whether to show debug menu in settings
    static var showDebugMenu: Bool {
        environment != .production
    }

    /// Whether to use mock data
    static var useMockData: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["USE_MOCK_DATA"] == "1"
        #else
        return false
        #endif
    }

    // MARK: - URL Schemes

    /// Custom URL scheme for deep linking
    static let urlScheme = "pruuf"

    /// Auth callback URL
    static let authCallbackURL = "\(urlScheme)://auth/callback"

    // MARK: - Storage Keys

    /// UserDefaults suite name
    static let userDefaultsSuite = "group.com.pruuf.ios"

    /// Keychain service identifier
    static let keychainService = "com.pruuf.ios.auth"
}

// MARK: - Environment Helpers

extension Config {

    /// Check if running in development environment
    static var isDevelopment: Bool {
        environment == .development
    }

    /// Check if running in staging environment
    static var isStaging: Bool {
        environment == .staging
    }

    /// Check if running in production environment
    static var isProduction: Bool {
        environment == .production
    }
}
