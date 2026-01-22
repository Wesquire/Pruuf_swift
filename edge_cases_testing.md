# PRUUF Critical Testing Suites (MVP Focus)

## Document Purpose
This document defines critical testing suites for PRUUF MVP launch. Tests are aligned with edge cases documented in `edge_cases.md` and focus exclusively on 🔴 MVP CRITICAL functionality. Phase 2 and Future edge cases are excluded.

## Priority Reference

This document covers ONLY:
- **🔴 MVP CRITICAL** - 67 edge cases, 54 functions (from edge_cases.md)

Tests for 🟡 PHASE 2 and 🟢 FUTURE edge cases are deferred to post-launch.

---

## TEST SUITE 1: AUTHENTICATION & ACCOUNT SECURITY (P0)

**Covers Edge Cases:** EC-1.1, EC-1.2, EC-1.3, EC-1.4, EC-2.1, EC-2.2, EC-2.3, EC-2.4, EC-2.6

### TS-1.1: Phone Number Authentication (EC-2.6)
**Priority:** P0
**Critical Because:** Users cannot access app without authentication

**Test Cases:**
1. **TC-1.1.1:** Valid phone number receives SMS code within 30 seconds
2. **TC-1.1.2:** SMS code verification succeeds with correct code
3. **TC-1.1.3:** SMS code verification fails with incorrect code (max 3 attempts)
4. **TC-1.1.4:** SMS code expires after 10 minutes
5. **TC-1.1.5:** Rate limiting: Max 5 SMS requests per phone number per hour
6. **TC-1.1.6:** User loses device, logs in with same phone on new device (EC-2.6)

**Expected Results:**
- Authentication flow completes in < 60 seconds for valid users
- Invalid attempts are blocked appropriately
- Account data restored on new device

---

### TS-1.2: Unique Code Generation & Validation (EC-1.1, EC-1.2, EC-1.3, EC-1.4)
**Priority:** P0
**Critical Because:** Connections depend on code system working correctly

**Test Cases:**
1. **TC-1.2.1:** Generate 1000 unique codes, verify zero collisions (EC-1.1)
2. **TC-1.2.2:** Valid code successfully creates connection
3. **TC-1.2.3:** Invalid code returns clear error message (EC-1.4)
4. **TC-1.2.4:** Regenerated code invalidates old code for new connections (EC-1.2)
5. **TC-1.2.5:** Regenerated code does NOT affect existing connections (EC-1.2)
6. **TC-1.2.6:** Rate limiting: Max 10 code validation attempts per hour per user (EC-1.3)
7. **TC-1.2.7:** Failed attempts logged for security audit (EC-1.4)

**Expected Results:**
- Code system is secure and abuse-resistant
- Existing connections never broken by code regeneration
- Clear error messages for all failure cases

---

### TS-1.3: Account Deletion & Data Cleanup (EC-2.1, EC-2.2, EC-2.3, EC-2.4)
**Priority:** P0
**Critical Because:** GDPR compliance and data cleanup required

**Test Cases:**
1. **TC-1.3.1:** Sender deletes account → All receivers notified immediately (EC-2.1)
2. **TC-1.3.2:** Receiver deletes account → All senders notified immediately (EC-2.2)
3. **TC-1.3.3:** All connections deleted when account deleted (EC-2.1, EC-2.2)
4. **TC-1.3.4:** All pending notifications canceled when account deleted (EC-2.4)
5. **TC-1.3.5:** Subscription canceled when account deleted (EC-2.3)
6. **TC-1.3.6:** 30-day soft delete period before hard delete (EC-2.3)
7. **TC-1.3.7:** Hard delete removes all PII after 30 days (EC-2.3)
8. **TC-1.3.8:** Historical data anonymized (shows "Deleted User") (EC-2.1)

**Expected Results:**
- Complete cascade deletion
- No orphaned records in database
- GDPR compliance maintained

---

## TEST SUITE 2: PAYMENT & SUBSCRIPTION (P0)

**Covers Edge Cases:** EC-3.1, EC-3.2, EC-3.4, EC-3.5, EC-3.6, EC-3.7, EC-11.1, EC-11.5

### TS-2.1: Payment Status Calculation (EC-3.1, EC-3.2, EC-11.1)
**Priority:** P0
**Critical Because:** Revenue depends on correct payment logic

**Test Cases:**
1. **TC-2.1.1:** User is sender for 1+ person → Never charged (free forever) (EC-3.1)
2. **TC-2.1.2:** User becomes sender after paying → Subscription auto-canceled (EC-3.2)
3. **TC-2.1.3:** User deletes all sender connections → Remains free (was_sender_ever flag) (EC-3.1)
4. **TC-2.1.4:** Receiver-only user → Prompted for $2.99/month subscription
5. **TC-2.1.5:** Free trial starts when receiver-only user adds first sender
6. **TC-2.1.6:** Trial lasts exactly 15 days
7. **TC-2.1.7:** After trial expires → Notifications stop until subscription (EC-3.7)
8. **TC-2.1.8:** User at 10-sender limit without subscription → Cannot add 11th (EC-3.6)
9. **TC-2.1.9:** User with subscription can monitor up to 10 senders (EC-3.6)
10. **TC-2.1.10:** Becoming sender at 11:59 PM → Free status applies immediately (EC-11.1)
11. **TC-2.1.11:** Trial user at 10-sender limit → Trial ends, limit enforced (EC-11.5)

**Expected Results:**
- Zero incorrect charges
- Free status correctly maintained for all sender users
- Payment gates enforced at correct points

---

### TS-2.2: App Store Subscription Sync (EC-3.5, EC-9.5)
**Priority:** P0
**Critical Because:** Payment failures cause revenue loss and bad UX

**Test Cases:**
1. **TC-2.2.1:** New subscription in App Store → Immediately active in app (EC-3.5)
2. **TC-2.2.2:** Subscription renewal in App Store → Continues service (EC-3.5)
3. **TC-2.2.3:** Subscription canceled in App Store → Notifications stop at period end (EC-3.5)
4. **TC-2.2.4:** Payment failure in App Store → 7-day grace period, then cutoff (EC-3.4)
5. **TC-2.2.5:** Refund issued in App Store → Access immediately revoked (EC-3.5)
6. **TC-2.2.6:** Subscription restored after lapse → Notifications resume immediately
7. **TC-2.2.7:** Webhook failures → Retry with exponential backoff (3 attempts) (EC-3.5)
8. **TC-2.2.8:** Database vs App Store mismatch → App Store is source of truth (EC-9.5)

**Expected Results:**
- Real-time sync between App Store and app
- No service interruption for paid users
- Proper handling of all App Store events

---

### TS-2.3: Payment Failure Handling (EC-3.4)
**Priority:** P0
**Critical Because:** Standard payment flow must handle failures gracefully

**Test Cases:**
1. **TC-2.3.1:** Day 1 of payment failure → Automatic retry (EC-3.4)
2. **TC-2.3.2:** Day 3 of payment failure → User notified "payment issue" (EC-3.4)
3. **TC-2.3.3:** Day 7 of payment failure → Notifications disabled (EC-3.4)
4. **TC-2.3.4:** Data remains intact for 30 days after cutoff (EC-3.4)
5. **TC-2.3.5:** User resubscribes after cutoff → Notifications resume immediately (EC-3.4)

**Expected Results:**
- Graceful degradation with clear communication
- No data loss during payment issues
- Easy recovery path for users

---

## TEST SUITE 3: CORE PING FUNCTIONALITY (P0)

**Covers Edge Cases:** EC-4.1, EC-4.2, EC-4.3, EC-4.5, EC-4.10, EC-4.11, EC-4.12, EC-10.2, EC-10.3, EC-10.4

### TS-3.1: Send Ping Flow
**Priority:** P0
**Critical Because:** Core purpose of the app

**Test Cases:**
1. **TC-3.1.1:** User taps "Send Ping" → Ping sent successfully < 3 seconds
2. **TC-3.1.2:** All connected receivers notified within 10 seconds
3. **TC-3.1.3:** Sender sees confirmation: "Checked in at [time]"
4. **TC-3.1.4:** Button disabled after successful ping (until midnight)
5. **TC-3.1.5:** Cannot send duplicate ping same day (backend validation) (EC-4.12)
6. **TC-3.1.6:** Ping creates database record with correct timestamp
7. **TC-3.1.7:** Ping sent during scheduled break shows special status (EC-5.2)
8. **TC-3.1.8:** Offline ping queued locally, sent when internet restored (EC-10.2)
9. **TC-3.1.9:** Idempotency: Retry does not create duplicate pings (EC-4.11)
10. **TC-3.1.10:** Ping timestamp uses server time (not device time)
11. **TC-3.1.11:** Slow network (30s) → Retry with timeout (EC-10.3)
12. **TC-3.1.12:** App crashes during ping → Retry on relaunch prevents loss (EC-10.4)

**Expected Results:**
- 100% of pings delivered to database
- 95%+ notification delivery rate
- No duplicate pings created
- Offline and crash recovery works reliably

---

### TS-3.2: Ping Timing & Deadlines
**Priority:** P0
**Critical Because:** Missed notifications defeat app purpose

**Test Cases:**
1. **TC-3.2.1:** User can ping anytime after midnight (12:01 AM onwards)
2. **TC-3.2.2:** User can ping until 11:59 PM same day
3. **TC-3.2.3:** Ping before deadline → Status shows "on time"
4. **TC-3.2.4:** No ping at deadline → Receivers notified within 1 minute
5. **TC-3.2.5:** No ping at +15 minutes → Second notification sent to receivers
6. **TC-3.2.6:** No ping at +60 minutes → Sender reminded to ping
7. **TC-3.2.7:** Late ping (after deadline) → Receivers notified of late check-in
8. **TC-3.2.8:** Ping exactly at midnight (12:00:00 AM) counts for new day (EC-4.10)
9. **TC-3.2.9:** Double-tap within 5 seconds → Only one ping created (EC-4.11)

**Expected Results:**
- All deadline notifications sent within ±1 minute of scheduled time
- Late pings correctly notify receivers
- No missed or duplicate notifications

---

### TS-3.3: Ping Time Changes (EC-4.1, EC-4.2, EC-4.3)
**Priority:** P0
**Critical Because:** Common user action, must not break expectations

**Test Cases:**
1. **TC-3.3.1:** Change ping time mid-day (already pinged) → New time applies tomorrow (EC-4.1)
2. **TC-3.3.2:** Change ping time mid-day (not pinged, earlier) → Old time expected today (EC-4.2)
3. **TC-3.3.3:** Change ping time mid-day (not pinged, later) → Old time expected today (EC-4.3)
4. **TC-3.3.4:** UI shows: "New ping time will take effect tomorrow" (EC-4.1, 4.2, 4.3)
5. **TC-3.3.5:** Receivers see updated ping time for future days

**Expected Results:**
- No retroactive changes to current day expectations
- Clear communication of when new time takes effect
- Prevents gaming the system

---

## TEST SUITE 4: TIMEZONE HANDLING (P0)

**Covers Edge Cases:** EC-4.5

### TS-4.1: Timezone Detection & Adjustment (EC-4.5)
**Priority:** P0
**Critical Because:** Wrong timezone = wrong notifications

**Test Cases:**
1. **TC-4.1.1:** App detects device timezone correctly on launch (EC-4.5)
2. **TC-4.1.2:** Ping time "9 AM" stays "9 AM local" when timezone changes (EC-4.5)
3. **TC-4.1.3:** User travels Pacific → Eastern → Ping expected at 9 AM Eastern (EC-4.5)
4. **TC-4.1.4:** Scheduled jobs check each user's local time correctly (EC-4.5)
5. **TC-4.1.5:** All timestamps stored in UTC, displayed in user's local time (EC-4.5)
6. **TC-4.1.6:** Receivers in different timezones see sender's status correctly

**Expected Results:**
- Ping time always means "local time" for sender
- No timezone-related missed notifications
- Correct behavior across all timezones

---

## TEST SUITE 5: SCHEDULED BREAKS (P0)

**Covers Edge Cases:** EC-5.1, EC-5.2, EC-5.4, EC-5.5, EC-5.8

### TS-5.1: Break Creation & Behavior (EC-5.1, EC-5.2, EC-5.8)
**Priority:** P0
**Critical Because:** Prevents false alarms during vacations

**Test Cases:**
1. **TC-5.1.1:** Create break with start + end date → Saved correctly (EC-5.1)
2. **TC-5.1.2:** Create indefinite pause (no end date) → Saved correctly (EC-5.1)
3. **TC-5.1.3:** Receivers notified when break scheduled
4. **TC-5.1.4:** Receivers see "On break until [date]" status (EC-5.1)
5. **TC-5.1.5:** During active break → No missed ping notifications sent (EC-5.2)
6. **TC-5.1.6:** During break, sender pings → Receivers see "On break (pinged)" (EC-5.2)
7. **TC-5.1.7:** Break ends (inclusive) → Normal expectations resume next day (EC-5.8)
8. **TC-5.1.8:** Delete break mid-break → Resume expectations next day (EC-5.5)

**Expected Results:**
- Zero false alarm notifications during breaks
- Clear status communication to receivers
- Proper resumption after break

---

### TS-5.2: Break & In-Person Interaction (EC-5.4)
**Priority:** P0
**Critical Because:** Both features must work together

**Test Cases:**
1. **TC-5.2.1:** Sender on break, receiver marks in-person → Both states shown (EC-5.4)
2. **TC-5.2.2:** Status shows "On break (verified in person)" (EC-5.4)
3. **TC-5.2.3:** No conflict between break and verification (EC-5.4)

**Expected Results:**
- Both features coexist gracefully
- Clear combined status display

---

## TEST SUITE 6: IN-PERSON VERIFICATION (P0)

**Covers Edge Cases:** EC-8.1, EC-8.2, EC-8.3, EC-8.7

### TS-6.1: Mark As Checked In Person (EC-8.1, EC-8.2, EC-8.3, EC-8.7)
**Priority:** P0
**Critical Because:** Prevents unnecessary alarm/worry

**Test Cases:**
1. **TC-6.1.1:** Mark in-person before deadline → Prevents missed notifications (EC-8.2)
2. **TC-6.1.2:** Mark in-person after deadline → Stops further notifications (EC-8.2)
3. **TC-6.1.3:** Multiple receivers can mark in-person independently (EC-8.1)
4. **TC-6.1.4:** Sender sees who verified them and when (EC-8.1)
5. **TC-6.1.5:** In-person + digital ping same day → Both recorded (EC-8.3)
6. **TC-6.1.6:** Action available in notification and in-app (EC-7.10)
7. **TC-6.1.7:** During break + in-person → Both states shown (EC-8.7)

**Expected Results:**
- Effectively stops unwanted notifications
- Clear record of who verified
- Works seamlessly with other features

---

## TEST SUITE 7: CONNECTION MANAGEMENT (P0)

**Covers Edge Cases:** EC-6.1, EC-6.2, EC-6.3, EC-6.4, EC-6.7, EC-6.8, EC-6.9, EC-6.12, EC-11.2, EC-11.3

### TS-7.1: Connection Creation (EC-6.1, EC-6.4, EC-6.7, EC-6.8, EC-6.9, EC-11.2, EC-11.3)
**Priority:** P0
**Critical Because:** Core relationship functionality

**Test Cases:**
1. **TC-7.1.1:** Valid code creates connection immediately
2. **TC-7.1.2:** Both users notified of new connection
3. **TC-7.1.3:** Connection appears in both users' lists
4. **TC-7.1.4:** Sender without ping time → Receiver sees "waiting" (EC-6.9, EC-11.3)
5. **TC-7.1.5:** Cannot connect to self (validation error) (EC-6.7)
6. **TC-7.1.6:** Cannot create duplicate connection (validation error) (EC-6.8)
7. **TC-7.1.7:** Bidirectional connections allowed (A monitors B, B monitors A) (EC-6.1, EC-11.2)
8. **TC-7.1.8:** Connection creation is atomic (no partial state) (EC-6.4)
9. **TC-7.1.9:** Rate limiting: Max 20 connection attempts per hour (EC-6.12)

**Expected Results:**
- Connection creation success rate > 99%
- No orphaned or incomplete connections
- Clear error messages for failures

---

### TS-7.2: Connection Deletion (EC-6.2, EC-6.3)
**Priority:** P0
**Critical Because:** Users must be able to remove unwanted connections

**Test Cases:**
1. **TC-7.2.1:** Sender deletes receiver → Receiver notified, connection removed (EC-6.3)
2. **TC-7.2.2:** Receiver deletes sender → Sender notified, connection removed (EC-6.2)
3. **TC-7.2.3:** No notifications sent after connection deleted
4. **TC-7.2.4:** Historical data preserved (shows connection existed)
5. **TC-7.2.5:** Can reconnect after deletion (not permanently blocked)

**Expected Results:**
- Clean deletion with proper notifications
- No ongoing notifications after deletion

---

## TEST SUITE 8: NOTIFICATIONS (P0)

**Covers Edge Cases:** EC-7.1, EC-7.3, EC-7.4, EC-7.6, EC-7.10

### TS-8.1: Notification Delivery (EC-7.1, EC-7.4, EC-7.6)
**Priority:** P0
**Critical Because:** Core communication mechanism

**Test Cases:**
1. **TC-8.1.1:** Successful ping → Receivers notified within 10 seconds
2. **TC-8.1.2:** Missed ping at deadline → Receivers notified within 1 minute
3. **TC-8.1.3:** Missed ping at +15 min → Second notification sent
4. **TC-8.1.4:** Late ping → Receivers notified of late check-in
5. **TC-8.1.5:** Sender at +60 min → Reminder notification sent
6. **TC-8.1.6:** Multiple receivers (10) → All notified simultaneously
7. **TC-8.1.7:** Notification failure → Retry 3 times with backoff (EC-7.4)
8. **TC-8.1.8:** Device token invalid → Mark as inactive, retry (EC-7.1)
9. **TC-8.1.9:** No duplicate notifications within 1 minute (EC-7.6)

**Expected Results:**
- 95%+ notification delivery rate
- No lost notifications for critical events
- Graceful handling of delivery failures

---

### TS-8.2: Notification Permissions & Actions (EC-7.3, EC-7.10)
**Priority:** P0
**Critical Because:** App unusable without notifications

**Test Cases:**
1. **TC-8.2.1:** Permissions denied → Show in-app banner with Settings link (EC-7.3)
2. **TC-8.2.2:** Detect permission status on app launch (EC-7.3)
3. **TC-8.2.3:** Re-prompt after connection created (EC-7.3)
4. **TC-8.2.4:** Notification action "Mark as checked in person" works (EC-7.10)
5. **TC-8.2.5:** Action triggers without opening app (EC-7.10)

**Expected Results:**
- Clear guidance for enabling notifications
- Notification actions work reliably
- In-app fallback when permissions denied

---

## TEST SUITE 9: DATA INTEGRITY (P0)

**Covers Edge Cases:** EC-9.1, EC-9.2, EC-9.4, EC-9.5

### TS-9.1: Ping Record Integrity (EC-9.1, EC-9.2)
**Priority:** P0
**Critical Because:** Historical data must be accurate

**Test Cases:**
1. **TC-9.1.1:** Every sent ping creates exactly one database record
2. **TC-9.1.2:** Missed days create "missed" record at end of day (EC-9.1)
3. **TC-9.1.3:** No duplicate ping records for same user/day (EC-9.2)
4. **TC-9.1.4:** Timestamps stored in UTC
5. **TC-9.1.5:** 30-day history displays correctly
6. **TC-9.1.6:** Records older than 90 days deleted automatically
7. **TC-9.1.7:** Data integrity check finds and fixes gaps/duplicates (EC-9.1, EC-9.2)
8. **TC-9.1.8:** Backfill creates missing records (EC-9.1)

**Expected Results:**
- 100% accurate historical records
- No data loss or corruption
- Automatic cleanup works reliably

---

### TS-9.2: Transaction Consistency (EC-9.4)
**Priority:** P0
**Critical Because:** Partial updates cause data corruption

**Test Cases:**
1. **TC-9.2.1:** Connection creation is atomic (all-or-nothing) (EC-9.4)
2. **TC-9.2.2:** Account deletion is atomic (all-or-nothing) (EC-9.4)
3. **TC-9.2.3:** Failed transaction rolls back completely (EC-9.4)
4. **TC-9.2.4:** Idempotency prevents duplicate operations on retry (EC-9.4)
5. **TC-9.2.5:** No orphaned records after transaction failure (EC-9.4)

**Expected Results:**
- Zero partial state corruption
- Safe retry behavior
- Database consistency maintained

---

### TS-9.3: Payment Data Integrity (EC-9.5)
**Priority:** P0
**Critical Because:** Payment integrity is business-critical

**Test Cases:**
1. **TC-9.3.1:** Daily sync with App Store detects mismatches (EC-9.5)
2. **TC-9.3.2:** Webhook updates subscription status in real-time (EC-9.5)
3. **TC-9.3.3:** Mismatch detected → App Store is source of truth (EC-9.5)
4. **TC-9.3.4:** Engineer alerted of discrepancy (EC-9.5)

**Expected Results:**
- Payment data always accurate
- Mismatches detected and corrected
- No revenue leakage

---

## TEST SUITE 10: SECURITY & PRIVACY (P0)

**Covers Edge Cases:** EC-1.3, EC-6.12, EC-12.2, EC-12.3, EC-12.6, EC-12.7

### TS-10.1: Rate Limiting & Abuse Prevention (EC-1.3, EC-6.12)
**Priority:** P0
**Critical Because:** Prevents spam and attacks

**Test Cases:**
1. **TC-10.1.1:** Max 5 SMS requests per phone per hour
2. **TC-10.1.2:** Max 10 code validation attempts per hour per user (EC-1.3)
3. **TC-10.1.3:** Max 20 connection attempts per hour per user (EC-6.12)
4. **TC-10.1.4:** Rate limits enforced at API level (not just UI)
5. **TC-10.1.5:** Clear error messages when rate limited
6. **TC-10.1.6:** Rate limits reset after time period expires

**Expected Results:**
- No brute force attacks possible
- Legitimate users not impacted
- Abuse attempts blocked

---

### TS-10.2: Data Privacy & GDPR (EC-12.2, EC-12.3, EC-12.6, EC-12.7)
**Priority:** P0
**Critical Because:** Legal compliance required

**Test Cases:**
1. **TC-10.2.1:** User can export all their data (JSON format) (EC-12.2)
2. **TC-10.2.2:** Export includes: profile, connections, pings, breaks, payment (EC-12.2)
3. **TC-10.2.3:** Account deletion triggers 30-day soft delete (EC-12.3)
4. **TC-10.2.4:** Hard delete removes all PII after 30 days (EC-12.3)
5. **TC-10.2.5:** Deleted user shows as "Deleted User" in others' history (EC-12.3)
6. **TC-10.2.6:** No data shared with third parties except Apple/APNs (EC-12.7)
7. **TC-10.2.7:** Privacy model: Senders see who monitors, receivers see status (EC-12.6)
8. **TC-10.2.8:** No public profiles, no user search (EC-12.6)

**Expected Results:**
- Full GDPR compliance
- Complete data deletion possible
- User data portable
- Privacy by design enforced

---

## TEST SUITE 11: APP STATE & CONNECTIVITY (P0)

**Covers Edge Cases:** EC-10.2, EC-10.3, EC-10.4, EC-10.5

### TS-11.1: Offline & Network Resilience (EC-10.2, EC-10.3, EC-10.4)
**Priority:** P0
**Critical Because:** Must handle poor connectivity gracefully

**Test Cases:**
1. **TC-11.1.1:** Ping while offline → Queued locally with timestamp (EC-10.2)
2. **TC-11.1.2:** When internet restored → Queued ping sent automatically (EC-10.2)
3. **TC-11.1.3:** "Sending..." indicator shows while queued (EC-10.2)
4. **TC-11.1.4:** Idempotency prevents duplicate if user retries (EC-10.2)
5. **TC-11.1.5:** API call timeout after 30 seconds (EC-10.3)
6. **TC-11.1.6:** Automatic retry with exponential backoff (EC-10.3)
7. **TC-11.1.7:** Max 3 retry attempts before showing error (EC-10.3)
8. **TC-11.1.8:** App crash during ping → Retry on relaunch (EC-10.4)
9. **TC-11.1.9:** Client-generated idempotency key prevents duplicates (EC-10.4)

**Expected Results:**
- Pings never lost due to connectivity issues
- Automatic retry when online
- Clear status indication
- No app crashes due to network issues

---

### TS-11.2: App Version Management (EC-10.5)
**Priority:** P0
**Critical Because:** Updates must not break existing users

**Test Cases:**
1. **TC-11.2.1:** App checks version on launch (EC-10.5)
2. **TC-11.2.2:** Data migration runs successfully on update (EC-10.5)
3. **TC-11.2.3:** No data loss during app updates (EC-10.5)
4. **TC-11.2.4:** Backward compatibility for 2-3 versions (EC-10.5)

**Expected Results:**
- Smooth update process
- No breaking changes without migration
- Data preserved across versions

---

## TEST SUITE 12: SCHEDULED JOBS (P0)

**Covers Edge Cases:** EC-13.4

### TS-12.1: Missed Ping Check Job (EC-13.4)
**Priority:** P0
**Critical Because:** Core functionality depends on this

**Test Cases:**
1. **TC-12.1.1:** Job runs every 1-5 minutes consistently (EC-13.4)
2. **TC-12.1.2:** Detects all users past deadline (within ±1 minute)
3. **TC-12.1.3:** Sends first notification at deadline
4. **TC-12.1.4:** Sends second notification at +15 minutes
5. **TC-12.1.5:** Sends sender reminder at +60 minutes
6. **TC-12.1.6:** Skips users on active breaks (EC-5.2)
7. **TC-12.1.7:** Handles multiple timezones correctly (EC-4.5)
8. **TC-12.1.8:** Job failure triggers alert to engineers (EC-13.4)
9. **TC-12.1.9:** Creates "missed" record at end of day (EC-9.1)
10. **TC-12.1.10:** Backup job runs if primary fails (EC-13.4)

**Expected Results:**
- 100% job execution reliability
- All missed pings detected within 1 minute
- Notifications sent on schedule

---

### TS-12.2: Daily Reset Job
**Priority:** P0
**Critical Because:** Resets daily ping status

**Test Cases:**
1. **TC-12.2.1:** Job runs at midnight in each user's timezone (EC-4.5)
2. **TC-12.2.2:** Ping status reset for all users
3. **TC-12.2.3:** "Send Ping" button re-enabled
4. **TC-12.2.4:** Previous day's pings archived

**Expected Results:**
- Clean daily reset
- No users stuck with "already pinged"

---

## TEST SUITE 13: OPERATIONS & MONITORING (P0)

**Covers Edge Cases:** EC-13.1, EC-13.4

### TS-13.1: Service Health Monitoring (EC-13.1, EC-13.4)
**Priority:** P0
**Critical Because:** Must detect service disruptions immediately

**Test Cases:**
1. **TC-13.1.1:** Health check endpoint returns status (EC-13.1)
2. **TC-13.1.2:** Checks database connectivity (EC-13.1)
3. **TC-13.1.3:** Checks APNs service status (EC-13.1)
4. **TC-13.1.4:** Checks Supabase edge functions (EC-13.1)
5. **TC-13.1.5:** Alert engineers if degraded (EC-13.1)
6. **TC-13.1.6:** Monitor scheduled job execution (EC-13.4)
7. **TC-13.1.7:** Alert if job hasn't run in X minutes (EC-13.4)

**Expected Results:**
- Real-time service health visibility
- Immediate alerting on failures
- Proactive issue detection

---

## TEST SUITE 14: PERFORMANCE (P0)

### TS-14.1: Performance Benchmarks
**Priority:** P0
**Critical Because:** Poor performance = bad UX

**Test Cases:**
1. **TC-14.1.1:** App launch time < 2 seconds
2. **TC-14.1.2:** Ping sent in < 3 seconds
3. **TC-14.1.3:** Notification received within 10 seconds of ping
4. **TC-14.1.4:** Dashboard loads in < 1 second
5. **TC-14.1.5:** Connection creation in < 2 seconds
6. **TC-14.1.6:** History view loads 30 days in < 1 second

**Expected Results:**
- Fast, responsive app
- No perceived lag
- Smooth scrolling

---

### TS-14.2: Load Testing
**Priority:** P0
**Critical Because:** Need to handle growth

**Test Cases:**
1. **TC-14.2.1:** 1000 simultaneous pings processed successfully
2. **TC-14.2.2:** 10,000 users with 9 AM ping time handled correctly
3. **TC-14.2.3:** Database queries complete in < 100ms at scale
4. **TC-14.2.4:** Notification queue processes 10,000/minute
5. **TC-14.2.5:** API endpoints handle 100 requests/second

**Expected Results:**
- System scales to thousands of users
- No degradation under load
- Queue doesn't back up

---

## CRITICAL TEST EXECUTION PLAN

### Phase 1: Pre-Launch (Must Pass 100%)
**All P0 tests must pass before launch**

**Priority Order:**
1. **Authentication & Account** (TS-1.1, TS-1.2, TS-1.3)
2. **Core Ping Flow** (TS-3.1, TS-3.2, TS-3.3)
3. **Scheduled Jobs** (TS-12.1, TS-12.2)
4. **Notifications** (TS-8.1, TS-8.2)
5. **Payment & Subscription** (TS-2.1, TS-2.2, TS-2.3)
6. **Data Integrity** (TS-9.1, TS-9.2, TS-9.3)
7. **Timezone Handling** (TS-4.1)
8. **Scheduled Breaks** (TS-5.1, TS-5.2)
9. **In-Person Verification** (TS-6.1)
10. **Connection Management** (TS-7.1, TS-7.2)
11. **Security & Privacy** (TS-10.1, TS-10.2)
12. **Connectivity** (TS-11.1, TS-11.2)
13. **Operations** (TS-13.1)
14. **Performance** (TS-14.1, TS-14.2)

### Phase 2: Beta Testing
- Run all P0 tests with real users
- Monitor performance metrics
- Validate edge case handling

### Phase 3: Continuous Integration
- Automated tests run on every commit
- P0 tests must pass for deployment
- Regression testing on all critical paths

---

## TEST AUTOMATION REQUIREMENTS

### Must Automate (P0):
- Authentication flow (TS-1.1, TS-1.2)
- Ping send/receive (TS-3.1)
- Notification delivery (TS-8.1)
- Payment status calculation (TS-2.1)
- Connection creation/deletion (TS-7.1, TS-7.2)
- Scheduled job execution (TS-12.1, TS-12.2)
- Data integrity checks (TS-9.1, TS-9.2)
- Rate limiting (TS-10.1)
- Offline queue (TS-11.1)

### Manual Testing Required:
- UI/UX validation
- iOS-specific behaviors
- App Store submission flow
- Real device notification delivery
- Multi-device testing
- Timezone testing across regions

---

## MONITORING & ALERTING

### Critical Metrics to Monitor:
1. **Ping success rate** (target: 99.9%) - TS-3.1
2. **Notification delivery rate** (target: 95%+) - TS-8.1
3. **Scheduled job execution rate** (target: 100%) - TS-12.1
4. **API error rate** (target: < 0.1%)
5. **Payment sync success rate** (target: 99.9%) - TS-2.2
6. **Database query performance** (target: < 100ms) - TS-14.2

### Alert Thresholds:
- Ping success rate < 98% → **Immediate P0 alert**
- Notification delivery < 90% → **Immediate P0 alert**
- Scheduled job missed → **Immediate P0 alert**
- API error rate > 1% → **P1 Warning**
- Database slow queries → **P1 Warning**

---

## REGRESSION TEST CHECKLIST

**Before Every Release:**
- [ ] All P0 tests pass (100% required)
- [ ] Payment flow verified end-to-end
- [ ] Notification delivery tested across scenarios
- [ ] Scheduled jobs running correctly
- [ ] Data integrity confirmed
- [ ] Security tests pass (rate limiting, GDPR)
- [ ] Performance benchmarks met
- [ ] No P0 bugs in backlog
- [ ] Load testing passed
- [ ] Multi-timezone testing passed

---

## EDGE CASE CROSS-REFERENCE

All test cases reference specific edge cases from `edge_cases.md` using the EC-X.Y format. This ensures:
- **Traceability**: Each test maps to documented edge case
- **Coverage**: All 🔴 MVP CRITICAL edge cases have tests
- **Alignment**: Testing document stays in sync with edge case document

### Coverage Summary:
- **67 MVP Critical Edge Cases** documented
- **200+ Test Cases** covering all MVP critical scenarios
- **14 Test Suites** organized by functional area
- **100% coverage** of P0 edge cases

---

## DEFERRED TESTING (Phase 2 & Future)

The following edge cases have tests deferred to post-launch:

### 🟡 Phase 2 Edge Cases (Not Tested for MVP):
- EC-1.5, EC-3.3, EC-3.8, EC-3.9, EC-4.4, EC-4.6, EC-4.7, EC-4.8, EC-4.9, EC-4.13
- EC-5.3, EC-5.6, EC-5.7, EC-5.9, EC-5.10
- EC-6.10, EC-6.11, EC-7.2, EC-7.5, EC-7.7
- EC-8.4, EC-8.5, EC-9.3, EC-9.6
- EC-10.1, EC-10.6, EC-10.7, EC-11.4, EC-11.6, EC-11.7
- EC-12.1, EC-12.4, EC-13.2, EC-13.3

### 🟢 Future Edge Cases (Not Tested for MVP):
- EC-2.5, EC-2.7, EC-2.8, EC-6.5, EC-6.6
- EC-7.8, EC-7.9, EC-7.11, EC-8.6, EC-8.8
- EC-10.8, EC-12.5, EC-13.5

---

## REVISION HISTORY
- **Version 1.0** - 2026-01-15 - Initial critical testing suite documentation
- **Version 2.0** - 2026-01-15 - Updated to align with priority levels from edge_cases.md v2.0
  - Focus exclusively on 🔴 MVP CRITICAL edge cases
  - Added EC-X.Y references throughout
  - Reorganized by priority
  - Removed non-critical tests

---

**END OF CRITICAL TESTING DOCUMENT**
