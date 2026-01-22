-- Storage Bucket Configuration for PRUUF iOS App
-- This migration sets up storage buckets for user-uploaded content

-- ============================================
-- CREATE STORAGE BUCKETS
-- ============================================

-- Avatars bucket (public) - for user profile pictures
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'avatars',
    'avatars',
    true,
    5242880, -- 5MB
    ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Profile photos bucket (private) - for additional profile media
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'profile-photos',
    'profile-photos',
    false,
    10485760, -- 10MB
    ARRAY['image/jpeg', 'image/png', 'image/heic', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- ============================================
-- STORAGE POLICIES FOR AVATARS BUCKET
-- ============================================

-- Allow public read access to avatars
CREATE POLICY "Public can view avatars"
ON storage.objects FOR SELECT
USING (bucket_id = 'avatars');

-- Allow authenticated users to upload their own avatar
CREATE POLICY "Users can upload own avatar"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'avatars' AND
    auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow users to update their own avatar
CREATE POLICY "Users can update own avatar"
ON storage.objects FOR UPDATE
USING (
    bucket_id = 'avatars' AND
    auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow users to delete their own avatar
CREATE POLICY "Users can delete own avatar"
ON storage.objects FOR DELETE
USING (
    bucket_id = 'avatars' AND
    auth.uid()::text = (storage.foldername(name))[1]
);

-- ============================================
-- STORAGE POLICIES FOR PROFILE-PHOTOS BUCKET
-- ============================================

-- Users can view their own profile photos
CREATE POLICY "Users can view own profile photos"
ON storage.objects FOR SELECT
USING (
    bucket_id = 'profile-photos' AND
    auth.uid()::text = (storage.foldername(name))[1]
);

-- Connected users can view profile photos (optional - for sharing features)
CREATE POLICY "Connected users can view profile photos"
ON storage.objects FOR SELECT
USING (
    bucket_id = 'profile-photos' AND
    EXISTS (
        SELECT 1 FROM public.connections c
        WHERE c.status = 'accepted'
        AND (
            (c.user_id = auth.uid() AND c.connected_user_id::text = (storage.foldername(name))[1]) OR
            (c.connected_user_id = auth.uid() AND c.user_id::text = (storage.foldername(name))[1])
        )
    )
);

-- Users can upload their own profile photos
CREATE POLICY "Users can upload own profile photos"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'profile-photos' AND
    auth.uid()::text = (storage.foldername(name))[1]
);

-- Users can update their own profile photos
CREATE POLICY "Users can update own profile photos"
ON storage.objects FOR UPDATE
USING (
    bucket_id = 'profile-photos' AND
    auth.uid()::text = (storage.foldername(name))[1]
);

-- Users can delete their own profile photos
CREATE POLICY "Users can delete own profile photos"
ON storage.objects FOR DELETE
USING (
    bucket_id = 'profile-photos' AND
    auth.uid()::text = (storage.foldername(name))[1]
);

-- ============================================
-- HELPER FUNCTIONS FOR STORAGE
-- ============================================

-- Function to get user's avatar URL
CREATE OR REPLACE FUNCTION get_avatar_url(user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    avatar_path TEXT;
BEGIN
    SELECT name INTO avatar_path
    FROM storage.objects
    WHERE bucket_id = 'avatars'
    AND name LIKE user_id::text || '/%'
    ORDER BY created_at DESC
    LIMIT 1;

    IF avatar_path IS NOT NULL THEN
        RETURN 'https://oaiteiceynliooxpeuxt.supabase.co/storage/v1/object/public/avatars/' || avatar_path;
    END IF;

    RETURN NULL;
END;
$$;
