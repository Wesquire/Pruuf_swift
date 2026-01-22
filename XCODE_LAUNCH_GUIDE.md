# PRUUF iOS App - Xcode Launch Guide

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Project Structure](#project-structure)
3. [Opening the Project](#opening-the-project)
4. [Configuring Xcode](#configuring-xcode)
5. [Building and Running](#building-and-running)
6. [Testing Authentication](#testing-authentication)
7. [Test Scenarios](#test-scenarios)
8. [Key Configuration Files](#key-configuration-files)
9. [Backend Configuration](#backend-configuration)
10. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before you begin, ensure you have:

| Requirement | Minimum Version | How to Check |
|-------------|-----------------|--------------|
| **macOS** | 13.0 (Ventura) | Apple Menu > About This Mac |
| **Xcode** | 15.0 | Open Xcode > About Xcode |
| **Swift** | 5.9 | `swift --version` in Terminal |
| **iOS Simulator** | iOS 15.0+ | Xcode > Window > Devices and Simulators |
| **Apple Developer Account** | Free or Paid | For physical device testing |

### Install Xcode (if needed)
```bash
# Option 1: Mac App Store
# Search "Xcode" in the App Store

# Option 2: Command line
xcode-select --install
```

---

## Project Structure

```
/Users/wesquire/Github/pruuf_swift/
├── Package.swift                    # Swift Package Manager configuration
├── PRUUF/                           # Main iOS app source code
│   ├── App/                         # App entry point
│   │   ├── PruufApp.swift          # @main SwiftUI App
│   │   └── AppDelegate.swift       # UIKit AppDelegate for push notifications
│   ├── Core/                        # Core business logic
│   │   ├── Config/
│   │   │   └── SupabaseConfig.swift # Supabase client configuration
│   │   ├── Models/                  # Data models (User, Ping, Connection, etc.)
│   │   └── Services/                # Business services
│   │       ├── AuthService.swift    # Authentication logic
│   │       ├── PingService.swift    # Ping management
│   │       ├── ConnectionService.swift
│   │       ├── NotificationService.swift
│   │       └── ...
│   ├── Features/                    # Feature modules (screens)
│   │   ├── Authentication/          # Login/verification screens
│   │   ├── Dashboard/               # Sender/Receiver dashboards
│   │   ├── Connections/             # Connection management
│   │   ├── Settings/                # App settings
│   │   ├── Notifications/           # Notification center
│   │   ├── Breaks/                  # Break scheduling
│   │   ├── Onboarding/              # New user onboarding
│   │   └── Subscription/            # Subscription management
│   ├── Resources/                   # App resources
│   │   ├── Assets.xcassets/         # Images, app icon, colors
│   │   ├── Info.plist               # App configuration
│   │   ├── PRUUF.entitlements       # App capabilities
│   │   └── Subscription.storekit    # StoreKit testing config
│   └── Shared/                      # Shared UI components
├── Tests/                           # Unit tests
│   └── PRUUFTests/
├── supabase/                        # Backend configuration
│   ├── config.toml                  # Supabase local config
│   ├── functions/                   # Edge Functions
│   │   └── send-apns-notification/  # APNs push notification function
│   └── migrations/                  # Database migrations
└── admin-dashboard/                 # Web admin dashboard (separate)
```

---

## Opening the Project

### Method 1: Terminal (Recommended)

```bash
# 1. Open Terminal (Cmd + Space, type "Terminal")

# 2. Navigate to the project directory
cd /Users/wesquire/Github/pruuf_swift

# 3. Open Package.swift in Xcode
open Package.swift
```

### Method 2: Finder

1. Open **Finder**
2. Navigate to: `/Users/wesquire/Github/pruuf_swift/`
3. Double-click **`Package.swift`**
4. Xcode will open automatically

### Method 3: Xcode

1. Open **Xcode**
2. Select **File > Open...** (or `Cmd + O`)
3. Navigate to `/Users/wesquire/Github/pruuf_swift/`
4. Select **`Package.swift`** and click **Open**

### After Opening

Wait for Xcode to:
1. **Index the project** (progress bar at top)
2. **Resolve package dependencies** (Supabase, KeychainSwift)
   - This may take 1-2 minutes on first open
   - Check progress: **View > Navigators > Show Package Dependencies**

---

## Configuring Xcode

### Step 1: Select the Scheme

1. Look at the **Scheme Selector** (top-left of Xcode, next to the Play/Stop buttons)
2. Click on it and select **PRUUF**
3. If you see "My Mac" as the destination, change it to an iOS Simulator

**Location in Xcode:**
```
┌─────────────────────────────────────────────────────────────┐
│ [▶️] [⏹️]  PRUUF > iPhone 16        [◀️▶️]                    │
│            ↑                        ↑                       │
│         Scheme                  Destination                 │
└─────────────────────────────────────────────────────────────┘
```

### Step 2: Select a Destination (Simulator)

1. Click on the **destination selector** (shows current device/simulator)
2. Choose an iOS Simulator:
   - **Recommended:** iPhone 16, iPhone 15 Pro, iPhone 14
   - **Minimum:** Any iOS 15.0+ simulator

**To see all simulators:**
- Xcode Menu: **Window > Devices and Simulators**
- Or press `Cmd + Shift + 2`

### Step 3: Verify Build Settings (Optional)

1. In the left sidebar, click on the **Package.swift** file at the top
2. Select the **PRUUF** target
3. Verify settings:
   - **iOS Deployment Target:** iOS 15.0
   - **Swift Language Version:** Swift 5

---

## Building and Running

### Quick Build and Run

**Keyboard Shortcut:** `Cmd + R`

**Or:**
1. Click the **Play button (▶️)** in the top-left of Xcode

### Build Only (Without Running)

**Keyboard Shortcut:** `Cmd + B`

### What Happens During Build

1. **Compiling Swift files** - All `.swift` files are compiled
2. **Linking dependencies** - Supabase SDK, KeychainSwift linked
3. **Code signing** - App is signed for simulator (automatic)
4. **Installing to Simulator** - App installed and launched

### First Build Notes

- First build takes longer (2-5 minutes) due to dependency compilation
- Subsequent builds are much faster (incremental)
- Watch the **Build Progress** bar at the top of Xcode

### Build Output Location

After a successful build, the app binary is located at:
```
/Users/wesquire/Github/pruuf_swift/.build/
```

---

## Testing Authentication

### Authentication Overview

PRUUF uses **phone number + APNs push notification** for authentication:
1. User enters their phone number
2. A 6-digit verification code is sent via APNs push notification
3. User enters the code to authenticate

**Note:** SMS/Twilio has been removed. All verification codes are delivered via Apple Push Notifications (APNs).

### Test User Credentials

| User | Phone | Role | Status | Unique Code |
|------|-------|------|--------|-------------|
| **User A (Alice)** | `+15551001001` | Sender | No connections | - |
| **User B (Bob)** | `+15551002002` | Receiver | No connections | `111222` |
| **User C (Charlie)** | `+15551003003` | Sender | Connected to Diana | - |
| **User D (Diana)** | `+15551004004` | Receiver | Connected to Charlie | `333444` |

### Testing in Simulator (Push Not Supported)

Since push notifications don't work in the iOS Simulator, the app automatically logs the verification code to the **Xcode Console**.

**Steps:**
1. Run the app in Simulator (`Cmd + R`)
2. Enter a test phone number (e.g., `+15551001001`)
3. Tap "Send Code"
4. **Check the Xcode Console** for the verification code:

```
========================================
VERIFICATION CODE: 123456
Phone: +15551001001
========================================
```

**To view the console:**
- Xcode Menu: **View > Debug Area > Activate Console**
- Or press `Cmd + Shift + C`

### Testing on Physical Device

For full APNs testing on a real iPhone:

**Prerequisites:**
1. Valid Apple Developer account (free works for development)
2. iPhone connected via USB or on same WiFi network
3. Trust this computer on your iPhone

**Steps:**
1. Connect your iPhone to your Mac
2. In Xcode, select your iPhone from the destination selector
3. You may need to:
   - Sign in with your Apple ID in Xcode (Preferences > Accounts)
   - Select your team in the project settings
4. Build and run (`Cmd + R`)
5. On first launch, allow push notifications when prompted
6. Enter a test phone number
7. The verification code arrives via push notification

---

## Test Scenarios

### Scenario 1: Sender with No Connections (User A - Alice)
- **Phone:** `+15551001001`
- **Expected:** Sender dashboard with no connections
- **Test:** Add a connection using Bob's code `111222`

### Scenario 2: Receiver with No Connections (User B - Bob)
- **Phone:** `+15551002002`
- **Expected:** Receiver dashboard waiting for senders
- **Unique Code:** `111222` (share this with senders)
- **Test:** Wait for Alice to connect using the code

### Scenario 3: Sender with Active Connection (User C - Charlie)
- **Phone:** `+15551003003`
- **Expected:** Sender dashboard showing connection to Diana
- **Test:** Complete today's ping, view streak, schedule a break

### Scenario 4: Receiver with Active Connection (User D - Diana)
- **Phone:** `+15551004004`
- **Expected:** Receiver dashboard showing Charlie's ping status
- **Unique Code:** `333444`
- **Test:** View pending ping from Charlie, check notification settings

---

## Key Configuration Files

### 1. Package.swift (Swift Package Configuration)
**Location:** `/Users/wesquire/Github/pruuf_swift/Package.swift`

Defines:
- Package name and platforms
- Dependencies (Supabase SDK, KeychainSwift)
- Build targets

### 2. SupabaseConfig.swift (Backend Connection)
**Location:** `/Users/wesquire/Github/pruuf_swift/PRUUF/Core/Config/SupabaseConfig.swift`

Contains:
- Supabase project URL
- Anonymous API key
- Client configuration

### 3. Info.plist (App Configuration)
**Location:** `/Users/wesquire/Github/pruuf_swift/PRUUF/Resources/Info.plist`

Contains:
- Bundle identifier
- Version numbers
- Required device capabilities

### 4. PRUUF.entitlements (App Capabilities)
**Location:** `/Users/wesquire/Github/pruuf_swift/PRUUF/Resources/PRUUF.entitlements`

Contains:
- Push notification entitlements
- App capabilities

### 5. Subscription.storekit (StoreKit Testing)
**Location:** `/Users/wesquire/Github/pruuf_swift/PRUUF/Resources/Subscription.storekit`

Contains:
- In-app purchase products for testing
- Subscription configuration

---

## Backend Configuration

### Supabase Project

| Setting | Value |
|---------|-------|
| **Project URL** | `https://oaiteiceynliooxpeuxt.supabase.co` |
| **Dashboard** | [https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt](https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt) |

### Supabase Dashboard Quick Links

| Section | URL |
|---------|-----|
| **Auth Users** | [View Users](https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt/auth/users) |
| **Table Editor** | [View Tables](https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt/editor) |
| **Edge Functions** | [View Functions](https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt/functions) |
| **Logs** | [View Logs](https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt/logs/explorer) |
| **Secrets** | [View Secrets](https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt/settings/vault/secrets) |

### API Keys

```
Supabase URL: https://oaiteiceynliooxpeuxt.supabase.co
Anon Key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9haXRlaWNleW5saW9veHBldXh0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg1MzA0MzEsImV4cCI6MjA4NDEwNjQzMX0.Htm_jL8JbLK2jhVlCUL0A7m6PJVY_ZuBx3FqZDZrtgk
```

### APNs Configuration (Already Set)

| Secret | Value |
|--------|-------|
| `APNS_TEAM_ID` | `XZAXF7Q3JG` |
| `APNS_KEY_ID` | `Y6G6XS949J` |
| `APNS_PRIVATE_KEY` | (configured in Supabase secrets) |

### Edge Functions

**Location:** `/Users/wesquire/Github/pruuf_swift/supabase/functions/`

| Function | Purpose |
|----------|---------|
| `send-apns-notification` | Sends push notifications via APNs |
| `generate-daily-pings` | Generates daily ping records |
| `process-missed-pings` | Handles missed ping detection |
| `send-ping-reminders` | Sends ping reminder notifications |

### Database Tables

**Location:** View in [Supabase Table Editor](https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt/editor)

| Table | Purpose |
|-------|---------|
| `users` | User accounts |
| `sender_profiles` | Sender-specific settings |
| `receiver_profiles` | Receiver-specific settings |
| `connections` | Sender-receiver connections |
| `pings` | Daily ping records |
| `breaks` | Scheduled breaks |
| `notifications` | In-app notifications |
| `unique_codes` | Receiver connection codes |

---

## Troubleshooting

### Build Errors

#### "Package resolution failed"
```bash
# In Terminal, navigate to project and reset:
cd /Users/wesquire/Github/pruuf_swift
rm -rf .build
rm -rf .swiftpm
rm Package.resolved

# Then reopen Package.swift in Xcode
```

**In Xcode:**
- Menu: **File > Packages > Reset Package Caches**
- Menu: **File > Packages > Resolve Package Versions**

#### "Module 'Supabase' not found"
1. Wait for package resolution to complete
2. Clean build folder: `Cmd + Shift + K`
3. Build again: `Cmd + B`

#### Build fails with Swift version errors
Ensure Xcode 15+ is installed:
```bash
xcode-select -p
# Should show: /Applications/Xcode.app/Contents/Developer
```

### Simulator Issues

#### Simulator won't boot
```bash
# Reset all simulators
xcrun simctl shutdown all
xcrun simctl erase all
```

**In Xcode:**
- Menu: **Window > Devices and Simulators**
- Right-click simulator > **Delete**
- Download a new simulator version

#### App won't install on Simulator
1. Clean build folder: `Cmd + Shift + K`
2. Delete app from Simulator
3. Build and run again

### Authentication Issues

#### "Verification code not received"
1. **In Simulator:** Check Xcode Console for printed code
2. **On Device:** Ensure push notifications are enabled
3. Check [Supabase Logs](https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt/logs/explorer) for errors

#### "Verification failed"
1. Code expires after 10 minutes - request a new one
2. Ensure you're entering the correct code
3. Check that phone number includes country code (e.g., `+1`)

#### "Cannot connect to Supabase"
1. Check internet connection
2. Verify Supabase URL in `SupabaseConfig.swift`
3. Check [Supabase Status](https://status.supabase.com/)

### Push Notification Issues

#### Push not working on device
1. Verify APNs credentials in Supabase secrets
2. Check Edge Function logs for errors
3. Ensure device token was registered
4. Verify notification permissions are granted

#### "Device token not found"
1. Delete and reinstall the app
2. When prompted, allow notifications
3. Check that `AppDelegate` is properly configured

---

## Useful Xcode Shortcuts

| Action | Shortcut |
|--------|----------|
| Build | `Cmd + B` |
| Run | `Cmd + R` |
| Stop | `Cmd + .` |
| Clean Build Folder | `Cmd + Shift + K` |
| Show/Hide Navigator | `Cmd + 0` |
| Show/Hide Debug Area | `Cmd + Shift + Y` |
| Show Console | `Cmd + Shift + C` |
| Open Quickly | `Cmd + Shift + O` |
| Find in Project | `Cmd + Shift + F` |
| Show File Inspector | `Cmd + Option + 1` |

---

## Additional Resources

- [Swift Documentation](https://www.swift.org/documentation/)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [Supabase Swift SDK](https://supabase.com/docs/reference/swift/introduction)
- [Apple Push Notifications Guide](https://developer.apple.com/documentation/usernotifications)

---

## Architecture Changes (2026-01-20)

### Removed
- Twilio SMS integration
- SMS OTP verification
- `[auth.sms]` configuration

### Added
- APNs push notification verification
- Verification code sent via `send-apns-notification` Edge Function
- Local verification code storage with 10-minute expiry
- Anonymous auth + phone association flow

### Auth Flow Diagram
```
User                    App                     Supabase              APNs
  |                      |                          |                   |
  |--Enter Phone-------->|                          |                   |
  |                      |--Generate Code---------->|                   |
  |                      |--Send Notification------>|------------------>|
  |<-----------------Push Notification-------------|-------------------|
  |--Enter Code--------->|                          |                   |
  |                      |--Verify Code (local)---->|                   |
  |                      |--signInAnonymously------>|                   |
  |<-Authenticated-------|<-------------------------|                   |
```

---

Updated: 2026-01-20
