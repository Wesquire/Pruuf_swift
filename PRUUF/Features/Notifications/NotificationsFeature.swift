import SwiftUI

// MARK: - Notifications Feature

/// Notifications feature namespace
/// Contains all in-app notification related views and components
enum NotificationsFeature {
    // Views implemented:
    // - NotificationCenterView (Phase 8.4) - In-app notification center
    //   - List of notifications from last 30 days
    //   - Grouped by date (Today, Yesterday, etc.)
    //   - Mark as read (individual and all)
    //   - Delete notifications (swipe or bulk)
    //   - Tap to navigate to relevant screen
    //
    // - NotificationBellButton (Phase 8.4) - Bell icon with badge
    //   - Shows unread count badge
    //   - Tap to open NotificationCenterView
    //   - Used in dashboard headers
    //
    // Services:
    // - InAppNotificationStore (Core/Services) - Manages notification data
    //   - Fetches last 30 days of notifications
    //   - Mark as read/delete functionality
    //   - Navigation destination mapping
}
