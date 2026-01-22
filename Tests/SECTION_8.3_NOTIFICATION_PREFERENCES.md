# Section 8.3: Notification Preferences

## Scope
Verify notification preference controls align with PRD section 8.3 (master toggle, sender/receiver preferences, per-sender muting, quiet hours plan).

## Evidence Checklist
- Master toggle to enable/disable all notifications and persist to user preferences.
- Sender preferences: ping reminders, 15-minute warning, deadline warning.
- Receiver preferences: ping completed, missed ping alerts, connection requests.
- Per-sender muting for receivers.
- Quiet hours planned/coming soon.
- Master toggle disables local ping notifications and re-enables scheduling for pending pings when turned on.

## Verification
- `Pruuf_Swift/PRUUF/Features/Settings/NotificationSettingsView.swift`: master toggle, sender/receiver sections, per-sender muting entry, quiet hours labeled as coming soon.
- `Pruuf_Swift/PRUUF/Core/Models/User.swift`: `NotificationPreferences` stores master toggle + sender/receiver settings + muted sender IDs + quiet hours fields.
- `Pruuf_Swift/PRUUF/Core/Services/NotificationPreferencesService.swift`: CRUD for notification preferences + mute/unmute helpers.
- `Pruuf_Swift/PRUUF/Features/Settings/NotificationSettingsView.swift`: master toggle cancels local notifications when disabled and reschedules pending ping notifications when enabled.
- `Pruuf_Swift/supabase/functions/send-ping-notification/index.ts`: server-side filtering for master toggle, per-sender muting, and receiver preference types.

## Gaps Found
None.

## Files Modified
- `Pruuf_Swift/PRUUF/Features/Settings/NotificationSettingsView.swift`

## Files Created
- `Pruuf_Swift/tests/SECTION_8.3_NOTIFICATION_PREFERENCES.md`
