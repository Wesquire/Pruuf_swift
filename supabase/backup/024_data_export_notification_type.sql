-- Migration: 024_data_export_notification_type.sql
-- Purpose: Add data_export_ready notification type to support GDPR data exports
-- Phase 10 Section 10.3: Data Export GDPR
-- Created: 2026-01-19

-- ============================================================================
-- 1. ADD DATA_EXPORT_READY TYPE TO NOTIFICATIONS TABLE
-- ============================================================================

-- Drop the existing constraint
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- Add the new constraint with data_export_ready and data_export_email_sent types
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
    CHECK (type IN (
        'ping_reminder',
        'deadline_warning',
        'missed_ping',
        'connection_request',
        'payment_reminder',
        'trial_ending',
        'break_notification',
        'data_export_ready',
        'data_export_email_sent'
    ));

-- ============================================================================
-- COMMENTS FOR DOCUMENTATION
-- ============================================================================

COMMENT ON CONSTRAINT notifications_type_check ON notifications IS
    'Allowed notification types including data export notifications for GDPR compliance (Phase 10 Section 10.3)';
