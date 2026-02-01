-- Migration: 20260131000001_add_sender_profile_columns.sql
-- Purpose: Add missing columns to sender_profiles table for invitation codes
-- Created: 2026-01-31

-- ============================================================================
-- 1. Add invitation_code column to sender_profiles
-- ============================================================================

ALTER TABLE sender_profiles
ADD COLUMN IF NOT EXISTS invitation_code TEXT UNIQUE;

-- Add index for fast code lookups
CREATE INDEX IF NOT EXISTS idx_sender_profiles_invitation_code
ON sender_profiles(invitation_code)
WHERE invitation_code IS NOT NULL;

-- ============================================================================
-- 2. Add is_active column to sender_profiles
-- ============================================================================

ALTER TABLE sender_profiles
ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

-- Add index for active sender lookups
CREATE INDEX IF NOT EXISTS idx_sender_profiles_active
ON sender_profiles(is_active)
WHERE is_active = true;

-- ============================================================================
-- 3. Add trial_start_date column to receiver_profiles (if missing)
-- ============================================================================

ALTER TABLE receiver_profiles
ADD COLUMN IF NOT EXISTS trial_start_date TIMESTAMPTZ;

-- ============================================================================
-- 4. Comments
-- ============================================================================

COMMENT ON COLUMN sender_profiles.invitation_code IS 'Unique 6-digit code for receivers to connect with this sender';
COMMENT ON COLUMN sender_profiles.is_active IS 'Whether the sender profile is currently active';
COMMENT ON COLUMN receiver_profiles.trial_start_date IS 'When the free trial period started';
