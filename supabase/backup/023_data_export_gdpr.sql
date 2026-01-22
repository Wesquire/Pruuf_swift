-- Data Export GDPR Migration
-- Phase 10 Section 10.3: Data Export GDPR
-- Per plan.md:
-- - Generate ZIP file containing user data
-- - Upload to Storage bucket with 7-day expiration
-- - Process within 48 hours
-- - Send notification when ready

-- ============================================
-- CREATE DATA EXPORTS STORAGE BUCKET
-- ============================================

-- Create data-exports bucket (private) - for GDPR data exports
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'data-exports',
    'data-exports',
    false,
    104857600, -- 100MB max for export files
    ARRAY['application/zip', 'application/x-zip-compressed']
)
ON CONFLICT (id) DO UPDATE SET
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- ============================================
-- STORAGE POLICIES FOR DATA-EXPORTS BUCKET
-- ============================================

-- Users can view their own data exports
DROP POLICY IF EXISTS "Users can view own data exports" ON storage.objects;
CREATE POLICY "Users can view own data exports"
ON storage.objects FOR SELECT
USING (
    bucket_id = 'data-exports' AND
    auth.uid()::text = (storage.foldername(name))[1]
);

-- Service role can upload exports (Edge Functions use service role)
DROP POLICY IF EXISTS "Service can upload data exports" ON storage.objects;
CREATE POLICY "Service can upload data exports"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'data-exports'
);

-- Users can delete their own exports
DROP POLICY IF EXISTS "Users can delete own data exports" ON storage.objects;
CREATE POLICY "Users can delete own data exports"
ON storage.objects FOR DELETE
USING (
    bucket_id = 'data-exports' AND
    auth.uid()::text = (storage.foldername(name))[1]
);

-- ============================================
-- CREATE DATA EXPORT REQUESTS TABLE
-- ============================================

-- Table to track data export requests (for async processing)
CREATE TABLE IF NOT EXISTS data_export_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'expired')),
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    file_path TEXT, -- Storage path in data-exports bucket
    file_size_bytes BIGINT,
    download_count INTEGER DEFAULT 0,
    error_message TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for data_export_requests
CREATE INDEX IF NOT EXISTS idx_data_export_requests_user ON data_export_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_data_export_requests_status ON data_export_requests(status) WHERE status IN ('pending', 'processing');
CREATE INDEX IF NOT EXISTS idx_data_export_requests_expires ON data_export_requests(expires_at) WHERE status = 'completed';

-- Updated_at trigger
DROP TRIGGER IF EXISTS data_export_requests_updated_at ON data_export_requests;
CREATE TRIGGER data_export_requests_updated_at
    BEFORE UPDATE ON data_export_requests
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- ============================================
-- RLS POLICIES FOR DATA EXPORT REQUESTS
-- ============================================

ALTER TABLE data_export_requests ENABLE ROW LEVEL SECURITY;

-- Users can view their own export requests
DROP POLICY IF EXISTS "Users can view own export requests" ON data_export_requests;
CREATE POLICY "Users can view own export requests"
ON data_export_requests FOR SELECT
USING (user_id = auth.uid());

-- Users can create export requests for themselves
DROP POLICY IF EXISTS "Users can create own export requests" ON data_export_requests;
CREATE POLICY "Users can create own export requests"
ON data_export_requests FOR INSERT
WITH CHECK (user_id = auth.uid());

-- Users can update their own export requests (for download count)
DROP POLICY IF EXISTS "Users can update own export requests" ON data_export_requests;
CREATE POLICY "Users can update own export requests"
ON data_export_requests FOR UPDATE
USING (user_id = auth.uid());

-- ============================================
-- DATABASE FUNCTIONS FOR DATA EXPORT
-- ============================================

-- Function to request data export
-- Returns the export request ID
CREATE OR REPLACE FUNCTION request_data_export(p_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_request_id UUID;
    v_existing_pending UUID;
BEGIN
    -- Check for existing pending or processing request in last 24 hours
    SELECT id INTO v_existing_pending
    FROM data_export_requests
    WHERE user_id = p_user_id
    AND status IN ('pending', 'processing')
    AND requested_at > NOW() - INTERVAL '24 hours'
    LIMIT 1;

    IF v_existing_pending IS NOT NULL THEN
        RETURN v_existing_pending; -- Return existing request
    END IF;

    -- Create new export request
    INSERT INTO data_export_requests (user_id, status)
    VALUES (p_user_id, 'pending')
    RETURNING id INTO v_request_id;

    -- Log audit event
    INSERT INTO audit_logs (user_id, action, resource_type, resource_id, details)
    VALUES (
        p_user_id,
        'data_export_requested',
        'data_export_request',
        v_request_id,
        jsonb_build_object(
            'request_id', v_request_id,
            'timestamp', NOW()
        )
    );

    RETURN v_request_id;
END;
$$;

-- Function to get all user data for export (called by Edge Function)
-- Returns JSONB with all user data
CREATE OR REPLACE FUNCTION get_user_export_data(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
    v_user_profile JSONB;
    v_sender_profile JSONB;
    v_receiver_profile JSONB;
    v_connections JSONB;
    v_pings JSONB;
    v_breaks JSONB;
    v_notifications JSONB;
    v_payment_transactions JSONB;
BEGIN
    -- 1. User Profile
    SELECT jsonb_build_object(
        'id', id,
        'phone_number', phone_number,
        'phone_country_code', phone_country_code,
        'timezone', timezone,
        'primary_role', primary_role,
        'is_active', is_active,
        'has_completed_onboarding', has_completed_onboarding,
        'notification_preferences', notification_preferences,
        'created_at', created_at,
        'updated_at', updated_at,
        'last_seen_at', last_seen_at
    ) INTO v_user_profile
    FROM users
    WHERE id = p_user_id;

    -- 2. Sender Profile (if exists)
    SELECT jsonb_build_object(
        'id', id,
        'ping_time', ping_time,
        'ping_enabled', ping_enabled,
        'created_at', created_at,
        'updated_at', updated_at
    ) INTO v_sender_profile
    FROM sender_profiles
    WHERE user_id = p_user_id;

    -- 3. Receiver Profile (if exists)
    SELECT jsonb_build_object(
        'id', id,
        'subscription_status', subscription_status,
        'subscription_start_date', subscription_start_date,
        'subscription_end_date', subscription_end_date,
        'trial_start_date', trial_start_date,
        'trial_end_date', trial_end_date,
        'created_at', created_at,
        'updated_at', updated_at
    ) INTO v_receiver_profile
    FROM receiver_profiles
    WHERE user_id = p_user_id;

    -- 4. Connections (both as sender and receiver)
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', c.id,
            'role_in_connection', CASE
                WHEN c.sender_id = p_user_id THEN 'sender'
                ELSE 'receiver'
            END,
            'other_user_phone', CASE
                WHEN c.sender_id = p_user_id THEN r.phone_number
                ELSE s.phone_number
            END,
            'status', c.status,
            'connection_code', c.connection_code,
            'created_at', c.created_at,
            'updated_at', c.updated_at,
            'deleted_at', c.deleted_at
        )
    ), '[]'::jsonb) INTO v_connections
    FROM connections c
    LEFT JOIN users s ON c.sender_id = s.id
    LEFT JOIN users r ON c.receiver_id = r.id
    WHERE c.sender_id = p_user_id OR c.receiver_id = p_user_id;

    -- 5. Pings (both as sender and receiver)
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', p.id,
            'role_in_ping', CASE
                WHEN p.sender_id = p_user_id THEN 'sender'
                ELSE 'receiver'
            END,
            'scheduled_time', p.scheduled_time,
            'deadline_time', p.deadline_time,
            'completed_at', p.completed_at,
            'completion_method', p.completion_method,
            'status', p.status,
            'verification_location', p.verification_location,
            'notes', p.notes,
            'created_at', p.created_at
        ) ORDER BY p.scheduled_time DESC
    ), '[]'::jsonb) INTO v_pings
    FROM pings p
    WHERE p.sender_id = p_user_id OR p.receiver_id = p_user_id;

    -- 6. Breaks (sender only)
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', b.id,
            'start_date', b.start_date,
            'end_date', b.end_date,
            'status', b.status,
            'notes', b.notes,
            'created_at', b.created_at
        ) ORDER BY b.start_date DESC
    ), '[]'::jsonb) INTO v_breaks
    FROM breaks b
    WHERE b.sender_id = p_user_id;

    -- 7. Notifications
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', n.id,
            'type', n.type,
            'title', n.title,
            'body', n.body,
            'sent_at', n.sent_at,
            'read_at', n.read_at,
            'delivery_status', n.delivery_status
        ) ORDER BY n.sent_at DESC
    ), '[]'::jsonb) INTO v_notifications
    FROM notifications n
    WHERE n.user_id = p_user_id;

    -- 8. Payment Transactions
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', pt.id,
            'amount', pt.amount,
            'currency', pt.currency,
            'status', pt.status,
            'transaction_type', pt.transaction_type,
            'created_at', pt.created_at
        ) ORDER BY pt.created_at DESC
    ), '[]'::jsonb) INTO v_payment_transactions
    FROM payment_transactions pt
    WHERE pt.user_id = p_user_id;

    -- Build final result
    v_result := jsonb_build_object(
        'export_info', jsonb_build_object(
            'exported_at', NOW(),
            'format_version', '1.0',
            'data_categories', ARRAY['user_profile', 'sender_profile', 'receiver_profile', 'connections', 'pings', 'breaks', 'notifications', 'payment_transactions']
        ),
        'user_profile', v_user_profile,
        'sender_profile', v_sender_profile,
        'receiver_profile', v_receiver_profile,
        'connections', v_connections,
        'pings', v_pings,
        'breaks', v_breaks,
        'notifications', v_notifications,
        'payment_transactions', v_payment_transactions
    );

    RETURN v_result;
END;
$$;

-- Function to mark export as completed
CREATE OR REPLACE FUNCTION complete_data_export(
    p_request_id UUID,
    p_file_path TEXT,
    p_file_size BIGINT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    -- Update request
    UPDATE data_export_requests
    SET
        status = 'completed',
        completed_at = NOW(),
        expires_at = NOW() + INTERVAL '7 days',
        file_path = p_file_path,
        file_size_bytes = p_file_size,
        updated_at = NOW()
    WHERE id = p_request_id
    RETURNING user_id INTO v_user_id;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- Log audit event
    INSERT INTO audit_logs (user_id, action, resource_type, resource_id, details)
    VALUES (
        v_user_id,
        'data_export_completed',
        'data_export_request',
        p_request_id,
        jsonb_build_object(
            'file_path', p_file_path,
            'file_size_bytes', p_file_size,
            'expires_at', NOW() + INTERVAL '7 days'
        )
    );

    RETURN TRUE;
END;
$$;

-- Function to mark export as failed
CREATE OR REPLACE FUNCTION fail_data_export(
    p_request_id UUID,
    p_error_message TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    UPDATE data_export_requests
    SET
        status = 'failed',
        error_message = p_error_message,
        updated_at = NOW()
    WHERE id = p_request_id
    RETURNING user_id INTO v_user_id;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- Log audit event
    INSERT INTO audit_logs (user_id, action, resource_type, resource_id, details)
    VALUES (
        v_user_id,
        'data_export_failed',
        'data_export_request',
        p_request_id,
        jsonb_build_object(
            'error_message', p_error_message
        )
    );

    RETURN TRUE;
END;
$$;

-- Function to get export download URL (increments download count)
CREATE OR REPLACE FUNCTION get_export_download_info(p_request_id UUID, p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_request RECORD;
BEGIN
    -- Get and validate request
    SELECT * INTO v_request
    FROM data_export_requests
    WHERE id = p_request_id
    AND user_id = p_user_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Export request not found');
    END IF;

    IF v_request.status != 'completed' THEN
        RETURN jsonb_build_object('error', 'Export not completed', 'status', v_request.status);
    END IF;

    IF v_request.expires_at < NOW() THEN
        -- Mark as expired
        UPDATE data_export_requests SET status = 'expired', updated_at = NOW() WHERE id = p_request_id;
        RETURN jsonb_build_object('error', 'Export has expired');
    END IF;

    -- Increment download count
    UPDATE data_export_requests
    SET download_count = download_count + 1, updated_at = NOW()
    WHERE id = p_request_id;

    RETURN jsonb_build_object(
        'file_path', v_request.file_path,
        'file_size_bytes', v_request.file_size_bytes,
        'expires_at', v_request.expires_at,
        'download_count', v_request.download_count + 1
    );
END;
$$;

-- Function to cleanup expired exports (runs via cron)
CREATE OR REPLACE FUNCTION cleanup_expired_exports()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_deleted_count INTEGER;
BEGIN
    -- Mark expired requests
    UPDATE data_export_requests
    SET status = 'expired', updated_at = NOW()
    WHERE status = 'completed'
    AND expires_at < NOW();

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

    -- Note: Actual file deletion from storage should be done by Edge Function
    -- as it requires storage API access

    RETURN v_deleted_count;
END;
$$;

-- ============================================
-- SCHEDULED JOB FOR EXPIRED EXPORT CLEANUP
-- ============================================

-- Add cron job to cleanup expired exports daily at 4 AM UTC
-- Note: This is added to existing scheduled jobs
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM cron.job WHERE jobname = 'cleanup-expired-exports'
    ) THEN
        PERFORM cron.schedule(
            'cleanup-expired-exports',
            '0 4 * * *', -- 4 AM UTC daily
            $$SELECT cleanup_expired_exports()$$
        );
    END IF;
EXCEPTION
    WHEN undefined_function THEN
        -- pg_cron not installed, skip
        RAISE NOTICE 'pg_cron extension not installed, skipping cron job creation';
    WHEN OTHERS THEN
        RAISE NOTICE 'Could not create cron job: %', SQLERRM;
END;
$$;

-- ============================================
-- COMMENTS FOR DOCUMENTATION
-- ============================================

COMMENT ON TABLE data_export_requests IS 'Tracks GDPR data export requests per Phase 10 Section 10.3';
COMMENT ON FUNCTION request_data_export(UUID) IS 'Creates a new data export request, returns existing pending if within 24h';
COMMENT ON FUNCTION get_user_export_data(UUID) IS 'Gathers all user data for GDPR export - called by export_user_data Edge Function';
COMMENT ON FUNCTION complete_data_export(UUID, TEXT, BIGINT) IS 'Marks export as completed with file info';
COMMENT ON FUNCTION fail_data_export(UUID, TEXT) IS 'Marks export as failed with error message';
COMMENT ON FUNCTION get_export_download_info(UUID, UUID) IS 'Gets download info and increments count';
COMMENT ON FUNCTION cleanup_expired_exports() IS 'Marks expired exports, runs daily via cron';
