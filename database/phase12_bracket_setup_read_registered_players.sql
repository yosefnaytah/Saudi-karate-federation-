-- =============================================================================
-- Phase 12 — Bracket Setup: referees can read public.users for registered athletes
-- =============================================================================
-- Run this entire file in Supabase → SQL Editor (one shot).
--
-- Problem: phase6c_* only allows reading users already on tournament_matches.
-- Bracket Setup needs names from tournament_registrations BEFORE matches exist.
--
-- This migration:
--   • Adds SECURITY DEFINER helpers that read role from public.users (bypasses RLS safely).
--   • Normalizes role strings (lower/trim) and accepts common aliases:
--       admin, skf_admin, referees_plus, referee_plus (legacy/typo), referee, referees (alias).
--   • Adds SELECT policies on public.users when a row is linked by
--       tournament_registrations.user_id (= athletes; NOT player_id — that column does not exist here).
--
-- Prerequisite: public.tournament_registrations, public.tournament_referees exist.
-- Safe to re-run (idempotent policies).
-- =============================================================================

-- Staff role as stored for auth.uid(), normalized (never NULL — empty string if missing row)
CREATE OR REPLACE FUNCTION public.skf_bracket_staff_normalized_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT lower(trim(COALESCE(
    (SELECT u.role::text FROM public.users u WHERE u.id = auth.uid()),
    ''
  )));
$$;

REVOKE ALL ON FUNCTION public.skf_bracket_staff_normalized_role() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.skf_bracket_staff_normalized_role() TO authenticated;
COMMENT ON FUNCTION public.skf_bracket_staff_normalized_role() IS
'Lowercased public.users.role for auth.uid(); used by bracket-setup RLS (SECURITY DEFINER avoids RLS recursion).';

-- Referee+, SKF admin, federation admin (any spelling variants above)
CREATE OR REPLACE FUNCTION public.skf_bracket_staff_is_plus_or_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.skf_bracket_staff_normalized_role() IN (
    'admin',
    'skf_admin',
    'referees_plus',
    'referee_plus'
  );
$$;

REVOKE ALL ON FUNCTION public.skf_bracket_staff_is_plus_or_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.skf_bracket_staff_is_plus_or_admin() TO authenticated;

-- Match official: assigned via tournament_referees
CREATE OR REPLACE FUNCTION public.skf_bracket_staff_is_assigned_referee()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.skf_bracket_staff_normalized_role() IN ('referee', 'referees');
$$;

REVOKE ALL ON FUNCTION public.skf_bracket_staff_is_assigned_referee() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.skf_bracket_staff_is_assigned_referee() TO authenticated;

-- Replace phase 11 policy names (same intent, improved role matching)
DROP POLICY IF EXISTS "Referee staff reads users with any registration" ON public.users;
DROP POLICY IF EXISTS "Referee reads users registered in assigned tournaments" ON public.users;

DROP POLICY IF EXISTS "Bracket staff reads registered players (plus or admin)" ON public.users;
CREATE POLICY "Bracket staff reads registered players (plus or admin)"
    ON public.users
    FOR SELECT
    TO authenticated
    USING (
        public.skf_bracket_staff_is_plus_or_admin()
        AND EXISTS (
            SELECT 1
            FROM public.tournament_registrations tr
            WHERE tr.user_id = users.id
        )
    );

DROP POLICY IF EXISTS "Bracket staff reads registered players (assigned referee)" ON public.users;
CREATE POLICY "Bracket staff reads registered players (assigned referee)"
    ON public.users
    FOR SELECT
    TO authenticated
    USING (
        public.skf_bracket_staff_is_assigned_referee()
        AND EXISTS (
            SELECT 1
            FROM public.tournament_registrations tr
            INNER JOIN public.tournament_referees tref
                ON tref.tournament_id = tr.tournament_id
               AND tref.referee_id = auth.uid()
            WHERE tr.user_id = users.id
        )
    );

COMMENT ON POLICY "Bracket staff reads registered players (plus or admin)" ON public.users IS
'Referee+ / SKF / admin: SELECT athletes who have any tournament_registrations row (bracket setup).';

COMMENT ON POLICY "Bracket staff reads registered players (assigned referee)" ON public.users IS
'Referee: SELECT athletes registered for tournaments this user is assigned to in tournament_referees.';

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC fallback: return user rows for bracket setup even when direct SELECT fails
-- (e.g. policy drift, caching). Caller must be bracket staff; each id must have
-- a registration visible under the same rules as the RLS policies above.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.bracket_setup_fetch_users_for_ids(p_user_ids uuid[])
RETURNS SETOF public.users
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT u.*
  FROM public.users u
  WHERE u.id = ANY(p_user_ids)
    AND (
      public.skf_bracket_staff_is_plus_or_admin()
      OR public.skf_bracket_staff_is_assigned_referee()
    )
    AND EXISTS (
      SELECT 1
      FROM public.tournament_registrations tr
      WHERE tr.user_id = u.id
        AND (
          public.skf_bracket_staff_is_plus_or_admin()
          OR EXISTS (
            SELECT 1
            FROM public.tournament_referees tref
            WHERE tref.tournament_id = tr.tournament_id
              AND tref.referee_id = auth.uid()
          )
        )
    );
$$;

REVOKE ALL ON FUNCTION public.bracket_setup_fetch_users_for_ids(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bracket_setup_fetch_users_for_ids(uuid[]) TO authenticated;

COMMENT ON FUNCTION public.bracket_setup_fetch_users_for_ids(uuid[]) IS
'Bracket setup: athletes public.users rows for IDs with at least one registration the caller may access. SECURITY DEFINER.';
