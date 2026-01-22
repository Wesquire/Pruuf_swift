# PRUUF Edge Cases & Edge Functions Documentation

## Document Purpose
This document catalogs all identified edge cases, their handling logic, and required edge functions for the PRUUF application. Each edge case is marked with a priority level to guide MVP development.

## Priority Levels

**🔴 MVP CRITICAL** - Must be implemented for launch. Core functionality depends on it.
**🟡 PHASE 2** - Important but can be deferred. Should be implemented within 3-6 months post-launch.
**🟢 FUTURE** - Nice to have. Can be implemented based on user feedback and business needs.

---

## CATEGORY 1: Unique Code System

### Edge Cases

#### EC-1.1: Code Collision 🔴 MVP CRITICAL
- **Scenario:** Two users randomly generate the same 6-digit code
- **Probability:** 1 in 1,000,000 per generation
- **Handling:** Validate uniqueness before assigning, regenerate if collision detected
- **Edge Function:** `validate_unique_code()`
- **Why Critical:** Code system must work reliably or connections fail

#### EC-1.2: Code Regeneration Impact 🔴 MVP CRITICAL
- **Scenario:** Sender regenerates their code; existing connections remain
- **Handling:** Connections store user_id (not code), so existing connections unaffected. Old code becomes invalid for new connections only.
- **Edge Function:** `regenerate_code()`
- **Why Critical:** Users need ability to regenerate codes for privacy/security

#### EC-1.3: Brute Force Attack 🔴 MVP CRITICAL
- **Scenario:** Malicious user tries guessing codes repeatedly (1000+ attempts)
- **Handling:** Rate limit to 10 code validation attempts per hour per IP/device
- **Edge Function:** `rate_limit_code_attempts()`
- **Why Critical:** Security vulnerability if not implemented

#### EC-1.4: Invalid Code Attempts 🔴 MVP CRITICAL
- **Scenario:** User repeatedly enters wrong codes (typos, old codes)
- **Handling:** Show clear error messages, log attempts for security audit
- **Edge Function:** `log_code_attempts()`
- **Why Critical:** User experience requires clear error handling

#### EC-1.5: Code Shared Publicly 🟡 PHASE 2
- **Scenario:** User posts their code on social media, gets spammed with unwanted connections
- **Handling:** Easy "Regenerate Code" button in settings, can delete unwanted connections
- **Edge Function:** `regenerate_code()` (same as EC-1.2)
- **Why Phase 2:** Edge case that can be handled with existing delete + regenerate features

---

## CATEGORY 2: Account & User Management

### Edge Cases

#### EC-2.1: Account Deletion - Orphaned Receivers 🔴 MVP CRITICAL
- **Scenario:** Sender deletes account; receivers monitoring them are left orphaned
- **Handling:**
  - Notify all receivers: "John has deleted their account"
  - Remove from receiver's monitoring list
  - Mark historical data as "deleted user"
- **Edge Function:** `delete_account()`
- **Why Critical:** GDPR compliance and data cleanup required

#### EC-2.2: Account Deletion - Orphaned Senders 🔴 MVP CRITICAL
- **Scenario:** Receiver deletes account; senders don't know they're no longer monitored
- **Handling:**
  - Notify all senders: "Sarah is no longer monitoring you"
  - Remove from sender's receiver list
- **Edge Function:** `delete_account()`
- **Why Critical:** GDPR compliance and data cleanup required

#### EC-2.3: Account Deletion - Payment Status 🔴 MVP CRITICAL
- **Scenario:** Paying user deletes account mid-billing cycle
- **Handling:**
  - Cancel subscription immediately
  - No refund (prorated service received)
  - 30-day soft delete grace period before hard delete
- **Edge Function:** `delete_account()`, `handle_payment_cancellation()`
- **Why Critical:** Payment integrity and Apple subscription compliance

#### EC-2.4: Account Deletion - Pending Notifications 🔴 MVP CRITICAL
- **Scenario:** User deletes account while notifications are queued
- **Handling:** Cancel all queued notifications immediately
- **Edge Function:** `delete_account()`, `cancel_pending_notifications()`
- **Why Critical:** Prevents notifications to/from deleted accounts

#### EC-2.5: Phone Number Change 🟢 FUTURE
- **Scenario:** User changes phone number, needs to keep account
- **Handling:**
  - Verify new phone number via SMS
  - Update all connections (user_id remains same)
  - Migrate device tokens
- **Edge Function:** `change_phone_number()`
- **Why Future:** Rare edge case. Users can create new account and reconnect if needed.

#### EC-2.6: Lost Device / Account Recovery 🔴 MVP CRITICAL
- **Scenario:** User loses phone but still has phone number
- **Handling:**
  - Re-verify phone number on new device
  - Restore account data
  - Update device token
- **Edge Function:** `account_recovery()` (simplified - handled by phone auth)
- **Why Critical:** Users must be able to access their account on new device

#### EC-2.7: Duplicate Accounts 🟢 FUTURE
- **Scenario:** User creates multiple accounts with different phone numbers
- **Handling:**
  - Detection via device fingerprinting (optional)
  - No prevention (legitimate use case: family sharing device)
  - Flag for abuse monitoring
- **Edge Function:** `detect_duplicate_accounts()`
- **Why Future:** Not critical for MVP. Can handle manually if abuse occurs.

#### EC-2.8: Account Suspension 🟢 FUTURE
- **Scenario:** User flagged for abuse/spam, account suspended
- **Handling:**
  - Disable all functionality
  - Notify connected users
  - Admin review process
- **Edge Function:** `suspend_account()`
- **Why Future:** Can handle rare abuse cases manually for MVP

---

## CATEGORY 3: Payment & Subscription

### Edge Cases

#### EC-3.1: Sender-First Then Deletes All Connections 🔴 MVP CRITICAL
- **Scenario:** User was sender (free), deletes all sender connections, now receiver-only
- **Handling:**
  - User remains free even if no active sender connections
  - Database flag: `was_sender_ever = true` (never changes)
- **Edge Function:** `recalculate_payment_status()`, `apply_free_status()`
- **Why Critical:** Core business logic for "sender = free forever"

#### EC-3.2: Paying Receiver Becomes Sender 🔴 MVP CRITICAL
- **Scenario:** User paying $2.99/month as receiver, then becomes a sender
- **Handling:**
  - Auto-cancel subscription immediately
  - Apply "free forever" status
  - No refund for current month
  - Notification: "You'll never be charged again!"
- **Edge Function:** `recalculate_payment_status()`, `apply_free_status()`
- **Why Critical:** Core business logic that affects revenue

#### EC-3.3: User Manipulates Sender Status 🟡 PHASE 2
- **Scenario:** User creates fake sender connection to avoid payment
- **Handling:**
  - Requires real connection from another user
  - Monitor for patterns: create sender, delete, repeat
  - Audit free status periodically
- **Edge Function:** `audit_free_status()`
- **Why Phase 2:** Fraud prevention important but can monitor manually initially

#### EC-3.4: Payment Failure Mid-Subscription 🔴 MVP CRITICAL
- **Scenario:** Credit card declined, payment fails
- **Handling:**
  - Day 1: Automatic retry
  - Day 3: Notification to user "payment issue"
  - Day 7: Disable receiver notifications (soft cutoff)
  - Keep data intact for 30 days
  - Can resubscribe anytime to restore
- **Edge Function:** `handle_payment_failure()`
- **Why Critical:** Standard payment flow must handle failures gracefully

#### EC-3.5: App Store Subscription Mismatch 🔴 MVP CRITICAL
- **Scenario:** User cancels in App Store but app thinks subscription active
- **Handling:**
  - Webhook listener for App Store Server Notifications
  - Real-time sync of subscription status
  - Handle: started, renewed, canceled, refunded, billing issue
- **Edge Function:** `sync_appstore_subscription()`
- **Why Critical:** Payment integrity depends on App Store sync

#### EC-3.6: At Sender Limit Without Subscription 🔴 MVP CRITICAL
- **Scenario:** Free user (sender) tries to add 11th sender to monitor
- **Handling:**
  - Block connection creation
  - Prompt: "Subscribe to monitor more than 10 people"
  - Show pricing and trial info
- **Edge Function:** `enforce_sender_limit()`
- **Why Critical:** Core business logic for 10-sender limit

#### EC-3.7: Trial Ends While App Closed 🔴 MVP CRITICAL
- **Scenario:** 15-day trial expires, user hasn't opened app in a week
- **Handling:**
  - Backend marks trial as expired
  - Notifications stop immediately
  - Next app open: prompt to subscribe
  - Show how many days they missed
- **Edge Function:** `handle_trial_expiration()`
- **Why Critical:** Trial flow must work correctly for revenue

#### EC-3.8: Active Subscription, App Deleted 🟡 PHASE 2
- **Scenario:** User deletes app but subscription continues in App Store
- **Handling:**
  - Subscription continues charging (out of our control)
  - User must cancel in App Store settings
  - If reinstall: subscription automatically recognized
- **Edge Function:** None (App Store handles)
- **Why Phase 2:** Documentation/support issue, not technical requirement

#### EC-3.9: Subscription Refund Request 🟡 PHASE 2
- **Scenario:** User requests refund through App Store
- **Handling:**
  - App Store processes refund
  - Webhook notifies our backend
  - Immediately revoke subscription access
  - Mark account appropriately
- **Edge Function:** `sync_appstore_subscription()`
- **Why Phase 2:** Handled by existing webhook infrastructure

---

## CATEGORY 4: Ping Timing & Timezone

### Edge Cases

#### EC-4.1: User Changes Ping Time Mid-Day (Already Pinged) 🔴 MVP CRITICAL
- **Scenario:** User pinged at 9 AM, then changes ping time to 10 AM same day
- **Handling:**
  - New time applies tomorrow
  - Today's ping already counts
  - Show: "New ping time will take effect tomorrow"
- **Edge Function:** `handle_ping_time_change()`
- **Why Critical:** Common user action that must work correctly

#### EC-4.2: User Changes Ping Time Mid-Day (Not Yet Pinged, Early New Time) 🔴 MVP CRITICAL
- **Scenario:** User hasn't pinged yet (deadline 9 AM), changes time to 8 AM (now "late")
- **Handling:**
  - New time applies tomorrow
  - Today still expects 9 AM ping
  - Prevents users from avoiding "late" status
- **Edge Function:** `handle_ping_time_change()`
- **Why Critical:** Prevents gaming the system

#### EC-4.3: User Changes Ping Time Mid-Day (Not Yet Pinged, Later New Time) 🔴 MVP CRITICAL
- **Scenario:** User hasn't pinged yet (deadline 9 AM), changes time to 2 PM
- **Handling:**
  - New time applies tomorrow
  - Today still expects 9 AM ping
  - Consistent with above rule
- **Edge Function:** `handle_ping_time_change()`
- **Why Critical:** Consistent behavior required

#### EC-4.4: User Changes Ping Time After Missing Deadline 🟡 PHASE 2
- **Scenario:** 10 AM, user missed 9 AM deadline, changes time to 11 AM
- **Handling:**
  - Notifications already sent (can't undo)
  - New time applies tomorrow
  - User can still ping today (counts as late)
- **Edge Function:** `handle_ping_time_change()`
- **Why Phase 2:** Edge case within edge case. Existing logic handles it.

#### EC-4.5: User Travels Across Timezones 🔴 MVP CRITICAL
- **Scenario:** Ping time 9 AM Pacific, user flies to New York (3-hour difference)
- **Handling:**
  - Ping time = "9 AM local" (adjusts with travel)
  - When timezone detected as changed, ping time stays 9 AM in new timezone
  - Store: ping_time = "09:00" + current_timezone
  - User pings at 9 AM Eastern (12 PM Pacific)
- **Edge Function:** `handle_timezone_change()`
- **Why Critical:** Users travel. This must work correctly.

#### EC-4.6: User Pings Mid-Flight 🟡 PHASE 2
- **Scenario:** User pings while in airplane mode or mid-flight across timezones
- **Handling:**
  - If online: Ping sent with current detected timezone
  - If offline: Queued locally, sent when online
  - Server uses ping timestamp to determine which "day" it counts for
- **Edge Function:** `queue_offline_pings()`, `determine_ping_day()`
- **Why Phase 2:** Rare scenario. Offline queue (MVP) handles it.

#### EC-4.7: Daylight Saving Time - Spring Forward 🟡 PHASE 2
- **Scenario:** Ping time set to 2:30 AM, DST makes 2 AM → 3 AM (2:30 doesn't exist)
- **Handling:**
  - Detect non-existent hour
  - Automatically adjust to 3:30 AM for that day only
  - Log DST transition
  - Next day returns to 2:30 AM
- **Edge Function:** `handle_dst_transition()`
- **Why Phase 2:** Affects users twice per year. Can handle manually for MVP.

#### EC-4.8: Daylight Saving Time - Fall Back 🟡 PHASE 2
- **Scenario:** Ping time set to 1:30 AM, DST makes 1 AM happen twice
- **Handling:**
  - Use first occurrence of 1:30 AM
  - Prevent duplicate notifications
  - Server time (UTC) is source of truth
- **Edge Function:** `handle_dst_transition()`
- **Why Phase 2:** Rare edge case. Server UTC time handles most issues.

#### EC-4.9: Ping Scheduled During DST Transition 🟡 PHASE 2
- **Scenario:** User scheduled break or ping exactly during DST transition hour
- **Handling:**
  - Convert all times to UTC for storage
  - Display in user's current timezone
  - Edge function handles conversion properly
- **Edge Function:** `handle_dst_transition()`
- **Why Phase 2:** Part of broader DST handling

#### EC-4.10: Ping Exactly at Midnight 🔴 MVP CRITICAL
- **Scenario:** Ping time set to 12:00 AM (midnight)
- **Handling:**
  - 12:00:00 AM = start of new day
  - Counts for the new day (not previous day)
  - User can ping from 12:00:00 AM onwards
  - Previous day's window closed at 11:59:59 PM
- **Edge Function:** `determine_ping_day()`
- **Why Critical:** Day boundary logic must be correct

#### EC-4.11: Multiple Pings in One Day (Accidental) 🔴 MVP CRITICAL
- **Scenario:** User taps "Send Ping" twice within 5 seconds (double-tap bug)
- **Handling:**
  - Detect duplicate pings within 5-second window
  - Only count first ping
  - Don't send duplicate notifications
  - Idempotency key prevents duplicate database records
- **Edge Function:** `deduplicate_pings()`
- **Why Critical:** Must prevent duplicate notifications

#### EC-4.12: Multiple Pings in One Day (Intentional) 🔴 MVP CRITICAL
- **Scenario:** User pings at 9 AM, button re-enables at 2 PM due to bug
- **Handling:**
  - Button should stay disabled until midnight
  - Backend validation: reject duplicate pings for same day
  - Show error: "You already pinged today at 9:04 AM"
- **Edge Function:** `validate_ping_attempt()`
- **Why Critical:** Prevents duplicate pings from UI bugs

#### EC-4.13: Device Clock Skew 🟡 PHASE 2
- **Scenario:** User's device clock is wrong (set to wrong date/time)
- **Handling:**
  - Server time (UTC) is source of truth
  - Ignore device timestamp for critical logic
  - If device time severely off (>1 hour), warn user
  - Use server-generated timestamps for all records
- **Edge Function:** `sync_clock_skew()`
- **Why Phase 2:** Server time is already source of truth. Warning is nice-to-have.

---

## CATEGORY 5: Scheduled Breaks

### Edge Cases

#### EC-5.1: Pause vs. Scheduled Break 🔴 MVP CRITICAL
- **Scenario:** User wants to pause indefinitely vs. specific date range
- **Handling:**
  - Same system, different UI
  - Scheduled break: start_date + end_date
  - Indefinite pause: start_date + null end_date
  - Both stored in Breaks table
  - UI shows "On break until June 7" vs "Paused (Resume anytime)"
- **Edge Function:** `validate_break_schedule()`, `handle_sender_pause()`
- **Why Critical:** Users need to take breaks without disconnecting

#### EC-5.2: User Pings During Scheduled Break 🔴 MVP CRITICAL
- **Scenario:** User on vacation June 1-7, pings anyway on June 3
- **Handling:**
  - Allow ping (optional, sender's choice)
  - Button shows "Send optional ping"
  - If pinged: Receivers see "🏖️ On break (pinged at 9:04 AM)"
  - If not pinged: No missed notifications sent
  - Create ping record with `pinged_during_break = true` flag
- **Edge Function:** `handle_ping_during_break()`
- **Why Critical:** Flexibility improves user experience

#### EC-5.3: Overlapping Break Schedules 🟡 PHASE 2
- **Scenario:** Break 1: June 1-10, Break 2: June 5-15
- **Handling:**
  - Validate on creation, show warning
  - Auto-merge into single break: June 1-15
  - Or block creation and ask user to edit existing break
- **Edge Function:** `validate_break_schedule()`
- **Why Phase 2:** Rare scenario. Can show error and let user fix manually.

#### EC-5.4: Receiver Marks In-Person During Sender's Break 🔴 MVP CRITICAL
- **Scenario:** Sender on break, receiver marks "checked in person"
- **Handling:**
  - Allow both states: "On break + verified in person"
  - Show: "🏖️ On break (verified in person at 10:15 AM)"
  - No conflict - both are valid
- **Edge Function:** `create_inperson_verification()`
- **Why Critical:** Both features must work together

#### EC-5.5: User Deletes Break Mid-Break 🔴 MVP CRITICAL
- **Scenario:** User scheduled break June 1-10, on June 5 deletes the break
- **Handling:**
  - Resume normal ping expectations starting next day (June 6)
  - Today (June 5): No ping expected (already in progress)
  - Notify receivers: "John's break has ended"
- **Edge Function:** `delete_break()`, `resume_from_break()`
- **Why Critical:** Users need ability to end breaks early

#### EC-5.6: Break Scheduled in Past 🟡 PHASE 2
- **Scenario:** User tries to schedule break for last week
- **Handling:**
  - Block creation: "Break must start today or in the future"
  - Or allow (for data correction purposes)
- **Edge Function:** `validate_break_schedule()`
- **Why Phase 2:** Simple validation. Low impact if missing.

#### EC-5.7: User Changes Ping Time While on Break 🟡 PHASE 2
- **Scenario:** On break June 1-7, changes ping time from 9 AM to 10 AM
- **Handling:**
  - Allow change
  - New time takes effect after break ends (June 8)
  - Store change immediately in database
- **Edge Function:** `handle_ping_time_change()`
- **Why Phase 2:** Edge case within edge case. Existing logic handles it.

#### EC-5.8: Break Ends at Midnight 🔴 MVP CRITICAL
- **Scenario:** Break scheduled June 1-7, does June 7 include the full day?
- **Handling:**
  - Inclusive: June 7 is last day of break
  - June 8 at 9 AM: First ping expected after break
  - Clear communication in UI: "On break until June 7"
- **Edge Function:** `check_active_breaks()`
- **Why Critical:** Day boundary logic must be clear

#### EC-5.9: Break Starts at Midnight 🟡 PHASE 2
- **Scenario:** Break starts June 1, user hasn't pinged yet on June 1
- **Handling:**
  - If break scheduled in advance: No ping expected June 1
  - If break scheduled during June 1: Depends on timing
- **Edge Function:** `check_active_breaks()`
- **Why Phase 2:** Edge case. Can document expected behavior.

#### EC-5.10: Indefinite Pause Never Resumed 🟡 PHASE 2
- **Scenario:** User pauses indefinitely, never resumes, months pass
- **Handling:**
  - Pause remains active indefinitely
  - Receivers see "Paused since June 1"
  - Receivers may choose to delete connection
  - No automatic expiration
- **Edge Function:** None (intended behavior)
- **Why Phase 2:** Intended behavior. No special handling needed.

---

## CATEGORY 6: Connection Management

### Edge Cases

#### EC-6.1: Simultaneous Mutual Connection 🔴 MVP CRITICAL
- **Scenario:** User A enters User B's code, User B enters User A's code at same time
- **Handling:**
  - Result: Two separate connections (A→B and B→A)
  - Both monitor each other (bidirectional monitoring)
  - This is valid use case (roommates, couples, etc.)
  - No special handling needed
- **Edge Function:** `create_connection()`
- **Why Critical:** Must support bidirectional monitoring

#### EC-6.2: Receiver Deletes Connection, Sender Unaware 🔴 MVP CRITICAL
- **Scenario:** Receiver stops monitoring sender, sender doesn't know
- **Handling:**
  - Notify sender: "Sarah is no longer monitoring you"
  - Remove from sender's "Who's Monitoring You" list
  - Sender can regenerate code if they want to reconnect
- **Edge Function:** `notify_connection_deleted()`
- **Why Critical:** Both parties need to know connection status

#### EC-6.3: Sender Deletes Receiver 🔴 MVP CRITICAL
- **Scenario:** Sender wants to remove specific receiver from their list
- **Handling:**
  - Allow deletion
  - Notify receiver: "John removed you from their contacts"
  - Delete connection record
  - Receiver can no longer see sender's status
- **Edge Function:** `delete_connection()`
- **Why Critical:** Senders need control over who monitors them

#### EC-6.4: Connection in Pending State 🔴 MVP CRITICAL
- **Scenario:** Code entered, API call in progress, app crashes
- **Handling:**
  - Use idempotency key
  - If retry, check if connection already exists
  - Don't create duplicate
  - Return existing connection if already created
- **Edge Function:** `create_connection()`
- **Why Critical:** Must handle network/app failures gracefully

#### EC-6.5: User Blocks Another User 🟢 FUTURE
- **Scenario:** Sender blocks specific receiver (harassment case)
- **Handling:**
  - Store in blocked_connections table
  - Delete existing connection
  - Prevent reconnection (code validation fails for blocked user)
  - Show: "Unable to connect with this user"
- **Edge Function:** `handle_blocked_users()`
- **Why Future:** Can use delete connection for MVP. True blocking is enhancement.

#### EC-6.6: User Unblocks Another User 🟢 FUTURE
- **Scenario:** Sender unblocks receiver, wants to reconnect
- **Handling:**
  - Remove from blocked_connections table
  - Allow new connection creation
  - Doesn't automatically recreate old connection
- **Edge Function:** `handle_blocked_users()`
- **Why Future:** Part of blocking feature (Future)

#### EC-6.7: Self-Connection Attempt 🔴 MVP CRITICAL
- **Scenario:** User enters their own code
- **Handling:**
  - Validate: sender_id ≠ receiver_id
  - Show error: "You cannot monitor yourself"
  - Block connection creation
- **Edge Function:** `validate_connection_target()`
- **Why Critical:** Basic validation to prevent invalid state

#### EC-6.8: Duplicate Connection Attempt 🔴 MVP CRITICAL
- **Scenario:** User A already monitors User B, tries to enter B's code again
- **Handling:**
  - Check if connection exists
  - Show: "You're already monitoring John"
  - Don't create duplicate
  - Optionally: Navigate to existing connection details
- **Edge Function:** `validate_connection_target()`
- **Why Critical:** Prevents duplicate connections and confusion

#### EC-6.9: Connection Without Ping Time Set 🔴 MVP CRITICAL
- **Scenario:** Receiver adds sender, but sender hasn't set their ping time yet
- **Handling:**
  - Allow connection creation
  - Receiver sees: "Waiting for John to set ping time"
  - No missed ping notifications sent (no expectation set)
  - Prompt sender to set ping time during onboarding
- **Edge Function:** `validate_sender_setup()`
- **Why Critical:** Onboarding flow must handle this gracefully

#### EC-6.10: Name or Photo Change Propagation 🟡 PHASE 2
- **Scenario:** Sender changes name from "John" to "Jonathan"
- **Handling:**
  - Update user profile immediately
  - Push change to all connected users (real-time sync)
  - Receivers see updated name immediately
  - No notification needed (silent update)
- **Edge Function:** `propagate_profile_changes()`
- **Why Phase 2:** Nice to have for real-time sync. Can refresh on app launch for MVP.

#### EC-6.11: Custom Nickname Conflict 🟡 PHASE 2
- **Scenario:** Receiver monitors two people named "John", sets nicknames
- **Handling:**
  - Allow duplicate nicknames (receiver's choice)
  - Store per connection: receiver_id + sender_id + custom_nickname
  - Display nickname in receiver's view only
  - Sender never sees their nickname
- **Edge Function:** None (stored in connections table)
- **Why Phase 2:** Feature works without special edge case handling

#### EC-6.12: Connection Spam 🔴 MVP CRITICAL
- **Scenario:** User sends 1000 connection requests in 1 hour
- **Handling:**
  - Rate limit: Max 20 code validation attempts per hour
  - After limit: "Too many attempts, try again later"
  - Prevent denial-of-service attacks
  - Log for abuse monitoring
- **Edge Function:** `rate_limit_connections()`
- **Why Critical:** Security requirement to prevent abuse

---

## CATEGORY 7: Notifications

### Edge Cases

#### EC-7.1: Device Token Expired 🔴 MVP CRITICAL
- **Scenario:** APNs device token expires or becomes invalid
- **Handling:**
  - Retry sending notification
  - If fails: Update device token status as inactive
  - On next app launch: Refresh token
  - In-app notifications as fallback
- **Edge Function:** `handle_notification_failure()`, `update_device_token()`
- **Why Critical:** Notification delivery is core functionality

#### EC-7.2: App Uninstalled 🟡 PHASE 2
- **Scenario:** User uninstalls app, but connections still active
- **Handling:**
  - APNs returns "unregistered" status
  - Mark device as inactive
  - Notifications queued but undeliverable
  - If user reinstalls: New device token, resume notifications
- **Edge Function:** `handle_notification_failure()`
- **Why Phase 2:** Handled by existing notification failure logic

#### EC-7.3: Notification Permission Denied 🔴 MVP CRITICAL
- **Scenario:** User denies notification permissions in iOS settings
- **Handling:**
  - Detect on app launch
  - Show in-app banner: "Enable notifications to receive pings"
  - Provide deep link to Settings
  - In-app notifications as fallback
  - Re-prompt strategically (after connection created)
- **Edge Function:** `check_notification_permissions()`
- **Why Critical:** App is useless without notifications

#### EC-7.4: Notification Delivery Failure 🔴 MVP CRITICAL
- **Scenario:** APNs service down, network issue
- **Handling:**
  - Retry logic: 3 attempts with exponential backoff
  - Queue failed notifications for later retry
  - Log failures for monitoring
  - Alert engineers if failure rate exceeds threshold
- **Edge Function:** `handle_notification_failure()`, `queue_notifications()`
- **Why Critical:** Must handle APNs service disruptions

#### EC-7.5: Notification Flood 🟡 PHASE 2
- **Scenario:** User monitors 10 senders, all miss check-ins (20 notifications in 15 min)
- **Handling:**
  - Allow all notifications (each is important)
  - iOS groups by app automatically
  - Consider: Summary notification option in future
  - Rate limit per sender (not per receiver)
- **Edge Function:** `queue_notifications()`
- **Why Phase 2:** iOS handles grouping. Custom batching is enhancement.

#### EC-7.6: Duplicate Notifications 🔴 MVP CRITICAL
- **Scenario:** Race condition, same notification sent twice
- **Handling:**
  - Check recent notification history before sending
  - Don't send identical notification within 1 minute
  - Use idempotency key for notification records
  - Deduplicate in queue
- **Edge Function:** `deduplicate_notifications()`
- **Why Critical:** Duplicate notifications are bad UX

#### EC-7.7: App Open When Notification Sent 🟡 PHASE 2
- **Scenario:** User has app open, push notification arrives
- **Handling:**
  - iOS shows banner or silent (system handles)
  - Update in-app UI immediately (real-time sync)
  - Don't duplicate alert in-app
  - Mark notification as read if viewing relevant screen
- **Edge Function:** None (iOS handles, app observes)
- **Why Phase 2:** iOS behavior. In-app sync is enhancement.

#### EC-7.8: Notification Text Too Long 🟢 FUTURE
- **Scenario:** User's name is very long, truncated in notification
- **Handling:**
  - iOS notification limit: ~178 characters
  - Truncate long names gracefully: "Jonathan Alexander Maximi... has pinged"
  - Use custom nickname if set by receiver (shorter)
  - Test with maximum length names
- **Edge Function:** `format_notification_content()`
- **Why Future:** iOS handles truncation automatically. Custom formatting is nice-to-have.

#### EC-7.9: Silent/Critical Notifications 🟢 FUTURE
- **Scenario:** Should missed pings override Do Not Disturb?
- **Handling:**
  - Standard notification priority for MVP
  - Respect user's Do Not Disturb settings
  - Can add "Critical Alerts" permission later (requires Apple approval)
- **Edge Function:** None (standard notifications only)
- **Why Future:** Requires special Apple approval. Standard notifications for MVP.

#### EC-7.10: Notification Action Buttons 🔴 MVP CRITICAL
- **Scenario:** Swipe notification, tap "Mark as checked in person"
- **Handling:**
  - iOS notification action registered in app
  - Tapping action triggers edge function
  - Create in-person verification record
  - Update UI if app open
  - No need to open app
- **Edge Function:** `create_inperson_verification()`
- **Why Critical:** Key feature for receivers to quickly verify

#### EC-7.11: Notification Localization 🟢 FUTURE
- **Scenario:** User's device in different language
- **Handling:**
  - Store notification templates in multiple languages
  - Detect user's device language
  - Send notification in appropriate language
- **Edge Function:** `format_notification_content()`
- **Why Future:** English only for MVP

---

## CATEGORY 8: In-Person Verification

### Edge Cases

#### EC-8.1: Multiple Receivers Mark In-Person 🔴 MVP CRITICAL
- **Scenario:** Mom and Dad both monitor sender, both mark "checked in person"
- **Handling:**
  - Allow both, record separately
  - Create verification record for each
  - Show in sender's history: "Verified by Mom at 10:15 AM, by Dad at 10:20 AM"
  - All receivers stop getting notifications
- **Edge Function:** `create_inperson_verification()`
- **Why Critical:** Multiple receivers is common use case

#### EC-8.2: In-Person Before Deadline 🔴 MVP CRITICAL
- **Scenario:** Receiver marks in-person at 8 AM, deadline is 9 AM
- **Handling:**
  - Allow anytime
  - Prevents missed ping notifications from firing at 9 AM
  - Proactive verification
  - Status: "✓ Verified in person at 8:15 AM"
- **Edge Function:** `handle_premature_inperson()`
- **Why Critical:** Common use case (family visits, sleepovers)

#### EC-8.3: Sender Pings After In-Person Verification 🔴 MVP CRITICAL
- **Scenario:** Receiver marks in-person at 8 AM, sender pings at 10 AM
- **Handling:**
  - Both records exist for same day
  - Show both in history
  - Not treated as duplicate/conflict
- **Edge Function:** `create_inperson_verification()`, `send_ping()`
- **Why Critical:** Both features must work together

#### EC-8.4: In-Person Verification at 11:59 PM 🟡 PHASE 2
- **Scenario:** Receiver marks in-person at 11:59 PM sender's local time
- **Handling:**
  - Use sender's timezone to determine "which day"
  - 11:59 PM sender's time = counts for that day
  - Prevents missed notifications retroactively (already sent)
  - Shows in history for that day
- **Edge Function:** `validate_inperson_timing()`
- **Why Phase 2:** Edge case of edge case. Timezone logic handles it.

#### EC-8.5: In-Person Verification Next Day 🟡 PHASE 2
- **Scenario:** Receiver marks in-person the day after sender missed
- **Handling:**
  - Allow marking for current day only
  - Can't retroactively mark yesterday as verified
  - Yesterday remains "missed" in history
- **Edge Function:** `validate_inperson_timing()`
- **Why Phase 2:** Simple validation. Low priority.

#### EC-8.6: Undo In-Person Verification 🟢 FUTURE
- **Scenario:** Receiver accidentally marks in-person, wants to undo
- **Handling:**
  - No undo for MVP
  - Once marked, permanent for that day
  - Can add undo within 5-minute window in future
- **Edge Function:** None (not supported for MVP)
- **Why Future:** We explicitly decided no undo for MVP

#### EC-8.7: In-Person During Scheduled Break 🔴 MVP CRITICAL
- **Scenario:** Sender on break, receiver marks in-person
- **Handling:**
  - Allow both states
  - Show: "🏖️ On break (verified in person at 10:15 AM)"
  - No conflict - both valid
  - Break continues after verification
- **Edge Function:** `create_inperson_verification()`
- **Why Critical:** Features must work together

#### EC-8.8: Sender Disputes In-Person 🟢 FUTURE
- **Scenario:** Sender claims they weren't checked on
- **Handling:**
  - No dispute mechanism for MVP
  - Record shows which receiver verified
  - Out-of-app resolution (family communication)
- **Edge Function:** None (stored data, no dispute)
- **Why Future:** Social problem, not technical. Can add notes feature later.

---

## CATEGORY 9: Data Integrity & Consistency

### Edge Cases

#### EC-9.1: Missing Ping Records 🔴 MVP CRITICAL
- **Scenario:** Scheduled job fails, no "missed" record created for a day
- **Handling:**
  - Daily data integrity check
  - Find gaps in history (missing days)
  - Backfill missing records next day
  - Mark as "missed" retroactively
  - Alert engineers of job failure
- **Edge Function:** `data_integrity_check()`, `backfill_missed_records()`
- **Why Critical:** Historical data must be accurate and complete

#### EC-9.2: Duplicate Ping Records 🔴 MVP CRITICAL
- **Scenario:** Race condition creates two ping records for same user/day
- **Handling:**
  - Daily integrity check detects duplicates
  - Keep first record, delete duplicate
  - Log for investigation
  - Implement idempotency keys to prevent
- **Edge Function:** `data_integrity_check()`
- **Why Critical:** Data corruption prevention

#### EC-9.3: Orphaned Connection Records 🟡 PHASE 2
- **Scenario:** User deleted but connection records remain
- **Handling:**
  - Daily check finds connections with deleted users
  - Clean up orphaned records
  - Cascade deletion should prevent this
  - Log as error if found
- **Edge Function:** `data_integrity_check()`
- **Why Phase 2:** Cascade deletion should prevent. Check is safety net.

#### EC-9.4: Database Transaction Failure 🔴 MVP CRITICAL
- **Scenario:** Connection creation fails halfway (sender updated, receiver not)
- **Handling:**
  - Wrap all multi-step operations in transactions
  - Rollback on failure
  - Retry with exponential backoff
  - Idempotency keys for retry safety
- **Edge Function:** `handle_transaction_failure()`
- **Why Critical:** Data consistency is fundamental

#### EC-9.5: Inconsistent Payment Status 🔴 MVP CRITICAL
- **Scenario:** Database shows subscribed, App Store shows canceled
- **Handling:**
  - Daily sync with App Store
  - Webhook handles real-time updates
  - If mismatch detected: App Store is source of truth
  - Update database to match
  - Alert engineers of discrepancy
- **Edge Function:** `sync_appstore_subscription()`, `audit_payment_status()`
- **Why Critical:** Payment integrity is business-critical

#### EC-9.6: Historical Data Corruption 🟡 PHASE 2
- **Scenario:** Ping timestamps are in future or far past
- **Handling:**
  - Validation on ping creation: timestamp within reasonable range
  - If corrupt data found: Flag for manual review
  - Don't auto-delete (may be legitimate timezone issue)
- **Edge Function:** `validate_ping_timestamp()`
- **Why Phase 2:** Validation exists. This is detection/cleanup.

---

## CATEGORY 10: App State & Connectivity

### Edge Cases

#### EC-10.1: App Killed by iOS 🟡 PHASE 2
- **Scenario:** iOS terminates app due to memory pressure
- **Handling:**
  - Background notifications still work (server-side)
  - App state lost, must restore on next launch
  - Scheduled jobs run independently of app state
- **Edge Function:** None (iOS handles background)
- **Why Phase 2:** iOS handles this. No special app logic needed.

#### EC-10.2: No Internet When Sending Ping 🔴 MVP CRITICAL
- **Scenario:** User taps "Send Ping" with no connectivity
- **Handling:**
  - Show: "No internet connection"
  - Queue ping locally with timestamp
  - Retry when connectivity restored
  - Show "Sending..." indicator
  - Idempotency prevents duplicate if user retries
- **Edge Function:** `queue_offline_pings()`, `handle_ping_retry()`
- **Why Critical:** Users may not have internet at ping time

#### EC-10.3: Slow Network During Ping 🔴 MVP CRITICAL
- **Scenario:** Ping API call takes 30+ seconds
- **Handling:**
  - Show loading indicator
  - Timeout after 30 seconds
  - Retry automatically
  - Show error if all retries fail
- **Edge Function:** `handle_ping_retry()`
- **Why Critical:** Must handle poor network conditions

#### EC-10.4: App Crashes During Ping 🔴 MVP CRITICAL
- **Scenario:** User taps button, app crashes before completion
- **Handling:**
  - Use client-generated idempotency key
  - On next launch, check if ping was sent
  - If unsure, retry (idempotency prevents duplicate)
  - Show notification: "Your ping from earlier was sent successfully"
- **Edge Function:** `handle_ping_retry()`, `verify_ping_status()`
- **Why Critical:** Must not lose pings due to crashes

#### EC-10.5: App Updates / Version Changes 🔴 MVP CRITICAL
- **Scenario:** User updates app, data migration needed
- **Handling:**
  - Database migrations handled by Supabase
  - Check app version on launch
  - Run migration logic if needed
  - Backward compatibility for 2-3 versions
- **Edge Function:** `check_app_version()`, `migrate_user_data()`
- **Why Critical:** Updates must not break existing users

#### EC-10.6: Force Update Required 🟡 PHASE 2
- **Scenario:** Critical bug, must force users to update
- **Handling:**
  - Check minimum supported version on app launch
  - If too old: Show "Update required" screen
  - Block access until updated
  - Link to App Store
- **Edge Function:** `check_app_version()`
- **Why Phase 2:** Rarely needed. Can handle manually if needed.

#### EC-10.7: Background Refresh Disabled 🟡 PHASE 2
- **Scenario:** User disables Background App Refresh in iOS settings
- **Handling:**
  - App can't refresh in background
  - Push notifications still work (server-side)
  - Detect on launch, show warning
  - Not critical for core functionality
- **Edge Function:** `ensure_background_capabilities()`
- **Why Phase 2:** Server-side notifications work regardless

#### EC-10.8: Low Power Mode 🟢 FUTURE
- **Scenario:** User enables Low Power Mode, background activity limited
- **Handling:**
  - iOS reduces background refresh
  - Push notifications still work
  - No special handling needed
- **Edge Function:** None (iOS handles)
- **Why Future:** No special handling needed

---

## CATEGORY 11: Business Logic

### Edge Cases

#### EC-11.1: Becoming Sender at 11:59 PM 🔴 MVP CRITICAL
- **Scenario:** User becomes sender (receiver monitors them) at 11:59 PM
- **Handling:**
  - Free status applies immediately
  - If paying subscription: Cancel immediately
  - Flag `was_sender_ever = true` set immediately
- **Edge Function:** `apply_free_status()`
- **Why Critical:** Payment logic must work at any time

#### EC-11.2: Circular Monitoring 🔴 MVP CRITICAL
- **Scenario:** User A monitors User B, User B monitors User A
- **Handling:**
  - Allowed (valid use case)
  - Two separate connections: A→B and B→A
  - Both users can be senders and receivers simultaneously
  - Both pay $0 if they were senders first
- **Edge Function:** None (supported by design)
- **Why Critical:** Must explicitly support this use case

#### EC-11.3: Sender Never Sets Ping Time 🔴 MVP CRITICAL
- **Scenario:** Receiver adds sender, but sender never completes setup
- **Handling:**
  - Connection exists but inactive
  - Receiver sees: "Waiting for John to set ping time"
  - No notifications sent (no expectation)
  - Prompt sender during onboarding
- **Edge Function:** `validate_sender_setup()`
- **Why Critical:** Onboarding flow must handle incomplete setup

#### EC-11.4: Receiver Monitors Indefinitely Paused Sender 🟡 PHASE 2
- **Scenario:** Receiver pays $2.99/month to monitor sender who's been paused for months
- **Handling:**
  - Subscription continues (receiver's choice)
  - Show receiver: "John has been paused since January 15"
  - Suggest removing inactive connections
  - Don't auto-cancel subscription
- **Edge Function:** `calculate_subscription_value()`
- **Why Phase 2:** Nice-to-have suggestion feature

#### EC-11.5: Trial User Monitors 10 Senders 🔴 MVP CRITICAL
- **Scenario:** Free trial user adds 10 senders, trial ends
- **Handling:**
  - During trial: Can monitor up to 10 senders
  - Trial ends: Prompt to subscribe
  - If don't subscribe: Notifications stop, connections remain
  - Can resubscribe anytime to resume
- **Edge Function:** `enforce_sender_limit()`, `handle_trial_expiration()`
- **Why Critical:** Trial and limit logic must work together

#### EC-11.6: User Deletes All Connections 🟡 PHASE 2
- **Scenario:** User deletes all sender and receiver connections
- **Handling:**
  - Allow deletion
  - Account remains active (empty)
  - Can add new connections anytime
  - If paying: Subscription continues until manually canceled
- **Edge Function:** None (standard deletion)
- **Why Phase 2:** Edge case. Can show suggestion to cancel subscription.

#### EC-11.7: Sender With Zero Receivers 🟡 PHASE 2
- **Scenario:** User is sender, but no receivers monitor them (all deleted connections)
- **Handling:**
  - Sender sees: "No one is monitoring you yet"
  - Can share code to add receivers
  - Ping button still available
  - Show: "Share your code to connect with family"
- **Edge Function:** None (valid state)
- **Why Phase 2:** Valid state. UI messaging is nice-to-have.

---

## CATEGORY 12: Security & Privacy

### Edge Cases

#### EC-12.1: Phone Stolen with App Open 🟡 PHASE 2
- **Scenario:** Attacker has access to unlocked app
- **Handling:**
  - App respects iOS auto-lock timeout
  - Consider: Require Face ID for sensitive operations
  - Rely on device security for MVP
- **Edge Function:** `session_management()`
- **Why Phase 2:** Device security is primary defense. Additional auth is enhancement.

#### EC-12.2: Data Export (GDPR) 🔴 MVP CRITICAL
- **Scenario:** User requests all their data
- **Handling:**
  - Export endpoint in settings
  - Generate JSON with all user data
  - Deliver via email or in-app download
  - 24-hour processing time
- **Edge Function:** `export_user_data()`
- **Why Critical:** GDPR legal requirement

#### EC-12.3: Right to be Forgotten (GDPR) 🔴 MVP CRITICAL
- **Scenario:** User requests complete data deletion
- **Handling:**
  - Account deletion triggers 30-day soft delete
  - After 30 days: Hard delete all data
  - Anonymize in other users' history
  - Irreversible
  - Provide download before deletion
- **Edge Function:** `permanent_data_deletion()`
- **Why Critical:** GDPR legal requirement

#### EC-12.4: Connection Request Spam 🟡 PHASE 2
- **Scenario:** User receives 100 unwanted connections
- **Handling:**
  - Regenerate code (invalidates old one)
  - Block specific users if harassment
  - Rate limit code attempts globally
- **Edge Function:** `regenerate_code_on_spam()`, `handle_blocked_users()`
- **Why Phase 2:** Rate limiting (MVP) handles most abuse. Blocking is enhancement.

#### EC-12.5: Abuse Reporting 🟢 FUTURE
- **Scenario:** User reports another user for harassment
- **Handling:**
  - Report button in connection details
  - Queue for admin review
  - Option to auto-block reported user
  - Serious cases: Suspend account
- **Edge Function:** `report_abuse()`
- **Why Future:** Can handle manually for MVP. Automated system is enhancement.

#### EC-12.6: Privacy - Who Can See What 🔴 MVP CRITICAL
- **Scenario:** Clarify data visibility
- **Handling:**
  - Senders see: Who monitors them
  - Receivers see: Senders' ping status and history
  - No public profiles
  - Can't search for users
  - Connection only via code
- **Edge Function:** None (privacy by design)
- **Why Critical:** Privacy model must be correct from launch

#### EC-12.7: Third-Party Data Sharing 🔴 MVP CRITICAL
- **Scenario:** Apple requires privacy nutrition label
- **Handling:**
  - Collect only: Phone number, name, photo, ping times
  - Never sell data
  - Share with: Apple (payment), APNs (notifications)
  - Clear privacy policy
- **Edge Function:** None (documentation)
- **Why Critical:** App Store requirement

---

## CATEGORY 13: Operations & Monitoring

### Edge Cases

#### EC-13.1: Service Health Monitoring 🔴 MVP CRITICAL
- **Scenario:** Detect if critical services are down
- **Handling:**
  - Health check endpoint: `/health`
  - Check: Database, APNs, Supabase edge functions
  - Alert engineers if degraded
  - Status page for users
- **Edge Function:** `health_check()`
- **Why Critical:** Must detect service disruptions immediately

#### EC-13.2: Metrics Collection 🟡 PHASE 2
- **Scenario:** Track app performance and user behavior
- **Handling:**
  - Collect anonymized metrics
  - Dashboard for monitoring
- **Edge Function:** `metrics_collection()`
- **Why Phase 2:** Basic error logging sufficient for MVP. Analytics are enhancement.

#### EC-13.3: Audit Logging 🟡 PHASE 2
- **Scenario:** Track sensitive operations for security
- **Handling:**
  - Log: Account deletions, payment changes, blocks
  - Store: user_id, action, timestamp
  - Retention: 1 year
- **Edge Function:** `audit_log()`
- **Why Phase 2:** Basic logging for MVP. Comprehensive audit system is enhancement.

#### EC-13.4: Scheduled Job Failure 🔴 MVP CRITICAL
- **Scenario:** Missed ping check job fails to run
- **Handling:**
  - Monitor job execution
  - Alert if job hasn't run in X minutes
  - Backup job runs 5 minutes later
  - Manual intervention if needed
- **Edge Function:** `monitor_scheduled_jobs()`
- **Why Critical:** Scheduled jobs are core functionality

#### EC-13.5: Database Backup & Recovery 🟢 FUTURE
- **Scenario:** Database corruption or data loss
- **Handling:**
  - Supabase handles automatic backups
  - Point-in-time recovery available
  - Document recovery procedures
- **Edge Function:** None (Supabase manages)
- **Why Future:** Supabase handles this. Documentation is nice-to-have.

---

## EDGE FUNCTION MASTER LIST BY PRIORITY

### 🔴 MVP CRITICAL (48 functions)

**Authentication & Account:**
1. `validate_unique_code()` - EC-1.1
2. `regenerate_code()` - EC-1.2
3. `rate_limit_code_attempts()` - EC-1.3
4. `log_code_attempts()` - EC-1.4
5. `delete_account()` - EC-2.1, 2.2, 2.3, 2.4
6. `handle_payment_cancellation()` - EC-2.3
7. `cancel_pending_notifications()` - EC-2.4
8. `account_recovery()` (simplified) - EC-2.6

**Payment & Subscription:**
9. `recalculate_payment_status()` - EC-3.1, 3.2
10. `apply_free_status()` - EC-3.1, 3.2, 11.1
11. `handle_payment_failure()` - EC-3.4
12. `sync_appstore_subscription()` - EC-3.5, 9.5
13. `enforce_sender_limit()` - EC-3.6, 11.5
14. `handle_trial_expiration()` - EC-3.7, 11.5

**Ping & Timing:**
15. `handle_ping_time_change()` - EC-4.1, 4.2, 4.3
16. `handle_timezone_change()` - EC-4.5
17. `determine_ping_day()` - EC-4.10
18. `deduplicate_pings()` - EC-4.11
19. `validate_ping_attempt()` - EC-4.12
20. `queue_offline_pings()` - EC-10.2
21. `handle_ping_retry()` - EC-10.2, 10.3, 10.4
22. `verify_ping_status()` - EC-10.4

**Scheduled Breaks:**
23. `validate_break_schedule()` - EC-5.1
24. `handle_sender_pause()` - EC-5.1
25. `handle_ping_during_break()` - EC-5.2
26. `create_inperson_verification()` - EC-5.4, 7.10, 8.1, 8.2, 8.3, 8.7
27. `delete_break()` - EC-5.5
28. `resume_from_break()` - EC-5.5
29. `check_active_breaks()` - EC-5.8

**Connections:**
30. `create_connection()` - EC-6.1, 6.4
31. `notify_connection_deleted()` - EC-6.2
32. `delete_connection()` - EC-6.3
33. `validate_connection_target()` - EC-6.7, 6.8
34. `validate_sender_setup()` - EC-6.9, 11.3
35. `rate_limit_connections()` - EC-6.12

**Notifications:**
36. `handle_notification_failure()` - EC-7.1, 7.4
37. `update_device_token()` - EC-7.1
38. `check_notification_permissions()` - EC-7.3
39. `queue_notifications()` - EC-7.4
40. `deduplicate_notifications()` - EC-7.6
41. `send_ping()` - Core ping function
42. `check_missed_pings()` - Scheduled job (every 1-5 min)
43. `daily_ping_reset()` - Scheduled job (midnight)

**In-Person Verification:**
44. `handle_premature_inperson()` - EC-8.2

**Data Integrity:**
45. `data_integrity_check()` - EC-9.1, 9.2
46. `backfill_missed_records()` - EC-9.1
47. `handle_transaction_failure()` - EC-9.4
48. `audit_payment_status()` - EC-9.5

**App State:**
49. `check_app_version()` - EC-10.5
50. `migrate_user_data()` - EC-10.5

**Security & Privacy:**
51. `export_user_data()` - EC-12.2
52. `permanent_data_deletion()` - EC-12.3

**Operations:**
53. `health_check()` - EC-13.1
54. `monitor_scheduled_jobs()` - EC-13.4

### 🟡 PHASE 2 (15 functions)

**Account:**
55. `audit_free_status()` - EC-3.3

**Timing:**
56. `handle_dst_transition()` - EC-4.7, 4.8, 4.9
57. `sync_clock_skew()` - EC-4.13

**Connections:**
58. `propagate_profile_changes()` - EC-6.10

**Notifications:**
59. `format_notification_content()` - EC-7.8

**In-Person:**
60. `validate_inperson_timing()` - EC-8.4, 8.5

**Data Integrity:**
61. `validate_ping_timestamp()` - EC-9.6

**App State:**
62. `ensure_background_capabilities()` - EC-10.7

**Business Logic:**
63. `calculate_subscription_value()` - EC-11.4

**Security:**
64. `session_management()` - EC-12.1

**Operations:**
65. `metrics_collection()` - EC-13.2
66. `audit_log()` - EC-13.3

### 🟢 FUTURE (7 functions)

**Account:**
67. `change_phone_number()` - EC-2.5
68. `detect_duplicate_accounts()` - EC-2.7
69. `suspend_account()` - EC-2.8

**Connections:**
70. `handle_blocked_users()` - EC-6.5, 6.6

**Security:**
71. `report_abuse()` - EC-12.5

**Operations:**
72. None additional

---

## SUMMARY STATISTICS

- **Total Edge Cases Documented:** 109
- **MVP Critical:** 67 edge cases (61%)
- **Phase 2:** 28 edge cases (26%)
- **Future:** 14 edge cases (13%)

- **Total Edge Functions:** 72
- **MVP Critical Functions:** 54 (75%)
- **Phase 2 Functions:** 11 (15%)
- **Future Functions:** 5 (7%)
- **Functions eliminated or consolidated:** 6 (from original 78)

---

## DEVELOPMENT GUIDANCE

### For MVP Development:
- **Focus exclusively on 🔴 MVP CRITICAL edge cases**
- These represent core functionality required for launch
- All 54 MVP Critical functions must be implemented
- Prioritize in this order:
  1. Authentication & core ping flow
  2. Payment logic & App Store sync
  3. Notifications & scheduled jobs
  4. Data integrity & GDPR compliance

### For Phase 2 (3-6 months post-launch):
- **Implement 🟡 PHASE 2 edge cases based on user feedback**
- These enhance UX but aren't launch-blockers
- 11 functions to implement
- Can be prioritized based on actual user pain points

### For Future Releases:
- **Consider 🟢 FUTURE edge cases based on scale and user requests**
- These are nice-to-have enhancements
- Only 5 functions - low burden
- Implement when business case is clear

---

## REVISION HISTORY
- **Version 1.0** - 2026-01-15 - Initial comprehensive edge case documentation
- **Version 2.0** - 2026-01-15 - Added priority levels (MVP Critical, Phase 2, Future) with rationale

---

**END OF EDGE CASES DOCUMENT**
