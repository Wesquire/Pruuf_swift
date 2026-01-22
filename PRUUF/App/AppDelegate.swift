import UIKit
import UserNotifications

/// App delegate for handling system-level callbacks
/// Manages push notifications registration and handling
class AppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - Services

    private let userService = UserService()

    // MARK: - Application Lifecycle

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Configure push notifications
        configureNotifications(application)

        // Sync timezone on app launch (Phase 6.1: Support sender travel)
        Task {
            await syncUserTimezoneIfNeeded()
        }

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Sync timezone when app becomes active (Phase 6.1: Support sender travel)
        // This ensures "9 AM local" means 9 AM wherever sender currently is
        Task {
            await syncUserTimezoneIfNeeded()
        }
    }

    /// Sync user's timezone with current device timezone
    /// Phase 6.1: "9 AM local" means 9 AM wherever sender currently is
    private func syncUserTimezoneIfNeeded() async {
        do {
            guard let session = try? await SupabaseConfig.auth.session else {
                return
            }

            try await userService.syncTimezoneIfNeeded(userId: session.user.id)
        } catch {
            // Non-critical - log but don't fail
            print("[AppDelegate] Failed to sync timezone: \(error.localizedDescription)")
        }
    }

    // MARK: - Push Notification Registration

    /// Configure push notification permissions and registration
    private func configureNotifications(_ application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self

        // Configure notification categories for PingNotificationScheduler
        Task { @MainActor in
            PingNotificationScheduler.shared.configureNotificationCategories()
        }

        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if let error = error {
                print("Error requesting notification permissions: \(error.localizedDescription)")
                return
            }

            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
    }

    // MARK: - Remote Notification Registration Callbacks

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Convert token to string format
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("Device Token: \(tokenString)")

        // Store the token for later use with Supabase
        Task {
            await NotificationService.shared.registerDeviceToken(tokenString)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    // MARK: - Background Fetch

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Handle silent push notifications for background updates
        Task {
            await handleBackgroundNotification(userInfo)
            completionHandler(.newData)
        }
    }

    /// Process background notifications
    private func handleBackgroundNotification(_ userInfo: [AnyHashable: Any]) async {
        // Handle different notification types
        guard let type = userInfo["type"] as? String else { return }

        switch type {
        case "ping_reminder", "deadline_warning", "deadline_final":
            // Trigger local reminder for pending ping
            await NotificationService.shared.handlePingReminder(userInfo)
        case "missed_ping", "ping_completed_ontime", "ping_completed_late":
            // Handle ping status notification (for receivers)
            await NotificationService.shared.handleMissedPingAlert(userInfo)
        case "break_started":
            // Handle break started notification (for receivers)
            await NotificationService.shared.handleMissedPingAlert(userInfo)
        case "connection_request":
            // Refresh connections data for the current user
            if let session = try? await SupabaseConfig.auth.session {
                // Default to receiver role for connection request notifications
                await ConnectionService.shared.refreshConnections(userId: session.user.id, role: .receiver)
            }
        default:
            break
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let preferences = NotificationPreferencesService.shared.preferences

        if preferences.vibrationEnabled {
            Haptics.selection()
        }

        if preferences.soundEnabled {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.banner, .badge])
        }
    }

    /// Handle user interaction with notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // Handle notification tap
        Task {
            await handleNotificationTap(userInfo, actionIdentifier: response.actionIdentifier)
            completionHandler()
        }
    }

    /// Process notification tap actions
    private func handleNotificationTap(_ userInfo: [AnyHashable: Any], actionIdentifier: String) async {
        guard let type = userInfo["type"] as? String else { return }

        // First, check if PingNotificationScheduler should handle this action
        if isNotificationActionForScheduler(actionIdentifier) {
            await PingNotificationScheduler.shared.handleNotificationAction(actionIdentifier, userInfo: userInfo)
            return
        }

        // Handle subscription action
        if isSubscriptionAction(actionIdentifier) {
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .navigateToSubscription,
                    object: nil,
                    userInfo: userInfo
                )
            }
            return
        }

        // Check for deeplink in notification payload
        if let deeplink = userInfo["deeplink"] as? String,
           let deeplinkURL = URL(string: deeplink) {
            await handleDeeplink(deeplinkURL, userInfo: userInfo)
            return
        }

        // Handle default tap actions based on notification type
        switch (type, actionIdentifier) {
        case ("ping_reminder", UNNotificationDefaultActionIdentifier),
             ("deadline_warning", UNNotificationDefaultActionIdentifier),
             ("deadline_final", UNNotificationDefaultActionIdentifier):
            // Navigate to ping confirmation screen for sender reminders
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .navigateToPingConfirmation,
                    object: nil,
                    userInfo: userInfo
                )
            }
        case ("missed_ping", UNNotificationDefaultActionIdentifier),
             ("ping_missed", UNNotificationDefaultActionIdentifier),
             ("ping_completed_ontime", UNNotificationDefaultActionIdentifier),
             ("ping_completed_late", UNNotificationDefaultActionIdentifier),
             ("ping_completed", UNNotificationDefaultActionIdentifier),
             ("break_started", UNNotificationDefaultActionIdentifier):
            // Navigate to connection details for receiver notifications
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .navigateToConnectionDetails,
                    object: nil,
                    userInfo: userInfo
                )
            }
        case ("connection_request", UNNotificationDefaultActionIdentifier),
             ("connection_new", UNNotificationDefaultActionIdentifier):
            // Navigate to connection requests
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .navigateToConnectionRequests,
                    object: nil,
                    userInfo: userInfo
                )
            }
        case ("trial_ending", UNNotificationDefaultActionIdentifier):
            // Navigate to subscription page
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .navigateToSubscription,
                    object: nil,
                    userInfo: userInfo
                )
            }
        default:
            break
        }
    }

    /// Handle deeplink navigation from notification
    private func handleDeeplink(_ url: URL, userInfo: [AnyHashable: Any]) async {
        guard url.scheme == "pruuf" else { return }

        await MainActor.run {
            switch url.host {
            case "dashboard":
                NotificationCenter.default.post(name: .navigateToDashboard, object: nil, userInfo: userInfo)
            case "sender":
                // Extract sender ID from path: pruuf://sender/[sender_id]
                NotificationCenter.default.post(name: .navigateToConnectionDetails, object: nil, userInfo: userInfo)
            case "connections":
                NotificationCenter.default.post(name: .navigateToConnectionRequests, object: nil, userInfo: userInfo)
            case "subscription":
                NotificationCenter.default.post(name: .navigateToSubscription, object: nil, userInfo: userInfo)
            default:
                // Default to dashboard for unknown deeplinks
                NotificationCenter.default.post(name: .navigateToDashboard, object: nil, userInfo: userInfo)
            }
        }
    }

    /// Check if the action identifier should be handled by PingNotificationScheduler
    private func isNotificationActionForScheduler(_ actionIdentifier: String) -> Bool {
        let schedulerActions = [
            "CONFIRM_PING",
            "URGENT_CONFIRM_PING",
            "FINAL_CONFIRM_PING",
            "SNOOZE_PING",
            "VIEW_DETAILS"
        ]
        return schedulerActions.contains(actionIdentifier)
    }

    /// Check if the action identifier should navigate to subscription
    private func isSubscriptionAction(_ actionIdentifier: String) -> Bool {
        return actionIdentifier == "SUBSCRIBE_NOW"
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let navigateToPingConfirmation = Notification.Name("navigateToPingConfirmation")
    static let navigateToConnectionDetails = Notification.Name("navigateToConnectionDetails")
    static let navigateToConnectionRequests = Notification.Name("navigateToConnectionRequests")
    static let navigateToSubscription = Notification.Name("navigateToSubscription")
    static let navigateToDashboard = Notification.Name("navigateToDashboard")
}
