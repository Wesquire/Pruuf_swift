# Admin Dashboard Quick Reference

**Quick access guide for PRUUF Admin Dashboard operations**

---

## Access

**URL**: https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt
**Email**: wesleymwilliams@gmail.com
**Password**: W@$hingt0n1

**Direct SQL Editor**: Click "SQL Editor" in left sidebar after login

---

## Quick Commands

### Daily Health Check

```sql
-- Morning dashboard snapshot
SELECT
    'Users' AS metric,
    (data->>'total_users')::TEXT AS value
FROM (SELECT get_admin_user_metrics() AS data) m
UNION ALL
SELECT
    'Active Last 24h',
    (data->>'active_users_last_7_days')::TEXT
FROM (SELECT get_admin_user_metrics() AS data) m
UNION ALL
SELECT
    'Pings Today',
    (data->>'total_pings_today')::TEXT
FROM (SELECT get_admin_ping_analytics() AS data) m
UNION ALL
SELECT
    'Completion Rate',
    ROUND((data->>'completion_rate_on_time')::NUMERIC * 100, 2)::TEXT || '%'
FROM (SELECT get_admin_ping_analytics() AS data) m
UNION ALL
SELECT
    'MRR',
    '$' || (data->>'monthly_recurring_revenue')::TEXT
FROM (SELECT get_admin_subscription_metrics() AS data) m
UNION ALL
SELECT
    'Health Status',
    (data->>'health_status')::TEXT
FROM (SELECT get_admin_system_health() AS data) m;
```

### Find a User

```sql
-- Search by phone (partial match)
SELECT * FROM admin_search_users_by_phone('555');

-- Get full details (replace with actual UUID)
SELECT * FROM admin_get_user_details('user-uuid-here');
```

### Check Missed Pings

```sql
-- Recent missed pings
SELECT
    jsonb_extract_path_text(alert, 'sender_phone') AS sender,
    jsonb_extract_path_text(alert, 'receiver_phone') AS receiver,
    jsonb_extract_path_text(alert, 'consecutive_misses') AS consecutive_misses,
    jsonb_extract_path_text(alert, 'scheduled_time') AS scheduled_time
FROM jsonb_array_elements(
    (SELECT admin_get_missed_ping_alerts(10))
) AS alert;
```

### Subscription Management

```sql
-- Extend trial by 15 days
SELECT admin_update_subscription(
    'user-uuid-here',
    'trial',
    (NOW() + INTERVAL '15 days')::TEXT
);

-- Activate paid subscription
SELECT admin_update_subscription(
    'user-uuid-here',
    'active',
    (NOW() + INTERVAL '30 days')::TEXT
);

-- Cancel subscription
SELECT admin_cancel_subscription(
    'user-uuid-here',
    'User requested cancellation'
);
```

### Test Operations

```sql
-- Send test notification
SELECT admin_send_test_notification(
    'user-uuid-here',
    'Test Notification',
    'This is a test message from admin'
);

-- Generate manual ping
SELECT admin_generate_manual_ping('connection-uuid-here');
```

### Payment Issues

```sql
-- Recent payment failures
SELECT
    jsonb_extract_path_text(failure, 'phone_number') AS phone,
    jsonb_extract_path_text(failure, 'amount') AS amount,
    jsonb_extract_path_text(failure, 'failure_reason') AS reason,
    jsonb_extract_path_text(failure, 'failed_at') AS failed_at
FROM jsonb_array_elements(
    (SELECT admin_get_payment_failures(20))
) AS failure
ORDER BY jsonb_extract_path_text(failure, 'failed_at') DESC;
```

### System Health Check

```sql
-- System health overview
SELECT
    (data->>'health_status')::TEXT AS status,
    (data->>'active_user_sessions')::INT AS sessions,
    (data->>'pending_pings')::INT AS pending,
    ROUND((data->>'push_notification_delivery_rate')::NUMERIC * 100, 1)::TEXT || '%' AS notif_rate,
    ROUND((data->>'api_error_rate_last_24h')::NUMERIC * 100, 2)::TEXT || '%' AS error_rate
FROM (SELECT get_admin_system_health() AS data) subq;
```

### Export Data

```sql
-- Export user report
SELECT * FROM admin_export_report('users', 'csv');

-- Export connection analytics
SELECT * FROM admin_export_report('connections', 'csv');

-- Export ping analytics
SELECT * FROM admin_export_report('pings', 'csv');
```

---

## Common Scenarios

### Scenario 1: User Can't Log In

```sql
-- Step 1: Find the user
SELECT * FROM admin_search_users_by_phone('+1555');

-- Step 2: Get details
SELECT * FROM admin_get_user_details('user-uuid-from-step-1');

-- Step 3: Check if deactivated
-- If is_active = false, reactivate:
SELECT admin_reactivate_user('user-uuid');
```

### Scenario 2: User Missed Payment

```sql
-- Step 1: Find the user
SELECT * FROM admin_search_users_by_phone('phone-number');

-- Step 2: Check payment failures
SELECT * FROM admin_get_payment_failures(50);

-- Step 3: Manually extend subscription (if needed)
SELECT admin_update_subscription(
    'user-uuid',
    'active',
    (NOW() + INTERVAL '30 days')::TEXT
);
```

### Scenario 3: User Reports Ping Not Sent

```sql
-- Step 1: Check ping status for user
SELECT * FROM pings
WHERE sender_id = 'user-uuid'
AND scheduled_time::DATE = CURRENT_DATE;

-- Step 2: Generate manual ping if needed
SELECT admin_generate_manual_ping('connection-uuid');

-- Step 3: Send test notification
SELECT admin_send_test_notification(
    'user-uuid',
    'Test Ping',
    'Testing notification delivery'
);
```

### Scenario 4: Refund Request

```sql
-- Step 1: Find the transaction
SELECT * FROM payment_transactions
WHERE user_id = 'user-uuid'
ORDER BY created_at DESC
LIMIT 10;

-- Step 2: Issue refund (Super Admin only)
SELECT admin_issue_refund(
    'transaction-uuid',
    '2.99',
    'User requested refund - issue description'
);
```

---

## Alert Thresholds

Monitor these daily:

| Metric | Threshold | Query |
|--------|-----------|-------|
| Ping completion rate | < 90% | `SELECT (data->>'completion_rate_on_time')::FLOAT FROM (SELECT get_admin_ping_analytics() AS data) m;` |
| Notification delivery | < 95% | `SELECT (data->>'push_notification_delivery_rate')::FLOAT FROM (SELECT get_admin_system_health() AS data) m;` |
| API error rate | > 2% | `SELECT (data->>'api_error_rate_last_24h')::FLOAT FROM (SELECT get_admin_system_health() AS data) m;` |
| Payment failures | > 5% | Check `admin_get_payment_failures(50)` count |

---

## Troubleshooting

### Can't Execute Admin Functions

```sql
-- Verify you're an admin
SELECT * FROM admin_users WHERE email = 'wesleymwilliams@gmail.com';

-- Check permissions
SELECT
    email,
    role,
    is_active,
    permissions
FROM admin_users
WHERE user_id = auth.uid();
```

### Need to View Raw Data

Use **Table Editor** instead of SQL:
1. Go to: https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt/editor
2. Select table from left sidebar
3. View/edit data in spreadsheet interface

---

## Full Documentation

For complete documentation, see: `ADMIN_DASHBOARD_IMPLEMENTATION.md`

For all available functions: `supabase/migrations/026_admin_dashboard_features.sql`
