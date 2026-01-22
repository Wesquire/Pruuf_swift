# PRUUF Admin Dashboard - Setup Guide

## Quick Start (5 minutes)

### Step 1: Install Dependencies
```bash
cd admin-dashboard
npm install
```

### Step 2: Verify Environment Variables
The `.env.local` file should already exist with:
```env
NEXT_PUBLIC_SUPABASE_URL=https://oaiteiceynliooxpeuxt.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

If it doesn't exist, copy `.env.local.example` to `.env.local` and fill in the values.

### Step 3: Run Development Server
```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) in your browser.

## Verification Checklist

After starting the dashboard, verify these sections are working:

### ✅ Overview Tab
- [ ] System Health card displays status (healthy/degraded/critical)
- [ ] Key metrics cards show numbers (Total Users, Active Connections, MRR, Pings Today)
- [ ] User Distribution section shows sender/receiver/both counts
- [ ] Ping Performance section shows completion rates

### ✅ User Management Tab
- [ ] Search box is visible
- [ ] Can enter phone number and search
- [ ] Search results display user cards with details

### ✅ Ping Analytics Tab
- [ ] Average Completion Time displayed
- [ ] Longest Streak displayed
- [ ] Average Streak displayed

### ✅ Subscriptions Tab
- [ ] MRR card shows revenue
- [ ] Conversion Rate displayed
- [ ] Churn Rate displayed
- [ ] Subscription Breakdown shows counts
- [ ] Payment Issues section shows failures/refunds/chargebacks

### ✅ System Health Tab
- [ ] Database & API Performance metrics visible
- [ ] Notifications & Jobs metrics visible
- [ ] Storage usage displayed

## Troubleshooting

### Error: "Cannot find module '@/lib/supabase'"

**Solution**: Run `npm install` to install all dependencies.

### Error: "fetch failed" or network errors

**Solution**:
1. Check `.env.local` file exists with correct values
2. Verify Supabase URL is correct
3. Check internet connection
4. Verify Supabase project is accessible

### Dashboard shows loading spinner forever

**Possible causes**:
1. **RLS policies blocking access**: You need to be authenticated as an admin
2. **Functions not deployed**: Ensure database migrations are applied
3. **Network issue**: Check browser console for errors

**Solution**:
```sql
-- Run this in Supabase SQL Editor to verify admin user exists
SELECT * FROM public.admin_users WHERE email = 'wesleymwilliams@gmail.com';

-- If no results, run:
INSERT INTO public.admin_users (email, role, is_active, permissions)
VALUES (
  'wesleymwilliams@gmail.com',
  'super_admin',
  true,
  '{"canViewUsers": true, "canEditUsers": true, ...}'::jsonb
);
```

### Metrics show 0 or null values

**Cause**: No data in database yet or functions returning empty results

**Solution**: This is normal for a new installation. Add test data:
1. Create test users in iOS app
2. Create connections
3. Generate pings
4. Wait for cron jobs to run

Alternatively, insert test data via SQL:
```sql
-- Example: Insert test user
INSERT INTO public.users (id, phone_number, primary_role, is_active)
VALUES (gen_random_uuid(), '+15555551234', 'sender', true);
```

## Production Deployment

### Deploy to Vercel

1. **Install Vercel CLI**:
   ```bash
   npm i -g vercel
   ```

2. **Login and Deploy**:
   ```bash
   cd admin-dashboard
   vercel
   ```

3. **Configure Environment Variables** in Vercel Dashboard:
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY`

4. **Set Production Domain** (optional):
   ```bash
   vercel --prod
   ```

### Deploy to Supabase Hosting

```bash
# Build the application
npm run build

# Deploy
supabase hosting deploy --project-ref oaiteiceynliooxpeuxt
```

### Deploy with Docker

```bash
# Build image
docker build -t pruuf-admin .

# Run container
docker run -p 3000:3000 \
  -e NEXT_PUBLIC_SUPABASE_URL=https://oaiteiceynliooxpeuxt.supabase.co \
  -e NEXT_PUBLIC_SUPABASE_ANON_KEY=your_key_here \
  pruuf-admin
```

## Security Hardening (Production)

### 1. Implement Authentication UI

Currently the dashboard uses direct Supabase connection. For production, add login page:

```typescript
// app/login/page.tsx
import { supabase } from '@/lib/supabase'

export default function LoginPage() {
  async function handleLogin(email: string, password: string) {
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password
    })
    // Handle response
  }
  // Render login form
}
```

### 2. Add Middleware for Auth Check

```typescript
// middleware.ts
import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

export function middleware(request: NextRequest) {
  // Check if user is authenticated
  // Redirect to login if not
}

export const config = {
  matcher: ['/']
}
```

### 3. IP Whitelist (Optional)

If dashboard should only be accessible from specific IPs:

```typescript
// middleware.ts
export function middleware(request: NextRequest) {
  const allowedIPs = process.env.ALLOWED_IPS?.split(',') || []
  const ip = request.ip || request.headers.get('x-forwarded-for')

  if (!allowedIPs.includes(ip)) {
    return new Response('Forbidden', { status: 403 })
  }

  return NextResponse.next()
}
```

### 4. Enable HTTPS Only

In production, ensure:
- Vercel automatically provides HTTPS
- For custom hosting, use Let's Encrypt or Cloudflare

### 5. Add Rate Limiting

```typescript
// Use Vercel Edge Config or Upstash Redis
import { Ratelimit } from "@upstash/ratelimit"

const ratelimit = new Ratelimit({
  redis: /* redis instance */,
  limiter: Ratelimit.slidingWindow(10, "10 s")
})
```

## Database Migration Verification

Ensure these migrations are applied:

```sql
-- Check if admin functions exist
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name LIKE 'admin_%'
OR routine_name LIKE 'get_admin_%';

-- Expected results (30+ functions):
-- admin_cancel_subscription
-- admin_create_impersonation_session
-- admin_deactivate_user
-- admin_export_report
-- admin_generate_manual_ping
-- admin_get_break_usage_stats
-- admin_get_connection_growth
-- admin_get_cron_job_stats
-- admin_get_edge_function_metrics
-- admin_get_missed_ping_alerts
-- admin_get_payment_failures
-- admin_get_ping_completion_rates
-- admin_get_refunds_chargebacks
-- admin_get_streak_distribution
-- admin_get_top_users_by_connections
-- admin_get_user_details
-- admin_issue_refund
-- admin_reactivate_user
-- admin_search_users_by_phone
-- admin_send_test_notification
-- admin_update_subscription
-- get_admin_connection_analytics
-- get_admin_ping_analytics
-- get_admin_subscription_metrics
-- get_admin_system_health
-- get_admin_user_metrics
```

If functions are missing, apply migrations:
```bash
cd ../supabase
supabase db push
```

## Performance Optimization

### 1. Enable Caching

Add caching to frequently accessed data:

```typescript
// lib/cache.ts
const cache = new Map()

export async function getCachedData(key: string, fetcher: () => Promise<any>, ttl = 60000) {
  const cached = cache.get(key)
  if (cached && Date.now() - cached.timestamp < ttl) {
    return cached.data
  }

  const data = await fetcher()
  cache.set(key, { data, timestamp: Date.now() })
  return data
}
```

### 2. Add Loading States

Already implemented via `loading` state variable.

### 3. Implement Pagination

For large datasets:

```typescript
// Add to lib/supabase.ts
export async function searchUsersWithPagination(
  phoneNumber: string,
  page: number = 0,
  limit: number = 20
) {
  // Implement pagination logic
}
```

## Monitoring

### 1. Add Error Tracking

```bash
npm install @sentry/nextjs
```

```typescript
// sentry.config.ts
import * as Sentry from "@sentry/nextjs"

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  tracesSampleRate: 1.0,
})
```

### 2. Add Analytics

```bash
npm install @vercel/analytics
```

```typescript
// app/layout.tsx
import { Analytics } from '@vercel/analytics/react'

export default function RootLayout({ children }) {
  return (
    <html>
      <body>
        {children}
        <Analytics />
      </body>
    </html>
  )
}
```

## Support

**Admin Contact**: wesleymwilliams@gmail.com
**Supabase Dashboard**: https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt
**Repository**: Check main project repository for issues

---

**Version**: 1.0.0
**Last Updated**: January 19, 2026
