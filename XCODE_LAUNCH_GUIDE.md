# PRUUF iOS App - Xcode Launch Guide

## Authentication Overview

PRUUF uses **phone number + APNs push notification** for authentication:
1. User enters their phone number
2. A 6-digit verification code is sent via APNs push notification
3. User enters the code to authenticate

**Note:** SMS/Twilio has been removed. All verification codes are delivered via Apple Push Notifications (APNs).

---

## Test User Credentials

| User | Phone | Role | Status | Unique Code |
|------|-------|------|--------|-------------|
| **User A (Alice)** | `+15551001001` | Sender | No connections | - |
| **User B (Bob)** | `+15551002002` | Receiver | No connections | `111222` |
| **User C (Charlie)** | `+15551003003` | Sender | Connected to Diana | - |
| **User D (Diana)** | `+15551004004` | Receiver | Connected to Charlie | `333444` |

---

## Step 1: Open in Xcode

1. Open Terminal and navigate to the project:
   ```bash
   cd /Users/wesquire/Github/pruuf_swift
   ```

2. Open the Swift Package in Xcode:
   ```bash
   open Package.swift
   ```

   Or double-click `Package.swift` in Finder.

3. Wait for Xcode to resolve package dependencies (Supabase, KeychainSwift, etc.)

---

## Step 2: Configure the Scheme

1. In Xcode, select the **PRUUF** scheme from the scheme selector (top left)
2. Select **iPhone 16** (or any iOS 15.0+ simulator) as the destination
3. The scheme should already be configured for Debug

---

## Step 3: Build and Run

1. Press `Cmd + R` or click the Play button
2. Wait for the build to complete (first build takes longer due to dependencies)
3. The app will launch in the iOS Simulator

---

## Step 4: Testing Authentication

### How the Auth Flow Works

1. **Phone Entry Screen**: User enters phone number with country code
2. **Verification Code Sent**: App calls `send-apns-notification` Edge Function
3. **Push Notification**: Verification code delivered via APNs
4. **Code Entry Screen**: User enters 6-digit code from notification
5. **Verification**: Code verified locally, user signed in via Supabase anonymous auth

### Testing in Simulator

Since push notifications don't work in the iOS Simulator, use one of these approaches:

#### Option A: Bypass for Testing (Recommended for Development)

In `AuthService.swift`, you can temporarily modify `sendVerificationCodeViaPush` to log the code instead of sending via APNs:

```swift
// For simulator testing, log the code
print("VERIFICATION CODE: \(code)")
```

Then check the Xcode console for the verification code.

#### Option B: Test on Physical Device

For full APNs testing, run on a physical device with:
1. Valid Apple Developer account
2. Push notification capability enabled
3. APNs certificate configured

#### Option C: Direct API Testing with Test User

U
```

---

## Test Scenarios

### Scenario 1: Sender with No Connections (User A - Alice)
- Phone: `+15551001001`
- Expected: Sender dashboard with no connections
- Test: Add a connection using Bob's code `111222`

### Scenario 2: Receiver with No Connections (User B - Bob)
- Phone: `+15551002002`
- Expected: Receiver dashboard waiting for senders
- Unique Code: `111222` (share this with senders)
- Test: Wait for Alice to connect using the code

### Scenario 3: Sender with Active Connection (User C - Charlie)
- Phone: `+15551003003`
- Expected: Sender dashboard showing connection to Diana
- Test: Complete today's ping, view streak, schedule a break

### Scenario 4: Receiver with Active Connection (User D - Diana)
- Phone: `+15551004004`
- Expected: Receiver dashboard showing Charlie's ping status
- Unique Code: `333444`
- Test: View pending ping from Charlie, check notification settings

---

## APNs Configuration

### Supabase Secrets (Already Configured)

The following APNs credentials are set in Supabase:

| Secret | Value |
|--------|-------|
| `APNS_TEAM_ID` | `XZAXF7Q3JG` |
| `APNS_KEY_ID` | `Y6G6XS949J` |
| `APNS_PRIVATE_KEY` | (configured) |

### Edge Function

The `send-apns-notification` Edge Function handles:
- Verification code delivery
- Ping notifications
- Connection notifications
- Missed ping alerts

---

## Database Summary

### Users Table
| ID | Phone | Role | Onboarding |
|----|-------|------|------------|
| f5715819-83e3-42c4-aec1-6116e03c5e4d | +15551001001 | sender | complete |
| c25d1e40-8945-48a9-9f29-847484b35c0c | +15551002002 | receiver | complete |
| c7b253d2-7ac7-405b-bc9a-885e46809e38 | +15551003003 | sender | complete |
| 83062724-babe-4193-9302-95a80051e641 | +15551004004 | receiver | complete |

### Connections Table
| Sender | Receiver | Status |
|--------|----------|--------|
| Charlie (User C) | Diana (User D) | active |

### Unique Codes Table
| Receiver | Code | Active |
|----------|------|--------|
| Bob (User B) | 111222 | Yes |
| Diana (User D) | 333444 | Yes |

### Pings Table
| Sender | Receiver | Status | Scheduled |
|--------|----------|--------|-----------|
| Charlie | Diana | pending | Today 8:00 AM UTC |

---

## Supabase Dashboard

- **Project URL**: https://oaiteiceynliooxpeuxt.supabase.co
- **Dashboard**: https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt

### Quick Links
- [Auth Users](https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt/auth/users)
- [Table Editor](https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt/editor)
- [Edge Functions](https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt/functions)
- [Logs](https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt/logs/explorer)
- [Secrets](https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt/settings/vault/secrets)

---

## Troubleshooting

### Build Errors
1. Clean build folder: `Cmd + Shift + K`
2. Reset package caches: `File > Packages > Reset Package Caches`
3. Restart Xcode

### Simulator Issues
1. Reset simulator: `Device > Erase All Content and Settings`
2. Boot specific simulator: `xcrun simctl boot <device-id>`

### Auth Issues
1. Check Supabase dashboard for user status
2. Verify verification code hasn't expired (10 minute expiry)
3. Check Keychain for stored tokens
4. Enable push notifications on physical device

### APNs Issues
1. Verify APNs credentials in Supabase secrets
2. Check Edge Function logs for errors
3. Ensure device token is registered
4. Test on physical device (push doesn't work in Simulator)

---

## API Keys (for reference)

```
Supabase URL: https://oaiteiceynliooxpeuxt.supabase.co
Anon Key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9haXRlaWNleW5saW9veHBldXh0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg1MzA0MzEsImV4cCI6MjA4NDEwNjQzMX0.Htm_jL8JbLK2jhVlCUL0A7m6PJVY_ZuBx3FqZDZrtgk
```

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
