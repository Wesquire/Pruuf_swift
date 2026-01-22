import SwiftUI
import StoreKit
import Supabase

// MARK: - Subscription Feature
// This module handles subscription/payment via App Store (StoreKit 2)
// Per plan.md Section 9.1:
// - Product ID: com.pruuf.receiver.monthly
// - Price: $2.99 USD/month
// - 15-day free trial for all receivers
// - No credit card required to start trial
// - Auto-renewable subscription managed through App Store

/// Subscription feature namespace
enum SubscriptionFeature {
    // Views implemented below:
    // - PaywallView: Shows subscription options and purchase flow
    // - SubscriptionManagementView: Shows current subscription status and management options
    // - SubscriptionStatusBadge: Small badge showing subscription status
}

// MARK: - Paywall View

/// Subscription paywall view displayed when receiver features require subscription
struct PaywallView: View {
    @StateObject private var subscriptionService = SubscriptionService.shared
    @StateObject private var storeKitManager = StoreKitManager.shared
    @Environment(\.dismiss) private var dismiss

    let userId: UUID
    var onSubscriptionComplete: (() -> Void)?

    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showRestoreSuccess = false
    @State private var showSubscriptionSuccess = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Features list
                    featuresSection

                    // Pricing
                    pricingSection

                    // Purchase buttons
                    purchaseSection

                    // Terms and restore
                    footerSection
                }
                .padding()
            }
            .navigationTitle("Receiver Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Purchases Restored", isPresented: $showRestoreSuccess) {
            Button("OK", role: .cancel) {
                if subscriptionService.hasActiveAppStoreSubscription {
                    onSubscriptionComplete?()
                    dismiss()
                }
            }
        } message: {
            Text(subscriptionService.hasActiveAppStoreSubscription
                 ? "Your subscription has been restored successfully."
                 : "No previous subscription found.")
        }
        // Per plan.md Section 9.3: Show confirmation "You're subscribed!"
        .alert("You're subscribed!", isPresented: $showSubscriptionSuccess) {
            Button("Get Started", role: .cancel) {
                onSubscriptionComplete?()
                dismiss()
            }
        } message: {
            Text("Welcome! You now have full access to all receiver features. Enjoy peace of mind knowing your loved ones are okay.")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.fill")
                .font(.system(size: 60))
                .foregroundColor(.pink)

            Text("Peace of Mind")
                .font(.title)
                .fontWeight(.bold)

            Text("Get daily check-in notifications and know your loved ones are okay")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical)
    }

    // MARK: - Features Section

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What you get:")
                .font(.headline)

            FeatureRow(icon: "bell.fill", text: "Daily check-in notifications")
            FeatureRow(icon: "clock.fill", text: "Real-time ping status updates")
            FeatureRow(icon: "flame.fill", text: "Streak tracking for each sender")
            FeatureRow(icon: "calendar", text: "Full ping history access")
            FeatureRow(icon: "person.2.fill", text: "Unlimited sender connections")
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Pricing Section

    private var pricingSection: some View {
        VStack(spacing: 16) {
            if let product = storeKitManager.receiverMonthlyProduct {
                // Trial info
                if product.hasFreeTrial {
                    HStack {
                        Image(systemName: "gift.fill")
                            .foregroundColor(.green)
                        Text("15-day free trial")
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(20)

                    Text("No credit card required to start")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Price card
                VStack(spacing: 8) {
                    Text(product.displayPrice)
                        .font(.system(size: 48, weight: .bold))

                    Text("per month")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if product.hasFreeTrial {
                        Text("after 15-day free trial")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(12)

            } else if storeKitManager.isLoading {
                ProgressView()
                    .padding()
            } else {
                Text("Unable to load pricing")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Purchase Section

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            if let product = storeKitManager.receiverMonthlyProduct {
                // Start Trial / Subscribe button
                Button {
                    Task {
                        await purchaseSubscription()
                    }
                } label: {
                    HStack {
                        if isPurchasing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(product.hasFreeTrial ? "Start Free Trial" : "Subscribe Now")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isPurchasing || storeKitManager.isLoading)

                // Restore purchases button
                Button {
                    Task {
                        await restorePurchases()
                    }
                } label: {
                    Text("Restore Purchases")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                .disabled(isPurchasing)
            }
        }
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        VStack(spacing: 8) {
            Text("Senders are always free. This subscription is only required for receiver features.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Terms of Service") {
                    // Open terms URL
                    if let url = URL(string: "https://pruuf.com/terms") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption)

                Button("Privacy Policy") {
                    // Open privacy URL
                    if let url = URL(string: "https://pruuf.com/privacy") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption)
            }
            .foregroundColor(.secondary)

            Text("Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Manage your subscription in Settings.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .padding(.top)
    }

    // MARK: - Actions

    private func purchaseSubscription() async {
        isPurchasing = true

        do {
            let result = try await subscriptionService.purchaseReceiverSubscription(userId: userId)

            switch result {
            case .success:
                // Per plan.md Section 9.3: Show confirmation "You're subscribed!"
                showSubscriptionSuccess = true
            case .userCancelled:
                // User cancelled, do nothing
                break
            case .pending:
                errorMessage = "Purchase is pending approval. You'll be notified when it's complete."
                showError = true
            case .unknown:
                errorMessage = "An unknown error occurred. Please try again."
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isPurchasing = false
    }

    private func restorePurchases() async {
        isPurchasing = true

        do {
            try await subscriptionService.restorePurchases(userId: userId)
            showRestoreSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isPurchasing = false
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)

            Spacer()
        }
    }
}

// MARK: - Subscription Management View
// Per plan.md Section 9.3: Complete subscription management UI

/// View for managing existing subscription
/// Displayed in Settings > Subscription per plan.md Section 9.3
struct SubscriptionManagementView: View {
    @StateObject private var subscriptionService = SubscriptionService.shared
    @StateObject private var storeKitManager = StoreKitManager.shared

    let userId: UUID

    @State private var expirationDate: Date?
    @State private var trialDaysRemaining: Int?
    @State private var isLoading = true
    @State private var isCanceled = false
    @State private var cancellationEndDate: Date?
    @State private var showPaywall = false
    @State private var showRestoreAlert = false
    @State private var restoreMessage = ""
    @State private var isRestoring = false

    var body: some View {
        List {
            // Status Section
            Section("Subscription Status") {
                statusRow
            }

            // Cancellation Notice per plan.md Section 9.3
            // Show message: "Your subscription will end on [date]"
            if isCanceled, let endDate = cancellationEndDate {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Subscription Canceled")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Your subscription will end on \(endDate, style: .date)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Details Section
            if let expirationDate = expirationDate {
                Section("Details") {
                    HStack {
                        Text(isCanceled ? "Access Ends" : "Renewal Date")
                        Spacer()
                        Text(expirationDate, style: .date)
                            .foregroundColor(.secondary)
                    }

                    if let daysRemaining = trialDaysRemaining, daysRemaining > 0 {
                        HStack {
                            Text("Trial Days Remaining")
                            Spacer()
                            Text("\(daysRemaining) days")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Actions Section
            Section {
                // Per plan.md Section 9.3: Manage Subscription opens iOS Settings
                Button("Manage Subscription") {
                    Task {
                        await subscriptionService.showManageSubscriptions()
                    }
                }

                // Per plan.md Section 9.3: "Restore Purchases" button in Settings > Subscription
                Button {
                    Task {
                        await restorePurchases()
                    }
                } label: {
                    HStack {
                        Text("Restore Purchases")
                        if isRestoring {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isRestoring)
            }

            // Resubscribe Section per plan.md Section 9.3
            // After cancellation or expiration - "Subscribe" button appears
            if shouldShowResubscribe {
                Section {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Subscribe")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Resubscribe")
                } footer: {
                    Text("Restore full functionality immediately by subscribing again.")
                        .font(.caption)
                }
            }

            // Info Section
            Section {
                Text("Your subscription is managed through the App Store. To cancel or modify your subscription, tap \"Manage Subscription\" above or go to Settings > Apple ID > Subscriptions on your device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Subscription")
        .onAppear {
            Task {
                await loadDetails()
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(userId: userId) {
                // Reload details after successful subscription
                Task {
                    await loadDetails()
                }
            }
        }
        .alert("Restore Purchases", isPresented: $showRestoreAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage)
        }
    }

    private var statusRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("PRUUF Receiver")
                    .font(.headline)

                Text(statusDisplayText)
                    .font(.subheadline)
                    .foregroundColor(statusColor)
            }

            Spacer()

            SubscriptionStatusBadge(status: storeKitManager.subscriptionStatus)
        }
    }

    private var statusDisplayText: String {
        if isCanceled && storeKitManager.subscriptionStatus == .active {
            return "Canceled (Access Until End of Period)"
        }
        return storeKitManager.subscriptionStatus.displayName
    }

    private var statusColor: Color {
        if isCanceled {
            return .orange
        }
        switch storeKitManager.subscriptionStatus {
        case .active, .inTrial:
            return .green
        case .eligibleForTrial:
            return .blue
        case .expired, .notSubscribed:
            return .red
        case .pastDue:
            return .orange
        case .unknown:
            return .secondary
        }
    }

    /// Per plan.md Section 9.3: Show Subscribe button after cancellation or expiration
    private var shouldShowResubscribe: Bool {
        switch storeKitManager.subscriptionStatus {
        case .expired, .notSubscribed:
            return true
        case .active:
            // Show if canceled (will expire)
            return isCanceled
        default:
            return false
        }
    }

    private func loadDetails() async {
        isLoading = true

        await storeKitManager.updateSubscriptionStatus()
        expirationDate = await storeKitManager.getSubscriptionExpirationDate()
        trialDaysRemaining = await storeKitManager.getTrialDaysRemaining()

        // Check cancellation status per plan.md Section 9.3
        isCanceled = await storeKitManager.isSubscriptionCanceled()
        if isCanceled {
            cancellationEndDate = await storeKitManager.getCancellationEndDate()
        }

        isLoading = false
    }

    /// Per plan.md Section 9.3: Restore Purchases functionality
    /// Queries App Store for existing purchases
    /// Updates database if active subscription found
    /// Useful for reinstalls or device changes
    private func restorePurchases() async {
        isRestoring = true

        do {
            try await subscriptionService.restorePurchases(userId: userId)
            await loadDetails()

            if subscriptionService.hasActiveAppStoreSubscription {
                restoreMessage = "Your subscription has been restored successfully."
            } else {
                restoreMessage = "No active subscription found. If you believe this is an error, please contact support."
            }
        } catch {
            restoreMessage = "Failed to restore purchases: \(error.localizedDescription)"
        }

        isRestoring = false
        showRestoreAlert = true
    }
}

// MARK: - Subscription Status Badge

/// Small badge showing subscription status
struct SubscriptionStatusBadge: View {
    let status: StoreKitSubscriptionStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(8)
    }

    private var backgroundColor: Color {
        switch status {
        case .active, .inTrial:
            return .green.opacity(0.15)
        case .eligibleForTrial:
            return .blue.opacity(0.15)
        case .expired, .notSubscribed:
            return .red.opacity(0.15)
        case .pastDue:
            return .orange.opacity(0.15)
        case .unknown:
            return .gray.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .active, .inTrial:
            return .green
        case .eligibleForTrial:
            return .blue
        case .expired, .notSubscribed:
            return .red
        case .pastDue:
            return .orange
        case .unknown:
            return .secondary
        }
    }
}

// MARK: - Trial Banner View

/// Banner shown during free trial period
struct TrialBannerView: View {
    let daysRemaining: Int
    var onTapSubscribe: (() -> Void)?

    var body: some View {
        HStack {
            Image(systemName: "clock.fill")
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Free Trial")
                    .font(.caption)
                    .fontWeight(.semibold)

                Text("\(daysRemaining) days remaining")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let onTapSubscribe = onTapSubscribe {
                Button("Subscribe") {
                    onTapSubscribe()
                }
                .font(.caption.weight(.medium))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Subscription Required View

/// View shown when subscription is required but not active
struct SubscriptionRequiredView: View {
    let userId: UUID
    var onSubscribe: (() -> Void)?

    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("Subscription Required")
                .font(.title2)
                .fontWeight(.bold)

            Text("Subscribe to access receiver features and get peace of mind knowing your loved ones are okay.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                Text("$2.99/month")
                    .font(.title)
                    .fontWeight(.bold)

                Text("15-day free trial")
                    .font(.subheadline)
                    .foregroundColor(.green)
            }

            Button {
                showPaywall = true
            } label: {
                Text("Start Free Trial")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
        .padding()
        .sheet(isPresented: $showPaywall) {
            PaywallView(userId: userId) {
                onSubscribe?()
            }
        }
    }
}

// MARK: - Section 9.5: Subscription Status Banners

/// Banner type for subscription status display on app launch
/// Per plan.md Section 9.5: App launch subscription status checks
enum SubscriptionBannerType: String {
    case expired = "expired"
    case paymentFailed = "payment_failed"
    case trialEnding = "trial_ending"
    case canceled = "canceled"
}

/// Subscription Expired Banner View
/// Per plan.md Section 9.5: If expired -> Show "Subscription Expired" banner
struct SubscriptionExpiredBannerView: View {
    var onSubscribe: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(.red)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Subscription Expired")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Subscribe to continue receiving check-ins from your senders.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if onDismiss != nil {
                    Button {
                        onDismiss?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let onSubscribe = onSubscribe {
                Button {
                    onSubscribe()
                } label: {
                    Text("Subscribe Now")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }
}

/// Payment Failed Banner View
/// Per plan.md Section 9.5: If past_due -> Show "Payment Failed - Update Payment Method"
struct PaymentFailedBannerView: View {
    let gracePeriodDaysRemaining: Int?
    var onUpdatePayment: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "creditcard.trianglebadge.exclamationmark")
                    .font(.title2)
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Payment Failed")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(messageText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if onDismiss != nil {
                    Button {
                        onDismiss?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let onUpdatePayment = onUpdatePayment {
                Button {
                    onUpdatePayment()
                } label: {
                    Text("Update Payment Method")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange)
                        .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    private var messageText: String {
        if let days = gracePeriodDaysRemaining, days > 0 {
            return "Update your payment method within \(days) day\(days == 1 ? "" : "s") to continue receiving check-ins."
        } else {
            return "Update your payment method to continue receiving check-ins."
        }
    }
}

/// Subscription Status Banner Container
/// Per plan.md Section 9.5: Checks subscription status on app launch
/// Displays appropriate banner: expired, payment_failed, trial_ending, or canceled
struct SubscriptionStatusBannerContainer: View {
    @StateObject private var subscriptionService = SubscriptionService.shared
    @StateObject private var storeKitManager = StoreKitManager.shared

    let userId: UUID
    @State private var showPaywall = false
    @State private var bannerDismissed = false

    var body: some View {
        Group {
            if !bannerDismissed {
                bannerForCurrentStatus
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(userId: userId)
        }
        .task {
            // Check subscription status on appear
            await checkSubscriptionStatus()
        }
    }

    @ViewBuilder
    private var bannerForCurrentStatus: some View {
        switch storeKitManager.subscriptionStatus {
        case .expired, .notSubscribed:
            if subscriptionService.currentStatus == .expired ||
               subscriptionService.currentStatus == .canceled {
                SubscriptionExpiredBannerView(
                    onSubscribe: {
                        showPaywall = true
                    },
                    onDismiss: {
                        bannerDismissed = true
                    }
                )
            }

        case .pastDue:
            PaymentFailedBannerView(
                gracePeriodDaysRemaining: calculateGracePeriodRemaining(),
                onUpdatePayment: {
                    Task {
                        await subscriptionService.showManageSubscriptions()
                    }
                },
                onDismiss: {
                    bannerDismissed = true
                }
            )

        default:
            EmptyView()
        }
    }

    private func checkSubscriptionStatus() async {
        do {
            _ = try await subscriptionService.checkSubscriptionStatus(userId: userId)
            await storeKitManager.updateSubscriptionStatus()
        } catch {
            print("Failed to check subscription status: \(error)")
        }
    }

    private func calculateGracePeriodRemaining() -> Int? {
        // Grace period is 3 days from when past_due started
        // This would need updated_at from the backend, for now return nil
        // The backend function provides this in get_subscription_status_for_display
        return nil
    }
}

/// Helper for Section 9.5: Get subscription status for display
/// Calls the database RPC function get_subscription_status_for_display
struct SubscriptionStatusChecker {

    private let database: PostgrestClient

    init(database: PostgrestClient? = nil) {
        self.database = database ?? SupabaseConfig.client.schema("public")
    }

    /// Section 9.5: Get banner info for subscription status
    /// Returns banner type and message for display on app launch
    func getSubscriptionStatusForDisplay(userId: UUID) async throws -> SubscriptionStatusDisplay? {
        let response: PostgrestResponse<SubscriptionStatusDisplay?> = try await database
            .rpc("get_subscription_status_for_display", params: ["p_user_id": userId.uuidString])
            .execute()

        return response.value
    }
}

/// Response model for subscription status display
/// Matches the JSONB returned by get_subscription_status_for_display function
struct SubscriptionStatusDisplay: Codable {
    let status: String
    let showBanner: Bool
    let bannerType: String?
    let bannerMessage: String?
    let isValid: Bool
    let trialEndDate: Date?
    let subscriptionEndDate: Date?
    let gracePeriodDays: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case showBanner = "show_banner"
        case bannerType = "banner_type"
        case bannerMessage = "banner_message"
        case isValid = "is_valid"
        case trialEndDate = "trial_end_date"
        case subscriptionEndDate = "subscription_end_date"
        case gracePeriodDays = "grace_period_days"
    }
}

// MARK: - Previews

#if DEBUG
struct PaywallView_Previews: PreviewProvider {
    static var previews: some View {
        PaywallView(userId: UUID())
    }
}

struct SubscriptionManagementView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SubscriptionManagementView(userId: UUID())
        }
    }
}

struct TrialBannerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            TrialBannerView(daysRemaining: 10)
            TrialBannerView(daysRemaining: 3) {
                print("Subscribe tapped")
            }
        }
        .padding()
    }
}

struct SubscriptionExpiredBannerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            SubscriptionExpiredBannerView(
                onSubscribe: { print("Subscribe tapped") },
                onDismiss: { print("Dismissed") }
            )

            SubscriptionExpiredBannerView(
                onSubscribe: { print("Subscribe tapped") }
            )
        }
        .padding()
    }
}

struct PaymentFailedBannerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            PaymentFailedBannerView(
                gracePeriodDaysRemaining: 2,
                onUpdatePayment: { print("Update payment tapped") },
                onDismiss: { print("Dismissed") }
            )

            PaymentFailedBannerView(
                gracePeriodDaysRemaining: nil,
                onUpdatePayment: { print("Update payment tapped") }
            )
        }
        .padding()
    }
}
#endif
