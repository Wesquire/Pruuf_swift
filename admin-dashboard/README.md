# PRUUF Admin Dashboard

Custom Next.js 14 admin dashboard for PRUUF iOS application with real-time analytics, user management, and system monitoring.

## Features

### ✅ Implemented Sections

1. **Overview Dashboard**
   - System health status (healthy/degraded/critical)
   - Key metrics cards (users, connections, MRR, pings)
   - User distribution by role
   - Ping performance metrics

2. **User Management**
   - Search users by phone number
   - View user details (role, connections, pings, subscription status)
   - User activity metrics
   - Account status indicators

3. **Connection Analytics**
   - Total/active/paused connections
   - Connection growth rate
   - Average connections per user
   - Month-over-month comparison

4. **Ping Analytics**
   - Total pings (today/week/month)
   - Completion rates (on-time/late/missed)
   - Average completion time
   - Streak statistics (longest/average)
   - Break usage statistics

5. **Subscription Metrics**
   - Monthly Recurring Revenue (MRR)
   - Trial to paid conversion rate
   - Churn rate and Lifetime Value (LTV)
   - Subscription breakdown (active/trial/past_due/canceled/expired)
   - Payment issues (failures/refunds/chargebacks)

6. **System Health**
   - Database connection pool usage
   - Average API query time
   - Push notification delivery rate
   - Cron job success rate
   - Storage usage
   - Active user sessions

## Tech Stack

- **Framework**: Next.js 14 (App Router)
- **UI Library**: shadcn/ui components + Radix UI
- **Styling**: Tailwind CSS
- **Backend**: Supabase (PostgreSQL + Edge Functions)
- **Charts**: Recharts
- **Authentication**: Supabase Auth
- **Language**: TypeScript

## Prerequisites

- Node.js 18.0 or higher
- npm or yarn package manager
- Access to PRUUF Supabase project

## Installation

### 1. Install Dependencies

```bash
cd admin-dashboard
npm install
```

### 2. Configure Environment Variables

Create a `.env.local` file in the `admin-dashboard` directory:

```env
NEXT_PUBLIC_SUPABASE_URL=https://oaiteiceynliooxpeuxt.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9haXRlaWNleW5saW9veHBldXh0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg1MzA0MzEsImV4cCI6MjA4NDEwNjQzMX0.Htm_jL8JbLK2jhVlCUL0A7m6PJVY_ZuBx3FqZDZrtgk
```

> **Note**: These are already configured in the `.env.local` file that was created.

### 3. Run Development Server

```bash
npm run dev
```

The dashboard will be available at [http://localhost:3000](http://localhost:3000)

### 4. Build for Production

```bash
npm run build
npm start
```

## Authentication

Currently, the dashboard connects directly to Supabase using the anon key. All admin functions are protected by Row Level Security (RLS) policies that check for admin role.

### Admin Credentials

- **Email**: wesleymwilliams@gmail.com
- **Password**: W@$hingt0n1
- **Role**: Super Admin

To access admin functions, you must:
1. Be authenticated with Supabase
2. Have an entry in the `admin_users` table with `role = 'super_admin'` or `role = 'admin'`

## Database Functions Used

The dashboard calls these Supabase RPC functions:

### User Management
- `get_admin_user_metrics()` - Total users, signups, activity
- `admin_search_users_by_phone(search_phone)` - Search users
- `admin_get_user_details(target_user_id)` - User details
- `admin_deactivate_user(target_user_id, reason)` - Deactivate account
- `admin_reactivate_user(target_user_id)` - Reactivate account
- `admin_update_subscription(target_user_id, status, end_date)` - Update subscription

### Connection Analytics
- `get_admin_connection_analytics()` - Connection stats
- `admin_get_top_users_by_connections(limit)` - Top users
- `admin_get_connection_growth(days_back)` - Growth over time

### Ping Analytics
- `get_admin_ping_analytics()` - Ping completion rates
- `admin_get_ping_completion_rates(days_back)` - Detailed rates
- `admin_get_streak_distribution()` - Streak ranges
- `admin_get_missed_ping_alerts(limit)` - Recent missed pings
- `admin_get_break_usage_stats()` - Break statistics

### Subscription Metrics
- `get_admin_subscription_metrics()` - Revenue, MRR, churn
- `admin_get_payment_failures(limit)` - Failed payments
- `admin_get_refunds_chargebacks(limit)` - Refund history

### System Health
- `get_admin_system_health()` - System metrics
- `admin_get_edge_function_metrics()` - Function performance
- `admin_get_cron_job_stats()` - Scheduled job stats

### Operations
- `admin_generate_manual_ping(connection_id)` - Create test ping
- `admin_send_test_notification(user_id, title, body)` - Send notification
- `admin_cancel_subscription(user_id, reason)` - Cancel subscription
- `admin_issue_refund(transaction_id, amount, reason)` - Issue refund

## File Structure

```
admin-dashboard/
├── app/
│   ├── layout.tsx          # Root layout
│   ├── page.tsx            # Main dashboard page
│   └── globals.css         # Global styles
├── components/
│   └── ui/                 # shadcn/ui components
│       ├── badge.tsx
│       ├── button.tsx
│       ├── card.tsx
│       ├── input.tsx
│       └── tabs.tsx
├── lib/
│   ├── supabase.ts         # Supabase client & API functions
│   └── utils.ts            # Utility functions
├── .env.local              # Environment variables
├── package.json            # Dependencies
├── tailwind.config.ts      # Tailwind configuration
├── tsconfig.json           # TypeScript configuration
└── README.md              # This file
```

## Deployment Options

### Option 1: Vercel (Recommended)

1. Push code to GitHub
2. Import project in Vercel
3. Add environment variables
4. Deploy

### Option 2: Supabase Hosting

```bash
# Build the app
npm run build

# Deploy to Supabase
supabase hosting deploy --project-ref oaiteiceynliooxpeuxt
```

### Option 3: Docker

```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build
EXPOSE 3000
CMD ["npm", "start"]
```

## Security Considerations

- All admin functions are protected by Supabase RLS policies
- Only users with admin role in `admin_users` table can execute admin functions
- Environment variables should never be committed to git
- Use HTTPS in production
- Consider adding IP whitelist for admin dashboard
- Enable MFA for admin accounts

## Troubleshooting

### Dashboard shows no data

1. Verify Supabase connection:
   ```bash
   # Check if environment variables are set
   echo $NEXT_PUBLIC_SUPABASE_URL
   ```

2. Check browser console for errors
3. Verify admin user exists in `admin_users` table
4. Ensure database migrations are applied

### Permission denied errors

1. Verify you're logged in with admin account
2. Check `admin_users` table for your user_id
3. Verify RLS policies are enabled
4. Check that admin functions have proper grants

### Metrics not updating

1. Click "Refresh Data" button
2. Check if edge functions are running
3. Verify cron jobs are executing
4. Check Supabase logs for errors

## Future Enhancements

- [ ] Add authentication UI (login page)
- [ ] Implement real-time data updates (Supabase Realtime)
- [ ] Add data visualization charts (line/bar charts for trends)
- [ ] Implement user impersonation feature
- [ ] Add export functionality (CSV/JSON)
- [ ] Create detailed audit log viewer
- [ ] Add bulk operations (bulk deactivate, bulk update)
- [ ] Implement advanced filtering and sorting
- [ ] Add email notification management
- [ ] Create custom reports builder

## Support

For issues or questions:
- Check the main PRUUF documentation
- Review Supabase logs at https://supabase.com/dashboard/project/oaiteiceynliooxpeuxt
- Contact admin: wesleymwilliams@gmail.com

---

**Built with**: Next.js 14 + Supabase + shadcn/ui
**Version**: 1.0.0
**Last Updated**: January 19, 2026
