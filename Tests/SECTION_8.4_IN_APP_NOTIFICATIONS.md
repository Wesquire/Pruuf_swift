# Section 8.4: In-App Notifications

## Scope
Verify in-app notification center functionality: bell badge, recent list, 30-day window, read/delete actions, and navigation from taps.

## Evidence Checklist
- Bell icon with badge count in dashboard headers.
- Notification center sheet with list of notifications.
- Fetch only last 30 days.
- Mark as read individually and all at once.
- Delete single or multiple notifications.
- Navigate to relevant screen on tap.

## Verification
- `Pruuf_Swift/PRUUF/Features/Notifications/NotificationBellButton.swift`: bell icon and badge count, refresh unread count.
- `Pruuf_Swift/PRUUF/Features/Dashboard/SenderDashboard/SenderDashboardView.swift`: bell in header and sheet presentation.
- `Pruuf_Swift/PRUUF/Features/Dashboard/ReceiverDashboard/ReceiverDashboardView.swift`: bell in header and sheet presentation.
- `Pruuf_Swift/PRUUF/Features/Notifications/NotificationCenterView.swift`: list of notifications, mark read (single/all), delete (single/multi), and tap handling.
- `Pruuf_Swift/PRUUF/Core/Services/InAppNotificationStore.swift`: fetch last 30 days, mark read, delete, and navigation destination dispatch.
- `Pruuf_Swift/PRUUF/Features/Dashboard/DashboardFeature.swift`: handles navigation destination after tap.

## Gaps Found
None.

## Files Modified
- `Pruuf_Swift/PRUUF/Features/Dashboard/DashboardFeature.swift`

## Files Created
- `Pruuf_Swift/tests/SECTION_8.4_IN_APP_NOTIFICATIONS.md`
