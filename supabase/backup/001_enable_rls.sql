-- Enable Row Level Security (RLS) for all tables
-- PRUUF iOS App - Supabase Configuration
-- Run this migration to set up RLS policies

-- ============================================
-- ENABLE RLS ON ALL TABLES
-- ============================================

-- Users Profile Table
ALTER TABLE IF EXISTS public.users ENABLE ROW LEVEL SECURITY;

-- Connections Table (friends/family relationships)
ALTER TABLE IF EXISTS public.connections ENABLE ROW LEVEL SECURITY;

-- Pings Table (daily check-ins)
ALTER TABLE IF EXISTS public.pings ENABLE ROW LEVEL SECURITY;

-- Emergency Contacts Table
ALTER TABLE IF EXISTS public.emergency_contacts ENABLE ROW LEVEL SECURITY;

-- Subscriptions Table
ALTER TABLE IF EXISTS public.subscriptions ENABLE ROW LEVEL SECURITY;

-- Ping Schedules Table
ALTER TABLE IF EXISTS public.ping_schedules ENABLE ROW LEVEL SECURITY;

-- Notifications Table
ALTER TABLE IF EXISTS public.notifications ENABLE ROW LEVEL SECURITY;

-- ============================================
-- RLS POLICIES FOR USERS TABLE
-- ============================================

-- Users can view their own profile
CREATE POLICY "Users can view own profile"
ON public.users FOR SELECT
USING (auth.uid() = id);

-- Users can update their own profile
CREATE POLICY "Users can update own profile"
ON public.users FOR UPDATE
USING (auth.uid() = id);

-- Users can insert their own profile (during signup)
CREATE POLICY "Users can insert own profile"
ON public.users FOR INSERT
WITH CHECK (auth.uid() = id);

-- ============================================
-- RLS POLICIES FOR CONNECTIONS TABLE
-- ============================================

-- Users can view connections where they are either user_id or connected_user_id
CREATE POLICY "Users can view their connections"
ON public.connections FOR SELECT
USING (
    auth.uid() = user_id OR
    auth.uid() = connected_user_id
);

-- Users can create connection requests
CREATE POLICY "Users can create connections"
ON public.connections FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Users can update connections they initiated or received
CREATE POLICY "Users can update their connections"
ON public.connections FOR UPDATE
USING (
    auth.uid() = user_id OR
    auth.uid() = connected_user_id
);

-- Users can delete connections they are part of
CREATE POLICY "Users can delete their connections"
ON public.connections FOR DELETE
USING (
    auth.uid() = user_id OR
    auth.uid() = connected_user_id
);

-- ============================================
-- RLS POLICIES FOR PINGS TABLE
-- ============================================

-- Users can view their own pings
CREATE POLICY "Users can view own pings"
ON public.pings FOR SELECT
USING (auth.uid() = user_id);

-- Connected users can view pings (for monitoring)
CREATE POLICY "Connected users can view pings"
ON public.pings FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.connections c
        WHERE c.status = 'accepted'
        AND (
            (c.user_id = auth.uid() AND c.connected_user_id = pings.user_id) OR
            (c.connected_user_id = auth.uid() AND c.user_id = pings.user_id)
        )
    )
);

-- Users can create their own pings
CREATE POLICY "Users can create own pings"
ON public.pings FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Users can update their own pings
CREATE POLICY "Users can update own pings"
ON public.pings FOR UPDATE
USING (auth.uid() = user_id);

-- ============================================
-- RLS POLICIES FOR EMERGENCY CONTACTS TABLE
-- ============================================

-- Users can view their own emergency contacts
CREATE POLICY "Users can view own emergency contacts"
ON public.emergency_contacts FOR SELECT
USING (auth.uid() = user_id);

-- Users can create their own emergency contacts
CREATE POLICY "Users can create own emergency contacts"
ON public.emergency_contacts FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Users can update their own emergency contacts
CREATE POLICY "Users can update own emergency contacts"
ON public.emergency_contacts FOR UPDATE
USING (auth.uid() = user_id);

-- Users can delete their own emergency contacts
CREATE POLICY "Users can delete own emergency contacts"
ON public.emergency_contacts FOR DELETE
USING (auth.uid() = user_id);

-- ============================================
-- RLS POLICIES FOR SUBSCRIPTIONS TABLE
-- ============================================

-- Users can view their own subscriptions
CREATE POLICY "Users can view own subscriptions"
ON public.subscriptions FOR SELECT
USING (auth.uid() = user_id);

-- System can insert subscriptions (via service role)
-- Note: Subscriptions are managed via webhooks with service role key

-- ============================================
-- RLS POLICIES FOR PING SCHEDULES TABLE
-- ============================================

-- Users can view their own ping schedules
CREATE POLICY "Users can view own ping schedules"
ON public.ping_schedules FOR SELECT
USING (auth.uid() = user_id);

-- Users can create their own ping schedules
CREATE POLICY "Users can create own ping schedules"
ON public.ping_schedules FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Users can update their own ping schedules
CREATE POLICY "Users can update own ping schedules"
ON public.ping_schedules FOR UPDATE
USING (auth.uid() = user_id);

-- Users can delete their own ping schedules
CREATE POLICY "Users can delete own ping schedules"
ON public.ping_schedules FOR DELETE
USING (auth.uid() = user_id);

-- ============================================
-- RLS POLICIES FOR NOTIFICATIONS TABLE
-- ============================================

-- Users can view their own notifications
CREATE POLICY "Users can view own notifications"
ON public.notifications FOR SELECT
USING (auth.uid() = user_id);

-- Users can update their own notifications (mark as read)
CREATE POLICY "Users can update own notifications"
ON public.notifications FOR UPDATE
USING (auth.uid() = user_id);

-- System can insert notifications (via service role or triggers)
-- Note: Notifications are created via triggers/functions with elevated privileges
