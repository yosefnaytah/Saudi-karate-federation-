-- Phase 11 — legacy; **use phase12_bracket_setup_read_registered_players.sql** (normalized staff roles).
-- This file remains for reference; phase12 drops/recreates the same policy *names* where applicable.
--
-- WHY THIS EXISTS
-- phase6c_referee_read_match_athletes (and variants) only allow SELECT on public.users when the
-- athlete already appears on tournament_matches (red_user_id / blue_user_id).
-- On Bracket Setup there are usually NO matches yet, so registered players are invisible and
-- the app shows "profiles could not be loaded" while tournament_registrations still returns rows.
--
-- YOU CAN INSTEAD run phase10_referee_read_policies.sql, which grants broader referee reads.
-- This file is a narrower add-on: only users who have at least one tournament registration,
-- with plain referees limited to tournaments they are assigned to.
--
-- Prerequisite: auth_user_role() (SECURITY DEFINER, no self-query on users) — see supabase_schema / RLS helpers.
-- Run in Supabase SQL Editor after phase6c (safe to run even if phase10 was already applied).

-- Referee+ / SKF admin: any user who has ever registered for a tournament
DROP POLICY IF EXISTS "Referee staff reads users with any registration" ON public.users;
CREATE POLICY "Referee staff reads users with any registration"
    ON public.users
    FOR SELECT
    TO authenticated
    USING (
        auth_user_role() IN ('referees_plus', 'skf_admin', 'admin')
        AND EXISTS (
            SELECT 1
            FROM public.tournament_registrations tr
            WHERE tr.user_id = users.id
        )
    );

-- Plain referee: only athletes registered for events this referee is assigned to
DROP POLICY IF EXISTS "Referee reads users registered in assigned tournaments" ON public.users;
CREATE POLICY "Referee reads users registered in assigned tournaments"
    ON public.users
    FOR SELECT
    TO authenticated
    USING (
        auth_user_role() = 'referee'
        AND EXISTS (
            SELECT 1
            FROM public.tournament_registrations tr
            INNER JOIN public.tournament_referees tref
                ON tref.tournament_id = tr.tournament_id
               AND tref.referee_id = auth.uid()
            WHERE tr.user_id = users.id
        )
    );

COMMENT ON POLICY "Referee staff reads users with any registration" ON public.users IS
'Allows Referee+ / SKF admin to load names for athletes in tournament_registrations (bracket setup before matches exist).';

COMMENT ON POLICY "Referee reads users registered in assigned tournaments" ON public.users IS
'Allows assigned match referees to load athlete names for registrations in their tournaments.';
