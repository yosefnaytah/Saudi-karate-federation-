-- =============================================================================
-- Phase 19 — Fix: allow authenticated users to write their own profiles row
-- =============================================================================
-- Problem: public.profiles has RLS enabled (phase13) but ONLY SELECT policies
--          were ever added. No INSERT or UPDATE policy exists for the owning
--          user. This means uploadPlayerAvatar() in player-dashboard.html fails
--          every time it calls sb.from('profiles').upsert(...), so avatar_url
--          is never saved and profile photos never appear anywhere in the system
--          (match control, bracket view, player dashboard).
--
-- Fix: add a single ALL policy scoped to auth.uid() = user_id so users can
--      INSERT their first profile row and UPDATE it thereafter (upsert pattern).
--
-- Safe to re-run.
-- =============================================================================

DROP POLICY IF EXISTS "Users can upsert own profile" ON public.profiles;
CREATE POLICY "Users can upsert own profile"
    ON public.profiles FOR ALL
    TO authenticated
    USING     (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

COMMENT ON POLICY "Users can upsert own profile" ON public.profiles IS
'Allows a user to INSERT their own profile row and UPDATE avatar_url via upsert. Required for player photo upload to work.';
