# PRUUF Admin Dashboard Credentials

> **SECURITY WARNING**: This file contains sensitive credential information.
> In production, credentials should be managed via secure secrets management.
> This file is for development and deployment reference only.

---

## Super Admin Account

| Field | Value |
|-------|-------|
| **Email** | wesleymwilliams@gmail.com |
| **Password** | W@$hingt0n1 |
| **Role** | Super Admin |
| **Status** | Active |

---

## Role: Super Admin

### Description
Full system access including analytics dashboard, user management, payment oversight, and system configuration.

### Permissions

| Permission | Granted |
|------------|---------|
| View Users | ✓ |
| Edit Users | ✓ |
| Delete Users | ✓ |
| Impersonate Users | ✓ |
| View Analytics | ✓ |
| Export Analytics | ✓ |
| View Subscriptions | ✓ |
| Modify Subscriptions | ✓ |
| Issue Refunds | ✓ |
| View Payments | ✓ |
| View Payment Details | ✓ |
| View System Health | ✓ |
| Modify System Config | ✓ |
| Manage Admins | ✓ |
| Send Broadcasts | ✓ |
| View Notification Logs | ✓ |

---

## Admin Dashboard Access

### Supabase Dashboard
- **URL**: https://oaiteiceynliooxpeuxt.supabase.co/project/_/admin
- **Access**: Log in with super admin credentials above

### Direct Database Access
- **Method**: Supabase SQL Editor
- **URL**: https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt/sql

### API Access
- **Base URL**: https://oaiteiceynliooxpeuxt.supabase.co
- **Auth**: Bearer token from Supabase Auth

---

## Setting Up Admin Access

### Step 1: Create Auth User

Create the admin user in Supabase Auth:

```bash
# Using Supabase CLI
supabase auth users create \
  --email wesleymwilliams@gmail.com \
  --password "W@$hingt0n1" \
  --data '{"role": "super_admin"}'
```

Or via Supabase Dashboard:
1. Go to Authentication > Users
2. Click "Add User"
3. Enter email: wesleymwilliams@gmail.com
4. Set password: W@$hingt0n1
5. Click "Create User"

### Step 2: Run Admin Migration

The admin roles migration (`004_admin_roles.sql`) creates the admin_users table
and seeds the super admin record.

```bash
# Apply migration
supabase db push
```

### Step 3: Link Auth User to Admin Record

After creating the auth user, update the admin_users record:

```sql
UPDATE public.admin_users
SET user_id = (
    SELECT id FROM auth.users
    WHERE email = 'wesleymwilliams@gmail.com'
)
WHERE email = 'wesleymwilliams@gmail.com';
```

---

## Admin Role Hierarchy

| Role | Level | Description |
|------|-------|-------------|
| Super Admin | 1 (Highest) | Full system access, can manage other admins |
| Admin | 2 | User management, analytics, payments (no system config) |
| Moderator | 3 | User management, content moderation |
| Support | 4 | View user details, handle support requests |
| Viewer | 5 (Lowest) | Read-only access to dashboards |

---

## Security Configuration

| Setting | Value |
|---------|-------|
| Session Timeout | 30 minutes |
| Max Failed Logins | 5 attempts |
| Lockout Duration | 15 minutes |
| Min Password Length | 12 characters |
| MFA Required | Recommended (not enforced initially) |
| Audit Log Retention | 365 days |

---

## Audit Logging

All admin actions are logged to `public.admin_audit_log`:

- User views
- User edits
- Subscription modifications
- System configuration changes
- Login attempts (success/failure)
- Session management

---

## Password Requirements

Admin passwords must meet these requirements:
- Minimum 12 characters
- At least one uppercase letter
- At least one lowercase letter
- At least one number
- At least one special character

The provided password `W@$hingt0n1` meets all requirements.

---

## Changing Admin Password

### Via Supabase Dashboard
1. Go to Authentication > Users
2. Find the admin user
3. Click the three-dot menu
4. Select "Reset Password"

### Via SQL
```sql
-- This sends a password reset email
SELECT auth.send_password_reset_email('wesleymwilliams@gmail.com');
```

---

## Adding New Admin Users

To add additional admins:

1. Create user in Supabase Auth
2. Insert into admin_users table:

```sql
INSERT INTO public.admin_users (user_id, email, role, is_active)
SELECT
    id,
    'newadmin@example.com',
    'admin',
    true
FROM auth.users
WHERE email = 'newadmin@example.com';
```

Only super admins can create new admin users.

---

## Troubleshooting

### Cannot Login
1. Verify email is correct
2. Check if account is locked (`locked_until` in admin_users)
3. Verify `is_active` is true
4. Check auth.users for the user record

### Permissions Not Working
1. Verify role is set correctly
2. Check permissions JSON override
3. Ensure RLS policies are applied

### Audit Logs Missing
1. Check if admin_id is linked correctly
2. Verify log_admin_action function is being called
3. Check for RLS policy issues

---

## Related Files

| File | Purpose |
|------|---------|
| `PRUUF/Core/Config/AdminConfig.swift` | iOS admin configuration |
| `supabase/migrations/004_admin_roles.sql` | Admin tables and seed data |
| `supabase/functions/` | Edge functions for admin operations |

---

**Last Updated**: 2026-01-17
**Version**: 1.0
