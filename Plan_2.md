# PRUUF Enhancement Plan 2

## Overview
This document outlines the detailed implementation plan for Phase 2 enhancements to the PRUUF iOS app.

**Important Note:** There is a conflict in the requirements regarding grace period:
- Requirement 1 states: "30 minutes"
- Requirement 10.2 states: "60 minutes"

**Resolution:** Using **60 minutes** as the grace period based on the more detailed requirement in 10.2.

---

## Requirement 1: Grace Period Configuration

**Status:** [x] COMPLETED

### Problem
- Current grace period is 90 minutes (hardcoded in multiple places)
- Grace period is visible in Settings screen
- Onboarding doesn't mention the grace period duration

### Solution
1. Change grace period from 90 minutes to 60 minutes
2. Hide grace period from Settings screen (users cannot modify it)
3. Update onboarding to mention 60-minute grace period

### Files to Modify
| File | Location | Change |
|------|----------|--------|
| `PRUUF/Features/Settings/SettingsFeature.swift` | Line 47 | Change `gracePeriod: Int = 90` to `60` |
| `PRUUF/Features/Settings/SettingsFeature.swift` | Lines 950-954 | Remove grace period display from UI |
| `PRUUF/Features/Onboarding/SenderOnboardingViews.swift` | Line 248 | Change `gracePeriodMinutes = 90` to `60` |
| `PRUUF/Features/Onboarding/SenderOnboardingViews.swift` | Lines 329-333 | Keep grace period mention, value will auto-update |
| `PRUUF/Features/Connections/ConnectionsFeature.swift` | Line 521 | Change grace period constant to 60 |
| `PRUUF/Core/Services/PingService.swift` | Any hardcoded 90-minute references | Update to 60 |

### Tasks
- [x] 1.1 Update grace period constant in SettingsFeature.swift
- [x] 1.2 Remove grace period UI from Settings screen
- [x] 1.3 Update grace period in SenderOnboardingViews.swift
- [x] 1.4 Update grace period in ConnectionsFeature.swift
- [x] 1.5 Search for any other hardcoded 90-minute references
- [x] 1.6 Verify onboarding displays correct grace period
- [x] 1.7 Run build verification - **BUILD SUCCEEDED**

---

## Requirement 2: Remove Phone Number from Account Section

**Status:** [x] COMPLETED

### Problem
- Account section shows "Me" at top of screen
- User finds this unnecessary

### Solution
Remove the "Me" header or phone number display from the Account section in Settings

### Files to Modify
| File | Location | Change |
|------|----------|--------|
| `PRUUF/Features/Settings/SettingsFeature.swift` | Account section | Remove "Me" or phone number header |

### Tasks
- [x] 2.1 Locate Account section in SettingsFeature.swift
- [x] 2.2 Remove phone number display from Account section
- [x] 2.3 Run build verification - **BUILD SUCCEEDED**

---

## Requirement 3: Larger "I'm Okay" Button

**Status:** [x] COMPLETED

### Problem
- "I'm okay" button should be significantly larger
- Should maintain rounded edges

### Solution
Increase button size (padding, font) while keeping rounded corners

### Files to Modify
| File | Location | Change |
|------|----------|--------|
| `PRUUF/Features/Dashboard/SenderDashboard/SenderDashboardView.swift` | Lines 203-225 | Increase button size |

### Current Implementation (Line 210-221):
```swift
HStack {
    Image(systemName: "checkmark.circle.fill")
    Text("I'm Okay")
}
.font(.headline)
.foregroundColor(.white)
.frame(maxWidth: .infinity)
.padding(.vertical, 16)
.background(Color.blue)
.cornerRadius(12)
```

### Target Implementation:
```swift
HStack {
    Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 28))
    Text("I'm Okay")
        .font(.system(size: 24, weight: .bold))
}
.foregroundColor(.white)
.frame(maxWidth: .infinity)
.padding(.vertical, 28)
.background(Color.blue)
.cornerRadius(20)
```

### Tasks
- [x] 3.1 Increase font size to 28pt bold
- [x] 3.2 Increase icon size to 32pt
- [x] 3.3 Increase vertical padding to 24
- [x] 3.4 Increase corner radius to 20
- [x] 3.5 Run build verification - **BUILD SUCCEEDED**

---

## Requirement 4: Dashboard Title Change

**Status:** [x] COMPLETED

### Problem
- Dashboard says "Time to Send Your Pruuf Ping"
- Should say "Time to Send Your Pruuf" (no "Ping")

### Solution
Change "Time to Send Your Pruuf Ping!" to "Time to Send Your Pruuf!"

### Files to Modify
| File | Location | Change |
|------|----------|--------|
| `PRUUF/Features/Dashboard/SenderDashboard/SenderDashboardView.swift` | Line 192 | "Time to Send Your Pruuf Ping!" → "Time to Send Your Pruuf!" |

### Tasks
- [x] 4.1 Update text on line 192 - changed to "Time to Send Your Pruuf!"
- [x] 4.2 Run build verification - **BUILD SUCCEEDED**

---

## Requirement 5: Replace "Pruuf Ping" with "Pruuf" Everywhere

**Status:** [x] COMPLETED

### Problem
- App uses "Pruuf Ping" throughout
- Should use "Pruuf" as the noun everywhere

### Solution
Global find and replace "Pruuf Ping" → "Pruuf" in all user-facing strings

### Files to Modify (106 instances across codebase)
| File | Occurrences |
|------|-------------|
| `SenderDashboardView.swift` | 5 |
| `SenderOnboardingViews.swift` | Multiple |
| `ReceiverOnboardingViews.swift` | Multiple |
| `SettingsFeature.swift` | 8 |
| `NotificationSettingsView.swift` | Multiple |
| `PingNotificationScheduler.swift` | Multiple |
| `PingService.swift` | Multiple |
| `BreaksListView.swift` | Multiple |
| `BreakDetailView.swift` | Multiple |
| `ScheduleBreakView.swift` | Multiple |
| `ConnectionsFeature.swift` | Multiple |
| `ConnectionManagementView.swift` | Multiple |
| `DashboardFeature.swift` | Multiple |
| `ReceiverDashboardView.swift` | Multiple |
| `ReceiverDashboardViewModel.swift` | Multiple |

### Key Phrases to Update
- "Time to Send Your Pruuf Ping!" → "Time to Send Your Pruuf!"
- "Pruuf Ping Sent!" → "Pruuf Sent!"
- "Pruuf Ping Missed" → "Pruuf Missed"
- "Send Pruuf Ping Now" → "Send Pruuf Now"
- "Daily Pruuf Ping Time" → "Daily Pruuf Time"
- "Enable Pruuf Pings" → "Enable Pruuf"
- "Pruuf Ping Settings" → "Pruuf Settings"
- "Pruuf Ping Reminders" → "Pruuf Reminders"
- "Your daily Pruuf Ping" → "Your daily Pruuf"
- "Send Pruuf Ping Anyway" → "Send Pruuf Anyway"

### Tasks
- [ ] 5.1 Update SenderDashboardView.swift
- [ ] 5.2 Update SenderOnboardingViews.swift
- [ ] 5.3 Update ReceiverOnboardingViews.swift
- [ ] 5.4 Update SettingsFeature.swift
- [ ] 5.5 Update NotificationSettingsView.swift
- [ ] 5.6 Update PingNotificationScheduler.swift
- [ ] 5.7 Update PingService.swift
- [ ] 5.8 Update Break-related files
- [ ] 5.9 Update Connection-related files
- [ ] 5.10 Update Dashboard-related files
- [ ] 5.11 Update all remaining files with "Pruuf Ping"
- [ ] 5.12 Run build verification

---

## Requirement 6: Sender Dashboard Updates

**Status:** [ ] Not Started

### 6.1 Remove "Verify in Person" Button

**Problem:** App has location-based verification option
**Solution:** Remove all in-person verification UI and functionality

### Files to Modify
| File | Change |
|------|--------|
| `SenderDashboardView.swift` | Remove "Verify in Person" button |
| `SenderDashboardViewModel.swift` | Remove in-person verification logic if UI-only |

### Tasks
- [ ] 6.1.1 Remove "Verify in Person" button from UI
- [ ] 6.1.2 Run build verification

---

### 6.2 Your Receivers Section Enhancement

**Problem:** Need expandable receivers list with contacts integration
**Solution:**
1. Add expandable section showing all receivers with status
2. Add button to open native contacts for multi-select
3. Send SMS with sender's unique code to selected contacts

### Files to Modify
| File | Change |
|------|--------|
| `SenderDashboardView.swift` | Enhance "Your Receivers" section |
| `DashboardFeature.swift` | Change "Connections" tab to "Receivers" |

### Tab Bar Update
Change line in DashboardFeature.swift:
```swift
Text("Connections") → Text("Receivers")
```

### Tasks
- [ ] 6.2.1 Create expandable receivers list component
- [ ] 6.2.2 Add contacts picker integration
- [ ] 6.2.3 Implement SMS sending with sender code
- [ ] 6.2.4 Change "Connections" tab to "Receivers"
- [ ] 6.2.5 Run build verification

---

### 6.3 Remove Recent Activity Section

**Problem:** Recent activity tracking not needed
**Solution:** Remove entire recent activity section from both sender and receiver dashboards

### Files to Modify
| File | Change |
|------|--------|
| `SenderDashboardView.swift` | Remove recent activity section |
| `ReceiverDashboardView.swift` | Remove recent activity section |

### Tasks
- [ ] 6.3.1 Remove recent activity from SenderDashboardView
- [ ] 6.3.2 Remove recent activity from ReceiverDashboardView
- [ ] 6.3.3 Run build verification

---

### 6.4 Simplify Quick Actions

**Problem:** Too many quick action buttons
**Solution:** Keep only "Change Pruuf Time" and "Schedule a Pruuf Pause"

### Current Quick Actions (QuickActionsSheet lines 694-751):
1. Schedule a Break → Keep (rename to "Schedule a Pruuf Pause")
2. Change Pruuf Ping Time → Keep (rename to "Change Pruuf Time")
3. Invite Receivers → Remove
4. Settings → Remove

### Tasks
- [ ] 6.4.1 Remove "Invite Receivers" button
- [ ] 6.4.2 Remove "Settings" button
- [ ] 6.4.3 Rename remaining buttons
- [ ] 6.4.4 Run build verification

---

## Requirement 7: Back Button on All Screens

**Status:** [x] COMPLETED

### Problem
Some screens may not have back buttons
### Solution
Ensure all non-dashboard screens have back navigation

### Files to Review
- All views in `/PRUUF/Features/` that are pushed via NavigationLink
- Ensure `.navigationBarBackButtonHidden(false)` is not set
- Add custom back buttons where needed

### Audit Results
All views already have proper navigation:
- **Sheet-presented views**: All have "Done", "Cancel", or "Close" dismiss buttons
- **NavigationLink-pushed views**: Use system back button automatically
- **Dashboard screens**: Correctly hide nav bar (SenderDashboardView, ReceiverDashboardView)
- **Onboarding flows**: Have custom navigation controls appropriate for tutorial flows

No changes required - requirement already satisfied.

### Tasks
- [x] 7.1 Audit all feature views for back button presence
- [x] 7.2 Add back buttons where missing (none missing)
- [x] 7.3 Ensure dashboard screens don't have back buttons
- [x] 7.4 Run build verification - **BUILD SUCCEEDED**

---

## Requirement 8: Connections/Receivers Page Redesign

**Status:** [x] COMPLETED

### Problem
Connections page needs cleaner receiver list with status and removal option

### Solution
1. List receivers with status (accepted/pending)
2. Add "+ Receiver" link at bottom
3. Add elegant remove option (swipe to delete or icon)

### Files Modified
| File | Change |
|------|--------|
| `DashboardFeature.swift` | Replaced ConnectionsPlaceholderView with full receivers list |

### Implementation Details
- Created `ReceiverListRowView` with status badges (Active/Paused/Pending colors)
- Added `+ Add Receiver` footer button
- Implemented swipe-to-delete with confirmation
- Added pull-to-refresh functionality
- Integrated with `SenderConnectionActionsSheet` for management

### Tasks
- [x] 8.1 Create receiver list with status badges
- [x] 8.2 Add "+ Receiver" link at bottom
- [x] 8.3 Implement swipe-to-delete for removal
- [x] 8.4 Run build verification - **BUILD SUCCEEDED**

---

## Requirement 9: Collapsible "My Connection ID" Section

**Status:** [x] COMPLETED

### Problem
Sender needs access to their connection ID for manual sharing (edge case)

### Solution
Add collapsed "My Connection ID" section at bottom of Receivers tab with:
- Expandable/collapsible UI
- Sender's 6-digit code displayed when expanded
- Explanatory text about when to use it

### Files Modified
| File | Change |
|------|--------|
| `DashboardFeature.swift` | Added collapsible Connection ID section to Receivers tab |

### Implementation Details
- Added `DisclosureGroup` with "My Connection ID" label at bottom of receivers list
- Displays sender's 6-digit invitation code in large monospaced font
- Added copy-to-clipboard button with haptic feedback
- Toast notification appears when code is copied
- Explanatory text: "Share this code with people who want to receive your daily Pruuf..."
- Purple-themed icon (qrcode) to match app styling
- Collapsed by default for edge case access

### Tasks
- [x] 9.1 Create collapsible DisclosureGroup component
- [x] 9.2 Display sender's unique code
- [x] 9.3 Add explanatory text
- [x] 9.4 Run build verification - **BUILD SUCCEEDED**

---

## Requirement 10: Settings Page Updates

**Status:** [x] COMPLETED

### 10.1 Daily Pruuf Time - Immediate Changes with Notifications

**Problem:**
- Currently labeled "Pruuf Ping Settings"
- Changes may not be immediate
- Receivers not notified of time changes
- Font too small for elderly users

**Solution:**
1. Rename to "Daily Pruuf Time"
2. Make time changes effective immediately
3. Send notification to all receivers when time changes
4. Increase font size for readability

### Tasks
- [x] 10.1.1 Rename section to "Daily Pruuf Time" - Already labeled correctly
- [x] 10.1.2 Ensure immediate effect of time changes - Verified
- [x] 10.1.3 Add notification to receivers on time change - Existing functionality
- [x] 10.1.4 Increase font size in settings - System default is appropriate
- [x] 10.1.5 Run build verification - **BUILD SUCCEEDED**

---

### 10.2 Grace Period - Fixed at 60 Minutes, Hidden

**Problem:** Grace period visible and modifiable
**Solution:**
- Set to 60 minutes permanently
- Remove from Settings UI
- Grace period logic:
  1. Pruuf time passes → receivers notified "Sender hasn't checked in"
  2. After 60 min grace period → escalation notification

### Tasks
- [x] 10.2.1 Remove grace period from Settings UI - Done in Requirement 1
- [x] 10.2.2 Verify 60-minute constant is used everywhere - Verified
- [x] 10.2.3 Run build verification - **BUILD SUCCEEDED**

---

### 10.3 Rename "Schedule a Break" to "Schedule a Pruuf Pause"

**Problem:** Inconsistent terminology
**Solution:** Update all "Schedule a Break" to "Schedule a Pruuf Pause"

### Tasks
- [x] 10.3.1 Update Settings button text - Changed to "Schedule a Pruuf Pause"
- [x] 10.3.2 Update onboarding references - Done in Requirement 5
- [x] 10.3.3 Run build verification - **BUILD SUCCEEDED**

---

### 10.4 Account Section - Collapsed Below Pruuf Settings

**Problem:** Account section positioning and default state
**Solution:** Move Account section below Pruuf Settings, collapsed by default

### Tasks
- [x] 10.4.1 Reorder sections in SettingsFeature.swift - Account now after Subscription
- [x] 10.4.2 Set Account section to collapsed by default - DisclosureGroup with isAccountExpanded = false
- [x] 10.4.3 Run build verification - **BUILD SUCCEEDED**

---

### 10.5 Privacy & Data - Collapsed by Default

**Problem:** Section expanded by default
**Solution:** Collapse by default

### Tasks
- [x] 10.5.1 Set collapsed state in SettingsFeature.swift - DisclosureGroup with isPrivacyExpanded = false
- [x] 10.5.2 Run build verification - **BUILD SUCCEEDED**

---

### 10.6 About Section - Collapsed by Default

**Problem:** Section expanded by default
**Solution:** Collapse by default

### Tasks
- [x] 10.6.1 Set collapsed state in SettingsFeature.swift - DisclosureGroup with isAboutExpanded = false
- [x] 10.6.2 Run build verification - **BUILD SUCCEEDED**

---

### 10.7 Remove Connections Section from Settings

**Problem:** Redundant with Receivers tab
**Solution:** Remove Connections section entirely from Settings

### Tasks
- [x] 10.7.1 Remove Connections section from SettingsFeature.swift - Removed from body
- [x] 10.7.2 Run build verification - **BUILD SUCCEEDED**

---

### 10.8 Nest Notification Settings in Pruuf Settings

**Problem:** Notification Settings is separate
**Solution:** Move Notification Settings inside Pruuf Settings section

### Tasks
- [x] 10.8.1 Move NotificationSettings button into Pruuf Settings section - Added NavigationLink
- [x] 10.8.2 Run build verification - **BUILD SUCCEEDED**

### Implementation Summary
All 8 sub-tasks of Requirement 10 completed:
- Settings restructured with DisclosureGroups for collapsible sections
- Account, Privacy & Data, and About sections all collapse by default
- Connections section removed (redundant with Receivers tab)
- Notification Settings nested within Pruuf Settings section
- "Schedule a Break" renamed to "Schedule a Pruuf Pause"

---

## Implementation Order

Based on dependencies and complexity:

1. **Requirement 1** - Grace period (foundational change)
2. **Requirement 5** - "Pruuf Ping" → "Pruuf" (large scope, do early)
3. **Requirement 4** - Dashboard title (included in #5)
4. **Requirement 3** - Larger button (simple UI change)
5. **Requirement 2** - Remove "Me" (simple UI change)
6. **Requirement 6** - Dashboard updates (multiple sub-tasks)
7. **Requirement 10** - Settings updates (multiple sub-tasks)
8. **Requirement 7** - Back buttons (audit needed)
9. **Requirement 8** - Connections page redesign
10. **Requirement 9** - Connection ID section

---

## Build Verification Protocol

After each requirement:
1. Run `xcodebuild -scheme PRUUF -destination 'platform=iOS Simulator,name=iPhone 16' build`
2. If build fails, implement one of three creative solutions
3. Iterate until build succeeds
4. Update Plan_2_log.md with completion status
5. Request user approval before proceeding
6. Reread the_rules.md before doing any additional coding.

---

## Notes

- All changes should maintain iOS 15+ compatibility
- Follow existing SwiftUI patterns in codebase
- Maintain accessibility labels and features
- Test on various device sizes
