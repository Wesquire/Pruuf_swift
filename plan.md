# PRUUF - Product Requirements Document
**Version:** 1.0
**Date:** January 16, 2026
**Product:** PRUUF iOS Mobile Application
**Platform:** iOS (Swift)
**Backend:** Supabase (PostgreSQL, Edge Functions, Auth, Storage)

---

## Document Overview

This Product Requirements Document (PRD) provides comprehensive specifications for building the PRUUF iOS mobile application. PRUUF is a daily check-in system that provides peace of mind through simple, reliable communication between Senders (people checking in) and Receivers (people being checked on).

**Core Principle:** "Peace of mind with one tap"

**Key Features:**
Phone number authentication via SMS, Role-based system (Sender/Receiver), Daily ping scheduling with customizable times, Directional connections using unique 6-digit codes, In-person verification option, Scheduled breaks/pauses, Real-time notifications, Subscription model: $2.99/month for receiver-only users (senders always free), 15-day free trial period, Admin dashboard for operations.

**Document Structure:**
This PRD is organized into phases representing logical implementation groupings. Each phase contains detailed specifications, technical requirements, user flows, and acceptance criteria. All user stories are included at the end of each relevant phase.

---

## PHASE 1: Project Setup & Configuration

### 1.1 Supabase Configuration
- Configure Supabase Project with URL: https://oaiteiceynliooxpeuxt.supabase.co
- Set Anon Public Key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9haXRlaWNleW5saW9veHBldXh0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg1MzA0MzEsImV4cCI6MjA4NDEwNjQzMX0.Htm_jL8JbLK2jhVlCUL0A7m6PJVY_ZuBx3FqZDZrtgk
- Initialize Supabase client in iOS Swift project
- Configure authentication providers (Phone/SMS)
- Enable Row Level Security (RLS) on all tables
- Set up Edge Functions for business logic
- Configure Storage buckets (if needed for profile pictures)
- Set up scheduled jobs for ping monitoring
- Configure webhooks for payment processing

### 1.2 iOS Project Setup
- Set Minimum iOS Version: iOS 15.0+
- Configure Language: Swift 5.9+
- Implement Architecture: MVVM (Model-View-ViewModel)
- Use Package Manager: Swift Package Manager (SPM)
- Add Supabase Swift SDK dependency from https://github.com/supabase/supabase-swift.git version 2.0.0+
- Add KeychainSwift for secure token storage
- Add SwiftUI Charts for analytics dashboard
- Create project folder structure: App/, Core/, Features/, Shared/, Resources/
- Create PruufApp.swift and AppDelegate.swift in App/
- Create Config/, Services/, Models/ folders in Core/
- Create SupabaseConfig.swift in Core/Config/
- Create AuthService.swift, PingService.swift, ConnectionService.swift, NotificationService.swift in Core/Services/
- Create User.swift, Connection.swift, Ping.swift, Break.swift in Core/Models/
- Create Authentication/, Onboarding/, Dashboard/, Connections/, Settings/, Subscription/ folders in Features/
- Create Components/, Extensions/, Utilities/ folders in Shared/
- Create Assets.xcassets and Info.plist in Resources/

### 1.3 Development Environment
- Install Xcode 15.0+
- Configure Apple Developer Account for push notifications and TestFlight
- Install Supabase CLI locally for edge function development
- Set up Git version control
- Create Config.swift with environment enum (development, staging, production)
- Configure supabaseURL and supabaseAnonKey in Config.swift

### 1.4 Admin Dashboard Credentials
- Set Admin Email: wesleymwilliams@gmail.com
- Set Admin Password: W@$hingt0n1
- Configure Role: Super Admin
- Grant Permissions: Full system access, analytics dashboard, user management, payment oversight

---

## PHASE 2: Database Schema & Row Level Security

### 2.1 Database Tables
- Create users table with columns: id (UUID PRIMARY KEY), phone_number (TEXT UNIQUE NOT NULL), phone_country_code (TEXT DEFAULT '+1'), created_at, updated_at, last_seen_at, is_active (BOOLEAN DEFAULT true), has_completed_onboarding (BOOLEAN DEFAULT false), primary_role (TEXT CHECK sender/receiver/both), timezone (TEXT DEFAULT 'UTC'), device_token (TEXT), notification_preferences (JSONB)
- Create index idx_users_phone on users(phone_number)
- Create index idx_users_active on users(is_active) WHERE is_active = true
- Create sender_profiles table with columns: id (UUID PRIMARY KEY), user_id (UUID REFERENCES users), ping_time (TIME NOT NULL), ping_enabled (BOOLEAN DEFAULT true), created_at, updated_at, UNIQUE(user_id)
- Create index idx_sender_profiles_user on sender_profiles(user_id)
- Create receiver_profiles table with columns: id (UUID PRIMARY KEY), user_id (UUID REFERENCES users), subscription_status (TEXT CHECK trial/active/past_due/canceled/expired DEFAULT 'trial'), subscription_start_date, subscription_end_date, trial_start_date (DEFAULT now()), trial_end_date (DEFAULT now() + 15 days), stripe_customer_id, stripe_subscription_id, created_at, updated_at, UNIQUE(user_id)
- Create index idx_receiver_profiles_user on receiver_profiles(user_id)
- Create index idx_receiver_profiles_subscription on receiver_profiles(subscription_status)
- Create index idx_receiver_profiles_stripe on receiver_profiles(stripe_customer_id)
- Create unique_codes table with columns: id (UUID PRIMARY KEY), code (TEXT UNIQUE NOT NULL CHECK 6-digit), receiver_id (UUID REFERENCES users), created_at, expires_at, is_active (BOOLEAN DEFAULT true), UNIQUE(receiver_id)
- Create index idx_unique_codes_code on unique_codes(code) WHERE is_active = true
- Create index idx_unique_codes_receiver on unique_codes(receiver_id)
- Create connections table with columns: id (UUID PRIMARY KEY), sender_id (UUID REFERENCES users), receiver_id (UUID REFERENCES users), status (TEXT CHECK pending/active/paused/deleted DEFAULT 'active'), created_at, updated_at, deleted_at, connection_code, UNIQUE(sender_id, receiver_id)
- Create index idx_connections_sender on connections(sender_id) WHERE status = 'active'
- Create index idx_connections_receiver on connections(receiver_id) WHERE status = 'active'
- Create index idx_connections_status on connections(status)
- Create pings table with columns: id (UUID PRIMARY KEY), connection_id (UUID REFERENCES connections), sender_id (UUID REFERENCES users), receiver_id (UUID REFERENCES users), scheduled_time (TIMESTAMPTZ NOT NULL), deadline_time (TIMESTAMPTZ NOT NULL), completed_at, completion_method (TEXT CHECK tap/in_person/auto_break), status (TEXT CHECK pending/completed/missed/on_break DEFAULT 'pending'), created_at, verification_location (JSONB), notes
- Create index idx_pings_connection on pings(connection_id)
- Create index idx_pings_sender on pings(sender_id)
- Create index idx_pings_receiver on pings(receiver_id)
- Create index idx_pings_status on pings(status)
- Create index idx_pings_scheduled on pings(scheduled_time) WHERE status = 'pending'
- Create breaks table with columns: id (UUID PRIMARY KEY), sender_id (UUID REFERENCES users), start_date (DATE NOT NULL), end_date (DATE NOT NULL), created_at, status (TEXT CHECK scheduled/active/completed/canceled DEFAULT 'scheduled'), notes, CHECK (end_date >= start_date)
- Create index idx_breaks_sender on breaks(sender_id)
- Create index idx_breaks_dates on breaks(start_date, end_date) WHERE status IN ('scheduled', 'active')
- Create notifications table with columns: id (UUID PRIMARY KEY), user_id (UUID REFERENCES users), type (TEXT CHECK ping_reminder/deadline_warning/missed_ping/connection_request/payment_reminder/trial_ending NOT NULL), title (TEXT NOT NULL), body (TEXT NOT NULL), sent_at (DEFAULT now()), read_at, metadata (JSONB), delivery_status (TEXT CHECK sent/failed/pending DEFAULT 'sent')
- Create index idx_notifications_user on notifications(user_id)
- Create index idx_notifications_sent on notifications(sent_at DESC)
- Create index idx_notifications_type on notifications(type)
- Create audit_logs table with columns: id (UUID PRIMARY KEY), user_id (UUID REFERENCES users ON DELETE SET NULL), action (TEXT NOT NULL), resource_type, resource_id, details (JSONB), ip_address (INET), user_agent, created_at
- Create index idx_audit_logs_user on audit_logs(user_id)
- Create index idx_audit_logs_created on audit_logs(created_at DESC)
- Create index idx_audit_logs_action on audit_logs(action)
- Create payment_transactions table with columns: id (UUID PRIMARY KEY), user_id (UUID REFERENCES users), stripe_payment_intent_id, amount (DECIMAL(10,2) NOT NULL), currency (TEXT DEFAULT 'USD'), status (TEXT CHECK pending/succeeded/failed/refunded DEFAULT 'pending'), transaction_type (TEXT CHECK subscription/refund/chargeback), created_at, metadata (JSONB)
- Create index idx_payment_transactions_user on payment_transactions(user_id)
- Create index idx_payment_transactions_status on payment_transactions(status)
- Create index idx_payment_transactions_stripe on payment_transactions(stripe_payment_intent_id)

### 2.2 Row Level Security Policies
- Enable RLS on users table with ALTER TABLE users ENABLE ROW LEVEL SECURITY
- Enable RLS on sender_profiles table
- Enable RLS on receiver_profiles table
- Enable RLS on unique_codes table
- Enable RLS on connections table
- Enable RLS on pings table
- Enable RLS on breaks table
- Enable RLS on notifications table
- Enable RLS on audit_logs table
- Enable RLS on payment_transactions table
- Create policy "Users can view own profile" ON users FOR SELECT USING (auth.uid() = id)
- Create policy "Users can update own profile" ON users FOR UPDATE USING (auth.uid() = id)
- Create policy "Admin can view all users" ON users FOR SELECT for admin users
- Create policy "Senders can view own profile" ON sender_profiles FOR SELECT USING (user_id = auth.uid())
- Create policy "Senders can update own profile" ON sender_profiles FOR UPDATE USING (user_id = auth.uid())
- Create policy "Senders can insert own profile" ON sender_profiles FOR INSERT WITH CHECK (user_id = auth.uid())
- Create policy "Receivers can view own profile" ON receiver_profiles FOR SELECT USING (user_id = auth.uid())
- Create policy "Receivers can update own profile" ON receiver_profiles FOR UPDATE USING (user_id = auth.uid())
- Create policy "Receivers can insert own profile" ON receiver_profiles FOR INSERT WITH CHECK (user_id = auth.uid())
- Create policy "Receivers can view own code" ON unique_codes FOR SELECT USING (receiver_id = auth.uid())
- Create policy "Anyone can lookup active codes" ON unique_codes FOR SELECT USING (is_active = true)
- Create policy "Users can view own connections" ON connections FOR SELECT USING (sender_id = auth.uid() OR receiver_id = auth.uid())
- Create policy "Users can create connections as sender" ON connections FOR INSERT WITH CHECK (sender_id = auth.uid())
- Create policy "Users can update own connections" ON connections FOR UPDATE USING (sender_id = auth.uid() OR receiver_id = auth.uid())
- Create policy "Users can delete own connections" ON connections FOR DELETE USING (sender_id = auth.uid() OR receiver_id = auth.uid())
- Create policy "Users can view own pings" ON pings FOR SELECT USING (sender_id = auth.uid() OR receiver_id = auth.uid())
- Create policy "Senders can update own pings" ON pings FOR UPDATE USING (sender_id = auth.uid())
- Create policy "Senders can view own breaks" ON breaks FOR SELECT USING (sender_id = auth.uid())
- Create policy "Senders can create own breaks" ON breaks FOR INSERT WITH CHECK (sender_id = auth.uid())
- Create policy "Senders can update own breaks" ON breaks FOR UPDATE USING (sender_id = auth.uid())
- Create policy "Senders can delete own breaks" ON breaks FOR DELETE USING (sender_id = auth.uid())
- Create policy "Users can view own notifications" ON notifications FOR SELECT USING (user_id = auth.uid())
- Create policy "Users can update own notifications" ON notifications FOR UPDATE USING (user_id = auth.uid())
- Create policy "Users can view own audit logs" ON audit_logs FOR SELECT USING (user_id = auth.uid())
- Create policy "Admin can view all audit logs" ON audit_logs FOR SELECT for admin users
- Create policy "Users can view own transactions" ON payment_transactions FOR SELECT USING (user_id = auth.uid())

### 2.3 Database Functions
- Create function generate_unique_code() that returns TEXT, generates 6-digit numeric code, checks for uniqueness against active codes, loops until unique code found
- Create function create_receiver_code(p_user_id UUID) that returns TEXT, calls generate_unique_code(), inserts code into unique_codes table, returns the new code
- Create function check_subscription_status(p_user_id UUID) that returns TEXT, checks trial_end_date and subscription_end_date, updates subscription_status to 'expired' if needed, returns current status
- Create function update_updated_at() as TRIGGER that sets NEW.updated_at = now()
- Create trigger users_updated_at BEFORE UPDATE ON users executing update_updated_at()
- Create trigger sender_profiles_updated_at BEFORE UPDATE ON sender_profiles executing update_updated_at()
- Create trigger receiver_profiles_updated_at BEFORE UPDATE ON receiver_profiles executing update_updated_at()
- Create trigger connections_updated_at BEFORE UPDATE ON connections executing update_updated_at()

---

## PHASE 3: Authentication & Onboarding

### 3.1 Authentication Flow
- Implement Phone Number + SMS OTP authentication using Supabase Auth
- On app launch check for existing session (Supabase Auth token in Keychain)
- If no session show Phone Number Entry screen with country code picker
- Send OTP via Supabase Auth signInWithOTP(phone:)
- Display 6-digit OTP code entry screen
- Verify OTP with Supabase Auth verifyOTP(phone:token:type:.sms)
- On successful verification create or retrieve user record in users table
- Check has_completed_onboarding flag to determine redirect destination
- If false redirect to Role Selection screen
- If true redirect to Dashboard
- Implement AuthService class with sendOTP, verifyOTP, fetchOrCreateUser methods
- Store auth token securely in iOS Keychain

### 3.2 Role Selection Screen
- Display title "How will you use PRUUF?" with subtitle "You can always add the other role later"
- Create Sender Card with checkmark icon, title "I want to check in daily", description "Let people know you're okay with a simple daily ping", tag "Always Free"
- Create Receiver Card with heart icon, title "I want peace of mind", description "Get daily confirmation that your loved ones are safe", tag "$2.99/month after 15-day trial"
- Allow only ONE option selection initially
- Highlight selected card with accent color
- Show "Continue" button at bottom after selection
- On continue update users.primary_role to selected role
- Create sender_profiles OR receiver_profiles record based on selection
- Redirect to role-specific onboarding flow
- Handle edge case EC-2.1: Save progress if user closes app mid-onboarding, resume on relaunch
- Handle edge case EC-2.2: Show option to add both roles after selecting first role

### 3.3 Sender Onboarding Flow
- Display Tutorial Screen Step 1 with title "How PRUUF Works for Senders"
- Show 3-4 tutorial slides: "Set your daily ping time", "Tap once to confirm you're okay", "Connect with people who care about you", "Take breaks when needed"
- Add Skip button in top right corner
- Add Next/Done button at bottom
- Display Ping Time Selection Step 2 with title "When should we remind you to ping?"
- Show iOS native wheel time picker with default 9:00 AM local time
- Display example "You'll have until 10:30 AM to check in (90-minute grace period)"
- Add Continue button
- Convert local time to UTC for storage in sender_profiles.ping_time
- Display Connection Invitation Step 3 with title "Invite people to receive your pings"
- Show "Select Contacts" button with iOS native contact picker
- Generate SMS with invitation message including sender name, 6-digit code, and app download link
- Add "Skip for Now" option
- Display Notification Permission Step 4 with system prompt
- Explain "Get reminders when it's time to ping"
- Request push notification permission using iOS native prompt
- Display Complete Step 5 with title "You're all set!"
- Show summary: Daily ping time and number of connections invited
- Add "Go to Dashboard" button
- Set has_completed_onboarding = true on completion

### 3.4 Receiver Onboarding Flow
- Display Tutorial Screen Step 1 with title "How PRUUF Works for Receivers"
- Show 3-4 tutorial slides: "Get daily pings from loved ones", "Know they're safe and sound", "Get notified if they miss a ping", "Connect using their unique code"
- Add Skip button in top right corner
- Add Next/Done button at bottom
- Display Your Unique Code Step 2 with title "Your PRUUF Code"
- Generate 6-digit code via create_receiver_code() function
- Display code in large readable font
- Add "Copy Code" button and "Share Code" button (iOS share sheet)
- Show explanation "Senders will use this code to connect with you"
- Display Connect to Sender Step 3 (Optional) with title "Do you have a sender's code?"
- Show 6-digit code entry field
- Add "Connect" button and "Skip for Now" option
- On successful connection verify code exists and is active, create connection record, show success message
- Display Subscription Explanation Step 4 with title "15 Days Free, Then $2.99/Month"
- List benefits: Unlimited sender connections, Real-time ping notifications, Peace of mind 24/7, Cancel anytime
- Show "Your free trial starts now" message with Continue button
- Display Notification Permission Step 5 with system prompt
- Explain "Get notified when senders ping you"
- Request push notification permission using iOS native prompt
- Display Complete Step 6 with title "You're all set!"
- Show summary: Your code, Trial ends date, Connections count
- Add "Go to Dashboard" button
- Set has_completed_onboarding = true on completion

### 3.5 User Stories Authentication and Onboarding
- US-1.1 Phone Number Authentication: Implement phone number entry screen with country code picker, send SMS OTP within 30 seconds, display 6-digit OTP entry with auto-fill support, persist session in secure keychain, add "Resend Code" option after 60 seconds, handle invalid phone numbers and network failures
- US-1.2 Role Selection: Create clear card-based UI showing both roles, display pricing information for Receiver role, show "Always Free" badge on Sender role, allow only one role selectable initially, persist selection to database, create appropriate profile record
- US-1.3 Sender Onboarding: Create tutorial screens with skip option, implement time picker for daily ping time, explain grace period (90 minutes), create contact invitation with SMS pre-populated, request notification permission, show completion confirmation screen, set has_completed_onboarding flag to true
- US-1.4 Receiver Onboarding: Create tutorial screens with skip option, generate and display 6-digit unique code, implement copy/share code functionality, add optional sender code entry, explain subscription (15 days free, $2.99/month), request notification permission, show completion confirmation screen, set has_completed_onboarding flag to true
- US-1.5 Session Persistence: Store auth token securely in iOS Keychain, implement automatic session restoration on app launch, handle token refresh automatically, clear all session data on logout, expire session after 30 days of inactivity

---

## PHASE 4: Dashboard & UI Components

### 4.1 Sender Dashboard
- Create Header Section with user name, settings icon (top right), and current time display
- Create Today's Ping Status Card as large central card
- Implement Pending State: title "Time to Ping!", countdown timer, large "I'm Okay" button in primary accent color, subtitle "Tap to let everyone know you're safe"
- Implement Completed State: green checkmark icon, title "Ping Sent!", time completed, subtitle "See you tomorrow"
- Implement Missed State: red alert icon, title "Ping Missed", time missed, "Ping Now" button for late submission
- Implement On Break State: calendar icon, title "On Break", break period display, "End Break Early" button
- Create In-Person Verification Button below ping card with location pin icon, text "Verify In Person", available at any time, request location permission on first use
- Create Your Receivers Section with title and count badge, scrollable list showing name/status/last interaction for each receiver, "+ Add Receiver" button, empty state message
- Create Recent Activity section showing last 7 days of ping history as calendar view with colored dots (green=on time, yellow=late, red=missed, gray=break), tap for details
- Create Quick Actions Bottom Sheet with "Schedule a Break", "Change Ping Time", "Invite Receivers", "Settings" options

### 4.2 Receiver Dashboard
- Create Header Section with user name, settings icon (top right), subscription status badge
- Create Your Senders Section with title and count badge, scrollable sender cards
- Display each sender card with: name, ping status (green checkmark/yellow clock/red alert/gray calendar), ping streak, action menu button
- Add "+ Connect to Sender" button at bottom
- Show empty state with code display and copy/share options
- Create Your PRUUF Code Card always visible with 6-digit code in large font, Copy button, Share button, "How to use" info icon
- Create Recent Activity section as timeline view of all sender pings, last 7 days default, filter by sender option
- Create Subscription Status Card showing trial countdown OR billing date OR expired alert with appropriate CTAs
- Create Quick Actions with "Share My Code", "Connect to Sender", "Manage Subscription", "Settings" options

### 4.3 Dual Role Dashboard
- Implement Tab Navigation with two tabs: "My Pings" and "Their Pings"
- Display Sender Dashboard in "My Pings" tab
- Display Receiver Dashboard in "Their Pings" tab
- Add badge notifications on tabs for missed pings or pending actions
- Apply subscription logic: If user has ANY receiver connections, subscription required; Sender functionality always remains free

### 4.4 UI Design Specifications
- Set Primary color to #007AFF (iOS Blue)
- Set Success color to #34C759 (iOS Green)
- Set Warning color to #FF9500 (iOS Orange)
- Set Error color to #FF3B30 (iOS Red)
- Set Background color to #F2F2F7 (iOS Gray 6 - Light Mode)
- Set Card Background to #FFFFFF
- Set Text Primary to #000000
- Set Text Secondary to #8E8E93
- Implement Dark Mode Support with system color adaptation
- Use SF Pro Display Bold for headings
- Use SF Pro Text Regular for body
- Use SF Pro Text Light for captions
- Use SF Mono Medium for 6-digit codes
- Set screen padding to 16pt, card padding to 16pt, element spacing to 12pt, section spacing to 24pt
- Implement button press animation with scale 0.95 and haptic feedback
- Use slide up/down with ease-in-out for card transitions
- Show iOS spinner with blur background for loading states
- Add confetti or checkmark animation for success states
- Set minimum touch target to 44x44 pt
- Support Dynamic Type for text sizing
- Add VoiceOver labels on all interactive elements
- Maintain color contrast ratio 4.5:1 minimum
- Support reduce motion for animations

### 4.5 Loading States and Empty States
- Implement full screen loading with iOS spinner centered with blur
- Use skeleton screens for inline card loading
- Add standard iOS pull-to-refresh
- Do not use progressive content loading (per user preference)
- Create No Receivers empty state for Sender with illustration, title "No receivers yet", message "Invite people to give them peace of mind", "Invite Receivers" button
- Create No Senders empty state for Receiver with illustration, title "No senders yet", message with code display, "Copy Code" and "Share Code" buttons
- Create No Activity empty state with calendar illustration, title "No activity yet", message "Your ping history will appear here"
- Create Network Error state with disconnected icon, title "Connection lost", message "Check your internet and try again", "Retry" button

### 4.6 User Stories Dashboard and UI
- US-4.1 Sender Dashboard View: Show ping status card with pending/completed/missed state, display countdown timer for time remaining, prominently display "I'm Okay" button, show all active connections in receivers list, display last 7 days in recent activity, support pull to refresh, use proper blocking UI for loading states
- US-4.2 Receiver Dashboard View: Show all connections in senders list, display current ping status on each sender card, use visual indicators (green/yellow/red) for status, display ping streaks for each sender, make unique code easily accessible, show subscription status, display empty state when no senders connected
- US-4.3 In-Person Verification: Make "Verify In Person" button always visible on dashboard, request location permission on first use, capture and store location with ping, mark ping as completed with "in_person" method, allow verification before scheduled ping time, notify receivers of in-person verification
- US-4.4 Dual Role Navigation: Implement tab navigation at top of screen, show sender dashboard in "My Pings" tab, show receiver dashboard in "Their Pings" tab, add badge notifications on tabs for urgent items, create smooth tab transitions, maintain scroll position in each tab
- US-4.5 Responsive Loading: Show full-screen spinner for initial load, use skeleton screens for cards during refresh, support pull-to-refresh on main dashboard, do not use progressive content loading, show error states with retry options, provide network status feedback

---

## PHASE 5: Connection Management

### 5.1 Creating Connections
- Implement Sender Connecting to Receiver flow
- On "+ Add Receiver" tap show "Connect to Receiver" screen
- Provide 6-digit code field for manual entry
- Support paste from clipboard with auto-detect
- Plan for QR code scanning (future enhancement)
- Validate code via edge function validate_connection_code()
- On valid code: create connection record with status='active', create ping record for today if not yet pinged, show success message "Connected to [Receiver Name]!", send notification to receiver "[Sender] is now sending you pings"
- On invalid code: show error "Invalid code. Please check and try again.", allow retry
- Handle EC-5.1: Prevent self-connection with error "Cannot connect to your own code"
- Handle EC-5.2: Prevent duplicate connection with error "You're already connected to this user"
- Handle EC-5.3: Reactivate deleted connection by updating status to 'active' and restoring pings
- Handle EC-5.4: Deduplicate simultaneous connections, keep first creation

### 5.2 Managing Connections
- Implement Sender Actions: "Pause Connection" sets status to 'paused' and stops ping generation, "Remove Connection" sets status to 'deleted', "Contact Receiver" opens SMS/phone, "View History" shows ping history for this receiver
- Implement Receiver Actions: "Pause Notifications" mutes notifications for this sender only, "Remove Connection" removes sender from list, "Contact Sender" opens SMS/phone, "View History" shows ping history for this sender

### 5.3 User Stories Connection Management
- US-5.1 Connect Using Code: Support 6-digit code entry field, enable paste from clipboard, validate code immediately, show receiver's name on success (from contacts), display connection in receivers list immediately, send notification to receiver, show error messages for invalid/expired codes
- US-5.2 Invite via SMS: Open contact picker from "Invite Receivers" button, pre-populate SMS with invitation message, include receiver's code in message, include app download link, support multiple recipients, use native iOS SMS composer
- US-5.3 Pause Connection: Provide pause option in connection menu, show confirmation dialog explaining impact, update connection status to 'paused', stop ping generation while paused, notify receiver of pause, provide easy "Resume Connection" option
- US-5.4 Remove Connection: Provide remove option in connection menu, show confirmation dialog to prevent accidents, set connection status to 'deleted', remove connection from list, notify other user of removal, allow reconnection using code later

---

## PHASE 6: Ping System & Scheduling

### 6.1 Daily Ping Generation
- Create Edge Function generate_daily_pings() running at midnight UTC (cron: 0 0 * * *)
- Create ping records for all active sender/receiver connections
- Respect sender breaks by creating pings with status='on_break'
- Check receiver subscription status before creating pings
- Calculate deadline as scheduled_time + 90 minutes
- Store ping_time in UTC in sender_profiles
- Convert to sender's local timezone for display
- Adjust automatically for sender travel using device timezone
- Apply rule: "9 AM local" means 9 AM wherever sender currently is

### 6.2 Ping Completion Methods
- Implement Tap to Ping Method 1: On "I'm Okay" tap call edge function complete_ping(), mark all pending pings for today as completed, set completion_method = 'tap', set completed_at = current timestamp, play success animation, notify receivers within 30 seconds
- Implement In-Person Verification Method 2: Available anytime via "Verify In Person" button, request location permission (first time only), capture GPS coordinates (lat, lon, accuracy), call complete_ping() with method='in_person' and location, store location in verification_location JSONB field, show "Verified in person" indicator to receivers
- Implement Late Ping Method 3: After deadline passes change button to "Ping Now", allow ping completion, mark as completed but flag as late, notify receivers "[Sender] pinged late at [time]", count toward streak

### 6.3 Ping Notifications Schedule
- Send To Sender at Scheduled Time: "Time to ping! Tap to let everyone know you're okay."
- Send To Sender 15 Minutes Before Deadline: "Reminder: 15 minutes until your ping deadline"
- Send To Sender At Deadline: "Final reminder: Your ping deadline is now"
- Send To Receivers On-Time Completion: "[Sender Name] is okay!"
- Send To Receivers Late Completion: "[Sender Name] pinged late at [time]"
- Send To Receivers Missed Ping (5 min after deadline): "[Sender Name] missed their ping. Last seen [time]."
- Send To Receivers Break Started: "[Sender Name] is on break until [date]"

### 6.4 Ping Streak Calculation
- Count consecutive days of completed pings
- Do NOT break streak for breaks (counted as completed)
- Reset streak to 0 on missed ping
- Count late pings toward streak
- Calculate daily via calculate_streak() function
- Display streak on receiver dashboard for each sender

### 6.5 User Stories Ping System
- US-6.1 Daily Ping Reminder: Send notification at exact scheduled time, include deep link to app, work when app is closed/backgrounded, allow notification preference customization, resend if notification fails
- US-6.2 Complete Ping by Tapping: Display "I'm Okay" button prominently when pending, complete all pending pings with single tap, play success animation (checkmark/confetti), update dashboard immediately to "Completed" state, notify all receivers within 30 seconds, record timestamp accurately
- US-6.3 In-Person Verification: Make "Verify In Person" button available anytime, request location permission on first use, capture current location (lat/lon/accuracy), mark ping as completed with 'in_person' method, store location securely in database, show "Verified in person" indicator to receivers
- US-6.4 Late Ping Submission: Show "Ping Now" button after deadline, mark ping as completed but flag as late, notify receivers it was late, count late pings toward streak, show actual completion time in timestamp
- US-6.5 View Ping History: Display calendar view for last 30 days, use color coding (green=on time, yellow=late, red=missed, gray=break), allow tap on date for details, display current streak prominently, provide filter by connection if multiple

---

## PHASE 7: Breaks & Pauses
**Build validation cadence:** Run build/test validation after all sections in this phase are complete (not after each section).

### 7.1 Scheduling Breaks
- Allow senders to pause ping requirements for planned absences (vacation, hospital stay, etc.)
- On "Schedule a Break" tap show "Schedule Break" screen
- Display Start Date picker (date only, not time)
- Display End Date picker (must be >= start date)
- Provide optional notes field
- Add "Schedule Break" button
- On submit: validate dates (end >= start, start >= today), create break record with status='scheduled', show confirmation "Break scheduled for [date range]", send notifications to all receivers "[Sender] will be on break [dates]"
- Show "On Break" state on dashboard during break period
- Implement status transitions: scheduled -> active (at start_date midnight), active -> completed (at end_date + 1 day midnight), scheduled or active -> canceled (user cancels early)
- During breaks: generate pings with status='on_break' instead of 'pending', show receivers "[Sender] is on break until [end_date]", continue streak (breaks don't break streaks), allow optional voluntary completion

### 7.2 Managing Breaks
- In Settings > Breaks show list of scheduled/active breaks with date range, status, notes
- Implement Cancel Break: tap break in list, show "Cancel Break" button, display confirmation dialog "Cancel this break?", on confirm update status to 'canceled', revert future pings to 'pending', notify receivers "[Sender] ended their break early"
- Implement End Break Early: show button on dashboard during active break, use same cancellation flow, immediately resume normal ping requirements

### 7.3 Break Edge Cases
- EC-7.1: Prevent overlapping breaks with error "You already have a break during this period"
- EC-7.2: If break starts today, immediately set status='active', today's ping becomes 'on_break'
- EC-7.3: If break ends today, tomorrow's ping reverts to 'pending'
- EC-7.4: Connection pause during break applies both statuses; no pings generated
- EC-7.5: Warn for breaks longer than 1 year: "Breaks longer than 1 year may affect your account"

### 7.4 User Stories Breaks
- US-7.1 Schedule a Break: Provide date pickers for start and end dates, include optional notes field for context, validate to prevent invalid date ranges, show confirmation message after scheduling, notify receivers of upcoming break, update dashboard to show break status
- US-7.2 Cancel Break Early: Show "End Break Early" button on dashboard, display confirmation dialog to prevent accidents, update break status to 'canceled', resume normal ping requirements immediately, notify receivers of early return
- US-7.3 View Break Schedule: Show list view of all breaks (scheduled, active, completed, canceled), display date range, status, notes for each, allow tap to view details or cancel, archive but keep visible past breaks, provide filter by status

---

## PHASE 8: Notifications

### 8.1 Push Notification Setup
- Enable Push Notifications capability in Xcode
- Register for remote notifications on app launch
- Request user permission during onboarding
- Store device token in users.device_token
- Use Apple Push Notification service (APNs)
- Store APNs device tokens in database via Supabase
- Send notifications via APNs HTTP/2 API from edge functions
- Handle token updates when device re-registers
- Remove invalid tokens on delivery failure

### 8.2 Notification Types and Content
- Ping Reminder to Sender: title "Time to ping!", body "Tap to let everyone know you're okay.", sound default, badge 1, deeplink pruuf://dashboard
- Missed Ping Alert to Receiver: title "Missed Ping Alert", body "[Sender Name] missed their ping. Last seen [time].", sound default, badge 1, category MISSED_PING, deeplink pruuf://sender/[sender_id]
- Ping Completed to Receiver: title "[Sender Name] is okay!", body "Checked in at [time]", sound default, deeplink pruuf://dashboard
- Connection Request to Receiver: title "New Connection", body "[Sender Name] is now sending you pings", sound default, deeplink pruuf://connections
- Trial Ending to Receiver: title "Trial Ending Soon", body "Your free trial ends in 3 days. Subscribe to keep your peace of mind.", sound default, deeplink pruuf://subscription

### 8.3 Notification Preferences
- Provide master toggle to enable/disable all notifications
- Sender preferences: Ping reminders (scheduled time), 15-minute warning, Deadline warning
- Receiver preferences: Ping completed notifications, Missed ping alerts, Connection requests
- Add per-sender muting for receivers
- Plan quiet hours feature for future (no notifications during specified times)

### 8.4 In-App Notifications
- Add bell icon in header with badge count
- Show list of recent notifications on tap
- Display last 30 days of notifications
- Allow mark as read individually or all at once
- Allow delete notifications
- Navigate to relevant screen on notification tap

### 8.5 User Stories Notifications
- US-8.1 Receive Push Notifications: Send notifications via APNs, display on lock screen and notification center, deep link to relevant screen in app, update badge count automatically, make sound and vibration configurable
- US-8.2 Customize Notification Preferences: Create Settings > Notifications screen, add toggle for each notification type, provide master enable/disable switch, allow per-sender muting for receivers, apply changes immediately
- US-8.3 View Notification History: Add bell icon with badge count in header, show list of last 30 days of notifications, allow mark as read individually or all, allow delete notifications, navigate to related content on tap

---

## PHASE 9: Subscription & Payments

### 9.1 Subscription Model
- Set Receiver-only users price to $2.99/month
- Keep Senders always free
- Charge Dual role users (Both) $2.99/month only if they have receiver connections
- Provide 15-day free trial for all receivers
- Do not require credit card to start trial
- Use Apple In-App Purchases (StoreKit 2) as payment provider
- Set Product ID to com.pruuf.receiver.monthly
- Configure as auto-renewable subscription managed through App Store

### 9.2 Trial Period
- Start trial immediately when user selects Receiver role (no payment required)
- Set trial_start_date = now
- Set trial_end_date = now + 15 days
- Set subscription_status = 'trial'
- Grant full access during trial
- Send notification on Day 12: "Your trial ends in 3 days"
- Send notification on Day 14: "Your trial ends tomorrow"
- Send notification on Day 15: "Your trial has ended. Subscribe to continue"
- If not subscribed by end of trial: set subscription_status = 'expired', stop receiver ping notifications, prevent senders from creating pings for expired receivers, show "Subscribe to Continue" banner, maintain read-only access to history

### 9.3 Subscription Management
- On "Subscribe Now" tap show App Store subscription sheet (StoreKit)
- Complete purchase through Apple
- Receive purchase notification in app
- Validate receipt with Apple
- Update database: set subscription_status = 'active', set subscription_start_date = now, set subscription_end_date = now + 1 month, store Apple receipt ID
- Resume full functionality
- Show confirmation "You're subscribed!"
- Provide "Restore Purchases" in Settings > Subscription to query App Store for existing purchases and update database
- Handle cancellation through iOS Settings > Apple ID > Subscriptions
- Detect cancellation via App Store Server Notifications
- Update subscription_status = 'canceled'
- Continue access until end of billing period
- Show message "Your subscription will end on [date]"
- Allow resubscribe after cancellation or expiration with same subscription flow

### 9.4 Payment Webhooks
- Listen for Apple App Store Server Notifications
- Handle INITIAL_BUY: Set status to 'active'
- Handle RENEWAL: Extend subscription_end_date
- Handle CANCEL: Set status to 'canceled'
- Handle DID_FAIL_TO_RENEW: Set status to 'past_due', notify user
- Handle REFUND: Set status to 'expired', log transaction
- Create Edge Function handle_appstore_webhook() to verify Apple signature, find user by transaction, process notification type, update subscription status

### 9.5 Subscription Status Checks
- Before ping generation: Check receiver subscription status via daily cron job, skip ping generation if expired, allow 3-day grace period for past_due then skip
- On app launch: Check subscription status, show "Subscription Expired" banner if expired, show "Payment Failed - Update Payment Method" if past_due

### 9.6 User Stories Subscription and Payments
- US-9.1 Start Free Trial: Start trial automatically when selecting Receiver role, do not require credit card during onboarding, grant full access for 15 days, display trial end date in dashboard, send notifications at 3 days, 1 day, and expiration
- US-9.2 Subscribe After Trial: Show "Subscribe Now" button in dashboard, display Apple subscription sheet, process payment through App Store, activate subscription immediately, display confirmation message
- US-9.3 Manage Subscription: Open iOS Settings from "Manage Subscription" link, show current status and next billing date, provide cancel option, continue access until end of period after cancel, allow resubscribe anytime
- US-9.4 Restore Purchases: Provide "Restore Purchases" button in Settings, query App Store for active purchases, update local database with subscription status, restore access immediately if subscription found, show error message if no subscription found

---

## PHASE 10: Settings & Preferences

### 10.1 Settings Screen Structure
- Navigate from Dashboard > Settings icon
- Create Account section: Phone number (read-only), Timezone (auto-detected, read-only), Role (Sender/Receiver/Both), "Add Sender Role" or "Add Receiver Role" button, "Delete Account" (danger zone)
- Create Ping Settings section (Senders only): Daily ping time (time picker), Grace period 90 minutes (read-only, future: customizable), Enable/disable pings toggle, "Schedule a Break"
- Create Notifications section: Master toggle enable/disable all, Ping reminders, 15-minute warning, Deadline warning, Ping completed (receivers), Missed ping alerts (receivers), Connection requests, Payment reminders
- Create Subscription section (Receivers only): Current status (Trial/Active/Expired), Next billing date, "Subscribe Now" or "Manage Subscription", "Restore Purchases"
- Create Connections section: View all connections, Manage active/paused connections, "Your PRUUF Code" (receivers)
- Create Privacy and Data section: Export my data (GDPR), Delete my data, Privacy policy link, Terms of service link
- Create About section: App version, Build number, "Contact Support", "Rate PRUUF", "Share with Friends"

### 10.2 Account Management
- Implement Add Role: Show "Add Sender Role" button for receivers, Show "Add Receiver Role" button for senders, on tap create sender_profiles or receiver_profiles record, update users.primary_role to 'both', redirect to role-specific onboarding, start 15-day trial for receiver role
- Implement Change Ping Time: Show iOS wheel time picker with current time, update sender_profiles.ping_time on save, show confirmation "Ping time updated to [time]", schedule next ping for new time, display note "This will take effect tomorrow"
- Implement Delete Account: Show "Delete Account" button in red, require confirmation "Are you sure?" dialog, require phone number entry to confirm, on confirm: soft delete with users.is_active = false, set all connections status = 'deleted', stop ping generation, cancel subscription, keep data for 30 days (regulatory requirement), log audit event, sign out user, schedule hard delete after 30 days via scheduled job

### 10.3 Data Export GDPR
- Provide "Export My Data" button in Privacy and Data section
- Generate ZIP file containing: User profile (JSON), All connections (JSON), All pings history (CSV), All notifications (CSV), Break history (JSON), Payment transactions (CSV)
- Deliver via email or download link
- Process within 48 hours
- Send notification when ready
- Create Edge Function export_user_data() to gather all user data, generate ZIP file, upload to Storage bucket with 7-day expiration, generate signed URL, send email with download link

### 10.4 User Stories Settings
- US-10.1 Change Ping Time: Navigate to Settings > Ping Settings > Daily Ping Time, show current time in time picker, save updates to database, display confirmation message, schedule next ping for new time, notify receivers of time change
- US-10.2 Add Second Role: Show "Add Receiver Role" button in Settings > Account, complete onboarding flow for new role, generate unique code for receivers, change dashboard to tabbed view, start trial for receiver functionality, require subscription if adding receiver connections
- US-10.3 Delete Account: Show "Delete Account" button in Settings, require multiple confirmation steps, require phone number verification, remove all connections, cancel subscription, mark account as deleted, retain data 30 days then purge, sign out user immediately
- US-10.4 Export My Data: Show "Export My Data" button in Settings > Privacy, display processing message, generate ZIP file with all data, send download link via email, include profile, connections, pings, notifications, payments, make available for 7 days

---

## PHASE 11: Admin Dashboard

### 11.1 Admin Access
- Set Admin Email: wesleymwilliams@gmail.com
- Set Admin Password: W@$hingt0n1
- Set Admin Role: Super Admin
- Configure Admin Dashboard URL: https://oaiteiceynliooxpeuxt.supabase.co/project/_/admin OR custom web dashboard

### 11.2 Admin Dashboard Features
- Create User Management section: Total users count, Active users (last 7/30 days), New signups (daily/weekly/monthly), User search by phone number, View user details, Impersonate user (for debugging), Deactivate/reactivate accounts, Manual subscription updates
- Create Connection Analytics section: Total connections, Active connections, Paused connections, Average connections per user, Connection growth over time, Top users by connection count
- Create Ping Analytics section: Total pings sent today/week/month, Completion rate (on-time vs late vs missed), Average completion time, Ping streaks distribution, Missed ping alerts, Break usage statistics
- Create Subscription Metrics section: Total revenue (MRR), Active subscriptions, Trial conversions, Churn rate, Average revenue per user (ARPU), Lifetime value (LTV), Payment failures, Refunds/chargebacks
- Create System Health section: Edge function execution times, Database query performance, API error rates, Push notification delivery rates, Cron job success rates, Storage usage
- Create Operations section: Manual ping generation (for testing), Send test notifications, Cancel subscriptions (with reason), Refund payments, View audit logs, Export reports (CSV/JSON)

### 11.3 Admin Roles and Permissions
- Configure Super Admin (wesleymwilliams@gmail.com): Full system access, User management, Subscription management, System configuration, View all data, Export reports
- Plan Support Admin role (future): View user data (read-only), View subscriptions (read-only), Cannot modify data, Cannot access financial info

### 11.4 Admin Dashboard Implementation
- Custom Dashboard (Recommended): Build with Next.js + React, Host separately or on Supabase hosting, Create custom analytics and visualizations, Provide better UX for operations tasks
- Use Tech Stack: Framework Next.js 14, UI shadcn/ui components, Charts Recharts or Chart.js, Auth Supabase Auth, Data Supabase queries

### 11.5 User Stories Admin Dashboard
- US-11.1 View User Metrics: Show total users, new signups, active users on dashboard, display charts for user growth over time, break down by role (sender/receiver/both), provide daily/weekly/monthly views, enable export to CSV
- US-11.2 Manage Subscriptions: Allow search user by phone/email, show subscription status and history, enable manual extend/cancel subscriptions, allow issue refunds, display payment transactions, log all changes to audit log
- US-11.3 Monitor System Health: Show real-time metrics for API response times, display edge function execution stats, alert on error rate thresholds, track push notification delivery rates, log cron job success/failure

---

## PHASE 12: Supabase Edge Functions

### 12.1 Edge Functions Overview
- Deploy all edge functions to Supabase
- Call from iOS app via REST API
- Set Base URL: https://oaiteiceynliooxpeuxt.supabase.co/functions/v1/
- Use Authentication: Bearer token (Supabase Auth JWT)

### 12.2 Edge Function Specifications
- Create validate-connection-code function: POST method, validate and create connections using 6-digit codes, accept request with code, connectingUserId, role (sender|receiver), return success boolean and connection object, handle edge cases for self-connection, duplicate, invalid code
- Create generate-daily-pings function: POST method (internal, cron-triggered), create daily ping records for all active connections, run on cron 0 0 * * * (daily at midnight UTC), query all active senders, check for active breaks, verify receiver subscriptions, create ping records with calculated deadlines
- Create complete-ping function: POST method, mark ping as completed, accept senderId, method (tap|in_person), optional location object, return success boolean and pings_completed count
- Create send-ping-notifications function: POST method (internal, cron-triggered), send scheduled ping reminders and alerts, run on cron */15 * * * * (every 15 minutes), find pending pings, check time until deadline, send appropriate notifications
- Create check-subscription-status function: POST method, validate receiver subscription before operations, accept userId, return status (trial|active|past_due|expired) and valid boolean
- Create handle-appstore-webhook function: POST method, process Apple In-App Purchase webhooks at /functions/v1/handle-appstore-webhook, verify Apple signature, update subscription status, send notifications
- Create export-user-data function: POST method, generate GDPR data export, accept userId, return success boolean and download_url
- Create calculate-streak function: POST method, calculate ping streak for a connection, accept senderId and receiverId, return streak number
- Create cleanup-expired-data function: POST method (internal, cron-triggered), remove old data and hard-delete accounts, run on cron 0 2 * * * (daily at 2 AM UTC), hard delete users marked deleted > 30 days ago, archive old notifications (> 90 days), remove expired data exports (> 7 days)

### 12.3 Rate Limiting
- Set Authentication limit: 5 requests/minute per user
- Set Ping completion limit: 10 requests/minute per user
- Set Connection creation limit: 5 requests/minute per user
- Set General API limit: 100 requests/minute per user
- Use Supabase built-in rate limiting
- Return 429 status code when exceeded
- Include retry-after header in response

### 12.4 Error Handling
- Use standard error response format with success boolean, error message, and error code
- Define error code INVALID_CODE: Code not found or inactive
- Define error code SELF_CONNECTION: Attempting to connect to self
- Define error code DUPLICATE_CONNECTION: Connection already exists
- Define error code SUBSCRIPTION_EXPIRED: Receiver subscription invalid
- Define error code RATE_LIMIT_EXCEEDED: Too many requests
- Define error code UNAUTHORIZED: Invalid auth token
- Define error code SERVER_ERROR: Internal server error

---

## PHASE 13: Security & Privacy

### 13.1 Data Security
- Encrypt all data at rest using Supabase PostgreSQL encryption
- Encrypt all data in transit using TLS 1.3
- Encrypt device tokens in database
- Store auth tokens in iOS Keychain (encrypted)
- Encrypt location data in JSONB field
- Use Phone number + SMS OTP authentication (no passwords to leak)
- Set JWT tokens with 30-day expiration
- Store refresh tokens securely
- Apply rate limiting on auth endpoints (5 attempts/min)
- Enforce Row Level Security (RLS) on all tables
- Ensure users can only access their own data
- Prevent receivers from seeing other receivers
- Prevent senders from seeing other senders' data
- Check admin role for admin endpoints

### 13.2 Privacy Compliance
- GDPR Right to access: Provide data export feature
- GDPR Right to erasure: Account deletion with 30-day retention
- GDPR Right to portability: ZIP export with machine-readable formats
- GDPR Consent management: Explicit opt-in for notifications
- GDPR Data minimization: Only collect necessary data
- CCPA: Include privacy policy link in app
- CCPA "Do Not Sell My Info": Not applicable as no data selling
- CCPA Data disclosure: Document what data is collected and why
- CCPA: Plan opt-out options for analytics (future)
- Set active user data retention: Indefinite while account active
- Set deleted accounts retention: 30 days soft delete, then hard delete
- Set notifications retention: 90 days, then archived
- Set audit logs retention: 1 year
- Set payment transactions retention: 7 years (regulatory requirement)

### 13.3 Security Best Practices
- Validate phone numbers with regex + libphonenumber
- Validate 6-digit codes as numeric only, exact length
- Validate dates for valid ranges
- Validate JSON payloads with schema validation
- Prevent SQL injection by using parameterized queries (Supabase SDK)
- Never use raw SQL from user input
- Use RLS policies to prevent unauthorized access
- Prevent XSS by sanitizing all user input (names, notes)
- Set Content Security Policy headers
- Never use eval() or innerHTML
- Apply rate limiting: Authentication 5/min per IP, API calls 100/min per user, Ping completion 10/min per user, Connection creation 5/min per user
- Monitor and alert on: Failed auth attempts (>10 in 1 hour), Unusual API usage patterns, Database query performance issues, Push notification delivery failures, Subscription webhook failures

## PHASE 14: Performance & Optimization

### 14.1 Performance Targets

**App Launch:**
- Cold launch: < 3 seconds to dashboard
- Warm launch: < 1 second to dashboard
- Auth token validation: < 500ms

**API Response Times:**
- Authentication (OTP send): < 2 seconds
- Complete ping: < 1 second
- Load dashboard: < 2 seconds
- Create connection: < 1 second

**Push Notifications:**
- Ping completion → Receiver notification: < 30 seconds
- Missed ping → Receiver notification: < 5 minutes
- Scheduled reminder → Sender notification: Within 1 minute of scheduled time

**Database Queries:**
- User profile fetch: < 100ms
- Connection list: < 200ms
- Ping history (30 days): < 300ms
- Dashboard data (all): < 500ms

### 14.2 Optimization Strategies

**Client-Side (iOS):**
- Lazy loading: Load data as needed, not all upfront
- Caching: Cache user profile, connections list (5 min TTL)
- Image optimization: Use SF Symbols instead of custom images
- Background refresh: Update data silently when app backgrounded
- Combine API calls: Batch related requests

**Server-Side (Supabase):**
- Database indexes: All foreign keys, frequently queried fields
- Query optimization: Use `.select()` with specific fields, avoid `*`
- Connection pooling: Supabase manages this automatically
- Edge function optimization: Minimize cold starts, use lightweight code
- Caching: Redis for frequently accessed data (future)

**Monitoring:**
- App Analytics: Track performance metrics
- Crash reporting: Sentry or Firebase Crashlytics
- API monitoring: Supabase built-in metrics
- Custom metrics: Dashboard load time, ping completion time

### 14.3 Scalability Considerations

**Current Scale:**
- Target: 10,000 users in first year
- Average: 2 connections per user
- Daily pings: 20,000/day
- Push notifications: 60,000/day (3x pings)

**Scaling Plan:**
- Database: PostgreSQL scales to 100,000+ users easily
- Edge functions: Auto-scale with Supabase
- Push notifications: APNs handles millions/day
- Storage: Minimal (no images, just JSON/text)

**Bottleneck Prevention:**
- Database connections: Use connection pooling
- Rate limiting: Prevent abuse
- Pagination: Limit query results (100 items max)
- Background jobs: Use cron for heavy operations (not API calls)

### 14.4 User Stories: Performance

#### US-14.1: Fast App Launch
**As a** user
**I want to** access the app quickly
**So that** I can complete my ping efficiently

**Acceptance Criteria:**
- [ ] Cold launch < 3 seconds
- [ ] Warm launch < 1 second
- [ ] Dashboard loads immediately
- [ ] No loading spinners for cached data

#### US-14.2: Responsive Ping Completion
**As a** sender
**I want to** see immediate feedback when pinging
**So that** I know it worked

**Acceptance Criteria:**
- [ ] Ping completion < 1 second
- [ ] Immediate UI update
- [ ] Success animation plays
- [ ] Receivers notified within 30 seconds

---

## PHASE 15: Testing & Quality Assurance

### 15.1 Testing Strategy

**Test Pyramid:**
- Unit tests: 60%
- Integration tests: 30%
- UI/E2E tests: 10%

**Coverage Target:** 80% code coverage minimum

### 15.2 Unit Tests

**Swift Unit Tests (XCTest):**
- Models: User, Connection, Ping, Break
- Services: AuthService, PingService, ConnectionService, NotificationService
- ViewModels: All view models
- Utilities: Date formatters, validators, helpers

**Example Test:**
```swift
func testPingCompletion() {
    let service = PingService()
    let expectation = expectation(description: "Ping completed")

    service.completePing(method: .tap) { result in
        switch result {
        case .success(let pingsCompleted):
            XCTAssertGreaterThan(pingsCompleted, 0)
            expectation.fulfill()
        case .failure(let error):
            XCTFail("Ping completion failed: \(error)")
        }
    }

    wait(for: [expectation], timeout: 5.0)
}
```

### 15.3 Integration Tests

**API Integration Tests:**
- Authentication flow (OTP send/verify)
- Connection creation (valid/invalid codes)
- Ping completion (tap/in-person)
- Subscription management
- Edge function interactions

**Database Integration Tests:**
- RLS policies enforce access control
- Foreign key constraints prevent orphans
- Triggers fire correctly (updated_at)
- Functions return correct results

### 15.4 UI Tests

**XCUITest Scenarios:**
1. **Onboarding Flow:**
   - Enter phone number
   - Verify OTP
   - Select role
   - Complete role-specific onboarding

2. **Sender Flow:**
   - View dashboard
   - Complete ping (tap)
   - Complete ping (in-person)
   - Schedule break
   - Add receiver connection

3. **Receiver Flow:**
   - View dashboard
   - See sender ping status
   - Copy/share code
   - Connect to sender
   - Subscribe

4. **Settings Flow:**
   - Change ping time
   - Toggle notifications
   - Delete account

### 15.5 Edge Case Testing

**Reference:** See `edge_cases_testing.md` for comprehensive test cases

**Priority Test Suites:**
- TS-1: Unique Code System (EC-1.1 through EC-1.5)
- TS-2: Authentication & Onboarding (EC-2.1 through EC-2.9)
- TS-3: Payment & Subscription (EC-3.1 through EC-3.12)
- TS-4: Ping Timing & Completion (EC-4.1 through EC-4.12)
- TS-5: Break Management (EC-7.1 through EC-7.7)

**Critical Edge Cases:**
- Code collision handling
- Duplicate connection prevention
- Subscription expiration handling
- Timezone changes during travel
- Network failures during ping
- Simultaneous ping attempts
- Payment failures

### 15.6 Performance Testing

**Load Testing:**
- Simulate 1,000 concurrent users
- Generate 10,000 daily pings
- Send 30,000 push notifications
- Measure response times under load

**Stress Testing:**
- Find breaking point (max users)
- Test database connection limits
- Test push notification throughput
- Test edge function concurrency

### 15.7 Security Testing

**Penetration Testing:**
- Attempt SQL injection
- Test XSS vulnerabilities
- Attempt unauthorized access (RLS bypass)
- Test rate limiting effectiveness
- Attempt session hijacking

**Privacy Testing:**
- Verify data isolation (users can't see others' data)
- Test data export completeness
- Test account deletion thoroughness
- Verify encryption at rest/transit

### 15.8 User Acceptance Testing (UAT)

**Beta Testing:**
- Recruit 50-100 beta testers
- Mix of senders and receivers
- Various iOS devices and versions
- Different geographic locations (timezones)
- Collect feedback via in-app survey

**Criteria for Launch:**
- All P0 bugs fixed
- 95% crash-free rate
- <1% failed ping notifications
- 100% subscription processing success
- Positive beta tester feedback (>4/5 rating)

### 15.9 User Stories: Testing

#### US-15.1: Automated Testing
**As a** developer
**I want to** have comprehensive automated tests
**So that** I can deploy with confidence

**Acceptance Criteria:**
- [ ] 80%+ code coverage
- [ ] All critical paths tested
- [ ] Tests run on every commit (CI/CD)
- [ ] Test results visible in PR