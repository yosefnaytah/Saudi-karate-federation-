-- =============================================================================
-- Phase 20 — Fix: profiles read access + phase18 RPC bad column reference
-- =============================================================================
-- Problems fixed:
--
-- 1. public.profiles RLS blocks referees from reading avatar_url for players
--    who were placed in bracket matches directly (no tournament_registrations row).
--    The phase13 policy requires EXISTS(tournament_registrations) — too narrow.
--    Fix: allow all authenticated users to read any profile row (avatar_url is
--    just a public photo URL; it is not sensitive data).
--
-- 2. referee_fetch_match_athletes (phase18) references u.profile_image_url which
--    does not exist on public.users in this database, causing the RPC to fail
--    on every call. Fix: remove the bad column reference.
--
-- Safe to re-run.
-- =============================================================================

-- ── Fix 1: open profiles for all authenticated readers ────────────────────────

DROP POLICY IF EXISTS "All authenticated can read profiles" ON public.profiles;
CREATE POLICY "All authenticated can read profiles"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (true);

-- ── Fix 2: recreate referee_fetch_match_athletes without bad column ───────────

CREATE OR REPLACE FUNCTION public.referee_fetch_match_athletes(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    m    RECORD;
    ok   BOOLEAN;
    red  jsonb;
    blue jsonb;
BEGIN
    IF p_match_id IS NULL THEN RETURN NULL; END IF;

    SELECT tm.id, tm.tournament_id, tm.red_user_id, tm.blue_user_id
    INTO m
    FROM public.tournament_matches tm
    WHERE tm.id = p_match_id;

    IF NOT FOUND THEN RETURN NULL; END IF;

    ok := public.skf_bracket_staff_is_plus_or_admin()
       OR (
            public.skf_bracket_staff_is_assigned_referee()
            AND EXISTS (
                SELECT 1 FROM public.tournament_referees tr
                WHERE tr.tournament_id = m.tournament_id
                  AND tr.referee_id = auth.uid()
            )
          );

    IF NOT ok THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    -- Red athlete — avatar comes from profiles; no reference to non-existent columns
    SELECT jsonb_build_object(
        'id',                u.id,
        'full_name',         u.full_name,
        'email',             u.email,
        'club_name',         u.club_name,
        'profile_image_url', COALESCE(NULLIF(trim(p.avatar_url), ''), '')
    )
    INTO red
    FROM public.users u
    LEFT JOIN public.profiles p ON p.user_id = u.id
    WHERE m.red_user_id IS NOT NULL
      AND u.id = m.red_user_id;

    -- Blue athlete
    SELECT jsonb_build_object(
        'id',                u.id,
        'full_name',         u.full_name,
        'email',             u.email,
        'club_name',         u.club_name,
        'profile_image_url', COALESCE(NULLIF(trim(p.avatar_url), ''), '')
    )
    INTO blue
    FROM public.users u
    LEFT JOIN public.profiles p ON p.user_id = u.id
    WHERE m.blue_user_id IS NOT NULL
      AND u.id = m.blue_user_id;

    RETURN jsonb_build_object('red', red, 'blue', blue);
END;
$$;

REVOKE ALL ON FUNCTION public.referee_fetch_match_athletes(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.referee_fetch_match_athletes(uuid) TO authenticated;
