# Section 8.2 Notification Types and Content - Test & Audit Log

## Itemized Todo List
1. Verify sender ping reminder title/body, badge, and deeplink.
2. Verify receiver missed ping alert title/body, category, and deeplink.
3. Verify receiver ping completed title/body and deeplink.
4. Verify connection request notification title/body and deeplink.
5. Verify trial ending notification title/body and deeplink.
6. Confirm default sound payload behavior.
7. Document gaps and resolve content mismatches.

## Evidence Review
- Notification content builder (server-side)
  - `Pruuf_Swift/supabase/functions/send-ping-notification/index.ts`
- APNs payload (sound/badge/category/thread)
  - `Pruuf_Swift/supabase/functions/send-apns-notification/index.ts`
- Notification type enums (client-side)
  - `Pruuf_Swift/PRUUF/Core/Models/Notification.swift`

## Findings
- Ping Reminder to Sender
  - Title/body match plan, badge=1, deeplink `pruuf://dashboard`.
- Missed Ping Alert to Receiver
  - Title/body match plan, category `MISSED_PING`, badge=1, deeplink `pruuf://sender/[sender_id]`.
- Ping Completed to Receiver
  - Title/body align with plan, deeplink `pruuf://dashboard`.
- Connection Request to Receiver
  - Title/body align with plan, deeplink `pruuf://connections`.
- Trial Ending to Receiver
  - Updated day-3 body to include subscription prompt.
- Sound
  - APNs payload defaults to `sound: default`.

## Gaps Found & Resolutions
- Trial ending day-3 body was missing the subscription prompt; updated to match plan copy.

## Build Validation
- Deferred until Phase 8 completion.

## Notes
- All required notification types map to APNs categories and deeplinks in edge functions.
