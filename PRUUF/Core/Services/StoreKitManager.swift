import Foundation
import StoreKit

/// Manages App Store subscriptions using StoreKit 2
/// Handles product loading, purchases, and subscription status
@MainActor
final class StoreKitManager: ObservableObject {

    // MARK: - Singleton

    static let shared = StoreKitManager()

    // MARK: - Product Identifiers

    /// Product ID for receiver monthly subscription per plan.md Section 9.1
    static let receiverMonthlyProductId = "com.pruuf.receiver.monthly"

    /// All product IDs
    static let allProductIds: Set<String> = [receiverMonthlyProductId]

    // MARK: - Published Properties

    /// Available products from App Store
    @Published private(set) var products: [Product] = []

    /// Currently purchased subscription product IDs
    @Published private(set) var purchasedSubscriptions: Set<String> = []

    /// Current subscription status
    @Published private(set) var subscriptionStatus: StoreKitSubscriptionStatus = .unknown

    /// Loading state
    @Published private(set) var isLoading: Bool = false

    /// Error state
    @Published private(set) var errorMessage: String?

    // MARK: - Private Properties

    private var updateListenerTask: Task<Void, Error>?

    // MARK: - Initialization

    private init() {
        // Start listening for transaction updates
        updateListenerTask = listenForTransactions()

        // Load products and check subscription status on init
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Product Loading

    /// Load available products from App Store
    func loadProducts() async {
        isLoading = true
        errorMessage = nil

        do {
            products = try await Product.products(for: Self.allProductIds)

            // Sort products (in case we add more later)
            products.sort { $0.displayPrice < $1.displayPrice }

        } catch {
            errorMessage = "Failed to load products: \(error.localizedDescription)"
            print("[StoreKitManager] Error loading products: \(error)")
        }

        isLoading = false
    }

    /// Get the receiver monthly subscription product
    var receiverMonthlyProduct: Product? {
        products.first { $0.id == Self.receiverMonthlyProductId }
    }

    // MARK: - Purchasing

    /// Purchase a product
    /// - Parameter product: The product to purchase
    /// - Returns: Purchase result indicating success, pending, or user cancelled
    func purchase(_ product: Product) async throws -> PurchaseResult {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                // Check if transaction is verified
                let transaction = try checkVerified(verification)

                // Update subscription status
                await updateSubscriptionStatus()

                // Finish the transaction
                await transaction.finish()

                return .success(transaction)

            case .userCancelled:
                return .userCancelled

            case .pending:
                return .pending

            @unknown default:
                return .unknown
            }

        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            throw StoreKitError.purchaseFailed(error.localizedDescription)
        }
    }

    /// Purchase the receiver monthly subscription
    func purchaseReceiverSubscription() async throws -> PurchaseResult {
        guard let product = receiverMonthlyProduct else {
            throw StoreKitError.productNotFound
        }
        return try await purchase(product)
    }

    // MARK: - Subscription Status

    /// Update subscription status from App Store
    func updateSubscriptionStatus() async {
        var foundActiveSubscription = false
        var newPurchasedSubscriptions: Set<String> = []

        // Check for active subscriptions
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productType == .autoRenewable {
                    newPurchasedSubscriptions.insert(transaction.productID)

                    if transaction.productID == Self.receiverMonthlyProductId {
                        foundActiveSubscription = true
                    }
                }
            }
        }

        purchasedSubscriptions = newPurchasedSubscriptions

        if foundActiveSubscription {
            subscriptionStatus = .active
        } else if await checkTrialEligibility() {
            subscriptionStatus = .eligibleForTrial
        } else {
            subscriptionStatus = .notSubscribed
        }
    }

    /// Check if user is eligible for free trial
    func checkTrialEligibility() async -> Bool {
        guard let product = receiverMonthlyProduct else {
            return false
        }

        // Check if user is eligible for introductory offer (free trial)
        do {
            let status = try await product.subscription?.status ?? []

            // If user has no subscription history, they're eligible for trial
            if status.isEmpty {
                return true
            }

            // Check if any subscription is currently in intro offer period
            for subscription in status {
                if case .verified(let renewalInfo) = subscription.renewalInfo {
                    if renewalInfo.offerType == .introductory {
                        // Currently in trial
                        subscriptionStatus = .inTrial
                        return false
                    }
                }
            }

            return false

        } catch {
            print("[StoreKitManager] Error checking trial eligibility: \(error)")
            return false
        }
    }

    /// Check if user has active receiver subscription
    var hasActiveReceiverSubscription: Bool {
        purchasedSubscriptions.contains(Self.receiverMonthlyProductId)
    }

    // MARK: - Subscription Details

    /// Get subscription expiration date
    func getSubscriptionExpirationDate() async -> Date? {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.receiverMonthlyProductId {
                    return transaction.expirationDate
                }
            }
        }
        return nil
    }

    /// Get current transaction ID (per plan.md Section 9.3 for database sync)
    func getCurrentTransactionId() async -> String? {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.receiverMonthlyProductId {
                    return String(transaction.id)
                }
            }
        }
        return nil
    }

    /// Get original transaction ID (per plan.md Section 9.3: Apple receipt ID)
    func getOriginalTransactionId() async -> String? {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.receiverMonthlyProductId {
                    return String(transaction.originalID)
                }
            }
        }
        return nil
    }

    /// Check if subscription is canceled but still active (per plan.md Section 9.3)
    /// Returns the cancellation end date if subscription is canceled
    func getCancellationEndDate() async -> Date? {
        guard let product = receiverMonthlyProduct else { return nil }

        do {
            let statuses = try await product.subscription?.status ?? []

            for status in statuses {
                if case .verified(let renewalInfo) = status.renewalInfo {
                    // Check if auto-renew is disabled (subscription is canceled)
                    if renewalInfo.willAutoRenew == false {
                        // Get the expiration date
                        if case .verified(let transaction) = status.transaction {
                            return transaction.expirationDate
                        }
                    }
                }
            }
        } catch {
            print("[StoreKitManager] Error checking cancellation status: \(error)")
        }

        return nil
    }

    /// Check if subscription was canceled and returns true if so
    func isSubscriptionCanceled() async -> Bool {
        guard let product = receiverMonthlyProduct else { return false }

        do {
            let statuses = try await product.subscription?.status ?? []

            for status in statuses {
                if case .verified(let renewalInfo) = status.renewalInfo {
                    // Auto-renew disabled means user canceled
                    if renewalInfo.willAutoRenew == false {
                        return true
                    }
                }
            }
        } catch {
            print("[StoreKitManager] Error checking cancellation: \(error)")
        }

        return false
    }

    /// Get remaining trial days if in trial period
    func getTrialDaysRemaining() async -> Int? {
        guard let product = receiverMonthlyProduct else { return nil }

        do {
            let statuses = try await product.subscription?.status ?? []

            for status in statuses {
                if case .verified(let renewalInfo) = status.renewalInfo {
                    if renewalInfo.offerType == .introductory {
                        // Currently in trial - calculate remaining days
                        if case .verified(let transaction) = status.transaction {
                            if let expirationDate = transaction.expirationDate {
                                let calendar = Calendar.current
                                let days = calendar.dateComponents([.day], from: Date(), to: expirationDate).day
                                return max(0, days ?? 0)
                            }
                        }
                    }
                }
            }
        } catch {
            print("[StoreKitManager] Error getting trial days: \(error)")
        }

        return nil
    }

    // MARK: - Restore Purchases

    /// Restore purchases from App Store
    func restorePurchases() async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
        } catch {
            errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
            throw StoreKitError.restoreFailed(error.localizedDescription)
        }
    }

    // MARK: - Manage Subscription

    /// Show App Store subscription management sheet
    func showManageSubscriptions() async {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            do {
                try await AppStore.showManageSubscriptions(in: windowScene)
            } catch {
                errorMessage = "Unable to open subscription management: \(error.localizedDescription)"
                print("[StoreKitManager] Error showing manage subscriptions: \(error)")
            }
        }
    }

    // MARK: - Transaction Listener

    /// Listen for transaction updates (renewals, refunds, etc.)
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    // Update subscription status when transactions change
                    await self.updateSubscriptionStatus()

                    // Finish the transaction
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Verification

    /// Check if a transaction is verified
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw StoreKitError.verificationFailed(error.localizedDescription)
        case .verified(let safe):
            return safe
        }
    }
}

// MARK: - Subscription Status Enum

/// Represents the current subscription status
enum StoreKitSubscriptionStatus: Equatable {
    case unknown
    case notSubscribed
    case eligibleForTrial
    case inTrial
    case active
    case expired
    case pastDue

    /// Display name for the status
    var displayName: String {
        switch self {
        case .unknown:
            return "Loading..."
        case .notSubscribed:
            return "Not Subscribed"
        case .eligibleForTrial:
            return "Start Free Trial"
        case .inTrial:
            return "Free Trial"
        case .active:
            return "Active"
        case .expired:
            return "Expired"
        case .pastDue:
            return "Payment Past Due"
        }
    }

    /// Whether receiver features should be accessible
    var hasReceiverAccess: Bool {
        switch self {
        case .inTrial, .active:
            return true
        case .unknown, .notSubscribed, .eligibleForTrial, .expired, .pastDue:
            return false
        }
    }
}

// MARK: - Purchase Result

/// Result of a purchase attempt
enum PurchaseResult {
    case success(Transaction)
    case userCancelled
    case pending
    case unknown

    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}

// MARK: - StoreKit Errors

/// Errors related to StoreKit operations
enum StoreKitError: LocalizedError {
    case productNotFound
    case purchaseFailed(String)
    case verificationFailed(String)
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "The subscription product could not be found. Please try again later."
        case .purchaseFailed(let message):
            return "Purchase failed: \(message)"
        case .verificationFailed(let message):
            return "Transaction verification failed: \(message)"
        case .restoreFailed(let message):
            return "Failed to restore purchases: \(message)"
        }
    }
}

// MARK: - Product Extensions

extension Product {
    /// Formatted price with introductory offer info
    var formattedPriceWithOffer: String {
        if let introOffer = subscription?.introductoryOffer {
            if introOffer.paymentMode == .freeTrial {
                let period = introOffer.period
                let periodString: String
                switch period.unit {
                case .day:
                    periodString = period.value == 1 ? "day" : "\(period.value) days"
                case .week:
                    periodString = period.value == 1 ? "week" : "\(period.value) weeks"
                case .month:
                    periodString = period.value == 1 ? "month" : "\(period.value) months"
                case .year:
                    periodString = period.value == 1 ? "year" : "\(period.value) years"
                @unknown default:
                    periodString = "\(period.value) periods"
                }
                return "\(periodString) free, then \(displayPrice)/month"
            }
        }
        return "\(displayPrice)/month"
    }

    /// Whether this product has a free trial offer
    var hasFreeTrial: Bool {
        subscription?.introductoryOffer?.paymentMode == .freeTrial
    }

    /// Trial period duration in days
    var trialDays: Int? {
        guard let introOffer = subscription?.introductoryOffer,
              introOffer.paymentMode == .freeTrial else {
            return nil
        }

        let period = introOffer.period
        switch period.unit {
        case .day:
            return period.value
        case .week:
            return period.value * 7
        case .month:
            return period.value * 30
        case .year:
            return period.value * 365
        @unknown default:
            return nil
        }
    }
}
