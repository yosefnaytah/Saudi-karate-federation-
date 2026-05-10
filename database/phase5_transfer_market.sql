-- Phase 5 (partial) — Transfer market: safe player-card read for club offers UI
-- This file is intentionally minimal for Part 1:
-- - It does NOT redesign your transfer workflow tables.
-- - It adds ONE RPC that returns clean player cards for active listings,
--   even when direct SELECT on public.users is restricted by RLS.
--
-- Required by: html/transfers.html (club admin listings)
--
-- Safe to run multiple times.

CREATE OR REPLACE FUNCTION public.get_transfer_listing_player_cards(p_player_ids uuid[])
RETURNS TABLE (
    user_id uuid,
    full_name text,
    email text,
    club_name text,
    age_group text,
    rank text,
    avatar_url text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    viewer_role text;
BEGIN
    -- Identify caller role via public.users (SECURITY DEFINER reads through RLS safely).
    SELECT u.role INTO viewer_role
    FROM public.users u
    WHERE u.id = auth.uid();

    IF viewer_role IS NULL OR viewer_role NOT IN ('club_admin', 'skf_admin', 'admin') THEN
        RAISE EXCEPTION 'forbidden';
    END IF;

    RETURN QUERY
    SELECT
        vp.user_id,
        vp.full_name,
        vp.email,
        vp.club_name,
        COALESCE(vp.age_category_label, vp.users_age_group, '') AS age_group,
        COALESCE(vp.belt_rank, '') AS rank,
        COALESCE(vp.avatar_url, '') AS avatar_url
    FROM public.v_player_profile vp
    WHERE vp.user_id = ANY (p_player_ids)
      AND EXISTS (
        SELECT 1
        FROM public.transfer_market_listings l
        WHERE l.player_user_id = vp.user_id
          AND l.status = 'active'
      );
END;
$$;

REVOKE ALL ON FUNCTION public.get_transfer_listing_player_cards(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_transfer_listing_player_cards(uuid[]) TO authenticated;

COMMENT ON FUNCTION public.get_transfer_listing_player_cards(uuid[]) IS
'Phase5 Part1: returns clean player cards (avatar/name/club/age/rank) for active transfer listings; club_admin + SKF only.';

