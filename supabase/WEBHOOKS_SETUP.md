# PRUUF Webhooks Configuration Guide

This document describes how to configure webhooks for payment processing in the PRUUF iOS app.

## Apple App Store Server Notifications V2

Per plan.md Section 9.4 and Section 12.2, PRUUF uses Apple App Store Server Notifications V2 for subscription management.

### Webhook Endpoint

**Primary Webhook URL (per plan.md Section 12.2):**
```
https://oaiteiceynliooxpeuxt.supabase.co/functions/v1/handle-appstore-webhook
```

This Edge Function handles all Apple App Store Server Notifications for subscription management.

### App Store Connect Setup

1. Go to **App Store Connect** → **Your App** → **App Information**
2. Under **"App Store Server Notifications"**, configure:
   - **Production Server URL:** `https://oaiteiceynliooxpeuxt.supabase.co/functions/v1/handle-appstore-webhook`
   - **Sandbox Server URL:** Same URL (handles both environments)
3. Select **Notification Version: Version 2**

### Handled Notification Types (Per plan.md Section 9.4)

| Notification Type | Subtype | Action |
|------------------|---------|--------|
| `SUBSCRIBED` | `INITIAL_BUY` | Set status to 'active' |
| `DID_RENEW` | - | Extend subscription_end_date |
| `DID_CHANGE_RENEWAL_STATUS` | `AUTO_RENEW_DISABLED` | Set status to 'canceled' |
| `DID_FAIL_TO_RENEW` | `BILLING_RETRY`, `GRACE_PERIOD` | Set status to 'past_due', notify user |
| `REFUND` | - | Set status to 'expired', log transaction |
| `EXPIRED` | - | Set status to 'expired' |
| `GRACE_PERIOD_EXPIRED` | - | Set status to 'expired' |
| `REVOKE` | - | Revoke access |

### Edge Function: handle-appstore-webhook

Per plan.md Section 9.4 and Section 12.2, the `handle_appstore_webhook()` Edge Function:

1. **Verifies Apple signature** - Validates JWS signed payloads using Apple's certificate chain
2. **Finds user by transaction** - Looks up user via `appAccountToken` or `originalTransactionId`
3. **Processes notification type** - Handles each notification type per the table above
4. **Updates subscription status** - Updates `receiver_profiles.subscription_status` in database

### Subscription Status Flow

```
INITIAL_BUY → 'active' (or 'trial' if intro offer)
DID_RENEW → 'active' (extends subscription_end_date)
AUTO_RENEW_DISABLED → 'canceled' (access continues until end of period)
DID_FAIL_TO_RENEW → 'past_due' (billing retry in progress)
EXPIRED → 'expired'
REFUND → 'expired' (immediate revocation)
```

## Product Configuration

### App Store Product ID

| Product ID | Description | Price |
|------------|-------------|-------|
| `com.pruuf.receiver.monthly` | Receiver Monthly Subscription | $2.99/month |

Per plan.md Section 9.1:
- **Receiver-only users:** $2.99/month
- **Senders:** Always free
- **Dual role users:** $2.99/month (only if they have receiver connections)
- **Free trial:** 15 days for all receivers (no credit card required)

## Environment Variables

Set these in Supabase Edge Function secrets:

```bash
# Required for production
supabase secrets set APPLE_BUNDLE_ID=com.pruuf.ios

# Optional: For additional signature verification
supabase secrets set APPLE_ROOT_CA_URL=https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
```

## Apple JWS Signature Verification

Apple App Store Server Notifications V2 sends signed payloads using JSON Web Signature (JWS). The `handle-appstore-webhook` function:

1. Parses the `signedPayload` from Apple
2. Decodes the JWS header to extract the certificate chain (`x5c`)
3. Verifies the certificate chain leads to Apple Root CA
4. Validates the signature using the leaf certificate
5. Decodes the payload containing the notification data

### Signed Data Structures

**signedTransactionInfo** contains:
- `transactionId` - Unique transaction identifier
- `originalTransactionId` - Original transaction ID (for subscription family)
- `productId` - App Store product ID
- `purchaseDate` - Purchase timestamp (ms)
- `expiresDate` - Expiration timestamp (ms)
- `appAccountToken` - User ID passed during purchase
- `offerType` - 1=intro offer (trial), 2=promotional, 3=offer code

**signedRenewalInfo** contains:
- `autoRenewStatus` - 1=enabled, 0=disabled
- `expirationIntent` - Reason for expiration
- `gracePeriodExpiresDate` - Grace period end timestamp
- `isInBillingRetryPeriod` - Whether Apple is retrying billing

## Testing

### Local Development

```bash
# Start local Supabase
supabase start

# Serve functions locally
supabase functions serve handle-appstore-webhook

# Test INITIAL_BUY
curl -X POST http://localhost:54321/functions/v1/handle-appstore-webhook \
  -H "Content-Type: application/json" \
  -d '{
    "notificationType": "SUBSCRIBED",
    "subtype": "INITIAL_BUY",
    "notificationUUID": "test-uuid",
    "data": {
      "appAppleId": 123456789,
      "bundleId": "com.pruuf.ios",
      "environment": "Sandbox",
      "signedTransactionInfo": "eyJhbGciOiJFUzI1NiIsIng1YyI6W119.eyJ0cmFuc2FjdGlvbklkIjoidGVzdC10eC0xMjMiLCJvcmlnaW5hbFRyYW5zYWN0aW9uSWQiOiJvcmlnLXR4LTEyMyIsInByb2R1Y3RJZCI6ImNvbS5wcnV1Zi5yZWNlaXZlci5tb250aGx5IiwicHVyY2hhc2VEYXRlIjoxNzA1MzMxMjAwMDAwLCJleHBpcmVzRGF0ZSI6MTcwNzkyMzIwMDAwMCwiZW52aXJvbm1lbnQiOiJTYW5kYm94IiwiYnVuZGxlSWQiOiJjb20ucHJ1dWYuaW9zIiwiYXBwQWNjb3VudFRva2VuIjoidGVzdC11c2VyLXV1aWQifQ.signature"
    },
    "version": "2.0",
    "signedDate": 1705331200000
  }'

# Test DID_FAIL_TO_RENEW
curl -X POST http://localhost:54321/functions/v1/handle-appstore-webhook \
  -H "Content-Type: application/json" \
  -d '{
    "notificationType": "DID_FAIL_TO_RENEW",
    "subtype": "BILLING_RETRY",
    "notificationUUID": "test-uuid-2",
    "data": {
      "appAppleId": 123456789,
      "bundleId": "com.pruuf.ios",
      "environment": "Sandbox",
      "signedTransactionInfo": "eyJhbGciOiJFUzI1NiIsIng1YyI6W119.eyJ0cmFuc2FjdGlvbklkIjoidGVzdC10eC0xMjQiLCJvcmlnaW5hbFRyYW5zYWN0aW9uSWQiOiJvcmlnLXR4LTEyMyIsInByb2R1Y3RJZCI6ImNvbS5wcnV1Zi5yZWNlaXZlci5tb250aGx5IiwicHVyY2hhc2VEYXRlIjoxNzA1MzMxMjAwMDAwLCJleHBpcmVzRGF0ZSI6MTcwNzkyMzIwMDAwMCwiZW52aXJvbm1lbnQiOiJTYW5kYm94IiwiYnVuZGxlSWQiOiJjb20ucHJ1dWYuaW9zIiwiYXBwQWNjb3VudFRva2VuIjoidGVzdC11c2VyLXV1aWQifQ.signature"
    },
    "version": "2.0",
    "signedDate": 1705331200000
  }'
```

### Sandbox Testing

1. Create sandbox test accounts in App Store Connect
2. Configure sandbox URL in App Store Connect
3. Test purchases using sandbox accounts on device
4. Webhooks will be sent with `environment: "Sandbox"`

## Database Updates

The webhook handler updates the `receiver_profiles` table:

### Subscription Activation (INITIAL_BUY, DID_RENEW)
```sql
-- Uses activate_appstore_subscription() function
UPDATE receiver_profiles SET
    subscription_status = 'active',
    subscription_start_date = NOW(),
    subscription_end_date = $expiration_date,
    app_store_transaction_id = $transaction_id,
    app_store_original_transaction_id = $original_transaction_id,
    app_store_product_id = 'com.pruuf.receiver.monthly',
    app_store_environment = $environment,
    updated_at = NOW()
WHERE user_id = $user_id;
```

### Cancellation (AUTO_RENEW_DISABLED)
```sql
UPDATE receiver_profiles SET
    subscription_status = 'canceled',
    subscription_end_date = $access_until,  -- Keeps end date for continued access
    updated_at = NOW()
WHERE user_id = $user_id;
```

### Billing Issue (DID_FAIL_TO_RENEW)
```sql
UPDATE receiver_profiles SET
    subscription_status = 'past_due',
    updated_at = NOW()
WHERE user_id = $user_id;

-- Plus notification to user
INSERT INTO notifications (user_id, type, title, body, sent_at, delivery_status)
VALUES ($user_id, 'payment_reminder', 'Payment Issue',
        'We couldn''t renew your subscription. Please update your payment method...',
        NOW(), 'sent');
```

### Refund
```sql
UPDATE receiver_profiles SET
    subscription_status = 'expired',
    updated_at = NOW()
WHERE user_id = $user_id;

-- Plus audit log entry
INSERT INTO audit_logs (user_id, action, resource_type, details)
VALUES ($user_id, 'subscription_refunded', 'subscription', $refund_details);
```

## Error Handling

The webhook returns appropriate HTTP status codes:

| Status | Meaning |
|--------|---------|
| 200 | Success - webhook processed |
| 400 | Bad Request - invalid payload format |
| 401 | Unauthorized - Apple signature verification failed |
| 500 | Server Error - processing failed |

**Apple Retry Policy:**
- Apple retries failed webhooks for up to 24 hours with exponential backoff
- Return 200 for all successfully processed notifications
- Return 200 for notifications about unknown users (to prevent retries)

## Monitoring

### Supabase Dashboard
- View Edge Function logs: **Dashboard → Edge Functions → handle-appstore-webhook → Logs**
- Check invocation count and error rates

### Audit Logs
All subscription changes are logged to the `audit_logs` table with:
- `user_id` - Affected user
- `action` - e.g., `subscription_initial_buy`, `subscription_renewed`, `subscription_canceled`, `subscription_refunded`
- `resource_type` - `subscription`
- `details` - JSON with transaction details

### Alerts
Set up alerts for:
- High error rate (>5%)
- Function timeout
- Signature verification failures
- Unusual refund patterns

## Troubleshooting

### Common Issues

1. **"Signature verification failed" error**
   - Verify Apple's certificate chain is being properly validated
   - Check that the payload hasn't been modified in transit
   - Ensure you're receiving App Store Server Notifications V2 (not V1)

2. **User not found**
   - Ensure `appAccountToken` is passed during purchase (contains user UUID)
   - Check if user's `app_store_original_transaction_id` matches

3. **Duplicate events**
   - The handler uses upsert logic to handle duplicates
   - Each notification has a unique `notificationUUID` for idempotency

4. **Wrong subscription status**
   - Check `signedTransactionInfo.expiresDate` for actual expiration
   - Verify the notification type and subtype combination
   - Review audit logs for subscription change history

## Legacy Webhook (Deprecated)

The `process-payment-webhook` function is deprecated. Use `handle-appstore-webhook` for all new integrations.

Migration:
1. Update App Store Connect to point to new URL
2. Both functions remain active during transition
3. Remove old function after confirming new endpoint works
