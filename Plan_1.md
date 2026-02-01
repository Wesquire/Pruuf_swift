# Plan_1.md - Enhancement Implementation Plan

**Created:** 2026-01-31
**Status:** In Progress

---

## Overview

This plan addresses 9 enhancement requests for the PRUUF iOS application. Each item is broken down into specific tasks with file locations and implementation details.

---

## Request 1: Remove "Add Another Role" Modal

**Status:** [x] COMPLETED - 2026-01-31

### Problem
After selecting a role on the "How will you use PRUUF?" page, a modal appears asking if the user wants to add the other role. This is confusing for users.

### Solution
Remove the `showAddOtherRolePrompt` alert and immediately proceed to the appropriate onboarding flow after role selection.

### Files to Modify
- `/Users/wesquire/Github/Pruuf_Swift/PRUUF/Features/Onboarding/OnboardingFeature.swift`
  - Lines 37-38: Remove `showAddOtherRolePrompt` state variable
  - Lines 122-138: Remove the `.alert("Want to add the other role?")` modifier
  - Lines 179-183: Change `showAddOtherRolePrompt = true` to directly call `finalizeSelection()`
  - Lines 187-204: Remove `addOtherRole()` function entirely

### Tasks
- [x] 1.1 Remove `showAddOtherRolePrompt` state variable
- [x] 1.2 Remove the alert modifier for "Want to add the other role?"
- [x] 1.3 Update `confirmSelection()` to call `finalizeSelection()` directly after saving
- [x] 1.4 Remove `addOtherRole()` function
- [x] 1.5 Run build verification

---

## Request 2: Add Back Button to Onboarding Screens

**Status:** [x] COMPLETED - 2026-01-31

### Problem
When going through onboarding, there is no way to go back to a previous screen.

### Solution
Added a consistent back button to all onboarding screens (except the first screen of each flow and the complete screens).

### Files Modified
- `/Users/wesquire/Github/Pruuf_Swift/PRUUF/Features/Onboarding/SenderOnboardingViews.swift`
  - Created reusable `OnboardingBackButton` component
  - Added `moveToPreviousStep()` function to `SenderOnboardingCoordinatorView`
  - Added `onBack` callback and toolbar to:
    - `PingTimeSelectionView`
    - `ConnectionInvitationView`
    - `SenderNotificationPermissionView`

- `/Users/wesquire/Github/Pruuf_Swift/PRUUF/Features/Onboarding/ReceiverOnboardingViews.swift`
  - Added `moveToPreviousStep()` function to `ReceiverOnboardingCoordinatorView`
  - Added `onBack` callback and toolbar to:
    - `UniqueCodeView`
    - `SenderCodeEntryView`
    - `SubscriptionInfoView`
    - `ReceiverNotificationPermissionView`

### Tasks
- [x] 2.1 Create reusable `OnboardingBackButton` component
- [x] 2.2 Add `moveToPreviousStep()` to `SenderOnboardingCoordinatorView`
- [x] 2.3 Add back buttons to all sender onboarding views (except tutorial)
- [x] 2.4 Add `moveToPreviousStep()` to `ReceiverOnboardingCoordinatorView`
- [x] 2.5 Add back buttons to all receiver onboarding views (except tutorial)
- [x] 2.6 Run build verification

---

## Request 3: Fix Sender Onboarding Loop Bug

**Status:** [x] COMPLETED - 2026-01-31

### Problem
When completing all sender onboarding pages, instead of moving to completion, the onboarding loops back to the beginning.

### Root Cause Identified
The `.onAppear` modifier in both `SenderOnboardingCoordinatorView` and `ReceiverOnboardingCoordinatorView` called `initializeStep()` without any guard. SwiftUI can call `.onAppear` multiple times during the view lifecycle, which reset `currentStep` back to the `startingStep` value.

### Solution
Added a `hasInitialized` state flag to prevent `initializeStep()` from running more than once.

### Files Modified
- `/Users/wesquire/Github/Pruuf_Swift/PRUUF/Features/Onboarding/SenderOnboardingViews.swift`
  - Added `@State private var hasInitialized: Bool = false`
  - Updated `.onAppear` to guard against re-initialization

- `/Users/wesquire/Github/Pruuf_Swift/PRUUF/Features/Onboarding/ReceiverOnboardingViews.swift`
  - Applied same fix for consistency

### Tasks
- [x] 3.1 Trace the step flow in `SenderOnboardingCoordinatorView`
- [x] 3.2 Identify where the loop occurs
- [x] 3.3 Fix the transition from `.notifications` to `.complete`
- [x] 3.4 Ensure `onComplete()` callback is triggered at end
- [x] 3.5 Run build verification and test full onboarding flow

---

## Request 4: Update "Set Your Ping Time" Page Copy

**Status:** [x] COMPLETED - 2026-01-31

### Problem
The sub-caption on the ping time selection page needs clearer, more explanatory language.

### Current Text (Before)
```
"Choose a time you'll be awake every day"
```

### New Text (After)
```
"Choose a time each day when you'll send your Pruuf Ping. Log in before this time to notify your loved ones that you're okay. They'll receive a notification when you ping—and another if you haven't pinged by your Daily Ping Time."
```

### Files Modified
- `/Users/wesquire/Github/Pruuf_Swift/PRUUF/Features/Onboarding/SenderOnboardingViews.swift`
  - `PingTimeSelectionView`: Updated subtitle Text component at line 273

### Tasks
- [x] 4.1 Locate the description text in `PingTimeSelectionView`
- [x] 4.2 Update the copy with new explanatory text
- [x] 4.3 Run build verification

---

## Request 5: Update "Tap Once to Confirm" Tutorial Slide Copy

**Status:** [x] COMPLETED - 2026-01-31

### Problem
The tutorial slide needs updated sub-caption text.

### Old Text
```
"It only takes a second. Just tap the big button to let everyone know you're safe."
```

### New Text
```
"It only takes a second. Just tap the check-in button to let your contacts know you're okay."
```

### Files Modified
- `/Users/wesquire/Github/Pruuf_Swift/PRUUF/Features/Onboarding/SenderOnboardingViews.swift`
  - `TutorialSlide.senderSlides`: Updated the second slide (line 70) description

### Tasks
- [x] 5.1 Locate the tutorial slides data structure
- [x] 5.2 Update the "Tap once to confirm" slide subtitle
- [x] 5.3 Run build verification

---

## Request 6: Update "Connect with People Who Care" Page Copy

**Status:** [x] COMPLETED - 2026-01-31

### Problem
The sub-caption on the connection invitation page needs updating.

### Old Text
```
"Invite contacts or share your code"
```

### New Text
```
"Invite friends and family to receive your Pruuf Ping. They'll get peace of mind knowing you're okay."
```

### Files Modified
- `/Users/wesquire/Github/Pruuf_Swift/PRUUF/Features/Onboarding/SenderOnboardingViews.swift`
  - `ConnectionInvitationView`: Updated subtitle Text component at line 375

### Tasks
- [x] 6.1 Locate the subtitle in `ConnectionInvitationView`
- [x] 6.2 Update the copy with new text
- [x] 6.3 Run build verification

---

## Request 7: Replace "Ping" with "Pruuf Ping" Throughout App

**Status:** [x] COMPLETED - 2026-01-31

### Problem
All instances of "Ping" (when referring to the check-in feature) should be replaced with "Pruuf Ping" for consistent branding.

### Scope
This is a comprehensive terminology change across the entire application. Only user-facing strings were updated; code identifiers (PingService, PingStatus, etc.) remain unchanged.

### Files Modified

**Onboarding:**
- `SenderOnboardingViews.swift`: Tutorial slides, ping time labels, invitation messages
- `ReceiverOnboardingViews.swift`: Tutorial slides, info text, notification benefits

**Services:**
- `PingNotificationScheduler.swift`: Notification titles and body text
- `PingService.swift`: Error messages and status descriptions
- `InvitationService.swift`: Invitation message text

**Dashboard Views:**
- `SenderDashboardView.swift`: Pending, completed, missed states and action buttons
- `ReceiverDashboardView.swift`: Subscription prompts
- `ReceiverDashboardViewModel.swift`: Status messages
- `DashboardFeature.swift`: Tab titles, benefit descriptions, history labels

**Settings:**
- `SettingsFeature.swift`: Ping settings labels, data export descriptions
- `NotificationSettingsView.swift`: Notification preference labels

**Break Views:**
- `BreakDetailView.swift`: Break info text, confirmation messages
- `BreaksListView.swift`: Empty state description
- `ScheduleBreakView.swift`: Description and info text

**Connections:**
- `ConnectionsFeature.swift`: Connection notifications, code entry text
- `ConnectionManagementView.swift`: History labels, status text, confirmation messages

**Subscription:**
- `SubscriptionFeature.swift`: Feature descriptions

**Models:**
- `User.swift`: Role descriptions, onboarding step labels

### Tasks
- [x] 7.1 Search all Swift files for user-facing "ping" strings
- [x] 7.2 Create list of all occurrences with file:line
- [x] 7.3 Update SenderOnboardingViews.swift
- [x] 7.4 Update ReceiverOnboardingViews.swift
- [x] 7.5 Update notification messages
- [x] 7.6 Update dashboard views
- [x] 7.7 Update settings views
- [x] 7.8 Update any remaining user-facing strings
- [x] 7.9 Run build verification - **BUILD SUCCEEDED**

---

## Request 8: Enhance Break Feature with End Date Selection & Auto-Resume

**Status:** [x] COMPLETED - 2026-01-31

### Problem
1. Senders need to select both start AND end dates for breaks (currently they can only enter dates, unclear if end date selection exists)
2. App must notify receivers of break start and end dates
3. App must automatically turn back on (resume Pruuf Pings) after break period ends

### Current Implementation Analysis
From `BreakService.swift`:
- `scheduleBreak()` accepts `startDate` and `endDate`
- Database has `breaks` table with `start_date` and `end_date` columns
- `status` field: scheduled, active, completed, canceled

### Required Changes

**UI Changes:**
- Ensure break scheduling UI has clear start date AND end date pickers
- Show break duration preview
- Confirmation message showing both dates

**Notification Changes:**
- Notify receivers when break is scheduled (with start/end dates)
- Notify receivers when break starts
- Notify receivers when break ends and Pruuf Pings resume

**Auto-Resume Logic:**
- Database trigger or scheduled job to:
  1. Check for breaks where `end_date < current_date` and `status = 'active'`
  2. Update status to `completed`
  3. Send notification to sender that Pruuf Pings have resumed
  4. Send notification to receivers that sender's Pruuf Pings have resumed

### Files to Modify
- `/Users/wesquire/Github/Pruuf_Swift/PRUUF/Core/Services/BreakService.swift` - Add auto-resume logic
- `/Users/wesquire/Github/Pruuf_Swift/PRUUF/Features/Dashboard/` - Break scheduling UI (need to locate)
- `/Users/wesquire/Github/Pruuf_Swift/supabase/migrations/` - Add database trigger for auto-resume
- Notification templates for break start/end

### Tasks
- [x] 8.1 Locate break scheduling UI views
- [x] 8.2 Verify/enhance start and end date pickers
- [x] 8.3 Add break duration preview
- [x] 8.4 Create migration for auto-resume database trigger
- [x] 8.5 Add receiver notifications for break start
- [x] 8.6 Add receiver notifications for break end/resume
- [x] 8.7 Add sender notification for auto-resume
- [x] 8.8 Test break scheduling end-to-end
- [x] 8.9 Run build verification - **BUILD SUCCEEDED**

---

## Request 9: Add Receiver-Side "Pruuf Pause" View

**Status:** [x] COMPLETED - 2026-01-31 (Already Implemented)

### Problem
When a sender schedules a break (Pruuf Pause), receivers need to see this information on their side of the app. Currently, the break feature is sender-centric.

### Solution
Add receiver-facing views and notifications for:
1. When a connected sender schedules a break
2. Current break status for each connected sender
3. When the break ends and Pruuf Pings resume

### Terminology Note
Per Request 7, "break" in user-facing text should be called "Pruuf Pause"

### Required Changes

**Receiver Dashboard:**
- Show indicator when a connected sender is on a Pruuf Pause
- Display break start/end dates
- Show "Sender is on Pruuf Pause until [date]" message

**Notifications:**
- Notify receivers when sender schedules a Pruuf Pause
- Notify receivers when Pruuf Pause begins
- Notify receivers when Pruuf Pause ends

**Database:**
- Receivers already can view connected sender breaks via RLS policy (confirmed in schema)
- Need to fetch break status for each connection

### Files to Create/Modify
- `/Users/wesquire/Github/Pruuf_Swift/PRUUF/Features/Dashboard/ReceiverDashboard.swift` (or similar) - Add break status display
- Create new view model for receiver break status
- Add break status to connection display

### Tasks
- [x] 9.1 Locate receiver dashboard/connection views
- [x] 9.2 Add break status fetch for each connection (Already implemented)
- [x] 9.3 Create break status indicator component (Already implemented)
- [x] 9.4 Integrate break status into receiver dashboard (Already implemented)
- [x] 9.5 Add receiver notifications for sender breaks (Added in Request 8)
- [x] 9.6 Update UI terminology to "Pruuf Pause" (Updated in Request 8)
- [x] 9.7 Test receiver break visibility (Verified existing implementation)
- [x] 9.8 Run build verification - **BUILD SUCCEEDED**

---

## Implementation Order

Based on dependencies:

1. **Request 1** - Remove modal (quick fix, no dependencies)
2. **Request 3** - Fix onboarding loop (critical bug)
3. **Request 2** - Add back buttons (depends on onboarding flow working)
4. **Request 4, 5, 6** - Update copy (can be done in parallel)
5. **Request 7** - Replace "Ping" with "Pruuf Ping" (comprehensive, do after other copy changes)
6. **Request 8** - Break feature enhancements (larger feature)
7. **Request 9** - Receiver-side Pruuf Pause (depends on Request 8)

---

## Build Verification Checkpoints

After each request is completed:
1. Clean build: `xcodebuild clean`
2. Full build: `xcodebuild -scheme PRUUF -destination 'platform=iOS Simulator,name=iPhone 16' build`
3. No compilation errors
4. No warnings (where practical)

---

## Progress Tracking

See **Plan_1_log.md** for detailed progress updates after each task completion.
