-- Migration 015: Notification Preferences Schema Update
-- Phase 8 Section 8.3: Notification Preferences
-- Adds comprehensive notification preference structure

-- This migration updates the notification_preferences JSONB structure to support:
-- - Master toggle (notifications_enabled)
-- - Sender preferences (ping_reminders, fifteen_minute_warning, deadline_warning)
-- - Receiver preferences (ping_completed_notifications, missed_ping_alerts, connection_requests)
-- - Per-sender muting (muted_sender_ids)
-- - Quiet hours (quiet_hours_enabled, quiet_hours_start, quiet_hours_end)

-- Create a function to migrate existing notification preferences to new schema
CREATE OR REPLACE FUNCTION migrate_notification_preferences(old_prefs JSONB)
RETURNS JSONB AS $$
DECLARE
    new_prefs JSONB;
BEGIN
    -- Start with defaults
    new_prefs := jsonb_build_object(
        'notifications_enabled', TRUE,
        'ping_reminders', COALESCE((old_prefs->>'ping_reminders')::boolean, TRUE),
        'fifteen_minute_warning', TRUE,
        'deadline_warning', COALESCE((old_prefs->>'deadline_alerts')::boolean, TRUE),
        'ping_completed_notifications', TRUE,
        'missed_ping_alerts', TRUE,
        'connection_requests', COALESCE((old_prefs->>'connection_requests')::boolean, TRUE),
        'muted_sender_ids', COALESCE(old_prefs->'muted_sender_ids', '[]'::jsonb),
        'quiet_hours_enabled', FALSE,
        'quiet_hours_start', NULL,
        'quiet_hours_end', NULL
    );

    RETURN new_prefs;
END;
$$ LANGUAGE plpgsql;

-- Update existing users with migrated preferences
-- Only update if the new fields don't already exist
UPDATE users
SET notification_preferences = migrate_notification_preferences(notification_preferences)
WHERE notification_preferences IS NOT NULL
  AND notification_preferences->>'notifications_enabled' IS NULL;

-- Set default preferences for users who don't have any
UPDATE users
SET notification_preferences = jsonb_build_object(
    'notifications_enabled', TRUE,
    'ping_reminders', TRUE,
    'fifteen_minute_warning', TRUE,
    'deadline_warning', TRUE,
    'ping_completed_notifications', TRUE,
    'missed_ping_alerts', TRUE,
    'connection_requests', TRUE,
    'muted_sender_ids', '[]'::jsonb,
    'quiet_hours_enabled', FALSE,
    'quiet_hours_start', NULL,
    'quiet_hours_end', NULL
)
WHERE notification_preferences IS NULL;

-- Create a function to get default notification preferences
CREATE OR REPLACE FUNCTION get_default_notification_preferences()
RETURNS JSONB AS $$
BEGIN
    RETURN jsonb_build_object(
        'notifications_enabled', TRUE,
        'ping_reminders', TRUE,
        'fifteen_minute_warning', TRUE,
        'deadline_warning', TRUE,
        'ping_completed_notifications', TRUE,
        'missed_ping_alerts', TRUE,
        'connection_requests', TRUE,
        'muted_sender_ids', '[]'::jsonb,
        'quiet_hours_enabled', FALSE,
        'quiet_hours_start', NULL,
        'quiet_hours_end', NULL
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Create a function to check if a user has notifications enabled
CREATE OR REPLACE FUNCTION user_notifications_enabled(p_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    prefs JSONB;
BEGIN
    SELECT notification_preferences INTO prefs
    FROM users
    WHERE id = p_user_id;

    IF prefs IS NULL THEN
        RETURN TRUE; -- Default to enabled
    END IF;

    RETURN COALESCE((prefs->>'notifications_enabled')::boolean, TRUE);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Create a function to check if a specific notification type is enabled
CREATE OR REPLACE FUNCTION should_send_notification(
    p_user_id UUID,
    p_notification_type TEXT,
    p_sender_id UUID DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    prefs JSONB;
    is_sender_muted BOOLEAN;
BEGIN
    SELECT notification_preferences INTO prefs
    FROM users
    WHERE id = p_user_id;

    -- Default to sending if no preferences set
    IF prefs IS NULL THEN
        RETURN TRUE;
    END IF;

    -- Check master toggle
    IF NOT COALESCE((prefs->>'notifications_enabled')::boolean, TRUE) THEN
        RETURN FALSE;
    END IF;

    -- Check quiet hours (future feature - always returns false for now to not block)
    -- Note: Quiet hours logic should be implemented client-side for timezone handling

    -- Check per-sender muting for receiver notifications
    IF p_sender_id IS NOT NULL AND prefs->'muted_sender_ids' IS NOT NULL THEN
        SELECT EXISTS(
            SELECT 1 FROM jsonb_array_elements_text(prefs->'muted_sender_ids') AS sender_id
            WHERE sender_id = p_sender_id::text
        ) INTO is_sender_muted;

        IF is_sender_muted THEN
            RETURN FALSE;
        END IF;
    END IF;

    -- Check notification type specific settings
    CASE p_notification_type
        WHEN 'ping_reminder' THEN
            RETURN COALESCE((prefs->>'ping_reminders')::boolean, TRUE);
        WHEN 'deadline_warning' THEN
            RETURN COALESCE((prefs->>'fifteen_minute_warning')::boolean, TRUE);
        WHEN 'deadline_final' THEN
            RETURN COALESCE((prefs->>'deadline_warning')::boolean, TRUE);
        WHEN 'missed_ping' THEN
            RETURN COALESCE((prefs->>'missed_ping_alerts')::boolean, TRUE);
        WHEN 'ping_completed_ontime', 'ping_completed_late' THEN
            RETURN COALESCE((prefs->>'ping_completed_notifications')::boolean, TRUE);
        WHEN 'connection_request' THEN
            RETURN COALESCE((prefs->>'connection_requests')::boolean, TRUE);
        WHEN 'break_started' THEN
            -- Use same setting as ping completed
            RETURN COALESCE((prefs->>'ping_completed_notifications')::boolean, TRUE);
        WHEN 'payment_reminder', 'trial_ending' THEN
            -- Always send payment-related notifications
            RETURN TRUE;
        ELSE
            -- Default to sending for unknown types
            RETURN TRUE;
    END CASE;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Create a function to mute a sender for a receiver
CREATE OR REPLACE FUNCTION mute_sender(
    p_receiver_id UUID,
    p_sender_id UUID
)
RETURNS JSONB AS $$
DECLARE
    current_prefs JSONB;
    muted_senders JSONB;
BEGIN
    -- Get current preferences
    SELECT notification_preferences INTO current_prefs
    FROM users
    WHERE id = p_receiver_id;

    IF current_prefs IS NULL THEN
        current_prefs := get_default_notification_preferences();
    END IF;

    -- Get current muted senders
    muted_senders := COALESCE(current_prefs->'muted_sender_ids', '[]'::jsonb);

    -- Add sender if not already muted
    IF NOT muted_senders ? p_sender_id::text THEN
        muted_senders := muted_senders || to_jsonb(p_sender_id::text);
    END IF;

    -- Update preferences
    current_prefs := jsonb_set(current_prefs, '{muted_sender_ids}', muted_senders);

    UPDATE users
    SET notification_preferences = current_prefs
    WHERE id = p_receiver_id;

    RETURN current_prefs;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create a function to unmute a sender for a receiver
CREATE OR REPLACE FUNCTION unmute_sender(
    p_receiver_id UUID,
    p_sender_id UUID
)
RETURNS JSONB AS $$
DECLARE
    current_prefs JSONB;
    muted_senders JSONB;
BEGIN
    -- Get current preferences
    SELECT notification_preferences INTO current_prefs
    FROM users
    WHERE id = p_receiver_id;

    IF current_prefs IS NULL THEN
        RETURN get_default_notification_preferences();
    END IF;

    -- Get current muted senders
    muted_senders := COALESCE(current_prefs->'muted_sender_ids', '[]'::jsonb);

    -- Remove sender from muted list
    muted_senders := (
        SELECT COALESCE(jsonb_agg(sender_id), '[]'::jsonb)
        FROM jsonb_array_elements_text(muted_senders) AS sender_id
        WHERE sender_id != p_sender_id::text
    );

    -- Update preferences
    current_prefs := jsonb_set(current_prefs, '{muted_sender_ids}', muted_senders);

    UPDATE users
    SET notification_preferences = current_prefs
    WHERE id = p_receiver_id;

    RETURN current_prefs;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create a function to check if a sender is muted
CREATE OR REPLACE FUNCTION is_sender_muted(
    p_receiver_id UUID,
    p_sender_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    prefs JSONB;
BEGIN
    SELECT notification_preferences INTO prefs
    FROM users
    WHERE id = p_receiver_id;

    IF prefs IS NULL OR prefs->'muted_sender_ids' IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN prefs->'muted_sender_ids' ? p_sender_id::text;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Create a function to update notification preferences
CREATE OR REPLACE FUNCTION update_notification_preferences(
    p_user_id UUID,
    p_preferences JSONB
)
RETURNS JSONB AS $$
DECLARE
    current_prefs JSONB;
BEGIN
    -- Get current preferences
    SELECT notification_preferences INTO current_prefs
    FROM users
    WHERE id = p_user_id;

    IF current_prefs IS NULL THEN
        current_prefs := get_default_notification_preferences();
    END IF;

    -- Merge new preferences with current (new values override old)
    current_prefs := current_prefs || p_preferences;

    -- Update user
    UPDATE users
    SET notification_preferences = current_prefs
    WHERE id = p_user_id;

    RETURN current_prefs;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create index for efficient notification preference lookups
CREATE INDEX IF NOT EXISTS idx_users_notifications_enabled
ON users USING btree (((notification_preferences->>'notifications_enabled')::boolean));

-- Grant execute permissions on functions
GRANT EXECUTE ON FUNCTION get_default_notification_preferences() TO authenticated;
GRANT EXECUTE ON FUNCTION user_notifications_enabled(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION should_send_notification(UUID, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION mute_sender(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION unmute_sender(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION is_sender_muted(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION update_notification_preferences(UUID, JSONB) TO authenticated;

-- Add comment documenting the notification preferences schema
COMMENT ON COLUMN users.notification_preferences IS 'JSONB notification preferences with schema:
{
  "notifications_enabled": boolean,      -- Master toggle
  "ping_reminders": boolean,              -- Sender: at scheduled time
  "fifteen_minute_warning": boolean,      -- Sender: 15 min before deadline
  "deadline_warning": boolean,            -- Sender: at deadline
  "ping_completed_notifications": boolean, -- Receiver: ping completed
  "missed_ping_alerts": boolean,          -- Receiver: missed ping
  "connection_requests": boolean,         -- Both: new connection requests
  "muted_sender_ids": string[],           -- Receiver: muted sender UUIDs
  "quiet_hours_enabled": boolean,         -- Future: quiet hours toggle
  "quiet_hours_start": string,            -- Future: HH:mm format
  "quiet_hours_end": string               -- Future: HH:mm format
}';
