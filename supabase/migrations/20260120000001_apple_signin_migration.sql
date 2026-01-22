-- Migration: 20260120000001_apple_signin_migration.sql
-- Description: Add optional email and apple_user_id fields for future features
-- Note: Phone number remains REQUIRED as the primary authentication method
-- SMS/Twilio removed - verification now uses APNs push notifications
-- Created: 2026-01-20

-- ============================================================================
-- 1. ADD OPTIONAL EMAIL AND APPLE SIGN-IN FIELDS
-- These are for future features, phone remains primary auth
-- ============================================================================

-- Email from Apple Sign-In (may be private relay email) - optional for future use
ALTER TABLE users ADD COLUMN IF NOT EXISTS email TEXT;

-- Apple User ID - unique identifier from Apple Sign-In - optional for future use
ALTER TABLE users ADD COLUMN IF NOT EXISTS apple_user_id TEXT UNIQUE;

-- ============================================================================
-- 2. CREATE INDEXES FOR NEW FIELDS
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_users_apple_user_id ON users(apple_user_id) WHERE apple_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL;

-- ============================================================================
-- 3. ADD COMMENTS FOR DOCUMENTATION
-- ============================================================================

COMMENT ON COLUMN users.email IS 'Optional email from Apple Sign-In (for future features)';
COMMENT ON COLUMN users.apple_user_id IS 'Optional Apple User ID from Apple Sign-In (for future features)';
COMMENT ON COLUMN users.phone_number IS 'Required phone number - PRIMARY authentication identifier';

-- ============================================================================
-- NOTE: phone_number and phone_country_code remain REQUIRED (NOT NULL)
-- Authentication flow uses APNs push notifications for verification instead of SMS
-- ============================================================================
