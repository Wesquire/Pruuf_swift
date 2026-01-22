# Section 8.1 Push Notification Setup - Test & Audit Log

## Itemized Todo List
1. Verify push notifications capability and entitlements are present.
2. Verify registration for remote notifications on app launch.
3. Verify permission request during onboarding.
4. Verify device token storage via Supabase (device_tokens + legacy users.device_token).
5. Verify APNs send pipeline and invalid token handling.
6. Verify token refresh handling and invalid token cleanup strategy.
7. Defer build/test validation until Phase 8 completion.

## Evidence Review
- Push capability + entitlements
  - `Pruuf_Swift/PRUUF/Resources/PRUUF.entitlements`
- App launch registration + UNUserNotificationCenter delegate
  - `Pruuf_Swift/PRUUF/App/AppDelegate.swift`
- Permission request during onboarding
  - `Pruuf_Swift/PRUUF/Features/Onboarding/SenderOnboardingViews.swift`
  - `Pruuf_Swift/PRUUF/Features/Onboarding/ReceiverOnboardingViews.swift`
- Device token storage (Supabase)
  - `Pruuf_Swift/PRUUF/Core/Services/NotificationService.swift`
  - `Pruuf_Swift/supabase/migrations/20260119000006_device_tokens.sql`
- APNs HTTP/2 send + invalid token cleanup
  - `Pruuf_Swift/supabase/functions/send-apns-notification/index.ts`

## Gaps Found & Resolutions
- Device token schema + RPCs existed only in backups; added migration to align repo schema with runtime usage.

## Build Validation
- Deferred until Phase 8 completion.

## Notes
- Token invalidation via APNs error reasons triggers `invalidate_device_token` to deactivate tokens.
