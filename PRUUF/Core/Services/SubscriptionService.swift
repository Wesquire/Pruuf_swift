import Foundation
import Supabase
import StoreKit

/// Service for managing receiver subscriptions
/// Handles subscription status checks, trial management, and App Store integration
/// Pricing per plan.md Section 9.1:
/// - Receiver-only users: $2.99/month
/// - Senders: Always free
/// - Dual role users (Both): $2.99/month (only if they have receiver connections)
/// - 15-day free trial for all receivers
/// - No credit card required to start trial
@MainActor
final class SubscriptionService: ObservableObject {

    // MARK: - Singleton

    static let shared = SubscriptionService()

    // MARK: - Published Properties

    @Published private(set) var currentStatus: SubscriptionStatus?
    @Published private(set) var receiverProfile: ReceiverProfile?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var storeKitStatus: StoreKitSubscriptionStatus = .unknown

    // MARK: - Private Properties

    private let database: PostgrestClient
    private let functions: FunctionsClient
    private let storeKitManager: StoreKitManager

    // MARK: - Initialization

    init(database: PostgrestClient? = nil,
         functions: FunctionsClient? = nil,
         storeKitManager: StoreKitManager? = nil) {
        self.database = database ?? SupabaseConfig.client.schema("public")
        self.functions = functions ?? SupabaseConfig.functions
        self.storeKitManager = storeKitManager ?? StoreKitManager.shared
    }

    // MARK: - Check Subscription Status

    /// Check and update subscription status using database function
    /// This automatically expires trials and subscriptions past their end date
    /// - Parameter userId: The user's UUID
    /// - Returns: The current subscription status
    func checkSubscriptionStatus(userId: UUID) async throws -> SubscriptionStatus? {
        isLoading = true
        defer { isLoading = false }

        // Call the database function via RPC
        let response: PostgrestResponse<String?> = try await database
            .rpc("check_subscription_status", params: ["p_user_id": userId.uuidString])
            .execute()

        guard let statusString = response.value else {
            currentStatus = nil
            return nil
        }

        let status = SubscriptionStatus(rawValue: statusString)
        currentStatus = status

        return status
    }

    // MARK: - Fetch Receiver Profile

    /// Fetch the full receiver profile for a user
    /// - Parameter userId: The user's UUID
    /// - Returns: The receiver profile if it exists
    func fetchReceiverProfile(userId: UUID) async throws -> ReceiverProfile? {
        isLoading = true
        defer { isLoading = false }

        do {
            let profile: ReceiverProfile = try await database
                .from("receiver_profiles")
                .select()
                .eq("user_id", value: userId.uuidString)
                .single()
                .execute()
                .value

            receiverProfile = profile
            currentStatus = profile.subscriptionStatus
            return profile
        } catch let postgrestError as PostgrestError {
            if postgrestError.code == "PGRST116" {
                return nil
            }
            throw SubscriptionServiceError.fetchFailed(postgrestError.localizedDescription)
        } catch {
            if error.localizedDescription.contains("no rows") ||
               error.localizedDescription.contains("0 rows") {
                return nil
            }
            throw SubscriptionServiceError.fetchFailed(error.localizedDescription)
        }
    }

    // MARK: - Trial Status

    /// Check if user is in active trial
    /// - Parameter userId: The user's UUID
    /// - Returns: Tuple of (isInTrial, daysRemaining)
    func getTrialStatus(userId: UUID) async throws -> (isInTrial: Bool, daysRemaining: Int?) {
        guard let profile = try await fetchReceiverProfile(userId: userId) else {
            return (false, nil)
        }

        return (profile.isInTrial, profile.trialDaysRemaining)
    }

    // MARK: - Subscription Access

    /// Check if user has active subscription (trial or paid)
    /// - Parameter userId: The user's UUID
    /// - Returns: True if subscription is active
    func hasActiveSubscription(userId: UUID) async throws -> Bool {
        let status = try await checkSubscriptionStatus(userId: userId)

        switch status {
        case .trial, .active:
            return true
        case .pastDue, .canceled, .expired, .none:
            return false
        }
    }

    // MARK: - Update Subscription

    /// Update subscription status after successful payment
    /// - Parameters:
    ///   - userId: The user's UUID
    ///   - stripeCustomerId: Stripe customer ID
    ///   - stripeSubscriptionId: Stripe subscription ID
    ///   - endDate: Subscription end date
    func activateSubscription(
        userId: UUID,
        stripeCustomerId: String,
        stripeSubscriptionId: String,
        endDate: Date
    ) async throws {
        isLoading = true
        defer { isLoading = false }

        let _: ReceiverProfile = try await database
            .from("receiver_profiles")
            .update([
                "subscription_status": SubscriptionStatus.active.rawValue,
                "subscription_start_date": ISO8601DateFormatter().string(from: Date()),
                "subscription_end_date": ISO8601DateFormatter().string(from: endDate),
                "stripe_customer_id": stripeCustomerId,
                "stripe_subscription_id": stripeSubscriptionId,
                "updated_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("user_id", value: userId.uuidString)
            .select()
            .single()
            .execute()
            .value

        currentStatus = .active
    }

    /// Cancel subscription
    /// - Parameter userId: The user's UUID
    func cancelSubscription(userId: UUID) async throws {
        isLoading = true
        defer { isLoading = false }

        let _: ReceiverProfile = try await database
            .from("receiver_profiles")
            .update([
                "subscription_status": SubscriptionStatus.canceled.rawValue,
                "updated_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("user_id", value: userId.uuidString)
            .select()
            .single()
            .execute()
            .value

        currentStatus = .canceled
    }

    // MARK: - Create Receiver Code

    /// Create or retrieve a unique code for the receiver
    /// Uses the database function to handle code generation and storage
    /// - Parameter userId: The user's UUID
    /// - Returns: The 6-digit unique code
    func createReceiverCode(userId: UUID) async throws -> String {
        isLoading = true
        defer { isLoading = false }

        let response: PostgrestResponse<String> = try await database
            .rpc("create_receiver_code", params: ["p_user_id": userId.uuidString])
            .execute()

        return response.value
    }

    /// Refresh the receiver's unique code (generate a new one)
    /// - Parameter userId: The user's UUID
    /// - Returns: The new 6-digit unique code
    func refreshReceiverCode(userId: UUID) async throws -> String {
        isLoading = true
        defer { isLoading = false }

        let response: PostgrestResponse<String> = try await database
            .rpc("refresh_receiver_code", params: ["p_user_id": userId.uuidString])
            .execute()

        return response.value
    }

    // MARK: - Get Receiver's Unique Code

    /// Get the existing unique code for a receiver
    /// - Parameter userId: The user's UUID
    /// - Returns: The unique code if it exists
    func getReceiverCode(userId: UUID) async throws -> String? {
        let codes: [UniqueCodeResponse] = try await database
            .from("unique_codes")
            .select("code")
            .eq("receiver_id", value: userId.uuidString)
            .eq("is_active", value: true)
            .execute()
            .value

        return codes.first?.code
    }

    // MARK: - Clear State

    /// Clear all local state
    func clearState() {
        currentStatus = nil
        receiverProfile = nil
        storeKitStatus = .unknown
    }

    // MARK: - App Store Integration (StoreKit 2)

    /// Sync subscription status between App Store and backend
    /// - Parameter userId: The user's UUID
    func syncWithAppStore(userId: UUID) async throws {
        isLoading = true
        defer { isLoading = false }

        // Update StoreKit status
        await storeKitManager.updateSubscriptionStatus()
        storeKitStatus = storeKitManager.subscriptionStatus

        // Get current backend status
        let backendProfile = try await fetchReceiverProfile(userId: userId)

        // Sync App Store status to backend
        switch storeKitManager.subscriptionStatus {
        case .active:
            // User has active App Store subscription
            if backendProfile?.subscriptionStatus != .active {
                try await updateBackendSubscriptionFromAppStore(userId: userId, status: .active)
            }

        case .inTrial:
            // User is in App Store trial
            if backendProfile?.subscriptionStatus != .trial {
                try await updateBackendSubscriptionFromAppStore(userId: userId, status: .trial)
            }

        case .expired, .notSubscribed:
            // Check if backend thinks subscription is active when App Store says no
            if backendProfile?.subscriptionStatus == .active {
                try await updateBackendSubscriptionFromAppStore(userId: userId, status: .expired)
            }

        case .eligibleForTrial:
            // User hasn't started trial yet - backend should handle initial trial
            break

        case .unknown, .pastDue:
            // Don't update backend for unknown states
            break
        }

        // Refresh local status
        _ = try await checkSubscriptionStatus(userId: userId)
    }

    /// Update backend subscription status from App Store
    /// Per plan.md Section 9.3: Updates subscription_status, dates, and Apple receipt ID
    private func updateBackendSubscriptionFromAppStore(userId: UUID, status: SubscriptionStatus) async throws {
        var updateData: [String: String] = [
            "subscription_status": status.rawValue,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]

        // Get expiration date from App Store if available
        if let expirationDate = await storeKitManager.getSubscriptionExpirationDate() {
            updateData["subscription_end_date"] = ISO8601DateFormatter().string(from: expirationDate)
        }

        // Set subscription start date for new subscriptions
        if status == .active || status == .trial {
            updateData["subscription_start_date"] = ISO8601DateFormatter().string(from: Date())
        }

        // Get Apple receipt/transaction ID from the current entitlement
        if let transactionId = await storeKitManager.getCurrentTransactionId() {
            updateData["app_store_transaction_id"] = transactionId
        }

        if let originalTransactionId = await storeKitManager.getOriginalTransactionId() {
            updateData["app_store_original_transaction_id"] = originalTransactionId
            // Per plan.md Section 9.3: stripe_subscription_id = Apple receipt ID
            // Using app_store_original_transaction_id as the persistent identifier
            updateData["stripe_subscription_id"] = originalTransactionId
        }

        let _: ReceiverProfile = try await database
            .from("receiver_profiles")
            .update(updateData)
            .eq("user_id", value: userId.uuidString)
            .select()
            .single()
            .execute()
            .value

        currentStatus = status
    }

    /// Start subscription purchase flow via App Store
    /// - Parameter userId: The user's UUID for backend sync
    /// - Returns: Purchase result
    func purchaseReceiverSubscription(userId: UUID) async throws -> PurchaseResult {
        isLoading = true
        defer { isLoading = false }

        let result = try await storeKitManager.purchaseReceiverSubscription()

        if result.isSuccess {
            // Sync with backend after successful purchase
            try await syncWithAppStore(userId: userId)
        }

        return result
    }

    /// Restore purchases from App Store
    /// - Parameter userId: The user's UUID for backend sync
    func restorePurchases(userId: UUID) async throws {
        isLoading = true
        defer { isLoading = false }

        try await storeKitManager.restorePurchases()
        try await syncWithAppStore(userId: userId)
    }

    /// Show App Store subscription management
    func showManageSubscriptions() async {
        await storeKitManager.showManageSubscriptions()
    }

    /// Get the receiver subscription product from App Store
    var receiverSubscriptionProduct: Product? {
        storeKitManager.receiverMonthlyProduct
    }

    /// Check if user has active subscription (from App Store)
    var hasActiveAppStoreSubscription: Bool {
        storeKitManager.hasActiveReceiverSubscription
    }

    /// Get trial days remaining from App Store
    func getAppStoreTrialDaysRemaining() async -> Int? {
        await storeKitManager.getTrialDaysRemaining()
    }

    // MARK: - Cancellation Status (Section 9.3)

    /// Per plan.md Section 9.3: Check if subscription is canceled but still active
    /// Returns the end date if subscription was canceled
    func getCancellationEndDate() async -> Date? {
        await storeKitManager.getCancellationEndDate()
    }

    /// Per plan.md Section 9.3: Check if user has canceled subscription
    func isSubscriptionCanceled() async -> Bool {
        await storeKitManager.isSubscriptionCanceled()
    }

    /// Per plan.md Section 9.3: Check if user has access despite canceled status
    /// Access continues until end of billing period
    func hasAccessDespiteCancellation() async -> Bool {
        if await storeKitManager.isSubscriptionCanceled() {
            // Check if still within the billing period
            if let endDate = await storeKitManager.getCancellationEndDate() {
                return endDate > Date()
            }
        }
        return false
    }

    // MARK: - Subscription Pricing Info

    /// Subscription price per plan.md Section 9.1
    static let monthlyPrice: Decimal = 2.99

    /// Trial duration in days per plan.md Section 9.1
    static let trialDays: Int = 15

    /// Product ID per plan.md Section 9.1
    static let productId = "com.pruuf.receiver.monthly"

    /// Check if user needs subscription (is receiver or both role)
    /// - Parameter userRole: The user's primary role
    /// - Returns: Whether subscription is required
    static func requiresSubscription(for userRole: UserRole?) -> Bool {
        switch userRole {
        case .receiver, .both:
            return true
        case .sender, .none:
            return false
        }
    }

    /// Get pricing description based on role
    /// - Parameter userRole: The user's role
    /// - Returns: Human-readable pricing string
    static func pricingDescription(for userRole: UserRole?) -> String {
        switch userRole {
        case .sender:
            return "Always Free"
        case .receiver:
            return "$2.99/month after 15-day free trial"
        case .both:
            return "$2.99/month for receiver features"
        case .none:
            return ""
        }
    }
}

// MARK: - Helper Types

private struct UniqueCodeResponse: Codable {
    let code: String
}

// MARK: - Subscription Service Errors

enum SubscriptionServiceError: LocalizedError {
    case fetchFailed(String)
    case updateFailed(String)
    case codeGenerationFailed(String)
    case paymentRequired
    case subscriptionExpired

    var errorDescription: String? {
        switch self {
        case .fetchFailed(let message):
            return "Failed to fetch subscription: \(message)"
        case .updateFailed(let message):
            return "Failed to update subscription: \(message)"
        case .codeGenerationFailed(let message):
            return "Failed to generate code: \(message)"
        case .paymentRequired:
            return "Payment required to continue using receiver features"
        case .subscriptionExpired:
            return "Your subscription has expired. Please renew to continue."
        }
    }
}
