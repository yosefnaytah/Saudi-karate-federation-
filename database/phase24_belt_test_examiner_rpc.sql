-- =============================================================================
-- phase24_belt_test_examiner_rpc.sql
-- SECURITY DEFINER RPCs so belt test examiners (referees_plus / admin)
-- can always fetch candidates + names without RLS blocking the users join.
-- Run once in the Supabase SQL Editor. Safe to re-run.
-- =============================================================================

-- ── 1. Fetch all candidates for an event (with player name + email + photo) ──
-- Must drop first because return type changed (added photo_url column)
DROP FUNCTION IF EXISTS public.skf_fetch_belt_test_candidates(UUID);

CREATE OR REPLACE FUNCTION public.skf_fetch_belt_test_candidates(p_event_id UUID)
RETURNS TABLE (
    id              UUID,
    user_id         UUID,
    current_rank    TEXT,
    requested_rank  TEXT,
    status          TEXT,
    notes           TEXT,
    result_notes    TEXT,
    created_at      TIMESTAMPTZ,
    full_name       TEXT,
    email           TEXT,
    photo_url       TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    caller_role TEXT;
BEGIN
    caller_role := auth_user_role();
    IF caller_role IS NULL OR caller_role NOT IN ('skf_admin', 'admin', 'referees_plus') THEN
        RAISE EXCEPTION 'forbidden: examiner role required' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        c.id,
        c.user_id,
        c.current_rank,
        c.requested_rank,
        c.status,
        c.notes,
        c.result_notes,
        c.created_at,
        u.full_name,
        u.email,
        COALESCE(u.profile_photo_url, p.avatar_url) AS photo_url
    FROM public.belt_test_candidates c
    LEFT JOIN public.users    u ON u.id = c.user_id
    LEFT JOIN public.profiles p ON p.user_id = c.user_id
    WHERE c.event_id = p_event_id
    ORDER BY c.created_at ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.skf_fetch_belt_test_candidates(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.skf_fetch_belt_test_candidates(UUID) TO authenticated;

-- ── 2. Count candidates per event (for the events list) ─────────────────────

CREATE OR REPLACE FUNCTION public.skf_count_belt_test_candidates(p_event_ids UUID[])
RETURNS TABLE (event_id UUID, cnt BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    caller_role TEXT;
BEGIN
    caller_role := auth_user_role();
    IF caller_role IS NULL OR caller_role NOT IN ('skf_admin', 'admin', 'referees_plus') THEN
        RAISE EXCEPTION 'forbidden: examiner role required' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT c.event_id, COUNT(*)::BIGINT
    FROM public.belt_test_candidates c
    WHERE c.event_id = ANY(p_event_ids)
    GROUP BY c.event_id;
END;
$$;

REVOKE ALL ON FUNCTION public.skf_count_belt_test_candidates(UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.skf_count_belt_test_candidates(UUID[]) TO authenticated;

-- ── Verify ────────────────────────────────────────────────────────────────────
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
      'skf_fetch_belt_test_candidates',
      'skf_count_belt_test_candidates'
  );
