# PRUUF Enhancement Plan 3 - Implementation Plan

## Overview
This plan covers 3 new requirements for the PRUUF iOS app focused on improving user confirmation, receiver notifications, and daily reset functionality.

---

## Requirement 1: Confirmation Dialog Before "I'm OK" Button

### Problem Statement
Currently, when users tap the "I'm Okay" button, the ping is immediately completed without any confirmation. This can lead to accidental taps that trigger notifications to all receivers.

### Proposed Solution
Add a SwiftUI confirmation dialog (`.confirmationDialog`) that appears when the user taps the "I'm OK" button. The dialog will ask the user to confirm their action before completing the ping.

### Files to Modify
1. **SenderDashboardView.swift** (lines 197-216)
   - Location: `/Users/wesquire/Github/Pruuf_Swift/PRUUF/Features/Dashboard/SenderDashboard/SenderDashboardView.swift`

### Implementation Steps

#### Step 1.1: Add State Variable for Confirmation Dialog
Add a `@State` variable to track whether the confirmation dialog should be shown:
```swift
@State private var showOkConfirmation = false
```

#### Step 1.2: Modify "I'm Okay" Button in `pendingPingContent`
Change the button action from directly calling `completePing()` to setting `showOkConfirmation = true`:
```swift
Button {
    showOkConfirmation = true
} label: {
    // ... existing label code
}
```

#### Step 1.3: Add Confirmation Dialog Modifier
Add `.confirmationDialog` modifier to the view hierarchy:
```swift
.confirmationDialog(
    "Send Your Pruuf?",
    isPresented: $showOkConfirmation,
    titleVisibility: .visible
) {
    Button("Yes, I'm Okay") {
        Task {
            await viewModel.completePing()
        }
    }
    Button("Cancel", role: .cancel) { }
} message: {
    Text("This will notify your receivers that you are safe.")
}
```

#### Step 1.4: Apply Same Pattern to Other Ping Completion Buttons
Apply the same confirmation pattern to:
- "Send Pruuf Now" button in `missedPingContent` (lines 267-285)
- "Send Pruuf Anyway (Optional)" button in `onBreakContent` (lines 309-327)

Each will need its own state variable and confirmation dialog.

### Verification Checklist
- [ ] Tapping "I'm Okay" shows confirmation dialog
- [ ] Tapping "Yes, I'm Okay" in dialog completes the ping
- [ ] Tapping "Cancel" in dialog dismisses without action
- [ ] Same behavior for "Send Pruuf Now" button
- [ ] Same behavior for "Send Pruuf Anyway" button
- [ ] Build succeeds with no errors

---

## Requirement 2: Send Notifications to Receivers Every Time Sender Hits OK

### Problem Statement
Currently, notifications are only sent when there are pending pings to complete. The requirement is to send notifications to receivers **every time** the sender hits the OK button, even if the window has already closed or they've already hit it that day.

### Current Behavior Analysis
The current flow in `SenderDashboardViewModel.swift`:
1. `completePing()` calls `pingService.completePing()` or the `complete_ping` RPC function
2. The `complete-ping` edge function only sends notifications when there are pending pings found
3. If no pending pings exist, it returns early with `completed_count: 0` and no notifications are sent

### Proposed Solution
Modify the system to **always** send a notification to receivers when the sender taps "I'm OK", regardless of ping status. This involves:
1. Creating a new edge function or modifying the existing one to send "sender is okay" notifications
2. Optionally modifying the iOS app to call a notification endpoint directly

### Option A: Modify Existing Edge Function (Recommended)
- **Pros**: Keeps notification logic centralized, handles receiver lookup consistently
- **Cons**: Changes existing function behavior, needs careful testing

### Option B: Create New "Send OK Notification" Edge Function
- **Pros**: Cleaner separation, doesn't risk breaking existing ping completion logic
- **Cons**: Additional function to maintain, duplicate receiver lookup logic

### Recommendation: Option A
Modify the existing `complete-ping` edge function to always send notifications, even when no pending pings are found.

### Files to Modify
1. **complete-ping/index.ts** (Supabase Edge Function)
   - Location: `/Users/wesquire/Github/Pruuf_Swift/supabase/functions/complete-ping/index.ts`

2. **SenderDashboardViewModel.swift** (Optional - if iOS-side changes needed)
   - Location: `/Users/wesquire/Github/Pruuf_Swift/PRUUF/Features/Dashboard/SenderDashboard/SenderDashboardViewModel.swift`

### Implementation Steps

#### Step 2.1: Analyze Current `complete-ping` Edge Function
Current behavior at lines 139-153:
- If no pending pings found, returns early with success: true, completed_count: 0
- **No notifications are sent** in this case

#### Step 2.2: Modify Edge Function to Always Send Notifications
Change the logic to:
1. Get the sender's active connections/receivers (even if no pending pings)
2. If no pending pings, still fetch receivers and send "I'm OK" notifications
3. Use a different notification type (e.g., `ping_voluntary` or `sender_ok_confirmation`)

#### Step 2.3: Add New Query to Fetch Active Receivers
Add query to get all active receivers for a sender from `connections` table:
```typescript
// Fetch active receivers for this sender
const { data: connections, error: connError } = await supabaseClient
  .from("connections")
  .select("receiver_id")
  .eq("sender_id", sender_id)
  .eq("status", "active");
```

#### Step 2.4: Send Notifications Even When No Pending Pings
Move notification logic to execute regardless of pending ping status.

#### Step 2.5: Update iOS App to Handle New Notification Type (Optional)
Update `NotificationService.swift` to recognize `sender_ok_confirmation` notification type.

### Verification Checklist
- [ ] Sender with pending pings: notification sent to receivers (existing behavior)
- [ ] Sender with no pending pings: notification still sent to receivers
- [ ] Sender already completed today's ping: notification sent again when hitting OK
- [ ] Notification content is appropriate for repeat confirmations
- [ ] Edge function handles errors gracefully
- [ ] Build succeeds with no errors

---

## Requirement 3: "I'm OK" Window Resets at Midnight

### Problem Statement
The "I'm OK" window should reset at 12:00 AM (midnight) local time, so only pings completed in the **current calendar day** satisfy the daily Pruuf requirement.

### Current Behavior Analysis
In `SenderDashboardViewModel.swift` at `loadTodayPingStatus()` (lines 200-218):
- Uses `calendar.startOfDay(for: Date())` to get today's start
- Queries pings where `scheduled_time >= startOfDay AND scheduled_time < endOfDay`
- **This already restricts to current calendar day**

In `determineTodayPingState()` (lines 315-344):
- Uses `todayPing` (which is already filtered to today's date)
- Determines state based on ping status

### Analysis: What Needs to Change?
The current implementation appears to already filter by current calendar day. However, we need to verify:
1. The UI properly reflects the reset at midnight
2. Any cached state is invalidated at midnight
3. The `TodayPingState` enum properly transitions back to `pending` at midnight

### Potential Issues Found
1. **Timer-based updates**: The `timeUpdateTimer` runs every second but only updates `currentTimeString` and `countdownString`. It doesn't reload the ping status.
2. **State persistence**: If the app is open at midnight, the state won't automatically refresh.

### Proposed Solution
Add midnight detection to refresh the dashboard state when the calendar day changes.

### Files to Modify
1. **SenderDashboardViewModel.swift**
   - Location: `/Users/wesquire/Github/Pruuf_Swift/PRUUF/Features/Dashboard/SenderDashboard/SenderDashboardViewModel.swift`

### Implementation Steps

#### Step 3.1: Track the Current Day
Add a property to track the current day and detect when it changes:
```swift
private var lastKnownDay: Date?
```

#### Step 3.2: Modify Timer Update Logic
In the timer callback (line 124-129), add midnight detection:
```swift
timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
    Task { @MainActor in
        self?.updateCurrentTime()
        self?.updateCountdown()
        self?.checkForDayChange()  // NEW: Check if day has changed
    }
}
```

#### Step 3.3: Implement Day Change Detection
Add a method to check if the day has changed and reload data:
```swift
private func checkForDayChange() {
    let calendar = Calendar.current
    let currentDay = calendar.startOfDay(for: Date())

    if let lastDay = lastKnownDay, lastDay != currentDay {
        // Day has changed - reload dashboard
        Task {
            await loadDashboardData()
        }
    }

    lastKnownDay = currentDay
}
```

#### Step 3.4: Initialize `lastKnownDay` on Load
In `loadDashboardData()`, set the initial `lastKnownDay`:
```swift
func loadDashboardData() async {
    // ... existing code ...
    lastKnownDay = Calendar.current.startOfDay(for: Date())
    // ... rest of function
}
```

#### Step 3.5: Consider Time Zone Changes
The system should handle time zone changes gracefully. Using `Calendar.current` already respects the user's current time zone.

### Verification Checklist
- [ ] At midnight, ping state resets from `completed` to `pending` (for next day)
- [ ] Dashboard properly shows "Time to Send Your Pruuf!" after midnight
- [ ] Previous day's completed ping no longer satisfies today's requirement
- [ ] App handles being open during midnight transition
- [ ] App handles user changing time zones
- [ ] Build succeeds with no errors

---

## Implementation Order

### Phase 1: Requirement 1 (Confirmation Dialog)
- Estimated changes: SwiftUI view only
- Risk level: Low
- Testing: Manual UI testing

### Phase 2: Requirement 3 (Midnight Reset)
- Estimated changes: ViewModel logic
- Risk level: Low
- Testing: Date manipulation testing

### Phase 3: Requirement 2 (Always Send Notifications)
- Estimated changes: Supabase Edge Function + potentially ViewModel
- Risk level: Medium (affects production notification flow)
- Testing: Edge function testing, notification verification

---

## Build Verification Strategy

After each requirement:
1. Run Xcode build to verify no compile errors
2. Verify no SwiftUI preview crashes
3. For edge function changes: Test locally with Supabase CLI
4. Document any issues in Plan_3_log.md

---

## Rollback Plan

If issues arise:
- Each requirement is independent and can be reverted separately
- Git commits should be made after each successful requirement completion
- Edge function changes can be rolled back via Supabase dashboard

---

## Notes

- All changes follow existing code patterns and conventions
- No new dependencies required
- No database schema changes required
- Notification changes affect production - test thoroughly
