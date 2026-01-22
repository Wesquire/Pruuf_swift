# PRUUF iOS Development Environment Setup

This document outlines the development environment requirements and setup instructions for the PRUUF iOS application.

## Requirements

### 1. Xcode 15.0+
- **Status:** Verified
- **Current Version:** Xcode 26.2 (Build 17C52)
- **Download:** [Mac App Store](https://apps.apple.com/app/xcode/id497799835)

**Required Xcode Components:**
- iOS 15.0+ SDK
- Swift 5.9+
- Simulator runtimes for testing

### 2. Apple Developer Account
- **Status:** Required for push notifications and TestFlight
- **Type:** Apple Developer Program membership ($99/year)
- **URL:** https://developer.apple.com/programs/

**Required Capabilities:**
- Push Notifications
- App Groups
- Associated Domains (for deep linking)
- Sign in with Apple (optional, for future feature)

**Certificates Required:**
- Apple Push Notification service (APNs) certificate
- iOS Distribution certificate (for TestFlight/App Store)
- iOS Development certificate

**Entitlements File:**
- Location: `PRUUF/Resources/PRUUF.entitlements`
- Contains: Push Notifications, App Groups, Keychain Access, Associated Domains

**Apple Developer Portal Setup:**

1. **Create App ID:**
   - Navigate to Certificates, Identifiers & Profiles
   - Create a new App ID with bundle identifier: `com.pruuf.ios`
   - Enable capabilities: Push Notifications, App Groups

2. **Configure Push Notifications:**
   - In App ID settings, click "Configure" next to Push Notifications
   - Create both Development and Production APNs certificates
   - Or use APNs Key (recommended): Create a new key with APNs enabled
   - Download and securely store the .p8 key file

3. **Create App Group:**
   - Create App Group with identifier: `group.com.pruuf.ios`
   - Assign to your App ID

4. **TestFlight Setup:**
   - Create app in App Store Connect
   - Configure Internal/External testing groups
   - Upload builds via Xcode or `xcrun altool`

5. **Production Certificates:**
   - Create iOS Distribution certificate
   - Create provisioning profile for App Store distribution

### 3. Supabase CLI
- **Status:** Verified
- **Current Version:** 2.67.1
- **Installation Path:** /opt/homebrew/bin/supabase

**Installation:**
```bash
brew install supabase/tap/supabase
```

**Usage:**
```bash
# Start local Supabase instance
supabase start

# Deploy edge functions
supabase functions deploy

# Run migrations
supabase db push

# Generate TypeScript types (for reference)
supabase gen types typescript --local
```

### 4. Git Version Control
- **Status:** Verified
- **Current Version:** 2.50.1 (Apple Git-155)

**Recommended Git Configuration:**
```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

## Environment Configuration

### Config.swift
Located at: `PRUUF/Core/Config/Config.swift`

The app uses a centralized configuration file with environment-aware settings:

- **Development:** Debug builds, verbose logging enabled, analytics disabled
- **Staging:** Pre-production testing, logging enabled, analytics enabled
- **Production:** Release builds, logging disabled, analytics enabled

### Environment Variables

For local development, you can set these environment variables:

```bash
# Enable mock data for testing
export USE_MOCK_DATA=1
```

### Supabase Configuration
Located at: `PRUUF/Core/Config/SupabaseConfig.swift`

Contains:
- Project URL
- Anonymous public key
- Auth configuration with PKCE flow
- Keychain storage for secure token management

## Project Structure

```
PRUUF/
├── App/                    # App entry points
│   ├── PruufApp.swift     # @main SwiftUI app
│   └── AppDelegate.swift  # Push notifications, deep links
├── Core/
│   ├── Config/            # Configuration files
│   │   ├── Config.swift   # Environment configuration
│   │   └── SupabaseConfig.swift
│   ├── Services/          # Business logic services
│   └── Models/            # Data models
├── Features/              # Feature modules (MVVM)
│   ├── Authentication/
│   ├── Onboarding/
│   ├── Dashboard/
│   ├── Connections/
│   ├── Settings/
│   └── Subscription/
├── Shared/
│   ├── Components/        # Reusable UI components
│   ├── Extensions/        # Swift extensions
│   └── Utilities/         # Helper utilities
└── Resources/
    ├── Assets.xcassets    # Images and colors
    └── Info.plist         # App configuration
```

## Getting Started

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd Pruuf_Swift
   ```

2. **Open in Xcode**
   ```bash
   open Package.swift
   ```

   Or open the directory in Xcode and it will recognize the Swift Package.

3. **Resolve Package Dependencies**
   - Xcode will automatically resolve dependencies from `Package.swift`
   - Wait for the Supabase Swift SDK to download

4. **Configure Signing**
   - Open project settings in Xcode
   - Select the PRUUF target
   - Set your Team under Signing & Capabilities
   - Enable required capabilities (Push Notifications, App Groups)

5. **Run on Simulator or Device**
   - Select a simulator or connected device
   - Press Cmd+R to build and run

## Supabase Local Development

For edge function development:

1. **Start local Supabase**
   ```bash
   cd supabase
   supabase start
   ```

2. **Deploy functions locally**
   ```bash
   supabase functions serve
   ```

3. **Test edge functions**
   ```bash
   curl -i --location --request POST \
     'http://127.0.0.1:54321/functions/v1/send-ping-notification' \
     --header 'Authorization: Bearer <anon-key>' \
     --header 'Content-Type: application/json' \
     --data '{"ping_id": "test-id"}'
   ```

## Troubleshooting

### Package Resolution Issues
```bash
# Clean derived data
rm -rf ~/Library/Developer/Xcode/DerivedData

# Reset package cache
swift package reset
```

### Supabase CLI Issues
```bash
# Update Supabase CLI
brew upgrade supabase

# Check status
supabase status
```

### Push Notification Testing
- Push notifications require a physical device
- Use Xcode's "Simulate Push Notification" feature for basic testing
- Register for APNs in AppDelegate

## Admin Dashboard Setup

### Super Admin Configuration

The PRUUF admin dashboard requires initial configuration of the Super Admin account.

**Admin Credentials:**
- **Email:** `wesleymwilliams@gmail.com`
- **Role:** Super Admin
- **Password:** Must be configured via Supabase Auth (never stored in code)

### Setting Up Admin User via Supabase Dashboard

1. **Navigate to Supabase Auth:**
   - Go to https://supabase.com/dashboard
   - Select the PRUUF project (`oaiteiceynliooxpeuxt`)
   - Navigate to Authentication > Users

2. **Create Admin User:**
   ```
   Email: wesleymwilliams@gmail.com
   Password: W@$hingt0n1
   Auto Confirm User: Yes (check this box)
   ```

3. **Verify Database Record:**
   The migration `004_admin_roles.sql` automatically creates the admin_users record.
   After creating the auth user, verify the record exists:
   ```sql
   SELECT * FROM admin_users WHERE email = 'wesleymwilliams@gmail.com';
   ```

4. **Link Auth User to Admin Record:**
   Update the admin_users record to link with the auth.users record:
   ```sql
   UPDATE admin_users
   SET user_id = (SELECT id FROM auth.users WHERE email = 'wesleymwilliams@gmail.com')
   WHERE email = 'wesleymwilliams@gmail.com';
   ```

### Setting Up Admin User via Supabase CLI

```bash
# Create the admin user
supabase auth admin create-user \
  --email wesleymwilliams@gmail.com \
  --password 'W@$hingt0n1' \
  --email-confirmed

# Verify user was created
supabase auth admin list-users
```

### Admin Permissions Granted

The Super Admin role includes full system access:

| Permission | Granted |
|------------|---------|
| Full system access | ✅ |
| Analytics dashboard | ✅ |
| User management | ✅ |
| Payment oversight | ✅ |
| View/Edit/Delete users | ✅ |
| Impersonate users | ✅ |
| Export analytics | ✅ |
| Modify subscriptions | ✅ |
| Issue refunds | ✅ |
| System configuration | ✅ |
| Manage other admins | ✅ |
| Send broadcasts | ✅ |

### Admin Dashboard Access

**Supabase Dashboard:**
- URL: https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt

**Custom Admin Dashboard (if deployed):**
- URL: Configured in `AdminDashboardConfig.supabaseDashboardURL`
- Default: https://oaiteiceynliooxpeuxt.supabase.co/project/_/admin

### Security Configuration

The admin system includes these security features:

| Setting | Value |
|---------|-------|
| Session Timeout | 30 minutes |
| Max Failed Logins | 5 attempts |
| Lockout Duration | 15 minutes |
| Min Password Length | 12 characters |
| MFA Required | Yes (recommended) |
| Audit Log Retention | 365 days |

### Enabling MFA for Admin Account

1. Log in to Supabase Dashboard
2. Navigate to Authentication > Settings
3. Enable MFA (TOTP) under Auth Providers
4. Update the admin_users record:
   ```sql
   UPDATE admin_users
   SET mfa_enabled = true
   WHERE email = 'wesleymwilliams@gmail.com';
   ```

### Troubleshooting Admin Access

**Cannot login:**
- Verify the user exists in auth.users
- Check if account is locked (failed_login_attempts >= 5)
- Verify admin_users record has is_active = true

**No admin permissions:**
- Verify admin_users.user_id is linked to auth.users.id
- Check that role is set to 'super_admin'
- Run the migration again if admin_users record is missing

**Reset admin account:**
```sql
-- Unlock account
UPDATE admin_users
SET failed_login_attempts = 0, locked_until = NULL
WHERE email = 'wesleymwilliams@gmail.com';

-- Reset password (via Supabase Dashboard or CLI)
```

## Verification Checklist

- [x] Xcode 15.0+ installed (current: 26.2)
- [x] Apple Developer Account configuration documented
- [x] PRUUF.entitlements file created with:
  - [x] Push Notifications (aps-environment)
  - [x] App Groups (group.com.pruuf.ios)
  - [x] Keychain Access Groups
  - [x] Associated Domains (pruuf.app)
- [x] Supabase CLI installed (current: 2.67.1)
- [x] Git installed (current: 2.50.1)
- [x] Config.swift created with environment enum (development, staging, production)
- [x] SupabaseConfig.swift configured with:
  - [x] supabaseURL: https://oaiteiceynliooxpeuxt.supabase.co
  - [x] supabaseAnonKey: Configured
- [x] Project structure established
- [x] Admin Dashboard Credentials configured:
  - [x] Admin Email: wesleymwilliams@gmail.com
  - [x] Admin Role: Super Admin
  - [x] Admin Permissions: Full system access, analytics dashboard, user management, payment oversight
  - [x] AdminConfig.swift created with role definitions and permissions
  - [x] 004_admin_roles.sql migration with admin_users table and Super Admin seed
  - [x] Password documentation (set via Supabase Auth, not in code)
