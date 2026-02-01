import Foundation
import Supabase

/// Authentication service for handling user authentication via Phone with APNs verification
/// Manages sign-in, sign-out, and session management
/// Integrates with UserService to manage user records in the database
///
/// Note: This implementation uses APNs push notifications for verification instead of SMS OTP.
/// The flow is:
/// 1. User enters phone number
/// 2. App sends verification code via APNs push notification
/// 3. User enters code from push notification
/// 4. Authentication completes
@MainActor
final class AuthService: ObservableObject {

    // MARK: - Published Properties

    /// The Supabase Auth user (from auth.users)
    @Published private(set) var currentUser: User?

    /// The PRUUF app user (from public.users table)
    @Published private(set) var currentPruufUser: PruufUser?

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var isLoading: Bool = false

    /// Indicates if user needs to complete onboarding
    @Published private(set) var needsOnboarding: Bool = false

    /// Current authentication state for routing
    @Published private(set) var authState: AuthState = .unknown

    /// Pending verification phone number
    @Published private(set) var pendingVerificationPhone: String?

    // MARK: - Private Properties

    private let auth: AuthClient
    private let userService: UserService

    /// Key for storing last activity timestamp in UserDefaults
    private static let lastActivityKey = "com.pruuf.lastActivityTimestamp"

    /// Key for storing pending verification code
    private static let pendingVerificationCodeKey = "com.pruuf.pendingVerificationCode"

    /// Key for storing pending verification phone
    private static let pendingVerificationPhoneKey = "com.pruuf.pendingVerificationPhone"

    /// Session expiry duration: 30 days in seconds
    private static let sessionExpiryDuration: TimeInterval = 30 * 24 * 60 * 60

    /// Verification code expiry: 10 minutes
    private static let verificationCodeExpiry: TimeInterval = 10 * 60

    // MARK: - Initialization

    init(authClient: AuthClient? = nil, userService: UserService? = nil) {
        self.auth = authClient ?? SupabaseConfig.auth
        self.userService = userService ?? UserService()
        Task { @MainActor in
            await checkCurrentSession()
            await listenToAuthChanges()
        }
    }

    // MARK: - Session Management

    /// Check if there's an existing valid session
    /// Implements US-1.5: Session expires after 30 days of inactivity
    func checkCurrentSession() async {
        authState = .loading

        // Check for session expiry due to inactivity (US-1.5)
        if isSessionExpiredDueToInactivity() {
            await forceSignOut()
            return
        }

        do {
            let session = try await auth.session
            self.currentUser = session.user
            self.isAuthenticated = true

            // Update last activity timestamp
            updateLastActivityTimestamp()

            // Fetch or create the PRUUF user record and check onboarding status
            await handlePostAuthenticationFlow(authUser: session.user)
        } catch {
            self.currentUser = nil
            self.currentPruufUser = nil
            self.isAuthenticated = false
            self.needsOnboarding = false
            self.authState = .unauthenticated
        }
    }

    /// Check if session has expired due to 30 days of inactivity
    private func isSessionExpiredDueToInactivity() -> Bool {
        guard let lastActivity = UserDefaults.standard.object(forKey: Self.lastActivityKey) as? Date else {
            // No last activity recorded, session is valid
            return false
        }

        let timeSinceLastActivity = Date().timeIntervalSince(lastActivity)
        return timeSinceLastActivity > Self.sessionExpiryDuration
    }

    /// Update the last activity timestamp
    func updateLastActivityTimestamp() {
        UserDefaults.standard.set(Date(), forKey: Self.lastActivityKey)
    }

    /// Clear the last activity timestamp (on sign out)
    private func clearLastActivityTimestamp() {
        UserDefaults.standard.removeObject(forKey: Self.lastActivityKey)
    }

    /// Force sign out without throwing errors (for session expiry)
    private func forceSignOut() async {
        do {
            try await auth.signOut()
        } catch {
            // Ignore errors - we're forcing a sign out due to expiry
        }

        self.currentUser = nil
        self.currentPruufUser = nil
        self.isAuthenticated = false
        self.needsOnboarding = false
        self.authState = .unauthenticated
        clearLastActivityTimestamp()
        userService.clearCurrentUser()
    }

    /// Listen to authentication state changes
    func listenToAuthChanges() async {
        for await (event, session) in auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn:
                self.currentUser = session?.user
                self.isAuthenticated = session != nil
            case .signedOut:
                self.currentUser = nil
                self.isAuthenticated = false
            case .tokenRefreshed:
                self.currentUser = session?.user
            case .userUpdated:
                self.currentUser = session?.user
            case .passwordRecovery, .mfaChallengeVerified, .userDeleted:
                break
            }
        }
    }

    // MARK: - Phone Authentication with APNs Verification

    /// Start phone verification by sending a code via APNs push notification
    /// - Parameters:
    ///   - phoneNumber: Phone number with country code (e.g., "+1234567890")
    ///   - deviceToken: The APNs device token for sending push notification
    /// - Throws: AuthError if verification initiation fails
    func startPhoneVerification(phoneNumber: String, deviceToken: String) async throws {
        isLoading = true
        defer { isLoading = false }

        // Validate phone number format
        guard isValidPhoneNumber(phoneNumber) else {
            throw AuthServiceError.invalidPhoneFormat
        }

        // Generate a 6-digit verification code
        let verificationCode = generateVerificationCode()

        // Store the code and phone number for verification
        storeVerificationData(code: verificationCode, phone: phoneNumber)

        self.pendingVerificationPhone = phoneNumber

        // Send the verification code via APNs push notification
        try await sendVerificationCodeViaPush(
            code: verificationCode,
            phoneNumber: phoneNumber,
            deviceToken: deviceToken
        )

        // Update auth state to verifying (triggers UI navigation)
        self.authState = .verifying
    }

    /// Verify the code entered by the user
    /// - Parameters:
    ///   - code: The verification code entered by user
    /// - Throws: AuthError if verification fails
    func verifyPhoneCode(_ code: String) async throws {
        isLoading = true

        guard let storedCode = getStoredVerificationCode(),
              let storedPhone = getStoredVerificationPhone() else {
            isLoading = false
            throw AuthServiceError.verificationExpired
        }

        // Check if verification code has expired
        if isVerificationExpired() {
            clearVerificationData()
            isLoading = false
            throw AuthServiceError.verificationExpired
        }

        // Verify the code matches
        guard code == storedCode else {
            isLoading = false
            throw AuthServiceError.invalidVerificationCode
        }

        // Clear verification data
        clearVerificationData()

        do {
            // Sign in with Supabase using anonymous auth, then link phone
            // This creates a user account without requiring SMS
            let response = try await auth.signInAnonymously()

            self.currentUser = response.user
            self.isAuthenticated = true
            self.pendingVerificationPhone = nil
            self.isLoading = false

            // Handle post-authentication flow (create/fetch user, check onboarding)
            // This is wrapped in its own do-catch to prevent crashes
            await handlePostAuthenticationFlow(authUser: response.user, phoneNumber: storedPhone)
        } catch {
            self.isLoading = false
            print("Authentication error: \(error.localizedDescription)")
            throw AuthServiceError.unknownError(error.localizedDescription)
        }
    }

    /// Send verification code via APNs push notification
    private func sendVerificationCodeViaPush(code: String, phoneNumber: String, deviceToken: String) async throws {
        #if DEBUG
        // In DEBUG mode, log the verification code to console for testing
        // This allows testing without a working APNs backend
        print("========================================")
        print("VERIFICATION CODE: \(code)")
        print("Phone: \(phoneNumber)")
        print("Device Token: \(deviceToken)")
        print("========================================")
        // In DEBUG mode, skip the Edge Function call entirely
        // The verification code is printed above - enter it manually
        return
        #else
        // RELEASE mode - send actual push notification via Edge Function

        // Skip APNs call in simulator (no push support)
        #if targetEnvironment(simulator)
        return // Success - code logged to console
        #endif

        // Create the request body
        let requestBody = SendVerificationNotificationRequest(
            deviceToken: deviceToken,
            title: "PRUUF Verification",
            body: "Your verification code is: \(code)",
            data: VerificationNotificationData(type: "verification", code: code)
        )

        // Call the send-apns-notification Edge Function
        let response: SendAPNsNotificationResponse = try await SupabaseConfig.client.functions.invoke(
            "send-apns-notification",
            options: FunctionInvokeOptions(body: requestBody)
        )

        // Check if the function call was successful
        guard response.success else {
            throw AuthServiceError.pushNotificationFailed
        }
        #endif
    }

    /// Generate a random 6-digit verification code
    private func generateVerificationCode() -> String {
        let code = Int.random(in: 100000...999999)
        return String(code)
    }

    /// Store verification data for later verification
    private func storeVerificationData(code: String, phone: String) {
        UserDefaults.standard.set(code, forKey: Self.pendingVerificationCodeKey)
        UserDefaults.standard.set(phone, forKey: Self.pendingVerificationPhoneKey)
        UserDefaults.standard.set(Date(), forKey: "\(Self.pendingVerificationCodeKey)_timestamp")
    }

    /// Get stored verification code
    private func getStoredVerificationCode() -> String? {
        UserDefaults.standard.string(forKey: Self.pendingVerificationCodeKey)
    }

    /// Get stored verification phone
    private func getStoredVerificationPhone() -> String? {
        UserDefaults.standard.string(forKey: Self.pendingVerificationPhoneKey)
    }

    /// Check if verification has expired
    private func isVerificationExpired() -> Bool {
        guard let timestamp = UserDefaults.standard.object(forKey: "\(Self.pendingVerificationCodeKey)_timestamp") as? Date else {
            return true
        }
        return Date().timeIntervalSince(timestamp) > Self.verificationCodeExpiry
    }

    /// Clear verification data
    private func clearVerificationData() {
        UserDefaults.standard.removeObject(forKey: Self.pendingVerificationCodeKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingVerificationPhoneKey)
        UserDefaults.standard.removeObject(forKey: "\(Self.pendingVerificationCodeKey)_timestamp")
    }

    /// Validate phone number format
    private func isValidPhoneNumber(_ phone: String) -> Bool {
        // Basic validation: starts with + and has 10-15 digits
        let phoneRegex = #"^\+[1-9]\d{9,14}$"#
        return phone.range(of: phoneRegex, options: .regularExpression) != nil
    }

    // MARK: - Post-Authentication Flow

    /// Handle the flow after successful authentication
    /// - Creates or retrieves user record from users table
    /// - Checks onboarding status and updates auth state
    /// - Parameters:
    ///   - authUser: The authenticated Supabase user
    ///   - phoneNumber: The phone number used for authentication (optional, used for new user creation)
    private func handlePostAuthenticationFlow(authUser: User, phoneNumber: String? = nil) async {
        // Set a safe default state immediately to prevent UI crashes during async operations
        self.needsOnboarding = true
        self.authState = .needsOnboarding

        do {
            // Get phone number from auth user if not provided
            let phone = phoneNumber ?? authUser.phone ?? ""

            // Fetch or create the PRUUF user record with a timeout to prevent hanging
            let pruufUser = try await withTimeout(seconds: 10) {
                try await self.userService.fetchOrCreateUser(
                    authId: authUser.id,
                    phoneNumber: phone
                )
            }

            self.currentPruufUser = pruufUser

            // Check onboarding status and set appropriate state
            if pruufUser.hasCompletedOnboarding {
                self.needsOnboarding = false
                self.authState = .authenticated
            }
            // If not completed, state is already set to needsOnboarding
        } catch {
            // Log the error but don't fail authentication
            // User is authenticated, but we couldn't fetch/create their record
            print("Error in post-authentication flow: \(error.localizedDescription)")
            // State is already set to needsOnboarding above, so user can proceed
        }
    }

    /// Execute an async operation with a timeout
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AuthServiceError.unknownError("Operation timed out")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Sign Out

    /// Sign out the current user
    /// Clears all session data including Keychain tokens (US-1.5)
    /// - Throws: AuthError if sign out fails
    func signOut() async throws {
        isLoading = true
        defer { isLoading = false }

        try await auth.signOut()
        self.currentUser = nil
        self.currentPruufUser = nil
        self.isAuthenticated = false
        self.needsOnboarding = false
        self.authState = .unauthenticated
        self.pendingVerificationPhone = nil
        clearLastActivityTimestamp()
        clearVerificationData()
        userService.clearCurrentUser()
    }

    // MARK: - User Info

    /// Get current user's ID
    var currentUserId: String? {
        currentUser?.id.uuidString
    }

    /// Get current user's phone number
    var currentPhoneNumber: String? {
        currentPruufUser?.phoneNumber
    }

    /// Refresh the current session token
    func refreshSession() async throws {
        let session = try await auth.refreshSession()
        self.currentUser = session.user
    }

    /// Update user metadata
    /// - Parameter metadata: Dictionary of metadata to update
    func updateUserMetadata(_ metadata: [String: AnyJSON]) async throws {
        isLoading = true
        defer { isLoading = false }

        let user = try await auth.update(user: UserAttributes(data: metadata))
        self.currentUser = user
    }

    /// Mark onboarding as complete for the current user
    func completeOnboarding() async throws {
        guard let userId = currentUser?.id else {
            throw AuthServiceError.sessionExpired
        }

        let updatedUser = try await userService.completeOnboarding(for: userId)
        self.currentPruufUser = updatedUser
        self.needsOnboarding = false
        self.authState = .authenticated
    }

    /// Get the current PRUUF user ID
    var currentPruufUserId: UUID? {
        currentPruufUser?.id
    }

    /// Resend verification code to the pending phone number
    /// - Parameter deviceToken: APNs device token
    func resendVerificationCode(deviceToken: String) async throws {
        guard let phone = pendingVerificationPhone else {
            throw AuthServiceError.phoneNumberRequired
        }

        try await startPhoneVerification(phoneNumber: phone, deviceToken: deviceToken)
    }
}

// MARK: - Auth State

/// Represents the current authentication state for routing
enum AuthState: Equatable {
    /// State is not yet determined
    case unknown
    /// Checking current session
    case loading
    /// User is not authenticated
    case unauthenticated
    /// User is in the process of verifying their phone
    case verifying
    /// User is authenticated but needs to complete onboarding
    case needsOnboarding
    /// User is fully authenticated and has completed onboarding
    case authenticated
}

// MARK: - AuthService Errors

enum AuthServiceError: LocalizedError {
    case phoneNumberRequired
    case verificationCodeRequired
    case invalidPhoneFormat
    case sessionExpired
    case verificationExpired
    case invalidVerificationCode
    case pushNotificationFailed
    case deviceTokenRequired
    case unknownError(String)

    var errorDescription: String? {
        switch self {
        case .phoneNumberRequired:
            return "Phone number is required"
        case .verificationCodeRequired:
            return "Verification code is required"
        case .invalidPhoneFormat:
            return "Invalid phone number format. Please include country code (e.g., +1234567890)"
        case .sessionExpired:
            return "Your session has expired. Please sign in again"
        case .verificationExpired:
            return "Verification code has expired. Please request a new code"
        case .invalidVerificationCode:
            return "Invalid verification code. Please try again"
        case .pushNotificationFailed:
            return "Failed to send verification code. Please check your connection and try again"
        case .deviceTokenRequired:
            return "Push notifications must be enabled to sign in"
        case .unknownError(let message):
            return message
        }
    }
}

// MARK: - APNs Notification Request/Response Models

/// Request body for sending verification code via APNs
struct SendVerificationNotificationRequest: Codable {
    let deviceToken: String
    let title: String
    let body: String
    let data: VerificationNotificationData
}

/// Data payload for verification notification
struct VerificationNotificationData: Codable {
    let type: String
    let code: String
}

/// Response from APNs notification Edge Function
struct SendAPNsNotificationResponse: Codable {
    let success: Bool
    let messageId: String?
    let error: String?
}
