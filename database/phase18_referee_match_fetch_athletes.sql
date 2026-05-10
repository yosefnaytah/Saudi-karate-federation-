-- =============================================================================
-- Phase 18 — Match Control: fetch red/blue athlete display data (SECURITY DEFINER)
-- =============================================================================
-- Run in Supabase SQL Editor after phase12 (skf_bracket_staff_* helpers).
--
-- Problem: RLS on public.users / public.profiles sometimes returns empty arrays
--          from the JS client even when the referee can see tournament_matches.
--          Match Control then shows "Participant" with no name or photo.
--
-- Fix: one RPC authorized like bracket_setup_fetch_avatars, returning JSON with
--      red/blue athlete { id, full_name, email, club_name, profile_image_url }.
--      profile_image_url is COALESCE(profiles.avatar_url, users.profile_image_url,
--      users.profile_photo_url).
--
-- Safe to re-run.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.referee_fetch_match_athletes(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    m RECORD;
    ok BOOLEAN;
    red jsonb;
    blue jsonb;
BEGIN
    IF p_match_id IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT tm.id, tm.tournament_id, tm.red_user_id, tm.blue_user_id
    INTO m
    FROM public.tournament_matches tm
    WHERE tm.id = p_match_id;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    ok := public.skf_bracket_staff_is_plus_or_admin()
       OR (
            public.skf_bracket_staff_is_assigned_referee()
            AND EXISTS (
                SELECT 1
                FROM public.tournament_referees tr
                WHERE tr.tournament_id = m.tournament_id
                  AND tr.referee_id = auth.uid()
            )
          );

    IF NOT ok THEN
        RAISE EXCEPTION 'not authorized'
            USING ERRCODE = '42501';
    END IF;

    SELECT jsonb_build_object(
        'id', u.id,
        'full_name', u.full_name,
        'email', u.email,
        'club_name', u.club_name,
        'profile_image_url',
        COALESCE(
            NULLIF(trim(p.avatar_url), ''),
            NULLIF(trim(u.profile_image_url), ''),
            NULLIF(trim(u.profile_photo_url), '')
        )
    )
    INTO red
    FROM public.users u
    LEFT JOIN public.profiles p ON p.user_id = u.id
    WHERE m.red_user_id IS NOT NULL
      AND u.id = m.red_user_id;

    SELECT jsonb_build_object(
        'id', u.id,
        'full_name', u.full_name,
        'email', u.email,
        'club_name', u.club_name,
        'profile_image_url',
        COALESCE(
            NULLIF(trim(p.avatar_url), ''),
            NULLIF(trim(u.profile_image_url), ''),
            NULLIF(trim(u.profile_photo_url), '')
        )
    )
    INTO blue
    FROM public.users u
    LEFT JOIN public.profiles p ON p.user_id = u.id
    WHERE m.blue_user_id IS NOT NULL
      AND u.id = m.blue_user_id;

    RETURN jsonb_build_object(
        'red', red,
        'blue', blue
    );
END;
$$;

REVOKE ALL ON FUNCTION public.referee_fetch_match_athletes(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.referee_fetch_match_athletes(uuid) TO authenticated;

COMMENT ON FUNCTION public.referee_fetch_match_athletes(uuid) IS
'Match Control: returns red/blue athlete display fields for a bout; authorized for Referee+ / assigned referee / admin. SECURITY DEFINER.';
