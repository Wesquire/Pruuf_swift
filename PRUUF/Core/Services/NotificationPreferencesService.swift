import Foundation
import Supabase

/// Service for managing user notification preferences
/// Handles CRUD operations for notification settings stored in the users table
@MainActor
final class NotificationPreferencesService: ObservableObject {

    // MARK: - Singleton

    static let shared = NotificationPreferencesService()

    // MARK: - Published Properties

    @Published private(set) var preferences: NotificationPreferences = .defaults
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    // MARK: - Private Properties

    private let database: PostgrestClient

    // MARK: - Initialization

    init(database: PostgrestClient? = nil) {
        self.database = database ?? SupabaseConfig.client.schema("public")
    }

    // MARK: - Fetch Preferences

    /// Fetch the current user's notification preferences
    func fetchPreferences() async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        guard let userId = try? await SupabaseConfig.auth.session.user.id else {
            throw NotificationPreferencesError.notAuthenticated
        }

        do {
            let response: [PreferencesResponse] = try await database
                .from("users")
                .select("notification_preferences")
                .eq("id", value: userId.uuidString)
                .execute()
                .value

            if let prefs = response.first?.notificationPreferences {
                self.preferences = prefs
            } else {
                // Use defaults if no preferences exist
                self.preferences = .defaults
            }
        } catch {
            self.error = error.localizedDescription
            throw NotificationPreferencesError.fetchFailed(error.localizedDescription)
        }
    }

    /// Get preferences for a specific user (admin use)
    func fetchPreferences(for userId: UUID) async throws -> NotificationPreferences {
        let response: [PreferencesResponse] = try await database
            .from("users")
            .select("notification_preferences")
            .eq("id", value: userId.uuidString)
            .execute()
            .value

        return response.first?.notificationPreferences ?? .defaults
    }

    // MARK: - Update Preferences

    /// Update the current user's notification preferences
    /// - Parameter newPreferences: The updated preferences
    func updatePreferences(_ newPreferences: NotificationPreferences) async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        guard let userId = try? await SupabaseConfig.auth.session.user.id else {
            throw NotificationPreferencesError.notAuthenticated
        }

        do {
            try await database
                .from("users")
                .update(["notification_preferences": newPreferences])
                .eq("id", value: userId.uuidString)
                .execute()

            self.preferences = newPreferences
            Logger.info("Notification preferences updated successfully")
        } catch {
            self.error = error.localizedDescription
            throw NotificationPreferencesError.updateFailed(error.localizedDescription)
        }
    }

    // MARK: - Master Toggle

    /// Enable or disable all notifications
    /// - Parameter enabled: Whether notifications should be enabled
    func setNotificationsEnabled(_ enabled: Bool) async throws {
        var updated = preferences
        updated.notificationsEnabled = enabled
        try await updatePreferences(updated)
    }

    // MARK: - Sender Preferences

    /// Update ping reminder preference (sender)
    /// - Parameter enabled: Whether to receive ping reminders
    func setPingReminders(_ enabled: Bool) async throws {
        var updated = preferences
        updated.pingReminders = enabled
        try await updatePreferences(updated)
    }

    /// Update 15-minute warning preference (sender)
    /// - Parameter enabled: Whether to receive 15-minute warning
    func setFifteenMinuteWarning(_ enabled: Bool) async throws {
        var updated = preferences
        updated.fifteenMinuteWarning = enabled
        try await updatePreferences(updated)
    }

    /// Update deadline warning preference (sender)
    /// - Parameter enabled: Whether to receive deadline warning
    func setDeadlineWarning(_ enabled: Bool) async throws {
        var updated = preferences
        updated.deadlineWarning = enabled
        try await updatePreferences(updated)
    }

    // MARK: - Receiver Preferences

    /// Update ping completed notification preference (receiver)
    /// - Parameter enabled: Whether to receive ping completed notifications
    func setPingCompletedNotifications(_ enabled: Bool) async throws {
        var updated = preferences
        updated.pingCompletedNotifications = enabled
        try await updatePreferences(updated)
    }

    /// Update missed ping alert preference (receiver)
    /// - Parameter enabled: Whether to receive missed ping alerts
    func setMissedPingAlerts(_ enabled: Bool) async throws {
        var updated = preferences
        updated.missedPingAlerts = enabled
        try await updatePreferences(updated)
    }

    /// Update connection request notification preference
    /// - Parameter enabled: Whether to receive connection request notifications
    func setConnectionRequests(_ enabled: Bool) async throws {
        var updated = preferences
        updated.connectionRequests = enabled
        try await updatePreferences(updated)
    }

    /// Update payment reminder notification preference (receiver)
    /// - Parameter enabled: Whether to receive payment reminder notifications
    func setPaymentReminders(_ enabled: Bool) async throws {
        var updated = preferences
        updated.paymentReminders = enabled
        try await updatePreferences(updated)
    }

    // MARK: - Per-Sender Muting (Receiver only)

    /// Mute notifications from a specific sender
    /// - Parameter senderId: The sender to mute
    func muteSender(_ senderId: UUID) async throws {
        let updated = preferences.mutingSender(senderId)
        try await updatePreferences(updated)
        Logger.info("Muted notifications from sender: \(senderId)")
    }

    /// Unmute notifications from a specific sender
    /// - Parameter senderId: The sender to unmute
    func unmuteSender(_ senderId: UUID) async throws {
        let updated = preferences.unmutingSender(senderId)
        try await updatePreferences(updated)
        Logger.info("Unmuted notifications from sender: \(senderId)")
    }

    /// Toggle mute status for a sender
    /// - Parameter senderId: The sender to toggle
    /// - Returns: Whether the sender is now muted
    @discardableResult
    func toggleSenderMute(_ senderId: UUID) async throws -> Bool {
        if preferences.isSenderMuted(senderId) {
            try await unmuteSender(senderId)
            return false
        } else {
            try await muteSender(senderId)
            return true
        }
    }

    /// Get list of muted sender IDs
    func getMutedSenderIds() -> [UUID] {
        preferences.mutedSenderIds ?? []
    }

    // MARK: - Sound and Vibration (US-8.1)

    /// Enable or disable notification sounds
    /// - Parameter enabled: Whether sounds should be enabled
    func setSoundEnabled(_ enabled: Bool) async throws {
        var updated = preferences
        updated.soundEnabled = enabled
        try await updatePreferences(updated)
        Logger.info("Notification sound \(enabled ? "enabled" : "disabled")")
    }

    /// Enable or disable notification vibration
    /// - Parameter enabled: Whether vibration should be enabled
    func setVibrationEnabled(_ enabled: Bool) async throws {
        var updated = preferences
        updated.vibrationEnabled = enabled
        try await updatePreferences(updated)
        Logger.info("Notification vibration \(enabled ? "enabled" : "disabled")")
    }

    // MARK: - Quiet Hours (Future Feature)

    /// Enable or disable quiet hours
    /// - Parameter enabled: Whether quiet hours should be enabled
    func setQuietHoursEnabled(_ enabled: Bool) async throws {
        var updated = preferences
        updated.quietHoursEnabled = enabled
        try await updatePreferences(updated)
    }

    /// Set quiet hours time range
    /// - Parameters:
    ///   - start: Start time in HH:mm format (24-hour)
    ///   - end: End time in HH:mm format (24-hour)
    func setQuietHours(start: String, end: String) async throws {
        var updated = preferences
        updated.quietHoursStart = start
        updated.quietHoursEnd = end
        updated.quietHoursEnabled = true
        try await updatePreferences(updated)
    }

    /// Clear quiet hours settings
    func clearQuietHours() async throws {
        var updated = preferences
        updated.quietHoursEnabled = false
        updated.quietHoursStart = nil
        updated.quietHoursEnd = nil
        try await updatePreferences(updated)
    }

    // MARK: - Check Notification Eligibility

    /// Check if a notification should be sent based on current preferences
    /// - Parameters:
    ///   - type: The notification type
    ///   - senderId: Optional sender ID for receiver notifications
    /// - Returns: Whether the notification should be sent
    func shouldSendNotification(type: NotificationType, senderId: UUID? = nil) -> Bool {
        return preferences.shouldSendNotification(type: type, senderId: senderId)
    }

    // MARK: - Reset to Defaults

    /// Reset all notification preferences to defaults
    func resetToDefaults() async throws {
        try await updatePreferences(.defaults)
        Logger.info("Notification preferences reset to defaults")
    }
}

// MARK: - Helper Types

private struct PreferencesResponse: Codable {
    let notificationPreferences: NotificationPreferences?

    enum CodingKeys: String, CodingKey {
        case notificationPreferences = "notification_preferences"
    }
}

// MARK: - Errors

enum NotificationPreferencesError: LocalizedError {
    case notAuthenticated
    case fetchFailed(String)
    case updateFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to manage notification preferences."
        case .fetchFailed(let message):
            return "Failed to load notification preferences: \(message)"
        case .updateFailed(let message):
            return "Failed to update notification preferences: \(message)"
        }
    }
}
