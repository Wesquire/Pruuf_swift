import Foundation

// MARK: - User Role

/// Primary role that determines the user's main use case in PRUUF
enum UserRole: String, Codable, CaseIterable, Equatable {
    case sender = "sender"
    case receiver = "receiver"
    case both = "both"

    /// Display title for the role
    var displayTitle: String {
        switch self {
        case .sender:
            return "I want to check in daily"
        case .receiver:
            return "I want peace of mind"
        case .both:
            return "Both sender and receiver"
        }
    }

    /// Description for the role
    var description: String {
        switch self {
        case .sender:
            return "Let people know you're okay with a simple daily ping"
        case .receiver:
            return "Get daily confirmation that your loved ones are safe"
        case .both:
            return "Check in daily and monitor loved ones"
        }
    }

    /// Pricing tag for the role
    var pricingTag: String {
        switch self {
        case .sender:
            return "Always Free"
        case .receiver:
            return "$2.99/month after 15-day trial"
        case .both:
            return "$2.99/month for receiver features"
        }
    }

    /// SF Symbol icon name for the role
    var iconName: String {
        switch self {
        case .sender:
            return "checkmark.circle.fill"
        case .receiver:
            return "heart.fill"
        case .both:
            return "person.2.fill"
        }
    }
}

/// Represents a user in the PRUUF system
/// Maps to the `users` table in Supabase
struct PruufUser: Codable, Identifiable, Equatable {
    /// Unique user identifier (matches Supabase auth.users.id)
    let id: UUID

    /// User's phone number (without country code) - PRIMARY authentication identifier
    let phoneNumber: String

    /// User's phone country code (e.g., "+1")
    var phoneCountryCode: String

    /// User's email address (optional, for future features)
    var email: String?

    /// Apple User ID from Apple Sign-In credential (optional, for future features)
    var appleUserId: String?

    /// When the user was created
    let createdAt: Date

    /// When the user was last updated
    var updatedAt: Date

    /// When the user was last seen/active
    var lastSeenAt: Date?

    /// Whether the user account is active
    var isActive: Bool

    /// Whether the user has completed onboarding
    var hasCompletedOnboarding: Bool

    /// User's primary role (sender, receiver, or both)
    var primaryRole: UserRole?

    /// User's timezone identifier (e.g., "America/New_York")
    var timezone: String

    /// Device token for push notifications
    var deviceToken: String?

    /// Notification preferences
    var notificationPreferences: NotificationPreferences

    /// Current onboarding step (for resuming mid-onboarding)
    var onboardingStep: OnboardingStep?

    /// User's display name (populated from sender/receiver profile or stored separately)
    var displayName: String?

    /// URL to user's avatar image (from storage bucket)
    var avatarURL: String?

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case phoneNumber = "phone_number"
        case phoneCountryCode = "phone_country_code"
        case email
        case appleUserId = "apple_user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastSeenAt = "last_seen_at"
        case isActive = "is_active"
        case hasCompletedOnboarding = "has_completed_onboarding"
        case primaryRole = "primary_role"
        case timezone
        case deviceToken = "device_token"
        case notificationPreferences = "notification_preferences"
        case onboardingStep = "onboarding_step"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
    }

    // MARK: - Computed Properties

    /// Full phone number with country code
    var fullPhoneNumber: String {
        "\(phoneCountryCode)\(phoneNumber)"
    }

    /// Display identifier - phone number (primary) or email if available
    var displayIdentifier: String {
        if !phoneNumber.isEmpty {
            return fullPhoneNumber
        }
        if let email = email {
            return email
        }
        return "User"
    }

    /// Get initials from display name
    var initials: String {
        guard let name = displayName, !name.isEmpty else {
            return "?"
        }
        let words = name.split(separator: " ")
        let initials = words.prefix(2).compactMap { $0.first?.uppercased() }
        return initials.joined()
    }
}

// MARK: - Notification Preferences

/// User's notification preferences stored as JSONB in database
/// Supports both sender and receiver notification settings per Section 8.3
struct NotificationPreferences: Codable, Equatable {
    // MARK: - Master Toggle

    /// Master toggle: Enable/Disable all notifications
    var notificationsEnabled: Bool

    // MARK: - Sender Preferences

    /// Whether to receive ping reminders at scheduled time (sender)
    var pingReminders: Bool

    /// Whether to receive 15-minute warning before deadline (sender)
    var fifteenMinuteWarning: Bool

    /// Whether to receive deadline warning notifications (sender)
    var deadlineWarning: Bool

    // MARK: - Receiver Preferences

    /// Whether to receive ping completed notifications (receiver)
    var pingCompletedNotifications: Bool

    /// Whether to receive missed ping alerts (receiver)
    var missedPingAlerts: Bool

    /// Whether to receive connection request notifications
    var connectionRequests: Bool

    /// Whether to receive payment reminder notifications (receivers only)
    var paymentReminders: Bool

    // MARK: - Per-Sender Muting (Receivers only)

    /// List of sender IDs whose notifications are muted (Receiver only)
    var mutedSenderIds: [UUID]?

    // MARK: - Sound and Vibration (US-8.1)

    /// Whether notification sounds are enabled
    var soundEnabled: Bool

    /// Whether vibration (haptic feedback) is enabled for notifications
    var vibrationEnabled: Bool

    // MARK: - Quiet Hours (Future Feature)

    /// Whether quiet hours are enabled
    var quietHoursEnabled: Bool

    /// Quiet hours start time in HH:MM format (24-hour)
    var quietHoursStart: String?

    /// Quiet hours end time in HH:MM format (24-hour)
    var quietHoursEnd: String?

    enum CodingKeys: String, CodingKey {
        case notificationsEnabled = "notifications_enabled"
        case pingReminders = "ping_reminders"
        case fifteenMinuteWarning = "fifteen_minute_warning"
        case deadlineWarning = "deadline_warning"
        case pingCompletedNotifications = "ping_completed_notifications"
        case missedPingAlerts = "missed_ping_alerts"
        case connectionRequests = "connection_requests"
        case paymentReminders = "payment_reminders"
        case mutedSenderIds = "muted_sender_ids"
        case soundEnabled = "sound_enabled"
        case vibrationEnabled = "vibration_enabled"
        case quietHoursEnabled = "quiet_hours_enabled"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
    }

    /// Default preferences (all enabled, sound/vibration enabled, quiet hours disabled)
    static let defaults = NotificationPreferences(
        notificationsEnabled: true,
        pingReminders: true,
        fifteenMinuteWarning: true,
        deadlineWarning: true,
        pingCompletedNotifications: true,
        missedPingAlerts: true,
        connectionRequests: true,
        paymentReminders: true,
        mutedSenderIds: nil,
        soundEnabled: true,
        vibrationEnabled: true,
        quietHoursEnabled: false,
        quietHoursStart: nil,
        quietHoursEnd: nil
    )

    /// Initialize with default values
    init(
        notificationsEnabled: Bool = true,
        pingReminders: Bool = true,
        fifteenMinuteWarning: Bool = true,
        deadlineWarning: Bool = true,
        pingCompletedNotifications: Bool = true,
        missedPingAlerts: Bool = true,
        connectionRequests: Bool = true,
        paymentReminders: Bool = true,
        mutedSenderIds: [UUID]? = nil,
        soundEnabled: Bool = true,
        vibrationEnabled: Bool = true,
        quietHoursEnabled: Bool = false,
        quietHoursStart: String? = nil,
        quietHoursEnd: String? = nil
    ) {
        self.notificationsEnabled = notificationsEnabled
        self.pingReminders = pingReminders
        self.fifteenMinuteWarning = fifteenMinuteWarning
        self.deadlineWarning = deadlineWarning
        self.pingCompletedNotifications = pingCompletedNotifications
        self.missedPingAlerts = missedPingAlerts
        self.connectionRequests = connectionRequests
        self.paymentReminders = paymentReminders
        self.mutedSenderIds = mutedSenderIds
        self.soundEnabled = soundEnabled
        self.vibrationEnabled = vibrationEnabled
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
    }

    // MARK: - Muting Helpers

    /// Check if a specific sender is muted
    /// - Parameter senderId: The sender's UUID
    /// - Returns: Whether the sender is muted
    func isSenderMuted(_ senderId: UUID) -> Bool {
        mutedSenderIds?.contains(senderId) ?? false
    }

    /// Create a copy with a sender added to the muted list
    /// - Parameter senderId: The sender to mute
    /// - Returns: Updated preferences with sender muted
    func mutingSender(_ senderId: UUID) -> NotificationPreferences {
        var updated = self
        var muted = mutedSenderIds ?? []
        if !muted.contains(senderId) {
            muted.append(senderId)
        }
        updated.mutedSenderIds = muted
        return updated
    }

    /// Create a copy with a sender removed from the muted list
    /// - Parameter senderId: The sender to unmute
    /// - Returns: Updated preferences with sender unmuted
    func unmutingSender(_ senderId: UUID) -> NotificationPreferences {
        var updated = self
        var muted = mutedSenderIds ?? []
        muted.removeAll { $0 == senderId }
        updated.mutedSenderIds = muted.isEmpty ? nil : muted
        return updated
    }

    // MARK: - Quiet Hours Helpers

    /// Check if quiet hours are currently active
    /// - Returns: Whether notifications should be suppressed due to quiet hours
    func isInQuietHours() -> Bool {
        guard quietHoursEnabled,
              let start = quietHoursStart,
              let end = quietHoursEnd else {
            return false
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        guard let startTime = formatter.date(from: start),
              let endTime = formatter.date(from: end) else {
            return false
        }

        let now = Date()
        let calendar = Calendar.current

        // Get current time as HH:mm
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let startHour = calendar.component(.hour, from: startTime)
        let startMinute = calendar.component(.minute, from: startTime)
        let endHour = calendar.component(.hour, from: endTime)
        let endMinute = calendar.component(.minute, from: endTime)

        let currentMinutes = currentHour * 60 + currentMinute
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute

        // Handle overnight quiet hours (e.g., 22:00 - 07:00)
        if startMinutes > endMinutes {
            return currentMinutes >= startMinutes || currentMinutes < endMinutes
        } else {
            return currentMinutes >= startMinutes && currentMinutes < endMinutes
        }
    }

    /// Check if a notification should be sent based on preferences
    /// - Parameters:
    ///   - type: The notification type
    ///   - senderId: Optional sender ID for receiver notifications
    /// - Returns: Whether the notification should be sent
    func shouldSendNotification(type: NotificationType, senderId: UUID? = nil) -> Bool {
        // Master toggle check
        guard notificationsEnabled else { return false }

        // Quiet hours check (future feature)
        if isInQuietHours() { return false }

        // Per-sender muting check for receiver notifications
        if let senderId = senderId, isSenderMuted(senderId) { return false }

        // Type-specific checks
        switch type {
        case .pingReminder:
            return pingReminders
        case .deadlineWarning:
            return fifteenMinuteWarning
        case .deadlineFinal:
            return deadlineWarning
        case .missedPing:
            return missedPingAlerts
        case .pingCompletedOnTime, .pingCompletedLate:
            return pingCompletedNotifications
        case .connectionRequest:
            return connectionRequests
        case .breakStarted, .breakNotification:
            return pingCompletedNotifications // Use same setting as ping completed
        case .paymentReminder, .trialEnding:
            return true // Always send payment-related notifications
        case .dataExportReady, .dataExportEmailSent:
            return true // Always notify about data exports
        case .pingTimeChanged:
            return pingReminders // Use same setting as ping reminders
        }
    }
}

// MARK: - User Update Request

/// Request model for updating user profile
struct UserUpdateRequest: Codable {
    var primaryRole: UserRole?
    var timezone: String?
    var hasCompletedOnboarding: Bool?
    var deviceToken: String?
    var notificationPreferences: NotificationPreferences?
    var onboardingStep: OnboardingStep?
    var lastSeenAt: Date?

    enum CodingKeys: String, CodingKey {
        case primaryRole = "primary_role"
        case timezone
        case hasCompletedOnboarding = "has_completed_onboarding"
        case deviceToken = "device_token"
        case notificationPreferences = "notification_preferences"
        case onboardingStep = "onboarding_step"
        case lastSeenAt = "last_seen_at"
    }
}

// MARK: - Onboarding Step

/// Tracks user's progress through onboarding flow (for resuming mid-onboarding - EC-2.1)
enum OnboardingStep: String, Codable, CaseIterable, Equatable {
    case roleSelection = "role_selection"
    case senderTutorial = "sender_tutorial"
    case senderPingTime = "sender_ping_time"
    case senderConnections = "sender_connections"
    case senderNotifications = "sender_notifications"
    case senderComplete = "sender_complete"
    case receiverTutorial = "receiver_tutorial"
    case receiverCode = "receiver_code"
    case receiverSubscription = "receiver_subscription"
    case receiverNotifications = "receiver_notifications"
    case receiverComplete = "receiver_complete"

    /// Display name for the step
    var displayName: String {
        switch self {
        case .roleSelection:
            return "Choose your role"
        case .senderTutorial:
            return "Sender tutorial"
        case .senderPingTime:
            return "Set ping time"
        case .senderConnections:
            return "Add connections"
        case .senderNotifications:
            return "Enable notifications"
        case .senderComplete:
            return "Setup complete"
        case .receiverTutorial:
            return "Receiver tutorial"
        case .receiverCode:
            return "Get your code"
        case .receiverSubscription:
            return "Subscription info"
        case .receiverNotifications:
            return "Enable notifications"
        case .receiverComplete:
            return "Setup complete"
        }
    }

    /// Whether this step is for sender onboarding
    var isSenderStep: Bool {
        switch self {
        case .senderTutorial, .senderPingTime, .senderConnections, .senderNotifications, .senderComplete:
            return true
        default:
            return false
        }
    }

    /// Whether this step is for receiver onboarding
    var isReceiverStep: Bool {
        switch self {
        case .receiverTutorial, .receiverCode, .receiverSubscription, .receiverNotifications, .receiverComplete:
            return true
        default:
            return false
        }
    }
}

// MARK: - Sender Profile

/// Sender-specific profile settings
/// Maps to the `sender_profiles` table in Supabase
struct SenderProfile: Codable, Identifiable, Equatable {
    /// Unique profile identifier
    let id: UUID

    /// Reference to the user
    let userId: UUID

    /// Daily ping time in UTC (HH:MM:SS format)
    var pingTime: String

    /// Whether pings are currently enabled
    var pingEnabled: Bool

    /// When the profile was created
    let createdAt: Date

    /// When the profile was last updated
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case pingTime = "ping_time"
        case pingEnabled = "ping_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Request model for creating a new sender profile
struct NewSenderProfileRequest: Codable {
    let userId: UUID
    let pingTime: String
    let pingEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case pingTime = "ping_time"
        case pingEnabled = "ping_enabled"
    }
}

// MARK: - Receiver Profile

/// Receiver-specific profile settings with subscription info
/// Maps to the `receiver_profiles` table in Supabase
struct ReceiverProfile: Codable, Identifiable, Equatable {
    /// Unique profile identifier
    let id: UUID

    /// Reference to the user
    let userId: UUID

    /// Current subscription status
    var subscriptionStatus: SubscriptionStatus

    /// When the subscription/trial started
    var subscriptionStartDate: Date?

    /// When the subscription/trial ends
    var subscriptionEndDate: Date?

    /// When the trial period started (timestamp when user selected receiver role)
    var trialStartDate: Date?

    /// When the trial period ends (15 days from signup)
    var trialEndDate: Date?

    /// Stripe customer ID for payment processing
    var stripeCustomerId: String?

    /// Stripe subscription ID
    var stripeSubscriptionId: String?

    /// When the profile was created
    let createdAt: Date

    /// When the profile was last updated
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case subscriptionStatus = "subscription_status"
        case subscriptionStartDate = "subscription_start_date"
        case subscriptionEndDate = "subscription_end_date"
        case trialStartDate = "trial_start_date"
        case trialEndDate = "trial_end_date"
        case stripeCustomerId = "stripe_customer_id"
        case stripeSubscriptionId = "stripe_subscription_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Whether the user is in trial period
    var isInTrial: Bool {
        guard subscriptionStatus == .trial else { return false }
        guard let trialEnd = trialEndDate else { return false }
        return Date() < trialEnd
    }

    /// Days remaining in trial
    var trialDaysRemaining: Int? {
        guard let trialEnd = trialEndDate else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0
        return max(0, days)
    }

    /// Whether the subscription is active (trial or paid)
    var isSubscriptionActive: Bool {
        switch subscriptionStatus {
        case .trial:
            return isInTrial
        case .active:
            return true
        case .pastDue, .canceled, .expired:
            return false
        }
    }
}

/// Request model for creating a new receiver profile
struct NewReceiverProfileRequest: Codable {
    let userId: UUID
    let subscriptionStatus: SubscriptionStatus
    let trialStartDate: Date
    let trialEndDate: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case subscriptionStatus = "subscription_status"
        case trialStartDate = "trial_start_date"
        case trialEndDate = "trial_end_date"
    }
}

// MARK: - Subscription Status

/// Subscription status for receiver profiles
enum SubscriptionStatus: String, Codable, CaseIterable, Equatable {
    case trial = "trial"
    case active = "active"
    case pastDue = "past_due"
    case canceled = "canceled"
    case expired = "expired"

    /// Display name for the status
    var displayName: String {
        switch self {
        case .trial:
            return "Free Trial"
        case .active:
            return "Active"
        case .pastDue:
            return "Past Due"
        case .canceled:
            return "Canceled"
        case .expired:
            return "Expired"
        }
    }

    /// Color hint for the status
    var isActive: Bool {
        switch self {
        case .trial, .active:
            return true
        case .pastDue, .canceled, .expired:
            return false
        }
    }
}
