-- phase23b_highlights_public_read.sql
-- Makes skf_highlights readable by anyone who is authenticated (no strict uid check).
-- Run this in the Supabase SQL Editor once.

-- Grant table access to both roles
GRANT SELECT ON public.skf_highlights TO anon;
GRANT SELECT ON public.skf_highlights TO authenticated;

-- Drop the old policy that required auth.uid() IS NOT NULL (blocks fresh sessions)
DROP POLICY IF EXISTS "hl_read_all" ON public.skf_highlights;

-- New policy: any active row is readable by authenticated users (auth.uid() is set by Supabase when logged in)
CREATE POLICY "hl_read_all" ON public.skf_highlights
FOR SELECT USING (is_active = TRUE);

-- Verify
SELECT policyname, cmd, qual
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'skf_highlights';
