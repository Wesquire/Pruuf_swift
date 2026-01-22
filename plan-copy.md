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

### Key Features
- Phone number authentication via SMS
- Role-based system (Sender/Receiver)
- Daily ping scheduling with customizable times
- Directional connections using unique 6-digit codes
- In-person verification option
- Scheduled breaks/pauses
- Real-time notifications
- Subscription model: $2.99/month for receiver-only users, senders always free
- 15-day free trial period
- Admin dashboard for operations

### Document Structure
This PRD is organized into phases representing logical implementation groupings. Each phase contains detailed specifications, technical requirements, user flows, and acceptance criteria. All user stories are included at the end of each relevant phase.

---

## PHASE 1: Project Setup & Configuration

### 1.1 Supabase Configuration

**Supabase Project Credentials:**
- **Project URL:** `https://oaiteiceynliooxpeuxt.supabase.co`
- **Anon Public Key:** `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9haXRlaWNleW5saW9veHBldXh0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg1MzA0MzEsImV4cCI6MjA4NDEwNjQzMX0.Htm_jL8JbLK2jhVlCUL0A7m6PJVY_ZuBx3FqZDZrtgk`

**Setup Steps:**
- Initialize Supabase client in iOS Swift project
- Configure authentication providers (Phone/SMS)
- Enable Row Level Security (RLS) on all tables
- Set up Edge Functions for business logic
- Configure Storage buckets (if needed for profile pictures)
- Set up scheduled jobs for ping monitoring
- Configure webhooks for payment processing

### 1.2 iOS Project Setup

**Requirements:**
- **Minimum iOS Version:** iOS 15.0+
- **Language:** Swift 5.9+
- **Architecture:** MVVM (Model-View-ViewModel)
- **Package Manager:** Swift Package Manager (SPM)

- Required Dependencies:**
```swift
// Supabase Swift SDK
.package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")

// Additional packages as needed:
// - KeychainSwift (secure token storage)
// - SwiftUI Charts (for analytics dashboard)
```
- Project Structure:**
```
PRUUF/
├── App/
│   ├── PruufApp.swift
│   └── AppDelegate.swift
├── Core/
│   ├── Config/
│   │   └── SupabaseConfig.swift
│   ├── Services/
│   │   ├── AuthService.swift
│   │   ├── PingService.swift
│   │   ├── ConnectionService.swift
│   │   └── NotificationService.swift
│   └── Models/
│       ├── User.swift
│       ├── Connection.swift
│       ├── Ping.swift
│       └── Break.swift
├── Features/
│   ├── Authentication/
│   ├── Onboarding/
│   ├── Dashboard/
│   ├── Connections/
│   ├── Settings/
│   └── Subscription/
├── Shared/
│   ├── Components/
│   ├── Extensions/
│   └── Utilities/
└── Resources/
    ├── Assets.xcassets
    └── Info.plist
```

### 1.3 Development Environment

**Configuration Requirements:**
- Xcode 15.0+
- Apple Developer Account (for push notifications, TestFlight)
- Supabase CLI installed locally for edge function development
- Git version control

- Environment Variables:**
```swift
// Config.swift
enum Config {
    static let supabaseURL = "https://oaiteiceynliooxpeuxt.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
    static let environment: Environment = .development

    enum Environment {
        case development
        case staging
        case production
    }
}
```

### 1.4 Admin Dashboard Credentials

- Admin Access:**- **Email:** wesleymwilliams@gmail.com
- **Password:** W@$hingt0n1
- **Role:** Super Admin
- **Permissions:** Full system access, analytics dashboard, user management, payment oversight

---

## PHASE 2: Database Schema & Row Level Security

### 2.1 Database Tables

- Table: `users`
Stores all user account information.

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_number TEXT UNIQUE NOT NULL,
    phone_country_code TEXT NOT NULL DEFAULT '+1',
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    last_seen_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT true,
    has_completed_onboarding BOOLEAN DEFAULT false,
    primary_role TEXT CHECK (primary_role IN ('sender', 'receiver', 'both')),
    timezone TEXT DEFAULT 'UTC',
    device_token TEXT, -- For push notifications
    notification_preferences JSONB DEFAULT '{"ping_reminders": true, "deadline_alerts": true, "connection_requests": true}'::jsonb
);

-- Indexes
CREATE INDEX idx_users_phone ON users(phone_number);
CREATE INDEX idx_users_active ON users(is_active) WHERE is_active = true;
```

#### Table: `sender_profiles`
Stores sender-specific settings.

```sql
CREATE TABLE sender_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    ping_time TIME NOT NULL, -- UTC time for daily ping
    ping_enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id)
);

-- Indexes
CREATE INDEX idx_sender_profiles_user ON sender_profiles(user_id);
```

- Table: `receiver_profiles`
Stores receiver-specific settings and subscription status.

```sql
- CREATE TABLE receiver_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    subscription_status TEXT CHECK (subscription_status IN ('trial', 'active', 'past_due', 'canceled', 'expired')) DEFAULT 'trial',
    subscription_start_date TIMESTAMPTZ,
    subscription_end_date TIMESTAMPTZ,
    trial_start_date TIMESTAMPTZ DEFAULT now(),
    trial_end_date TIMESTAMPTZ DEFAULT (now() + INTERVAL '15 days'),
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id)
);

-- Indexes
- CREATE INDEX idx_receiver_profiles_user ON receiver_profiles(user_id);
- CREATE INDEX idx_receiver_profiles_subscription ON receiver_profiles(subscription_status);
- CREATE INDEX idx_receiver_profiles_stripe ON receiver_profiles(stripe_customer_id);
```

- Table: `unique_codes`
- Manages 6-digit unique codes for connections.

```sql
- CREATE TABLE unique_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL CHECK (code ~ '^[0-9]{6}$'),
    receiver_id UUID REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ, -- NULL = never expires
    is_active BOOLEAN DEFAULT true,
    UNIQUE(receiver_id) -- One code per receiver
);

-- Indexes
- CREATE INDEX idx_unique_codes_code ON unique_codes(code) WHERE is_active = true;
- CREATE INDEX idx_unique_codes_receiver ON unique_codes(receiver_id);
```

- Table: `connections`
Manages sender-receiver relationships.

```sql
- CREATE TABLE connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID REFERENCES users(id) ON DELETE CASCADE,
    receiver_id UUID REFERENCES users(id) ON DELETE CASCADE,
    status TEXT CHECK (status IN ('pending', 'active', 'paused', 'deleted')) DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    connection_code TEXT, -- The code used to establish connection
    UNIQUE(sender_id, receiver_id)
);

-- Indexes
- CREATE INDEX idx_connections_sender ON connections(sender_id) WHERE status = 'active';
- CREATE INDEX idx_connections_receiver ON connections(receiver_id) WHERE status = 'active';
- CREATE INDEX idx_connections_status ON connections(status);
```

- able: `pings`
Tracks all ping events.

```sql
- CREATE TABLE pings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id UUID REFERENCES connections(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES users(id) ON DELETE CASCADE,
    receiver_id UUID REFERENCES users(id) ON DELETE CASCADE,
    scheduled_time TIMESTAMPTZ NOT NULL,
    deadline_time TIMESTAMPTZ NOT NULL, -- scheduled_time + grace period
    completed_at TIMESTAMPTZ,
    completion_method TEXT CHECK (completion_method IN ('tap', 'in_person', 'auto_break')),
    status TEXT CHECK (status IN ('pending', 'completed', 'missed', 'on_break')) DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now(),
    verification_location JSONB, -- {lat, lon, accuracy} if in-person verification
    notes TEXT
);

-- Indexes
- CREATE INDEX idx_pings_connection ON pings(connection_id);
- CREATE INDEX idx_pings_sender ON pings(sender_id);
- CREATE INDEX idx_pings_receiver ON pings(receiver_id);
- CREATE INDEX idx_pings_status ON pings(status);
- CREATE INDEX idx_pings_scheduled ON pings(scheduled_time) WHERE status = 'pending';
```

- Table: `breaks`
- Manages scheduled breaks from ping requirements.

```sql
- CREATE TABLE breaks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID REFERENCES users(id) ON DELETE CASCADE,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    status TEXT CHECK (status IN ('scheduled', 'active', 'completed', 'canceled')) DEFAULT 'scheduled',
    notes TEXT,
    CHECK (end_date >= start_date)
);

-- Indexes
- CREATE INDEX idx_breaks_sender ON breaks(sender_id);
- CREATE INDEX idx_breaks_dates ON breaks(start_date, end_date) WHERE status IN ('scheduled', 'active');
```

- Table: `notifications`
Stores notification history for audit trail.

```sql
- CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    type TEXT CHECK (type IN ('ping_reminder', 'deadline_warning', 'missed_ping', 'connection_request', 'payment_reminder', 'trial_ending')) NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    sent_at TIMESTAMPTZ DEFAULT now(),
    read_at TIMESTAMPTZ,
    metadata JSONB, -- {ping_id, connection_id, etc.}
    delivery_status TEXT CHECK (delivery_status IN ('sent', 'failed', 'pending')) DEFAULT 'sent'
);

-- Indexes
- CREATE INDEX idx_notifications_user ON notifications(user_id);
- CREATE INDEX idx_notifications_sent ON notifications(sent_at DESC);
- CREATE INDEX idx_notifications_type ON notifications(type);
```

- Table: `audit_logs`
Tracks system events for compliance and debugging.

```sql
- CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    resource_type TEXT, -- 'user', 'connection', 'ping', 'payment', etc.
    resource_id UUID,
    details JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes
- CREATE INDEX idx_audit_logs_user ON audit_logs(user_id);
- CREATE INDEX idx_audit_logs_created ON audit_logs(created_at DESC);
- CREATE INDEX idx_audit_logs_action ON audit_logs(action);
```

- Table: `payment_transactions`
Tracks all payment events.

```sql
- CREATE TABLE payment_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    stripe_payment_intent_id TEXT,
    amount DECIMAL(10,2) NOT NULL,
    currency TEXT DEFAULT 'USD',
    status TEXT CHECK (status IN ('pending', 'succeeded', 'failed', 'refunded')) DEFAULT 'pending',
    transaction_type TEXT CHECK (transaction_type IN ('subscription', 'refund', 'chargeback')),
    created_at TIMESTAMPTZ DEFAULT now(),
    metadata JSONB
);

-- Indexes
- CREATE INDEX idx_payment_transactions_user ON payment_transactions(user_id);
- CREATE INDEX idx_payment_transactions_status ON payment_transactions(status);
- CREATE INDEX idx_payment_transactions_stripe ON payment_transactions(stripe_payment_intent_id);
```

### 2.2 Row Level Security (RLS) Policies

- Enable RLS on all tables:**
```sql
- ALTER TABLE users ENABLE ROW LEVEL SECURITY;
- ALTER TABLE sender_profiles ENABLE ROW LEVEL SECURITY;
- ALTER TABLE receiver_profiles ENABLE ROW LEVEL SECURITY;
- ALTER TABLE unique_codes ENABLE ROW LEVEL SECURITY;
- ALTER TABLE connections ENABLE ROW LEVEL SECURITY;
- ALTER TABLE pings ENABLE ROW LEVEL SECURITY;
- ALTER TABLE breaks ENABLE ROW LEVEL SECURITY;
- ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
- ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
- ALTER TABLE payment_transactions ENABLE ROW LEVEL SECURITY;
```

- RLS Policies: `users`

```sql
-- Users can read their own profile
- CREATE POLICY "Users can view own profile" ON users
    FOR SELECT
    USING (auth.uid() = id);

-- Users can update their own profile
- CREATE POLICY "Users can update own profile" ON users
    FOR UPDATE
    USING (auth.uid() = id);

-- Admin can view all users
- CREATE POLICY "Admin can view all users" ON users
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM users
            WHERE id = auth.uid()
            AND phone_number = '+1ADMIN' -- Placeholder for admin check
        )
    );
```

- LS Policies: `sender_profiles`

```sql
-- Senders can manage their own profile
- CREATE POLICY "Senders can view own profile" ON sender_profiles
    FOR SELECT
    USING (user_id = auth.uid());

- CREATE POLICY "Senders can update own profile" ON sender_profiles
    FOR UPDATE
    USING (user_id = auth.uid());

- CREATE POLICY "Senders can insert own profile" ON sender_profiles
    FOR INSERT
    WITH CHECK (user_id = auth.uid());
```

#### RLS Policies: `receiver_profiles`

```sql
-- Receivers can manage their own profile
- CREATE POLICY "Receivers can view own profile" ON receiver_profiles
    FOR SELECT
    USING (user_id = auth.uid());

- CREATE POLICY "Receivers can update own profile" ON receiver_profiles
    FOR UPDATE
    USING (user_id = auth.uid());

- CREATE POLICY "Receivers can insert own profile" ON receiver_profiles
    FOR INSERT
    WITH CHECK (user_id = auth.uid());
```

#### RLS Policies: `unique_codes`

```sql
-- Receivers can view their own code
- CREATE POLICY "Receivers can view own code" ON unique_codes
    FOR SELECT
    USING (receiver_id = auth.uid());

-- Anyone can lookup a code (for connection creation)
- CREATE POLICY "Anyone can lookup active codes" ON unique_codes
    FOR SELECT
    USING (is_active = true);
```

#### RLS Policies: `connections`

```sql
-- Users can view connections where they are sender or receiver
- CREATE POLICY "Users can view own connections" ON connections
    FOR SELECT
    USING (sender_id = auth.uid() OR receiver_id = auth.uid());

-- Users can create connections as sender
- CREATE POLICY "Users can create connections as sender" ON connections
    FOR INSERT
    WITH CHECK (sender_id = auth.uid());

-- Users can update their own connections
- CREATE POLICY "Users can update own connections" ON connections
    FOR UPDATE
    USING (sender_id = auth.uid() OR receiver_id = auth.uid());

-- Users can delete their own connections
- CREATE POLICY "Users can delete own connections" ON connections
    FOR DELETE
    USING (sender_id = auth.uid() OR receiver_id = auth.uid());
```

#### RLS Policies: `pings`

```sql
-- Users can view pings for their connections
- CREATE POLICY "Users can view own pings" ON pings
    FOR SELECT
    USING (sender_id = auth.uid() OR receiver_id = auth.uid());

-- Senders can update their pings (completion)
- CREATE POLICY "Senders can update own pings" ON pings
    FOR UPDATE
    USING (sender_id = auth.uid());
```

#### RLS Policies: `breaks`

```sql
-- Senders can manage their own breaks
- CREATE POLICY "Senders can view own breaks" ON breaks
    FOR SELECT
    USING (sender_id = auth.uid());

- CREATE POLICY "Senders can create own breaks" ON breaks
    FOR INSERT
    WITH CHECK (sender_id = auth.uid());

- CREATE POLICY "Senders can update own breaks" ON breaks
    FOR UPDATE
    USING (sender_id = auth.uid());

- CREATE POLICY "Senders can delete own breaks" ON breaks
    FOR DELETE
    USING (sender_id = auth.uid());
```

#### RLS Policies: `notifications`

```sql
-- Users can view their own notifications
- CREATE POLICY "Users can view own notifications" ON notifications
    FOR SELECT
    USING (user_id = auth.uid());

-- Users can update their own notifications (marking as read)
- CREATE POLICY "Users can update own notifications" ON notifications
    FOR UPDATE
    USING (user_id = auth.uid());
```

#### RLS Policies: `audit_logs`

```sql
-- Users can view their own audit logs
- CREATE POLICY "Users can view own audit logs" ON audit_logs
    FOR SELECT
    USING (user_id = auth.uid());

-- Admin can view all audit logs
- CREATE POLICY "Admin can view all audit logs" ON audit_logs
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM users
            WHERE id = auth.uid()
            AND phone_number = '+1ADMIN' -- Placeholder for admin check
        )
    );
```

#### RLS Policies: `payment_transactions`

```sql
-- Users can view their own payment transactions
- CREATE POLICY "Users can view own transactions" ON payment_transactions
    FOR SELECT
    USING (user_id = auth.uid());
```

### 2.3 Database Functions

#### Function: `generate_unique_code()`

```sql
- CREATE OR REPLACE FUNCTION generate_unique_code()
- RETURNS TEXT AS $$
- DECLARE
    new_code TEXT;
    code_exists BOOLEAN;
- BEGIN
    LOOP
        -- Generate 6-digit numeric code
        new_code := LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0');

        -- Check if code exists
        SELECT EXISTS(
            SELECT 1 FROM unique_codes
            WHERE code = new_code AND is_active = true
        ) INTO code_exists;

        -- Exit loop if code is unique
        EXIT WHEN NOT code_exists;
    END LOOP;

    RETURN new_code;
END;
$$ LANGUAGE plpgsql;
```

#### Function: `create_receiver_code()`

```sql
- CREATE OR REPLACE FUNCTION create_receiver_code(p_user_id UUID)
-RETURNS TEXT AS $$
DECLARE
    v_code TEXT;
BEGIN
    -- Generate unique code
    v_code := generate_unique_code();

    -- Insert code
    INSERT INTO unique_codes (code, receiver_id)
    VALUES (v_code, p_user_id);

    RETURN v_code;
END;
$$ LANGUAGE plpgsql;
```

#### Function: `check_subscription_status()`

```sql
- CREATE OR REPLACE FUNCTION check_subscription_status(p_user_id UUID)
RETURNS TEXT AS $$
DECLARE
    v_status TEXT;
    v_trial_end TIMESTAMPTZ;
    v_sub_end TIMESTAMPTZ;
- BEGIN
    SELECT
        subscription_status,
        trial_end_date,
        subscription_end_date
    INTO v_status, v_trial_end, v_sub_end
    FROM receiver_profiles
    WHERE user_id = p_user_id;

    -- Check if trial expired
    IF v_status = 'trial' AND v_trial_end < now() THEN
        UPDATE receiver_profiles
        SET subscription_status = 'expired'
        WHERE user_id = p_user_id;
        RETURN 'expired';
    END IF;

    -- Check if subscription expired
    IF v_status = 'active' AND v_sub_end < now() THEN
        UPDATE receiver_profiles
        SET subscription_status = 'expired'
        WHERE user_id = p_user_id;
        RETURN 'expired';
    END IF;

    RETURN v_status;
END;
$$ LANGUAGE plpgsql;
```

#### Function: `update_updated_at()`

```sql
- CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for all tables with updated_at
C- REATE TRIGGER users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

- CREATE TRIGGER sender_profiles_updated_at BEFORE UPDATE ON sender_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

- CREATE TRIGGER receiver_profiles_updated_at BEFORE UPDATE ON receiver_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

- CREATE TRIGGER connections_updated_at BEFORE UPDATE ON connections
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

---

## PHASE 3: Authentication & Onboarding

### 3.1 Authentication Flow

**Method:** Phone Number + SMS OTP (One-Time Password)

**Flow:**
1. User launches app
2. App checks for existing session (Supabase Auth token in Keychain)
3. If no session, show Phone Number Entry screen
4. User enters phone number with country code picker
5. App sends OTP via Supabase Auth
6. User enters 6-digit OTP code
7. On successful verification:
   - Create/retrieve user record in `users` table
   - Check `has_completed_onboarding` flag
   - If false, redirect to Role Selection
   - If true, redirect to Dashboard

**Implementation Details:**

```swift
// AuthService.swift
class AuthService {
    let supabase = SupabaseClient(
        supabaseURL: URL(string: Config.supabaseURL)!,
        supabaseKey: Config.supabaseAnonKey
    )

    func sendOTP(phoneNumber: String) async throws {
        try await supabase.auth.signInWithOTP(
            phone: phoneNumber
        )
    }

    func verifyOTP(phoneNumber: String, token: String) async throws -> User {
        let session = try await supabase.auth.verifyOTP(
            phone: phoneNumber,
            token: token,
            type: .sms
        )

        // Fetch or create user
        return try await fetchOrCreateUser(authId: session.user.id)
    }

    func fetchOrCreateUser(authId: UUID) async throws -> User {
        // Check if user exists
        let response = try await supabase.database
            .from("users")
            .select()
            .eq("id", value: authId)
            .single()
            .execute()

        if let user = try? response.decoded(as: User.self) {
            return user
        }

        // Create new user
        let newUser = User(id: authId, phoneNumber: phoneNumber)
        try await supabase.database
            .from("users")
            .insert(newUser)
            .execute()

        return newUser
    }
}
```

### 3.2 Role Selection Screen

**Purpose:** Determine if user is primarily a Sender, Receiver, or needs both roles.

**UI Layout:**
- Title: "How will you use PRUUF?"
- Subtitle: "You can always add the other role later"
- Two large cards:
  - **Sender Card:**
    - Icon: Checkmark symbol
    - Title: "I want to check in daily"
    - Description: "Let people know you're okay with a simple daily ping"
    - Tag: "Always Free"
  - **Receiver Card:**
    - Icon: Heart symbol
    - Title: "I want peace of mind"
    - Description: "Get daily confirmation that your loved ones are safe"
    - Tag: "$2.99/month after 15-day trial"

**Selection Logic:**
- User can only select ONE option initially
- Selection highlights the card with accent color
- "Continue" button appears at bottom
- On continue:
  - Update `users.primary_role`
  - Create `sender_profiles` OR `receiver_profiles` record
  - Redirect to role-specific onboarding flow

**Edge Cases Handled:**
- EC-2.1: User closes app mid-onboarding → Save progress, resume on relaunch
- EC-2.2: User wants both roles → Show option after selecting first role

### 3.3 Sender Onboarding Flow

**Step 1: Tutorial Screen**
- Title: "How PRUUF Works for Senders"
- 3-4 slides explaining:
  1. "Set your daily ping time"
  2. "Tap once to confirm you're okay"
  3. "Connect with people who care about you"
  4. "Take breaks when needed"
- Skip button (top right)
- Next/Done button (bottom)

**Step 2: Ping Time Selection**
- Title: "When should we remind you to ping?"
- Time picker (iOS native wheel picker)
- Subtitle: "Choose a time you'll be awake every day"
- Default: 9:00 AM (user's local time)
- Example: "You'll have until 10:30 AM to check in (90-minute grace period)"
- Continue button

**Implementation:**
```swift
// Store ping_time in sender_profiles as UTC time
func savePingTime(_ localTime: Date) async throws {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.hour, .minute], from: localTime)

    let pingTimeUTC = convertToUTC(hour: components.hour!, minute: components.minute!)

    try await supabase.database
        .from("sender_profiles")
        .insert([
            "user_id": currentUser.id,
            "ping_time": pingTimeUTC
        ])
        .execute()
}
```

**Step 3: Connection Invitation**
- Title: "Invite people to receive your pings"
- Subtitle: "They'll get peace of mind knowing you're safe"
- "Select Contacts" button
- Contact picker (iOS native)
- For each selected contact:
  - Generate SMS with invitation:
    ```
    [Sender Name] wants to send you daily pings on PRUUF to let you know they're safe. Download the app and use code [6-digit code] to connect: https://pruuf.app/join
    ```
- "Skip for Now" option
- Continue button

**Step 4: Notification Permission**
- System prompt for push notification permission
- Explanation: "Get reminders when it's time to ping"
- Request permission using iOS native prompt

**Step 5: Complete**
- Title: "You're all set!"
- Summary of setup:
  - Daily ping time
  - Number of connections invited
- "Go to Dashboard" button
- Set `has_completed_onboarding = true`

### 3.4 Receiver Onboarding Flow

**Step 1: Tutorial Screen**
- Title: "How PRUUF Works for Receivers"
- 3-4 slides explaining:
  1. "Get daily pings from loved ones"
  2. "Know they're safe and sound"
  3. "Get notified if they miss a ping"
  4. "Connect using their unique code"
- Skip button (top right)
- Next/Done button (bottom)

**Step 2: Your Unique Code**
- Title: "Your PRUUF Code"
- Large display of 6-digit code (generated via `create_receiver_code()`)
- Subtitle: "Share this code with senders who want to check in with you"
- "Copy Code" button
- "Share Code" button (iOS share sheet)
- Explanation: "Senders will use this code to connect with you"
- Continue button

**Step 3: Connect to Sender (Optional)**
- Title: "Do you have a sender's code?"
- Subtitle: "If someone invited you, enter their code to connect"
- 6-digit code entry field
- "Connect" button
- "Skip for Now" option
- On successful connection:
  - Verify code exists and is active
  - Create connection record
  - Show success message: "Connected to [Sender Name]!"

**Step 4: Subscription Explanation**
- Title: "15 Days Free, Then $2.99/Month"
- Benefits list:
  - "Unlimited sender connections"
  - "Real-time ping notifications"
  - "Peace of mind 24/7"
  - "Cancel anytime"
- "Your free trial starts now" message
- "Continue" button (does not require payment yet)
- Note: Payment required after trial expires

**Step 5: Notification Permission**
- System prompt for push notification permission
- Explanation: "Get notified when senders ping you"
- Request permission using iOS native prompt

**Step 6: Complete**
- Title: "You're all set!"
- Summary:
  - Your code: [6-digit code]
  - Trial ends: [Date]
  - Connections: [Number]
- "Go to Dashboard" button
- Set `has_completed_onboarding = true`

### 3.5 User Stories: Authentication & Onboarding

#### US-1.1: Phone Number Authentication
**As a** new user
**I want to** sign up using my phone number
**So that** I can quickly create an account without email/password

**Acceptance Criteria:**
- [ ] Phone number entry screen with country code picker
- [ ] SMS OTP sent within 30 seconds
- [ ] 6-digit OTP entry with auto-fill support
- [ ] Session persists in secure keychain
- [ ] "Resend Code" option after 60 seconds
- [ ] Error handling for invalid phone numbers
- [ ] Error handling for network failures

#### US-1.2: Role Selection
**As a** new user
**I want to** choose my role (Sender or Receiver)
**So that** the app is configured for my needs

**Acceptance Criteria:**
- [ ] Clear card-based UI showing both roles
- [ ] Pricing information visible for Receiver role
- [ ] "Always Free" badge on Sender role
- [ ] Only one role selectable initially
- [ ] Selection persisted to database
- [ ] Appropriate profile record created

#### US-1.3: Sender Onboarding
**As a** new sender
**I want to** complete guided setup
**So that** I understand how to use PRUUF and configure my ping time

**Acceptance Criteria:**
- [ ] Tutorial screens with skip option
- [ ] Time picker for daily ping time
- [ ] Grace period explanation (90 minutes)
- [ ] Contact invitation with SMS pre-populated
- [ ] Notification permission request
- [ ] Completion confirmation screen
- [ ] `has_completed_onboarding` flag set to true

#### US-1.4: Receiver Onboarding
**As a** new receiver
**I want to** get my unique code and understand the subscription
**So that** I can connect with senders and know the pricing

**Acceptance Criteria:**
- [ ] Tutorial screens with skip option
- [ ] 6-digit unique code generated and displayed
- [ ] Copy/Share code functionality
- [ ] Optional sender code entry
- [ ] Subscription explanation (15 days free, $2.99/month)
- [ ] Notification permission request
- [ ] Completion confirmation screen
- [ ] `has_completed_onboarding` flag set to true

#### US-1.5: Session Persistence
**As a** returning user
**I want to** stay logged in
**So that** I don't have to re-authenticate every time

**Acceptance Criteria:**
- [ ] Auth token stored securely in iOS Keychain
- [ ] Automatic session restoration on app launch
- [ ] Token refresh handled automatically
- [ ] Logout clears all session data
- [ ] Session expires after 30 days of inactivity

---

## PHASE 4: Dashboard & UI Components

### 4.1 Sender Dashboard

**Primary Screen Components:**

**1. Header Section:**
- User's name (from phone contact or "Me")
- Settings icon (top right)
- Current time display

**2. Today's Ping Status Card:**
- Large central card showing:
  - **Pending State:**
    - Title: "Time to Ping!"
    - Countdown: "2 hours 15 minutes remaining"
    - Large "I'm Okay" button (primary accent color)
    - Subtitle: "Tap to let everyone know you're safe"
  - **Completed State:**
    - Green checkmark icon
    - Title: "Ping Sent!"
    - Time completed: "Completed at 9:15 AM"
    - Subtitle: "See you tomorrow"
  - **Missed State:**
    - Red alert icon
    - Title: "Ping Missed"
    - Time missed: "Deadline was 10:30 AM"
    - "Ping Now" button (marks as late but sends)
  - **On Break State:**
    - Calendar icon
    - Title: "On Break"
    - Break period: "Until [End Date]"
    - "End Break Early" button

**3. In-Person Verification Button:**
- Secondary button below ping card
- Icon: Location pin
- Text: "Verify In Person"
- Available at any time
- Triggers location permission request first time

**4. Your Receivers Section:**
- Title: "Your Receivers" with count badge
- List of receivers (scrollable if more than 3)
- Each receiver shows:
  - Name (from phone contact or "Unknown")
  - Status indicator: "Active" (green dot) or "Paused" (gray)
  - Last interaction timestamp
- "+ Add Receiver" button at bottom
- Empty state: "No receivers yet. Invite people to give them peace of mind."

**5. Recent Activity:**
- Last 7 days of ping history
- Simple calendar view with colored dots:
  - Green: Completed on time
  - Yellow: Completed late
  - Red: Missed
  - Gray: On break
- Tap to see details

**6. Quick Actions (Bottom Sheet):**
- "Schedule a Break"
- "Change Ping Time"
- "Invite Receivers"
- "Settings"

### 4.2 Receiver Dashboard

**Primary Screen Components:**

**1. Header Section:**
- User's name
- Settings icon (top right)
- Subscription status badge ("Trial: 12 days left" or "Active")

**2. Your Senders Section:**
- Title: "Your Senders" with count badge
- List of senders (scrollable)
- Each sender card shows:
  - Name (from phone contact or phone number)
  - **Ping Status:**
    - Green checkmark: "Pinged today at 9:15 AM"
    - Yellow clock: "Ping expected by 10:30 AM" (with countdown)
    - Red alert: "Missed ping - Last seen [date/time]"
    - Gray calendar: "On break until [date]"
  - Ping streak: "42 days in a row"
  - Action button: "..." menu for options
- "+ Connect to Sender" button at bottom
- Empty state: "No senders yet. Share your code: [6-digit code] (Copy)"

**3. Your PRUUF Code Card:**
- Always visible at top or in prominent position
- Shows 6-digit code in large, readable font
- "Copy" button
- "Share" button
- "How to use" info icon

**4. Recent Activity:**
- Timeline view of all sender pings
- Last 7 days by default
- Filter by sender
- Each entry shows:
  - Sender name
  - Timestamp
  - Status (completed/missed)
  - Method (tap/in-person)

**5. Subscription Status Card:**
- **During Trial:**
  - "Trial ends in [X] days"
  - "Subscribe to keep your peace of mind"
  - "Subscribe Now" button
- **Active Subscription:**
  - "Next billing: [Date]"
  - "$2.99/month"
  - "Manage Subscription" link
- **Expired/Past Due:**
  - Red alert banner
  - "Subscription expired - Update payment"
  - "Update Payment" button

**6. Quick Actions:**
- "Share My Code"
- "Connect to Sender"
- "Manage Subscription"
- "Settings"

### 4.3 Dual Role Dashboard (Both)

For users with both sender and receiver roles:

**Tab Navigation:**
- Two tabs at top: "My Pings" and "Their Pings"
- "My Pings" tab shows Sender Dashboard
- "Their Pings" tab shows Receiver Dashboard
- Badge notifications on tabs for missed pings or pending actions

**Subscription Logic:**
- If user has ANY receiver connections → Subscription required
- Sender functionality always remains free

### 4.4 UI/UX Design Specifications

**Color Palette:**
- Primary: `#007AFF` (iOS Blue)
- Success: `#34C759` (iOS Green)
- Warning: `#FF9500` (iOS Orange)
- Error: `#FF3B30` (iOS Red)
- Background: `#F2F2F7` (iOS Gray 6 - Light Mode)
- Card Background: `#FFFFFF`
- Text Primary: `#000000`
- Text Secondary: `#8E8E93`

**Dark Mode Support:**
- All colors adapt to dark mode equivalents
- Use iOS system colors for automatic adaptation

**Typography:**
- Headings: SF Pro Display, Bold
- Body: SF Pro Text, Regular
- Captions: SF Pro Text, Light
- Code (for 6-digit codes): SF Mono, Medium

**Spacing:**
- Screen padding: 16pt
- Card padding: 16pt
- Element spacing: 12pt
- Section spacing: 24pt

**Animations:**
- Button press: Scale 0.95 with haptic feedback
- Card transitions: Slide up/down with ease-in-out
- Loading states: iOS spinner with blur background
- Success states: Confetti or checkmark animation

**Accessibility:**
- Minimum touch target: 44x44 pt
- Text size supports Dynamic Type
- VoiceOver labels on all interactive elements
- Color contrast ratio: 4.5:1 minimum
- Reduce motion support for animations

### 4.5 Loading States & Empty States

**Loading States:**
- Full screen loading: iOS spinner centered with blur
- Inline loading: Skeleton screens for cards
- Pull to refresh: Standard iOS pull-to-refresh
- No progressive content loading (per user preference)

**Empty States:**
- **No Receivers (Sender):**
  - Illustration: Empty inbox
  - Title: "No receivers yet"
  - Message: "Invite people to give them peace of mind"
  - Button: "Invite Receivers"

- **No Senders (Receiver):**
  - Illustration: Waiting figure
  - Title: "No senders yet"
  - Message: "Share your code: [6-digit code]"
  - Buttons: "Copy Code" + "Share Code"

- **No Activity:**
  - Illustration: Calendar
  - Title: "No activity yet"
  - Message: "Your ping history will appear here"

- **Network Error:**
  - Illustration: Disconnected icon
  - Title: "Connection lost"
  - Message: "Check your internet and try again"
  - Button: "Retry"

### 4.6 User Stories: Dashboard & UI

#### US-4.1: Sender Dashboard View
**As a** sender
**I want to** see my daily ping status at a glance
**So that** I know if I need to ping and who is receiving my pings

**Acceptance Criteria:**
- [ ] Ping status card shows pending/completed/missed state
- [ ] Countdown timer shows time remaining
- [ ] "I'm Okay" button is prominently displayed
- [ ] Receivers list shows all active connections
- [ ] Recent activity shows last 7 days
- [ ] Pull to refresh updates all data
- [ ] Loading states use proper blocking UI

#### US-4.2: Receiver Dashboard View
**As a** receiver
**I want to** see all my senders' ping statuses
**So that** I know everyone is safe

**Acceptance Criteria:**
- [ ] Senders list shows all connections
- [ ] Each sender card shows current ping status
- [ ] Visual indicators (green/yellow/red) show status at a glance
- [ ] Ping streaks displayed for each sender
- [ ] My unique code is easily accessible
- [ ] Subscription status is visible
- [ ] Empty state shows when no senders connected

#### US-4.3: In-Person Verification
**As a** sender
**I want to** verify in person as an alternative to tapping
**So that** I have flexibility in how I complete my ping

**Acceptance Criteria:**
- [ ] "Verify In Person" button always visible on dashboard
- [ ] Location permission requested on first use
- [ ] Location captured and stored with ping
- [ ] Ping marked as completed with "in_person" method
- [ ] Works even before scheduled ping time
- [ ] Receivers notified of in-person verification

#### US-4.4: Dual Role Navigation
**As a** user with both roles
**I want to** easily switch between sender and receiver views
**So that** I can manage both aspects of my account

**Acceptance Criteria:**
- [ ] Tab navigation at top of screen
- [ ] "My Pings" tab shows sender dashboard
- [ ] "Their Pings" tab shows receiver dashboard
- [ ] Badge notifications on tabs for urgent items
- [ ] Smooth tab transitions
- [ ] Each tab maintains its scroll position

#### US-4.5: Responsive Loading
**As a** user
**I want to** see proper loading states
**So that** I understand when the app is working

**Acceptance Criteria:**
- [ ] Full-screen spinner for initial load
- [ ] Skeleton screens for cards during refresh
- [ ] Pull-to-refresh supported on main dashboard
- [ ] No progressive content loading
- [ ] Error states with retry options
- [ ] Network status feedback

---

## PHASE 5: Connection Management

### 5.1 Creating Connections

**Sender Connecting to Receiver:**

**Flow:**
1. Sender taps "+ Add Receiver" from dashboard
2. Show "Connect to Receiver" screen
3. Input options:
   - Manual entry: 6-digit code field
   - Paste from clipboard (auto-detect)
   - Scan QR code (future enhancement)
4. Sender enters receiver's code
5. App validates code via edge function `validate_connection_code()`
6. If valid:
   - Create connection record with status='active'
   - Create ping record for today (if not yet pinged)
   - Show success message: "Connected to [Receiver Name]!"
   - Send notification to receiver: "[Sender] is now sending you pings"
7. If invalid:
   - Show error: "Invalid code. Please check and try again."
   - Allow retry

**Edge Cases Handled:**
- EC-5.1: Self-connection attempt → Error: "Cannot connect to your own code"
- EC-5.2: Duplicate connection → Error: "You're already connected to this user"
- EC-5.3: Reactivating deleted connection → Update status to 'active', restore pings
- EC-5.4: Both users add each other simultaneously → Deduplicate, keep first creation

### 5.2 Managing Connections

**Sender Actions:**
- "Pause Connection" → Sets connection status to 'paused', stops ping generation
- "Remove Connection" → Sets connection status to 'deleted'
- "Contact Receiver" → Opens SMS/phone to receiver
- "View History" → Shows ping history for this receiver

**Receiver Actions:**
- "Pause Notifications" → Mutes notifications for this sender only
- "Remove Connection" → Removes sender from list
- "Contact Sender" → Opens SMS/phone to sender
- "View History" → Shows ping history for this sender

### 5.3 User Stories: Connection Management

#### US-5.1: Connect Using Code
**As a** sender
**I want to** connect to a receiver using their code
**So that** they receive my daily pings

**Acceptance Criteria:**
- [ ] Code entry field supports 6 digits
- [ ] Paste from clipboard supported
- [ ] Code validation happens immediately
- [ ] Success message shows receiver's name (from contacts)
- [ ] Connection appears immediately in receivers list
- [ ] Receiver gets notification of new connection
- [ ] Error messages for invalid/expired codes

#### US-5.2: Invite via SMS
**As a** sender
**I want to** invite receivers via SMS
**So that** they can easily download the app and connect

**Acceptance Criteria:**
- [ ] "Invite Receivers" button opens contact picker
- [ ] Pre-populated SMS with invitation message
- [ ] Receiver's code included in message
- [ ] App download link included
- [ ] Multiple recipients supported
- [ ] SMS composer is native iOS interface

#### US-5.3: Pause Connection
**As a** sender
**I want to** temporarily pause pings to a specific receiver
**So that** they don't worry if I need privacy

**Acceptance Criteria:**
- [ ] Pause option in connection menu
- [ ] Confirmation dialog explains impact
- [ ] Connection status updates to 'paused'
- [ ] No pings generated while paused
- [ ] Receiver notified of pause
- [ ] Easy to resume ("Resume Connection" option)

#### US-5.4: Remove Connection
**As a** user
**I want to** remove a connection
**So that** I can manage my connections list

**Acceptance Criteria:**
- [ ] Remove option in connection menu
- [ ] Confirmation dialog prevents accidents
- [ ] Connection status set to 'deleted'
- [ ] Removed connection disappears from list
- [ ] Other user notified of removal
- [ ] Can reconnect using code again later

---

## PHASE 6: Ping System & Scheduling

### 6.1 Daily Ping Generation

**Automated Ping Creation:**
- Edge Function `generate_daily_pings()` runs at midnight UTC (cron: `0 0 * * *`)
- Creates ping records for all active sender/receiver connections
- Respects sender breaks (creates pings with status='on_break')
- Checks receiver subscription status before creating pings
- Calculates deadline as scheduled_time + 90 minutes

**Scheduled Time Calculation:**
- Sender's ping_time stored in UTC
- Converted to sender's local timezone for display
- Adjusts automatically when sender travels (uses device timezone)
- Example: "9 AM local" means 9 AM wherever sender currently is

### 6.2 Ping Completion Methods

**Method 1: Tap to Ping**
1. Sender taps "I'm Okay" button
2. App calls edge function `complete_ping()`
3. All pending pings for today marked as completed
4. completion_method = 'tap'
5. completed_at = current timestamp
6. Success animation plays
7. Receivers notified within 30 seconds

**Method 2: In-Person Verification**
1. Sender taps "Verify In Person" button (available anytime)
2. App requests location permission (first time only)
3. Captures GPS coordinates (lat, lon, accuracy)
4. Calls `complete_ping()` with method='in_person' and location
5. Location stored in verification_location JSONB field
6. Same completion flow as tap
7. Receivers see "Verified in person" indicator

**Method 3: Late Ping**
1. After deadline passes, "I'm Okay" changes to "Ping Now"
2. Sender can still complete ping
3. Ping marked as completed but flagged as late
4. Receivers notified it was late: "[Sender] pinged late at [time]"
5. Still counts toward streak

### 6.3 Ping Notifications Schedule

**To Sender:**
1. **Scheduled Time:** "Time to ping! Tap to let everyone know you're okay."
2. **15 Minutes Before Deadline:** "Reminder: 15 minutes until your ping deadline"
3. **At Deadline:** "Final reminder: Your ping deadline is now"

**To Receivers:**
1. **On-Time Completion:** "[Sender Name] is okay! ✓"
2. **Late Completion:** "[Sender Name] pinged late at [time]"
3. **Missed Ping (5 min after deadline):** "[Sender Name] missed their ping. Last seen [time]."
4. **Break Started:** "[Sender Name] is on break until [date]"

### 6.4 Ping Streak Calculation

**Rules:**
- Consecutive days of completed pings
- Breaks do NOT break the streak (counted as completed)
- Missed pings reset streak to 0
- Late pings count toward streak
- Calculated daily via `calculate_streak()` function
- Displayed on receiver dashboard for each sender

### 6.5 User Stories: Ping System

#### US-6.1: Daily Ping Reminder
**As a** sender
**I want to** receive a notification at my scheduled ping time
**So that** I remember to check in

**Acceptance Criteria:**
- [ ] Notification sent at exact scheduled time
- [ ] Notification includes deep link to app
- [ ] Works even when app is closed/backgrounded
- [ ] Notification preferences can be customized
- [ ] "Resend" if notification fails

#### US-6.2: Complete Ping by Tapping
**As a** sender
**I want to** complete my ping with one tap
**So that** it's quick and easy

**Acceptance Criteria:**
- [ ] "I'm Okay" button prominently displayed when pending
- [ ] Single tap completes all pending pings
- [ ] Success animation plays (checkmark/confetti)
- [ ] Dashboard immediately updates to "Completed" state
- [ ] All receivers notified within 30 seconds
- [ ] Timestamp recorded accurately

#### US-6.3: In-Person Verification
**As a** sender
**I want to** verify in person using location
**So that** I have proof of presence

**Acceptance Criteria:**
- [ ] "Verify In Person" button available anytime
- [ ] Location permission requested on first use
- [ ] Current location captured (lat/lon/accuracy)
- [ ] Ping marked as completed with 'in_person' method
- [ ] Location stored securely in database
- [ ] Receivers see "Verified in person" indicator

#### US-6.4: Late Ping Submission
**As a** sender
**I want to** submit a ping after the deadline
**So that** I can still notify receivers even if late

**Acceptance Criteria:**
- [ ] "Ping Now" button available after deadline
- [ ] Ping marked as completed but flagged as late
- [ ] Receivers notified it was a late ping
- [ ] Late pings still count toward streak
- [ ] Timestamp shows actual completion time

#### US-6.5: View Ping History
**As a** sender or receiver
**I want to** see ping history
**So that** I can track consistency

**Acceptance Criteria:**
- [ ] Calendar view shows last 30 days
- [ ] Color coding: Green (on time), Yellow (late), Red (missed), Gray (break)
- [ ] Tap date to see details
- [ ] Current streak displayed prominently
- [ ] Filter by connection (if multiple)

---

## PHASE 7: Breaks & Pauses

### 7.1 Scheduling Breaks

**Purpose:** Allow senders to pause ping requirements for planned absences (vacation, hospital stay, etc.)

**Flow:**
1. Sender taps "Schedule a Break" from dashboard
2. Show "Schedule Break" screen with:
   - Start Date picker (date only, not time)
   - End Date picker (must be >= start date)
   - Optional notes field
   - "Schedule Break" button
3. On submit:
   - Validate dates (end >= start, start >= today)
   - Create break record with status='scheduled'
   - Show confirmation: "Break scheduled for [date range]"
   - Send notifications to all receivers: "[Sender] will be on break [dates]"
4. Dashboard shows "On Break" state during break period

**Break Status Transitions:**
- `scheduled` → `active` (automatically at start_date midnight)
- `active` → `completed` (automatically at end_date + 1 day midnight)
- `scheduled` or `active` → `canceled` (user cancels early)

**Ping Behavior During Breaks:**
- Daily ping generation still occurs
- Pings created with status='on_break' instead of 'pending'
- Receivers see: "[Sender] is on break until [end_date]"
- Streak continues (breaks don't break streaks)
- Sender not required to ping, but CAN complete voluntarily

### 7.2 Managing Breaks

**View Upcoming Breaks:**
- Settings > Breaks
- List of scheduled/active breaks
- Each shows: Date range, Status, Notes

**Cancel Break:**
- Tap break in list
- "Cancel Break" button
- Confirmation dialog: "Cancel this break?"
- On confirm:
  - Update status to 'canceled'
  - Future pings revert to 'pending'
  - Notify receivers: "[Sender] ended their break early"

**End Break Early:**
- "End Break Early" button on dashboard during active break
- Same cancellation flow
- Immediately resume normal ping requirements

### 7.3 Edge Cases

- EC-7.1: Overlapping breaks → Prevent: Show error "You already have a break during this period"
- EC-7.2: Break starts today → Immediately set status='active', today's ping becomes 'on_break'
- EC-7.3: Break ends today → Tomorrow's ping reverts to 'pending'
- EC-7.4: Connection pause during break → Both statuses apply; no pings generated
- EC-7.5: Break longer than 1 year → Warn: "Breaks longer than 1 year may affect your account"

### 7.4 User Stories: Breaks

#### US-7.1: Schedule a Break
**As a** sender
**I want to** schedule a break from ping requirements
**So that** receivers know I'm away and don't worry

**Acceptance Criteria:**
- [ ] Date pickers for start and end dates
- [ ] Optional notes field for context
- [ ] Validation prevents invalid date ranges
- [ ] Confirmation message after scheduling
- [ ] Receivers notified of upcoming break
- [ ] Dashboard shows break status

#### US-7.2: Cancel Break Early
**As a** sender
**I want to** end a break early
**So that** I can resume normal pings sooner than planned

**Acceptance Criteria:**
- [ ] "End Break Early" button on dashboard
- [ ] Confirmation dialog prevents accidents
- [ ] Break status updated to 'canceled'
- [ ] Normal ping requirements resume immediately
- [ ] Receivers notified of early return

#### US-7.3: View Break Schedule
**As a** sender
**I want to** see my upcoming and past breaks
**So that** I can manage my schedule

**Acceptance Criteria:**
- [ ] List view of all breaks (scheduled, active, completed, canceled)
- [ ] Each break shows date range, status, notes
- [ ] Can tap to view details or cancel
- [ ] Past breaks archived but visible
- [ ] Filter by status

---

## PHASE 8: Notifications

### 8.1 Push Notification Setup

**iOS Configuration:**
1. Enable Push Notifications capability in Xcode
2. Register for remote notifications
3. Request user permission during onboarding
4. Store device token in `users.device_token`
5. Use Apple Push Notification service (APNs)

**Supabase Integration:**
- Store APNs device tokens in database
- Edge functions send notifications via APNs HTTP/2 API
- Handle token updates when device re-registers
- Remove invalid tokens on delivery failure

### 8.2 Notification Types & Content

**1. Ping Reminder (to Sender)**
```json
{
  "aps": {
    "alert": {
      "title": "Time to ping!",
      "body": "Tap to let everyone know you're okay."
    },
    "sound": "default",
    "badge": 1
  },
  "deeplink": "pruuf://dashboard"
}
```

**2. Missed Ping Alert (to Receiver)**
```json
{
  "aps": {
    "alert": {
      "title": "Missed Ping Alert",
      "body": "[Sender Name] missed their ping. Last seen [time]."
    },
    "sound": "default",
    "badge": 1,
    "category": "MISSED_PING"
  },
  "deeplink": "pruuf://sender/[sender_id]"
}
```

**3. Ping Completed (to Receiver)**
```json
{
  "aps": {
    "alert": {
      "title": "[Sender Name] is okay!",
      "body": "Checked in at [time] ✓"
    },
    "sound": "default"
  },
  "deeplink": "pruuf://dashboard"
}
```

**4. Connection Request (to Receiver)**
```json
{
  "aps": {
    "alert": {
      "title": "New Connection",
      "body": "[Sender Name] is now sending you pings"
    },
    "sound": "default"
  },
  "deeplink": "pruuf://connections"
}
```

**5. Trial Ending (to Receiver)**
```json
{
  "aps": {
    "alert": {
      "title": "Trial Ending Soon",
      "body": "Your free trial ends in 3 days. Subscribe to keep your peace of mind."
    },
    "sound": "default"
  },
  "deeplink": "pruuf://subscription"
}
```

### 8.3 Notification Preferences

**Settings > Notifications:**
- Master toggle: Enable/Disable all notifications
- Sender preferences:
  - Ping reminders (scheduled time)
  - 15-minute warning
  - Deadline warning
- Receiver preferences:
  - Ping completed notifications
  - Missed ping alerts
  - Connection requests
- Per-sender muting for receivers
- Quiet hours: No notifications during specified times (future)

### 8.4 In-App Notifications

**Notification Center (in-app):**
- Bell icon in header with badge count
- Tap to see list of recent notifications
- Last 30 days of notifications
- Mark as read individually or all at once
- Delete notifications
- Tap notification to navigate to relevant screen

### 8.5 User Stories: Notifications

#### US-8.1: Receive Push Notifications
**As a** user
**I want to** receive push notifications for important events
**So that** I stay informed without opening the app

**Acceptance Criteria:**
- [ ] Notifications sent via APNs
- [ ] Appear on lock screen and notification center
- [ ] Deep links open relevant screen in app
- [ ] Badge count updates automatically
- [ ] Sound and vibration configurable

#### US-8.2: Customize Notification Preferences
**As a** user
**I want to** customize which notifications I receive
**So that** I'm not overwhelmed by alerts

**Acceptance Criteria:**
- [ ] Settings > Notifications screen
- [ ] Toggle for each notification type
- [ ] Master enable/disable switch
- [ ] Per-sender muting (receivers only)
- [ ] Changes take effect immediately

#### US-8.3: View Notification History
**As a** user
**I want to** see past notifications
**So that** I can review what I might have missed

**Acceptance Criteria:**
- [ ] Bell icon with badge count in header
- [ ] List of last 30 days of notifications
- [ ] Mark as read individually or all
- [ ] Delete notifications
- [ ] Tap to navigate to related content

---

## PHASE 9: Subscription & Payments

### 9.1 Subscription Model

**Pricing:**
- Receiver-only users: $2.99/month
- Senders: Always free
- Dual role users (Both): $2.99/month (only if they have receiver connections)
- 15-day free trial for all receivers
- No credit card required to start trial

**Payment Provider:** Apple In-App Purchases (StoreKit 2)

**Subscription Tiers:**
- Product ID: `com.pruuf.receiver.monthly`
- Price: $2.99 USD/month
- Auto-renewable subscription
- Managed through App Store

### 9.2 Trial Period

**Trial Flow:**
1. User selects Receiver role during onboarding
2. Trial starts immediately (no payment required)
3. trial_start_date = now
4. trial_end_date = now + 15 days
5. subscription_status = 'trial'
6. User gets full access during trial

**Trial Notifications:**
- Day 12: "Your trial ends in 3 days"
- Day 14: "Your trial ends tomorrow"
- Day 15: "Your trial has ended. Subscribe to continue"

**Post-Trial Behavior:**
- If not subscribed by end of trial:
  - subscription_status = 'expired'
  - Receivers stop getting ping notifications
  - Senders cannot create pings for expired receivers
  - User sees "Subscribe to Continue" banner
  - Access to history remains (read-only)

### 9.3 Subscription Management

**Subscribe Flow:**
1. User taps "Subscribe Now" button
2. Show App Store subscription sheet (StoreKit)
3. User completes purchase through Apple
4. App receives purchase notification
5. Validate receipt with Apple
6. Update database:
   - subscription_status = 'active'
   - subscription_start_date = now
   - subscription_end_date = now + 1 month
   - stripe_subscription_id = Apple receipt ID
7. Resume full functionality
8. Show confirmation: "You're subscribed! ✓"

**Restore Purchases:**
- "Restore Purchases" button in Settings > Subscription
- Queries App Store for existing purchases
- Updates database if active subscription found
- Useful for reinstalls or device changes

**Cancel Subscription:**
- Handled through iOS Settings > Apple ID > Subscriptions
- App detects cancellation via App Store Server Notifications
- Update subscription_status = 'canceled'
- Access continues until end of billing period
- Show message: "Your subscription will end on [date]"

**Resubscribe:**
- After cancellation or expiration
- "Subscribe" button appears
- Same subscription flow as initial purchase
- Restores full functionality immediately

### 9.4 Payment Webhooks

**App Store Server Notifications:**
Listen for Apple's webhooks for:
- `INITIAL_BUY` → Set status to 'active'
- `RENEWAL` → Extend subscription_end_date
- `CANCEL` → Set status to 'canceled'
- `DID_FAIL_TO_RENEW` → Set status to 'past_due', notify user
- `REFUND` → Set status to 'expired', log transaction

**Edge Function: `handle_appstore_webhook()`**
```javascript
export async function handler(req: Request) {
  const notification = await req.json();
  const { notificationType, subtype, data } = notification;

  // Verify webhook signature from Apple
  const isValid = await verifyAppleWebhookSignature(req);
  if (!isValid) {
    return new Response('Invalid signature', { status: 401 });
  }

  const transactionId = data.transactionId;
  const productId = data.productId;

  // Find user by transaction/receipt
  const { data: receiver } = await supabaseAdmin
    .from('receiver_profiles')
    .select('user_id')
    .eq('stripe_subscription_id', transactionId)
    .single();

  switch (notificationType) {
    case 'INITIAL_BUY':
      await updateSubscription(receiver.user_id, 'active');
      break;
    case 'RENEWAL':
      await extendSubscription(receiver.user_id, 30); // days
      break;
    case 'CANCEL':
      await updateSubscription(receiver.user_id, 'canceled');
      break;
    case 'DID_FAIL_TO_RENEW':
      await updateSubscription(receiver.user_id, 'past_due');
      await sendPaymentFailedNotification(receiver.user_id);
      break;
    case 'REFUND':
      await updateSubscription(receiver.user_id, 'expired');
      await logRefund(receiver.user_id, transactionId);
      break;
  }

  return new Response('OK', { status: 200 });
}
```

### 9.5 Subscription Status Checks

**Before Ping Generation:**
- Daily cron job checks receiver subscription status
- If expired → Skip ping generation for that connection
- If past_due → Grace period of 3 days, then skip

**On App Launch:**
- Check subscription status
- If expired → Show "Subscription Expired" banner
- If past_due → Show "Payment Failed - Update Payment Method"

### 9.6 User Stories: Subscription & Payments

#### US-9.1: Start Free Trial
**As a** new receiver
**I want to** start a 15-day free trial without payment
**So that** I can try PRUUF before committing

**Acceptance Criteria:**
- [ ] Trial starts automatically when selecting Receiver role
- [ ] No credit card required during onboarding
- [ ] Full access for 15 days
- [ ] Trial end date displayed in dashboard
- [ ] Notifications at 3 days, 1 day, and expiration

#### US-9.2: Subscribe After Trial
**As a** receiver
**I want to** subscribe after my trial ends
**So that** I can continue using PRUUF

**Acceptance Criteria:**
- [ ] "Subscribe Now" button in dashboard
- [ ] Apple subscription sheet shown
- [ ] Payment processed through App Store
- [ ] Subscription activated immediately
- [ ] Confirmation message displayed

#### US-9.3: Manage Subscription
**As a** subscribed receiver
**I want to** manage my subscription
**So that** I can cancel or update payment

**Acceptance Criteria:**
- [ ] "Manage Subscription" link opens iOS Settings
- [ ] Current status and next billing date visible
- [ ] Cancel option available
- [ ] Access continues until end of period after cancel
- [ ] Can resubscribe anytime

#### US-9.4: Restore Purchases
**As a** receiver who reinstalled the app
**I want to** restore my subscription
**So that** I don't lose access

**Acceptance Criteria:**
- [ ] "Restore Purchases" button in Settings
- [ ] Queries App Store for active purchases
- [ ] Updates local database with subscription status
- [ ] Access restored immediately if subscription found
- [ ] Error message if no subscription found

---

## PHASE 10: Settings & Preferences

### 10.1 Settings Screen Structure

**Navigation:** Dashboard > Settings icon

**Sections:**

**1. Account**
- Phone number (read-only)
- Timezone (auto-detected, read-only)
- Role: Sender / Receiver / Both
- "Add Sender Role" or "Add Receiver Role" button
- "Delete Account" (danger zone)

**2. Ping Settings (Senders only)**
- Daily ping time (time picker)
- Grace period: 90 minutes (read-only, future: customizable)
- Enable/disable pings (master toggle)
- "Schedule a Break"

**3. Notifications**
- Master toggle: Enable/Disable all
- Ping reminders
- 15-minute warning
- Deadline warning
- Ping completed (receivers)
- Missed ping alerts (receivers)
- Connection requests
- Payment reminders

**4. Subscription (Receivers only)**
- Current status (Trial / Active / Expired)
- Next billing date
- "Subscribe Now" or "Manage Subscription"
- "Restore Purchases"

**5. Connections**
- View all connections
- Manage active/paused connections
- "Your PRUUF Code" (receivers)

**6. Privacy & Data**
- Export my data (GDPR compliance)
- Delete my data
- Privacy policy link
- Terms of service link

**7. About**
- App version
- Build number
- "Contact Support"
- "Rate PRUUF"
- "Share with Friends"

### 10.2 Account Management

**Add Role:**
- "Add Sender Role" button (for receivers)
- "Add Receiver Role" button (for senders)
- On tap:
  - Create sender_profiles or receiver_profiles record
  - Update users.primary_role to 'both'
  - Redirect to role-specific onboarding
  - For receiver role: Start 15-day trial

**Change Ping Time:**
- Time picker (iOS wheel)
- Shows current time
- Updates sender_profiles.ping_time
- Confirmation: "Ping time updated to [time]"
- Next ping scheduled for new time
- Note: "This will take effect tomorrow"

**Delete Account:**
- "Delete Account" button in red
- Confirmation flow:
  1. "Are you sure?" dialog
  2. "Enter your phone number to confirm"
  3. On confirm:
     - Soft delete: Set users.is_active = false
     - Set all connections status = 'deleted'
     - Stop ping generation
     - Cancel subscription
     - Keep data for 30 days (regulatory requirement)
     - Log audit event
     - Sign out user
  4. After 30 days: Hard delete all user data (scheduled job)

### 10.3 Data Export (GDPR)

**Export My Data:**
- "Export My Data" button in Privacy & Data
- Generates ZIP file containing:
  - User profile (JSON)
  - All connections (JSON)
  - All pings history (CSV)
  - All notifications (CSV)
  - Break history (JSON)
  - Payment transactions (CSV)
- Delivered via email or download link
- Processed within 48 hours
- Notification when ready

**Edge Function: `export_user_data()`**
```javascript
export async function handler(req: Request) {
  const { userId } = await req.json();

  // Gather all user data
  const userData = await gatherUserData(userId);

  // Generate ZIP file
  const zipBuffer = await createZip(userData);

  // Upload to Storage bucket (temporary, 7-day expiration)
  const { data: upload } = await supabaseAdmin.storage
    .from('exports')
    .upload(`${userId}-export-${Date.now()}.zip`, zipBuffer);

  // Generate signed URL
  const { data: signedUrl } = await supabaseAdmin.storage
    .from('exports')
    .createSignedUrl(upload.path, 60 * 60 * 24 * 7); // 7 days

  // Send email with download link
  await sendEmail(
    user.email,
    'Your PRUUF Data Export',
    `Your data export is ready: ${signedUrl}`
  );

  return new Response('Export initiated', { status: 200 });
}
```

### 10.4 User Stories: Settings

#### US-10.1: Change Ping Time
**As a** sender
**I want to** change my daily ping time
**So that** it fits my schedule

**Acceptance Criteria:**
- [ ] Settings > Ping Settings > Daily Ping Time
- [ ] Time picker shows current time
- [ ] Updates saved to database
- [ ] Confirmation message displayed
- [ ] Next ping scheduled for new time
- [ ] Receivers notified of time change

#### US-10.2: Add Second Role
**As a** sender
**I want to** add the receiver role
**So that** I can use both features

**Acceptance Criteria:**
- [ ] "Add Receiver Role" button in Settings > Account
- [ ] Onboarding flow for new role
- [ ] Unique code generated (receivers)
- [ ] Dashboard changes to tabbed view
- [ ] Trial starts for receiver functionality
- [ ] Subscription required if adding receiver connections

#### US-10.3: Delete Account
**As a** user
**I want to** delete my account
**So that** my data is removed

**Acceptance Criteria:**
- [ ] "Delete Account" button in Settings
- [ ] Multiple confirmation steps
- [ ] Phone number verification required
- [ ] All connections removed
- [ ] Subscription canceled
- [ ] Account marked as deleted
- [ ] Data retained 30 days then purged
- [ ] User signed out immediately

#### US-10.4: Export My Data
**As a** user
**I want to** export all my data
**So that** I have a copy for my records

**Acceptance Criteria:**
- [ ] "Export My Data" button in Settings > Privacy
- [ ] Processing message displayed
- [ ] ZIP file generated with all data
- [ ] Download link sent via email
- [ ] Includes: profile, connections, pings, notifications, payments
- [ ] Available for 7 days

---

## PHASE 11: Admin Dashboard

### 11.1 Admin Access

**Admin Credentials:**
- Email: wesleymwilliams@gmail.com
- Password: W@$hingt0n1
- Role: Super Admin

**Admin Dashboard URL:**
- https://oaiteiceynliooxpeuxt.supabase.co/project/_/admin
- OR custom web dashboard built with React/Next.js

### 11.2 Admin Dashboard Features

**1. User Management**
- Total users count
- Active users (last 7/30 days)
- New signups (daily/weekly/monthly)
- User search by phone number
- View user details
- Impersonate user (for debugging)
- Deactivate/reactivate accounts
- Manual subscription updates

**2. Connection Analytics**
- Total connections
- Active connections
- Paused connections
- Average connections per user
- Connection growth over time
- Top users by connection count

**3. Ping Analytics**
- Total pings sent today/week/month
- Completion rate (on-time vs late vs missed)
- Average completion time
- Ping streaks distribution
- Missed ping alerts
- Break usage statistics

**4. Subscription Metrics**
- Total revenue (MRR)
- Active subscriptions
- Trial conversions
- Churn rate
- Average revenue per user (ARPU)
- Lifetime value (LTV)
- Payment failures
- Refunds/chargebacks

**5. System Health**
- Edge function execution times
- Database query performance
- API error rates
- Push notification delivery rates
- Cron job success rates
- Storage usage

**6. Operations**
- Manual ping generation (for testing)
- Send test notifications
- Cancel subscriptions (with reason)
- Refund payments
- View audit logs
- Export reports (CSV/JSON)

### 11.3 Admin Roles & Permissions

**Super Admin (wesleymwilliams@gmail.com):**
- Full system access
- User management
- Subscription management
- System configuration
- View all data
- Export reports

**Support Admin (future):**
- View user data (read-only)
- View subscriptions (read-only)
- Cannot modify data
- Cannot access financial info

### 11.4 Admin Dashboard Implementation

**Option A: Supabase Admin Panel**
- Use built-in Supabase admin panel
- Direct database access
- No custom UI needed
- Limited customization

**Option B: Custom Dashboard (Recommended)**
- Build with Next.js + React
- Hosted separately or on Supabase hosting
- Custom analytics and visualizations
- Better UX for operations tasks

**Tech Stack:**
- Framework: Next.js 14
- UI: shadcn/ui components
- Charts: Recharts or Chart.js
- Auth: Supabase Auth
- Data: Supabase queries

### 11.5 User Stories: Admin Dashboard

#### US-11.1: View User Metrics
**As an** admin
**I want to** view user growth and engagement metrics
**So that** I can monitor product health

**Acceptance Criteria:**
- [ ] Dashboard shows total users, new signups, active users
- [ ] Charts for user growth over time
- [ ] Breakdown by role (sender/receiver/both)
- [ ] Daily/weekly/monthly views
- [ ] Export to CSV

#### US-11.2: Manage Subscriptions
**As an** admin
**I want to** manage user subscriptions
**So that** I can handle support requests

**Acceptance Criteria:**
- [ ] Search user by phone/email
- [ ] View subscription status and history
- [ ] Manually extend/cancel subscriptions
- [ ] Issue refunds
- [ ] View payment transactions
- [ ] Audit log of changes

#### US-11.3: Monitor System Health
**As an** admin
**I want to** monitor system performance
**So that** I can identify issues quickly

**Acceptance Criteria:**
- [ ] Real-time metrics for API response times
- [ ] Edge function execution stats
- [ ] Error rate alerts
- [ ] Push notification delivery rates
- [ ] Cron job success/failure logs

---

## PHASE 12: Supabase Edge Functions

### 12.1 Edge Functions Overview

All edge functions deployed to Supabase and called from iOS app via REST API.

**Base URL:** `https://oaiteiceynliooxpeuxt.supabase.co/functions/v1/`

**Authentication:** Bearer token (Supabase Auth JWT)

### 12.2 Edge Function Specifications

**1. `validate-connection-code`**
- **Method:** POST
- **Purpose:** Validate and create connections using 6-digit codes
- **Request:**
```json
{
  "code": "123456",
  "connectingUserId": "uuid",
  "role": "sender" | "receiver"
}
```
- **Response:**
```json
{
  "success": true,
  "connection": { ... }
}
```
- **Edge Cases:** Self-connection, duplicate, invalid code

**2. `generate-daily-pings`**
- **Method:** POST (internal, cron-triggered)
- **Purpose:** Create daily ping records for all active connections
- **Cron:** `0 0 * * *` (daily at midnight UTC)
- **Logic:**
  - Query all active senders
  - Check for active breaks
  - Verify receiver subscriptions
  - Create ping records with calculated deadlines

**3. `complete-ping`**
- **Method:** POST
- **Purpose:** Mark ping as completed
- **Request:**
```json
{
  "senderId": "uuid",
  "method": "tap" | "in_person",
  "location": { "lat": 0, "lon": 0, "accuracy": 0 } | null
}
```
- **Response:**
```json
{
  "success": true,
  "pings_completed": 3
}
```

**4. `send-ping-notifications`**
- **Method:** POST (internal, cron-triggered)
- **Purpose:** Send scheduled ping reminders and alerts
- **Cron:** `*/15 * * * *` (every 15 minutes)
- **Logic:**
  - Find pending pings
  - Check time until deadline
  - Send appropriate notifications (scheduled, 15-min, deadline, missed)

**5. `check-subscription-status`**
- **Method:** POST
- **Purpose:** Validate receiver subscription before operations
- **Request:**
```json
{
  "userId": "uuid"
}
```
- **Response:**
```json
{
  "status": "trial" | "active" | "past_due" | "expired",
  "valid": true | false
}
```

**6. `handle-appstore-webhook`**
- **Method:** POST
- **Purpose:** Process Apple In-App Purchase webhooks
- **Webhook URL:** `https://oaiteiceynliooxpeuxt.supabase.co/functions/v1/handle-appstore-webhook`
- **Request:** Apple Server Notification payload
- **Logic:**
  - Verify signature
  - Update subscription status
  - Send notifications

**7. `export-user-data`**
- **Method:** POST
- **Purpose:** Generate GDPR data export
- **Request:**
```json
{
  "userId": "uuid"
}
```
- **Response:**
```json
{
  "success": true,
  "download_url": "https://..."
}
```

**8. `calculate-streak`**
- **Method:** POST
- **Purpose:** Calculate ping streak for a connection
- **Request:**
```json
{
  "senderId": "uuid",
  "receiverId": "uuid"
}
```
- **Response:**
```json
{
  "streak": 42
}
```

**9. `cleanup-expired-data`**
- **Method:** POST (internal, cron-triggered)
- **Purpose:** Remove old data and hard-delete accounts
- **Cron:** `0 2 * * *` (daily at 2 AM UTC)
- **Logic:**
  - Hard delete users marked deleted > 30 days ago
  - Archive old notifications (> 90 days)
  - Remove expired data exports (> 7 days)

### 12.3 Rate Limiting

**Limits per user:**
- Authentication: 5 requests/minute
- Ping completion: 10 requests/minute
- Connection creation: 5 requests/minute
- General API: 100 requests/minute

**Implementation:**
- Use Supabase built-in rate limiting
- Return 429 status code when exceeded
- Include retry-after header

### 12.4 Error Handling

**Standard Error Response:**
```json
{
  "success": false,
  "error": "Error message",
  "code": "ERROR_CODE"
}
```

**Common Error Codes:**
- `INVALID_CODE`: Code not found or inactive
- `SELF_CONNECTION`: Attempting to connect to self
- `DUPLICATE_CONNECTION`: Connection already exists
- `SUBSCRIPTION_EXPIRED`: Receiver subscription invalid
- `RATE_LIMIT_EXCEEDED`: Too many requests
- `UNAUTHORIZED`: Invalid auth token
- `SERVER_ERROR`: Internal server error

---

## PHASE 13: Security & Privacy

### 13.1 Data Security

**Encryption:**
- All data encrypted at rest (Supabase PostgreSQL encryption)
- All data encrypted in transit (TLS 1.3)
- Device tokens encrypted in database
- Auth tokens stored in iOS Keychain (encrypted)
- Location data encrypted (JSONB field)

**Authentication:**
- Phone number + SMS OTP (no passwords to leak)
- JWT tokens with 30-day expiration
- Refresh tokens stored securely
- Rate limiting on auth endpoints (5 attempts/min)

**Authorization:**
- Row Level Security (RLS) on all tables
- Users can only access their own data
- Receivers cannot see other receivers
- Senders cannot see other senders' data
- Admin role checks for admin endpoints

### 13.2 Privacy Compliance

**GDPR Compliance:**
- Right to access: Data export feature
- Right to erasure: Account deletion with 30-day retention
- Right to portability: ZIP export with machine-readable formats
- Consent management: Explicit opt-in for notifications
- Data minimization: Only collect necessary data

**CCPA Compliance:**
- Privacy policy link in app
- "Do Not Sell My Info" (not applicable - no data selling)
- Data disclosure: What data is collected and why
- Opt-out options for analytics (future)

**Data Retention:**
- Active user data: Indefinite (while account active)
- Deleted accounts: 30 days soft delete, then hard delete
- Notifications: 90 days, then archived
- Audit logs: 1 year
- Payment transactions: 7 years (regulatory requirement)

### 13.3 Security Best Practices

**Input Validation:**
- Phone numbers: Regex validation + libphonenumber
- 6-digit codes: Numeric only, exact length
- Dates: Valid date ranges
- JSON payloads: Schema validation

**SQL Injection Prevention:**
- Use parameterized queries (Supabase SDK)
- No raw SQL from user input
- RLS policies prevent unauthorized access

**XSS Prevention:**
- Sanitize all user input (names, notes)
- Content Security Policy headers
- No eval() or innerHTML

**Rate Limiting:**
- Authentication: 5/min per IP
- API calls: 100/min per user
- Ping completion: 10/min per user
- Connection creation: 5/min per user

**Monitoring & Alerts:**
- Failed auth attempts (>10 in 1 hour)
- Unusual API usage patterns
- Database query performance issues
- Push notification delivery failures
- Subscription webhook failures

### 13.4 Vulnerability Prevention

**Prevent:**
- Mass assignment: Explicitly define allowed fields
- Insecure direct object references: RLS enforced
- CSRF: Use Supabase auth tokens, not cookies
- Session fixation: New session on auth
- Timing attacks: Constant-time comparisons

**Security Headers:**
```
Strict-Transport-Security: max-age=31536000
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Content-Security-Policy: default-src 'self'
```

### 13.5 User Stories: Security & Privacy

#### US-13.1: Secure Authentication
**As a** user
**I want to** know my account is secure
**So that** my data is protected

**Acceptance Criteria:**
- [ ] Phone + OTP authentication (no password leaks)
- [ ] Auth tokens stored in Keychain
- [ ] Sessions expire after 30 days
- [ ] Failed attempts rate limited

#### US-13.2: Data Privacy
**As a** user
**I want to** control my personal data
**So that** I maintain privacy

**Acceptance Criteria:**
- [ ] Can export all data anytime
- [ ] Can delete account and data
- [ ] Only necessary data collected
- [ ] Privacy policy clearly explains data usage
- [ ] No data sold to third parties

---

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

#### US-15.2: Beta Testing Program
**As a** product manager
**I want to** run a beta test with real users
**So that** I can validate the product before launch

**Acceptance Criteria:**
- [ ] 50-100 beta testers recruited
- [ ] TestFlight build distributed
- [ ] In-app feedback form
- [ ] Analytics tracking enabled
- [ ] Weekly feedback reviews

---

## PHASE 16: Deployment & Launch

### 16.1 Pre-Launch Checklist

**Technical:**
- [ ] All P0 and P1 bugs resolved
- [ ] 80%+ test coverage achieved
- [ ] Load testing completed successfully
- [ ] Security audit passed
- [ ] App Store screenshots prepared (all sizes)
- [ ] App Store description written
- [ ] Privacy policy published
- [ ] Terms of service published
- [ ] App Store Connect configured
- [ ] In-App Purchases configured and approved
- [ ] Push notification certificates uploaded
- [ ] Supabase production environment configured
- [ ] Edge functions deployed to production
- [ ] Database migrations applied
- [ ] RLS policies enabled
- [ ] Admin dashboard deployed
- [ ] Analytics tracking configured
- [ ] Crash reporting configured

**Business:**
- [ ] Pricing finalized ($2.99/month)
- [ ] Payment processing tested
- [ ] Customer support email set up
- [ ] Landing page launched (pruuf.app)
- [ ] Social media accounts created
- [ ] Press kit prepared
- [ ] Launch announcement drafted

### 16.2 App Store Submission

**App Metadata:**
- **App Name:** PRUUF
- **Subtitle:** Peace of mind with one tap
- **Category:** Health & Fitness (or Lifestyle)
- **Keywords:** check-in, safety, ping, peace of mind, daily, family, caregiver
- **Age Rating:** 4+
- **Privacy Policy URL:** https://pruuf.app/privacy
- **Support URL:** https://pruuf.app/support

**App Description:**
```
PRUUF gives you peace of mind through simple daily check-ins.

FOR SENDERS (Always Free):
• Set your daily ping time
• One tap to let loved ones know you're safe
• Schedule breaks when away
• Always free, no matter how many connections

FOR RECEIVERS ($2.99/month, 15 days free):
• Get daily confirmation from loved ones
• Instant notifications when they check in
• See their ping history and streaks
• Alerts if they miss a check-in

HOW IT WORKS:
1. Senders get a daily reminder to "ping" at their chosen time
2. One tap confirms they're okay
3. Receivers get instant peace of mind

Perfect for:
• Adult children checking on aging parents
• Caregivers monitoring loved ones
• Solo travelers staying connected
• Anyone wanting daily reassurance

Privacy-focused. Simple. Reliable.
```

**Screenshots:** (Prepare for all iPhone sizes)
1. Dashboard (sender view with ping button)
2. Dashboard (receiver view with sender statuses)
3. Connection screen with unique code
4. Ping completion success
5. Settings screen

### 16.3 Launch Strategy

**Phase 1: Soft Launch (Week 1-2)**
- Release to limited regions (US only)
- Monitor crash rates and performance
- Gather initial user feedback
- Fix critical bugs quickly
- Optimize onboarding based on drop-off rates

**Phase 2: Public Launch (Week 3)**
- Release to all regions
- Announce on social media
- Press outreach
- Product Hunt launch
- Monitor app store reviews
- Respond to support requests

**Phase 3: Growth (Month 2+)**
- Implement user feedback
- A/B test onboarding flow
- Optimize subscription conversion
- Add requested features
- Referral program (future)

### 16.4 Monitoring Post-Launch

**Key Metrics to Track:**
- Daily active users (DAU)
- New signups
- Onboarding completion rate
- Trial to paid conversion rate
- Churn rate
- Daily pings sent
- Ping completion rate (on-time vs late vs missed)
- Push notification delivery rate
- App crashes
- API error rates
- Average revenue per user (ARPU)

**Alerting Thresholds:**
- Crash rate > 1% → Page on-call engineer
- Ping notification failure > 5% → Investigate immediately
- API error rate > 2% → Check Supabase status
- Subscription webhook failures → Verify Apple integration

### 16.5 User Stories: Deployment

#### US-16.1: Smooth App Store Review
**As a** developer
**I want to** pass App Store review on first submission
**So that** we can launch on schedule

**Acceptance Criteria:**
- [ ] All App Store guidelines followed
- [ ] Privacy policy linked and accessible
- [ ] In-App Purchases correctly configured
- [ ] Demo account provided for reviewers
- [ ] App metadata complete and accurate

#### US-16.2: Production Monitoring
**As an** operator
**I want to** monitor production health
**So that** I can respond to issues quickly

**Acceptance Criteria:**
- [ ] Real-time dashboards for key metrics
- [ ] Alerts configured for critical thresholds
- [ ] On-call rotation established
- [ ] Runbooks for common issues
- [ ] Incident response plan documented

---

## PHASE 17: Future Enhancements (Post-MVP)

### 17.1 Phase 2 Features

**Priority 2 (🟡) Edge Cases from edge_cases.md:**
- Custom grace periods per sender
- Recurring breaks (weekly, monthly patterns)
- Group connections (family groups)
- Quiet hours (no notifications during sleep)
- Custom notification sounds
- Emergency contact escalation (if multiple missed pings)
- QR code for easy connection sharing
- In-app messaging between connected users
- Photo sharing with pings
- Widget for iOS home screen

### 17.2 Phase 3 Features (Future 🟢)

**Future Enhancements:**
- Android app
- Web dashboard (view-only)
- Apple Watch app
- Family sharing (multiple receivers under one subscription)
- Location sharing history
- Health data integration (step count, heart rate)
- SOS/panic button
- Scheduled video calls
- AI-powered wellness insights
- Integration with smart home devices
- Medication reminders
- Appointment reminders

### 17.3 Internationalization

**Supported Languages:**
- MVP: English only
- Phase 2: Spanish, French
- Phase 3: German, Italian, Portuguese, Chinese, Japanese

**Localization:**
- All UI strings externalized
- Date/time formatting per locale
- Phone number formatting per country
- Currency formatting for pricing

---

## APPENDIX A: Database Schema Reference

See Phase 2 for complete database schema including:
- users
- sender_profiles
- receiver_profiles
- unique_codes
- connections
- pings
- breaks
- notifications
- audit_logs
- payment_transactions

All tables include RLS policies, indexes, and triggers.

---

## APPENDIX B: API Reference

**Base URL:** `https://oaiteiceynliooxpeuxt.supabase.co`

**Authentication:** 
```
Authorization: Bearer <JWT_TOKEN>
```

**Endpoints:**

```
POST /auth/v1/otp
POST /auth/v1/verify
POST /functions/v1/validate-connection-code
POST /functions/v1/complete-ping
POST /functions/v1/check-subscription-status
POST /functions/v1/export-user-data
POST /functions/v1/calculate-streak
POST /functions/v1/handle-appstore-webhook
```

See Phase 12 for detailed specifications.

---

## APPENDIX C: Edge Cases Reference

See `edge_cases.md` for comprehensive list of 109 edge cases across 13 categories with priority levels (🔴 MVP CRITICAL, 🟡 PHASE 2, 🟢 FUTURE).

Key categories:
1. Unique Code System
2. Account Management
3. Payment & Subscriptions
4. Ping Timing & Scheduling
5. Break Management
6. Connection Management
7. Notification Delivery
8. In-Person Verification
9. Data Integrity
10. App State Management
11. Business Logic
12. Security & Privacy
13. Operations & Admin

---

## APPENDIX D: Testing Reference

See `edge_cases_testing.md` for:
- 14 test suites covering 67 MVP CRITICAL edge cases
- 200+ specific test cases with acceptance criteria
- Test execution plan
- Automation requirements
- Monitoring metrics
- Regression testing checklist

---

## DOCUMENT REVISION HISTORY

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-16 | AI Assistant | Initial PRD creation with all phases, user stories, and technical specifications |

---

## CONCLUSION

This Product Requirements Document provides comprehensive specifications for building the PRUUF iOS mobile application. It covers all aspects from authentication to deployment, including:

- **17 Implementation Phases** with detailed requirements
- **60+ User Stories** with acceptance criteria
- **Complete Database Schema** with RLS policies
- **12+ Supabase Edge Functions** with specifications
- **Security & Privacy** compliance (GDPR, CCPA)
- **Performance Targets** and optimization strategies
- **Testing Strategy** with 80% coverage target
- **Deployment Plan** with launch strategy

**Key Credentials:**
- Supabase URL: `https://oaiteiceynliooxpeuxt.supabase.co`
- Supabase Anon Key: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`
- Admin Email: `wesleymwilliams@gmail.com`
- Admin Password: `W@$hingt0n1`

**Next Steps:**
1. Review and approve this PRD
2. Set up development environment
3. Initialize Supabase project with provided credentials
4. Implement Phase 1: Project Setup & Configuration
5. Proceed sequentially through phases
6. Run tests continuously throughout development
7. Deploy to TestFlight for beta testing
8. Submit to App Store

**Support:**
For questions or clarifications, refer to:
- `edge_cases.md` - Edge case handling
- `edge_cases_testing.md` - Testing specifications
- This PRD - All implementation details

---

**END OF DOCUMENT**
