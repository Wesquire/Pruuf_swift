-- Migration: 006_connection_invitations.sql
-- Description: Create connection_invitations table for SMS invitation workflow
-- Section 3.3: Sender Onboarding Flow - Connection Invitation

-- Create invitation status enum
CREATE TYPE invitation_status AS ENUM ('pending', 'accepted', 'declined', 'cancelled', 'expired');

-- Create connection_invitations table
CREATE TABLE IF NOT EXISTS connection_invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    invitation_code VARCHAR(6) NOT NULL,
    recipient_phone_number VARCHAR(20) NOT NULL,
    recipient_name VARCHAR(255),
    status invitation_status NOT NULL DEFAULT 'pending',
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create unique index on invitation_code (only for pending invitations)
CREATE UNIQUE INDEX idx_invitation_code_pending
ON connection_invitations(invitation_code)
WHERE status = 'pending';

-- Create index for looking up invitations by sender
CREATE INDEX idx_invitations_sender_id ON connection_invitations(sender_id);

-- Create index for looking up invitations by recipient phone
CREATE INDEX idx_invitations_recipient_phone ON connection_invitations(recipient_phone_number);

-- Create index for looking up pending invitations
CREATE INDEX idx_invitations_pending ON connection_invitations(status) WHERE status = 'pending';

-- Enable RLS
ALTER TABLE connection_invitations ENABLE ROW LEVEL SECURITY;

-- RLS Policies for connection_invitations

-- Senders can view their own invitations
CREATE POLICY "Senders can view own invitations"
ON connection_invitations FOR SELECT
TO authenticated
USING (sender_id = auth.uid());

-- Senders can create invitations
CREATE POLICY "Senders can create invitations"
ON connection_invitations FOR INSERT
TO authenticated
WITH CHECK (sender_id = auth.uid());

-- Senders can update their own invitations (cancel)
CREATE POLICY "Senders can update own invitations"
ON connection_invitations FOR UPDATE
TO authenticated
USING (sender_id = auth.uid())
WITH CHECK (sender_id = auth.uid());

-- Anyone authenticated can read invitations by code (for accepting)
CREATE POLICY "Authenticated users can read invitations by code"
ON connection_invitations FOR SELECT
TO authenticated
USING (status = 'pending');

-- Authenticated users can update pending invitations (accept/decline)
CREATE POLICY "Authenticated users can accept invitations"
ON connection_invitations FOR UPDATE
TO authenticated
USING (status = 'pending');

-- Create trigger for updated_at
CREATE TRIGGER update_connection_invitations_updated_at
    BEFORE UPDATE ON connection_invitations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Function to generate unique invitation code
CREATE OR REPLACE FUNCTION generate_invitation_code()
RETURNS VARCHAR(6) AS $$
DECLARE
    new_code VARCHAR(6);
    code_exists BOOLEAN;
BEGIN
    LOOP
        -- Generate random 6-digit code
        new_code := LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0');

        -- Check if code already exists in pending invitations
        SELECT EXISTS(
            SELECT 1 FROM connection_invitations
            WHERE invitation_code = new_code
            AND status = 'pending'
        ) INTO code_exists;

        -- Exit loop if code is unique
        EXIT WHEN NOT code_exists;
    END LOOP;

    RETURN new_code;
END;
$$ LANGUAGE plpgsql;

-- Function to expire old invitations (called by scheduled job)
CREATE OR REPLACE FUNCTION expire_old_invitations()
RETURNS void AS $$
BEGIN
    UPDATE connection_invitations
    SET status = 'expired',
        updated_at = NOW()
    WHERE status = 'pending'
    AND expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- Add scheduled job to expire invitations (runs daily at midnight UTC)
SELECT cron.schedule(
    'expire-old-invitations',
    '0 0 * * *',
    $$SELECT expire_old_invitations()$$
);

-- Add comments
COMMENT ON TABLE connection_invitations IS 'Stores pending connection invitations sent via SMS';
COMMENT ON COLUMN connection_invitations.invitation_code IS '6-digit code for recipient to use when accepting invitation';
COMMENT ON COLUMN connection_invitations.recipient_phone_number IS 'Phone number of the person being invited';
COMMENT ON COLUMN connection_invitations.recipient_name IS 'Name of recipient from sender contacts (for display)';
COMMENT ON COLUMN connection_invitations.expires_at IS 'When the invitation expires (default 7 days)';
