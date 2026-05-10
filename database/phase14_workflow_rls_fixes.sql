-- =============================================================================
-- Phase 14 — Workflow RLS fixes
-- =============================================================================
-- Fixes three gaps found during end-to-end workflow review:
--
--  1. referees_plus could not DELETE tournament_matches — blocked bracket
--     regeneration (saveLocalBracketToDb does DELETE then INSERT).
--
--  2. Players could not read opponent user data — tournament_matches SELECT
--     works for players, but the follow-up SELECT on public.users to get the
--     opponent's name returned nothing (no policy for players reading others).
--
--  3. Players could not read opponent avatar_url from public.profiles — same
--     gap as #2 but for the profiles table.
--
-- Safe to re-run (idempotent).
-- =============================================================================

-- ── Fix 1: DELETE on tournament_matches — add referees_plus ──────────────────
DROP POLICY IF EXISTS "tm_delete_skf_only" ON public.tournament_matches;
CREATE POLICY "tm_delete_skf_only"
    ON public.tournament_matches FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid()
              AND u.role IN ('skf_admin', 'admin', 'referees_plus')
        )
    );

COMMENT ON POLICY "tm_delete_skf_only" ON public.tournament_matches IS
'SKF admin, admin, and referee+ can delete matches (needed for bracket regeneration).';

-- ── Fix 2: Players can read opponent users rows (for upcoming match display) ──
DROP POLICY IF EXISTS "Player reads match opponents" ON public.users;
CREATE POLICY "Player reads match opponents"
    ON public.users FOR SELECT
    TO authenticated
    USING (
        -- The reading user is a participant in a match where THIS user is the other side
        EXISTS (
            SELECT 1
            FROM public.tournament_matches tm
            WHERE (
                (tm.red_user_id  = auth.uid() AND tm.blue_user_id = users.id)
                OR
                (tm.blue_user_id = auth.uid() AND tm.red_user_id  = users.id)
            )
        )
    );

COMMENT ON POLICY "Player reads match opponents" ON public.users IS
'Players can read the users row of their direct match opponent (for upcoming-match display in dashboard).';

-- ── Fix 3: Players can read opponent avatar from public.profiles ─────────────
DROP POLICY IF EXISTS "Player reads match opponent profiles" ON public.profiles;
CREATE POLICY "Player reads match opponent profiles"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.tournament_matches tm
            WHERE (
                (tm.red_user_id  = auth.uid() AND tm.blue_user_id = profiles.user_id)
                OR
                (tm.blue_user_id = auth.uid() AND tm.red_user_id  = profiles.user_id)
            )
        )
    );

COMMENT ON POLICY "Player reads match opponent profiles" ON public.profiles IS
'Players can read the profile (avatar_url) of their direct match opponent.';
