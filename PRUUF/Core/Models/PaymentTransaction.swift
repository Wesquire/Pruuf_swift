import Foundation

/// Represents a payment transaction
/// Maps to the `payment_transactions` table in Supabase
struct PaymentTransaction: Codable, Identifiable, Equatable {
    /// Unique transaction identifier
    let id: UUID

    /// User who made the payment
    let userId: UUID

    /// Stripe payment intent ID
    let stripePaymentIntentId: String?

    /// Transaction amount
    let amount: Decimal

    /// Currency code (default: USD)
    let currency: String

    /// Transaction status
    var status: PaymentStatus

    /// Type of transaction
    let transactionType: TransactionType?

    /// When the transaction was created
    let createdAt: Date

    /// Additional metadata
    var metadata: PaymentMetadata?

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case stripePaymentIntentId = "stripe_payment_intent_id"
        case amount
        case currency
        case status
        case transactionType = "transaction_type"
        case createdAt = "created_at"
        case metadata
    }

    // MARK: - Computed Properties

    /// Formatted amount with currency
    var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(currency) \(amount)"
    }

    /// Whether the payment was successful
    var isSuccessful: Bool {
        status == .succeeded
    }
}

// MARK: - Payment Status

/// Status of a payment transaction
/// Maps to CHECK constraint: status IN ('pending', 'succeeded', 'failed', 'refunded')
enum PaymentStatus: String, Codable, CaseIterable {
    /// Payment is pending
    case pending = "pending"

    /// Payment succeeded
    case succeeded = "succeeded"

    /// Payment failed
    case failed = "failed"

    /// Payment was refunded
    case refunded = "refunded"

    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        case .refunded:
            return "Refunded"
        }
    }

    var iconName: String {
        switch self {
        case .pending:
            return "clock.fill"
        case .succeeded:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .refunded:
            return "arrow.uturn.backward.circle.fill"
        }
    }

    /// Whether this is a terminal (final) state
    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .refunded:
            return true
        case .pending:
            return false
        }
    }
}

// MARK: - Transaction Type

/// Types of payment transactions
/// Maps to CHECK constraint: transaction_type IN ('subscription', 'refund', 'chargeback')
enum TransactionType: String, Codable, CaseIterable {
    /// Subscription payment
    case subscription = "subscription"

    /// Refund
    case refund = "refund"

    /// Chargeback
    case chargeback = "chargeback"

    var displayName: String {
        switch self {
        case .subscription:
            return "Subscription"
        case .refund:
            return "Refund"
        case .chargeback:
            return "Chargeback"
        }
    }
}

// MARK: - Payment Metadata

/// Additional metadata for payment transactions
struct PaymentMetadata: Codable, Equatable {
    /// Subscription period start
    var periodStart: Date?

    /// Subscription period end
    var periodEnd: Date?

    /// Original transaction ID (for refunds)
    var originalTransactionId: UUID?

    /// Refund reason
    var refundReason: String?

    /// Product ID
    var productId: String?

    /// Price tier
    var priceTier: String?

    enum CodingKeys: String, CodingKey {
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case originalTransactionId = "original_transaction_id"
        case refundReason = "refund_reason"
        case productId = "product_id"
        case priceTier = "price_tier"
    }
}
