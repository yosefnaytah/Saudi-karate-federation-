-- =============================================================================
-- Phase 13 — Bracket Setup: referees can read public.profiles (avatar_url)
-- =============================================================================
-- Problem:  public.profiles has RLS with no SELECT policy for referees, so
--           avatar_url (the primary profile photo) is always invisible to
--           bracket-staff users even after phase 12 fixed public.users.
--
-- Fix:
--   • Adds an RLS policy on public.profiles that mirrors the phase-12 logic:
--     bracket staff may read profiles for users who have tournament_registrations.
--   • Adds a SECURITY DEFINER RPC  bracket_setup_fetch_avatars(uuid[])  that
--     returns (user_id, avatar_url) for any list of IDs, usable as a hard
--     fallback if the direct join is still blocked.
--
-- Safe to re-run (idempotent).
-- =============================================================================

-- ── RLS policy on public.profiles ────────────────────────────────────────────

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Allow users to always read their own profile
DROP POLICY IF EXISTS "Users read own profile" ON public.profiles;
CREATE POLICY "Users read own profile"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- Allow bracket staff (referee+, admin) to read any registered player's profile
DROP POLICY IF EXISTS "Bracket staff reads registered player profiles" ON public.profiles;
CREATE POLICY "Bracket staff reads registered player profiles"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (
        (
            public.skf_bracket_staff_is_plus_or_admin()
            OR public.skf_bracket_staff_is_assigned_referee()
        )
        AND EXISTS (
            SELECT 1
            FROM public.tournament_registrations tr
            WHERE tr.user_id = profiles.user_id
        )
    );

COMMENT ON POLICY "Bracket staff reads registered player profiles" ON public.profiles IS
'Referee/Referee+/Admin can read avatar_url for players with at least one tournament registration.';

-- ── RPC fallback: fetch (user_id, avatar_url) bypassing RLS ──────────────────

CREATE OR REPLACE FUNCTION public.bracket_setup_fetch_avatars(p_user_ids uuid[])
RETURNS TABLE(user_id uuid, avatar_url text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT p.user_id, p.avatar_url
    FROM public.profiles p
    WHERE p.user_id = ANY(p_user_ids)
      AND p.avatar_url IS NOT NULL
      AND p.avatar_url <> ''
      AND (
          public.skf_bracket_staff_is_plus_or_admin()
          OR public.skf_bracket_staff_is_assigned_referee()
      );
$$;

REVOKE ALL ON FUNCTION public.bracket_setup_fetch_avatars(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bracket_setup_fetch_avatars(uuid[]) TO authenticated;

COMMENT ON FUNCTION public.bracket_setup_fetch_avatars(uuid[]) IS
'Bracket setup: returns (user_id, avatar_url) from public.profiles for given IDs. SECURITY DEFINER.';
