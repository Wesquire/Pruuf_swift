# PRUUF Enhancement Plan 4 - Comprehensive Implementation Plan

## Overview
This plan addresses 12 requirements focused on restructuring the receiver invitation flow, dashboard UI, and settings page. The primary changes involve:
- Reworking how senders invite receivers (address book selection → text notification with unique code)
- Restructuring the sender dashboard UI
- Modifying the settings page
- Cleaning up unused UI elements

---

## Requirement 1: Rework Receiver Invitation Flow

### Current State
- Sender enters receiver's 6-digit code manually
- Connection is made via code lookup in `AddConnectionView`

### Target State
- Sender selects phone numbers from address book
- Selected receivers receive TEXT notification with sender's unique code
- Receivers use sender's code to connect

### Implementation Plan

#### 1.1 Create Address Book Contact Picker
**File:** `PRUUF/Features/Connections/ContactPickerView.swift` (NEW)
- Import `ContactsUI` framework
- Create `ContactPickerView` using `CNContactPickerViewController`
- Allow multi-select for phone numbers
- Return array of selected phone numbers

#### 1.2 Modify InvitationService for SMS
**File:** `PRUUF/Core/Services/InvitationService.swift`
- Add method `sendInvitationSMS(to phoneNumbers: [String], senderCode: String)`
- Use `MFMessageComposeViewController` for SMS
- SMS content: "Hi! I'd like you to be my Pruuf receiver. Download PRUUF and use my code: [SENDER_CODE] to connect. [APP_STORE_LINK]"

#### 1.3 Update AddConnectionView Flow
**File:** `PRUUF/Features/Connections/ConnectionsFeature.swift`
- Replace code entry UI with contact picker
- After selection, trigger SMS invitation
- Create pending connection records for invited receivers

#### 1.4 Create Edge Function for SMS (Optional - if using Twilio)
**File:** `supabase/functions/send-invitation-sms/index.ts`
- Alternative to device SMS using Twilio
- Handles bulk SMS sending

---

## Requirement 2: Sender's Unique Code Visibility

### Current State
- Sender's invitation code exists in `sender_profiles.invitation_code`
- Code shown in Receivers tab (collapsible)

### Target State
- Collapsed button showing sender's code on ALL screens where sender selects receivers
- Code explains purpose and allows easy copying

### Implementation Plan

#### 2.1 Create Reusable SenderCodeBadge Component
**File:** `PRUUF/Core/Components/SenderCodeBadge.swift` (NEW)
- Collapsible button component
- Shows "My Connection Code" when collapsed
- Expands to show 6-digit code with copy button
- Explanatory text about sharing code

#### 2.2 Add SenderCodeBadge to Key Screens
- `SenderDashboardView.swift` - In receivers section
- `ConnectionsPlaceholderView` (Receivers tab) - Already has it
- `AddConnectionView` - When inviting receivers

---

## Requirement 3: Sender Workflow Restructure

### Complete Flow
1. Sender logs in with phone → confirmed via notification
2. Sender selects potential receivers from address book
3. Creates unique sender connection code
4. Sends text notification to selected receivers with code
5. Sender views connection status in Receivers tab
6. Visual indicator for confirmed vs pending
7. Option to "nudge" unconfirmed receivers
8. Collapsed "My Connection Code" button visible

### Implementation Plan

#### 3.1 Connection Status Visual Indicators
**File:** `PRUUF/Features/Dashboard/DashboardFeature.swift`
- Update `ReceiverListRowView` to show clear status badges
- Green checkmark for connected
- Orange clock for pending
- Add "Nudge" button for pending receivers

#### 3.2 Nudge Functionality
**File:** `PRUUF/Core/Services/InvitationService.swift`
- Add `nudgeReceiver(receiverId: UUID, senderCode: String)` method
- Resends SMS invitation
- Rate limiting: max 1 nudge per 24 hours per receiver

#### 3.3 Update Connection States
**Database:** Check `connections` table has `pending` status
- Pending: Invitation sent, not accepted
- Active: Receiver accepted invitation
- Paused: Temporarily disabled
- Deleted: Removed

---

## Requirement 4: Remove "+ Add Receivers" from Dashboard

### Current State
- `addReceiverButton` exists in `SenderDashboardView.swift` (lines 445-457)

### Implementation Plan
**File:** `PRUUF/Features/Dashboard/SenderDashboard/SenderDashboardView.swift`
- Remove `addReceiverButton` computed property
- Remove call to `addReceiverButton` in `receiversSection`

---

## Requirement 5: Fix "Invite Receivers" Flow

### Current State
- Takes user to code entry screen

### Target State
- Takes user directly to phone contact picker
- Multi-select receivers from address book
- Already-connected receivers should NOT be selectable

### Implementation Plan
**File:** `PRUUF/Features/Connections/ConnectionsFeature.swift`
- Modify flow to skip code entry
- Go directly to contact picker
- Filter out already-connected phone numbers

---

## Requirement 6: Restructure "Your Receivers" Section

### Current State
- Lists all receivers with expand/collapse

### Target State
- Only two buttons: "View Receivers" and "Invite Receivers"
- Text for entering receiver's code (if sender received code from receiver)

### Implementation Plan

#### 6.1 Update receiversSection
**File:** `PRUUF/Features/Dashboard/SenderDashboard/SenderDashboardView.swift`
- Replace receiver list with two action buttons
- Add text and button for entering receiver's code

#### 6.2 Create ReceiverCodeEntryView
**File:** `PRUUF/Features/Connections/ReceiverCodeEntryView.swift` (NEW)
- Modal for sender to enter receiver's unique code
- Explains the reverse connection flow
- 6-digit code entry with validation

---

## Requirement 7: Move Quick Actions to Dashboard Settings Section

### Current State
- Quick Actions sheet with "Change Pruuf Time" and "Schedule a Pruuf Pause"

### Target State
- New "Settings" section on dashboard (collapsible, default open)
- Contains the two action items directly

### Implementation Plan
**File:** `PRUUF/Features/Dashboard/SenderDashboard/SenderDashboardView.swift`
- Remove `quickActionsButton` and `QuickActionsSheet`
- Add new `settingsSection` with DisclosureGroup
- Include "Change Pruuf Time" and "Schedule a Pruuf Pause" buttons
- Default expanded state

---

## Requirement 8: Remove "+ Receivers" Button from Section

### Current State
- Button at bottom left of "Your Receivers" section

### Implementation Plan
**File:** `PRUUF/Features/Dashboard/SenderDashboard/SenderDashboardView.swift`
- Remove `addReceiverButton` from `receiversSection`
- (Overlaps with Requirement 4)

---

## Requirement 9: Dashboard Layout Restructure

### Target Layout
1. **Ping Section**: "Time to send your pruuf" with large blue button
   - Caption: "Tap the Pruuf Ping button to let your receivers know that you're ok"
2. **Your Receivers Section**:
   - "See My Receivers" button → Receivers tab
   - "Invite Receivers" button → Contact picker
3. **Receivers Page Updates**:
   - Show accepted and pending users
   - Reminder option for pending users
   - Scrollable list
   - "I received a code" section with modal explanation

### Implementation Plan

#### 9.1 Update todayPingCard Caption
**File:** `SenderDashboardView.swift`
- Update caption text to specified wording

#### 9.2 Restructure receiversSection
**File:** `SenderDashboardView.swift`
- Two main action buttons
- "I received a code" button with modal

#### 9.3 Update ConnectionsPlaceholderView
**File:** `DashboardFeature.swift`
- Show status badges (accepted/pending)
- Add reminder buttons for pending
- Make list scrollable in box
- Add "I received a code" modal

---

## Requirement 10: Settings Page Restructure

### Changes Required

#### 10.1 Pruuf Settings
- Keep Daily Pruuf Time (make visually clear it's changeable)
- REMOVE "Enable Pruufs" toggle
- Schedule a Pruuf Pause: clarify start/end date flow

#### 10.2 Notification Settings
- All sections collapsed by default
- Master Control at BOTTOM
- Remove "System Permission"
- Rename "Deadline Warning" → "Deadline Passed" (after 60-min grace)
- Hide "Receiver Notifications" for sender-only users
- Gray out payment reminders for senders with note

#### 10.3 Per-Sender Settings
- REMOVE entirely

#### 10.4 Quiet Hours
- REMOVE entirely

#### 10.5 Subscription Settings
- Gray out for sender-only users with "free" message

### Implementation Plan
**Files:**
- `PRUUF/Features/Settings/SettingsFeature.swift`
- `PRUUF/Features/Settings/NotificationSettingsView.swift`

---

## Requirement 11: Remove "Their Pruufs" Tab

### Current State
- DualRoleDashboardView has "My Pruufs" and "Their Pruufs" tabs

### Implementation Plan
**File:** `PRUUF/Features/Dashboard/DashboardFeature.swift`
- Remove "Their Pruufs" tab from DualRoleDashboardView
- Simplify to single view for dual-role users

---

## Requirement 12: Build Verification

### Process
- Run clean build after all changes
- If errors occur:
  1. Analyze error messages
  2. Propose 3 creative solutions
  3. Implement best solution
  4. Repeat until success

---

## Implementation Order

1. **Requirement 4 & 8**: Remove "+ Add Receivers" buttons (quick wins)
2. **Requirement 7**: Move Quick Actions to Settings section
3. **Requirement 6**: Restructure "Your Receivers" section
4. **Requirement 9**: Complete dashboard layout restructure
5. **Requirement 11**: Remove "Their Pruufs" tab
6. **Requirement 10**: Settings page restructure
7. **Requirement 2**: Create SenderCodeBadge component
8. **Requirement 1**: Address book contact picker
9. **Requirement 5**: Fix invite receivers flow
10. **Requirement 3**: Complete workflow with nudge functionality
11. **Requirement 12**: Final build verification

---

## Files to Modify

| File | Requirements |
|------|--------------|
| SenderDashboardView.swift | 4, 6, 7, 8, 9 |
| DashboardFeature.swift | 3, 9, 11 |
| ConnectionsFeature.swift | 1, 5 |
| SettingsFeature.swift | 10 |
| NotificationSettingsView.swift | 10 |
| InvitationService.swift | 1, 3 |

## New Files to Create

| File | Purpose |
|------|---------|
| ContactPickerView.swift | Address book contact selection |
| SenderCodeBadge.swift | Reusable code display component |
| ReceiverCodeEntryView.swift | Modal for entering receiver's code |

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| SMS permissions on iOS | Use native MFMessageComposeViewController |
| Contact picker privacy | Request permission with clear explanation |
| Breaking existing connections | Migration path for existing users |
| Build errors | 3-solution approach for each error |

---

## Session Tracking

Each requirement will be completed in sequence with:
1. Implementation
2. Build verification
3. User approval before proceeding
