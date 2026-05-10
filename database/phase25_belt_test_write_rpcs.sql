-- =============================================================================
-- phase25_belt_test_write_rpcs.sql
-- SECURITY DEFINER RPCs that let referees_plus / admin write to
-- belt_test_candidates without needing direct RLS UPDATE grants.
-- Run once in the Supabase SQL Editor. Safe to re-run.
-- =============================================================================

-- ── 1. Record exam result (passed / failed + notes) ──────────────────────────
DROP FUNCTION IF EXISTS public.skf_belt_test_record_result(UUID, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.skf_belt_test_record_result(
    p_candidate_id  UUID,
    p_result        TEXT,        -- 'passed' or 'failed'
    p_result_notes  TEXT DEFAULT NULL
)
RETURNS VOID
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

    IF p_result NOT IN ('passed', 'failed') THEN
        RAISE EXCEPTION 'invalid result value: must be passed or failed' USING ERRCODE = '22023';
    END IF;

    UPDATE public.belt_test_candidates
    SET
        status       = p_result,
        result_notes = p_result_notes,
        updated_at   = NOW()
    WHERE id = p_candidate_id;
END;
$$;

REVOKE ALL ON FUNCTION public.skf_belt_test_record_result(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.skf_belt_test_record_result(UUID, TEXT, TEXT) TO authenticated;


-- ── 2. Set candidate status (approved / rejected / pending) ──────────────────
DROP FUNCTION IF EXISTS public.skf_belt_test_set_status(UUID, TEXT);
CREATE OR REPLACE FUNCTION public.skf_belt_test_set_status(
    p_candidate_id  UUID,
    p_new_status    TEXT         -- 'approved', 'rejected', 'pending'
)
RETURNS VOID
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

    IF p_new_status NOT IN ('pending', 'approved', 'rejected', 'passed', 'failed') THEN
        RAISE EXCEPTION 'invalid status value' USING ERRCODE = '22023';
    END IF;

    UPDATE public.belt_test_candidates
    SET
        status     = p_new_status,
        updated_at = NOW()
    WHERE id = p_candidate_id;
END;
$$;

REVOKE ALL ON FUNCTION public.skf_belt_test_set_status(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.skf_belt_test_set_status(UUID, TEXT) TO authenticated;


-- ── Verify ────────────────────────────────────────────────────────────────────
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
      'skf_belt_test_record_result',
      'skf_belt_test_set_status'
  );
