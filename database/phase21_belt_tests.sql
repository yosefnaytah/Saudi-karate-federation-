-- =============================================================================
-- Phase 21 — Belt Tests (Kyu/Dan Grading Examinations) MVP
-- =============================================================================
-- Dependencies (run first):
--   supabase_schema.sql                      users, base RLS
--   supabase_player_profile_columns.sql      users.rank column
--   sprint_a_foundations.sql                 profiles table
--   phase19_profiles_write_policy.sql
--   phase20_profiles_open_read_and_rpc_fix.sql
--
-- Run order: after phase20 (see MIGRATION_RUN_ORDER.sql)
-- Safe to re-run (idempotent).
--
-- Tables:
--   public.belt_test_events     — SKF admin schedules grading sessions
--   public.belt_test_candidates — Players apply; admin approves, grades, updates rank
--
-- RPC:
--   skf_belt_test_record_result(p_candidate_id, p_result, p_result_notes)
--     Sets status to 'passed' or 'failed'; on pass also writes users.rank
--     from requested_rank snapshot. SECURITY DEFINER, admin-only.
--
-- Manual test checklist — bottom of file.
-- =============================================================================

-- ── 1. Tables ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.belt_test_events (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    title       TEXT        NOT NULL,
    event_date  TIMESTAMPTZ NOT NULL,
    location    TEXT        NOT NULL DEFAULT '',
    notes       TEXT,
    status      TEXT        NOT NULL DEFAULT 'draft'
                                CHECK (status IN ('draft', 'open', 'closed', 'completed')),
    created_by  UUID        REFERENCES public.users(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_bte_status     ON public.belt_test_events(status);
CREATE INDEX IF NOT EXISTS idx_bte_event_date ON public.belt_test_events(event_date);

CREATE TABLE IF NOT EXISTS public.belt_test_candidates (
    id              UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id        UUID    NOT NULL REFERENCES public.belt_test_events(id) ON DELETE CASCADE,
    user_id         UUID    NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    current_rank    TEXT,                  -- snapshot at time of application
    requested_rank  TEXT    NOT NULL,
    status          TEXT    NOT NULL DEFAULT 'pending'
                                CHECK (status IN ('pending', 'approved', 'rejected', 'passed', 'failed')),
    notes           TEXT,                  -- player notes on application
    result_notes    TEXT,                  -- examiner notes after grading
    graded_by       UUID    REFERENCES public.users(id) ON DELETE SET NULL,
    graded_at       TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (event_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_btc_event  ON public.belt_test_candidates(event_id);
CREATE INDEX IF NOT EXISTS idx_btc_user   ON public.belt_test_candidates(user_id);
CREATE INDEX IF NOT EXISTS idx_btc_status ON public.belt_test_candidates(status);

-- ── 2. updated_at triggers ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.tr_bte_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END; $$;

DROP TRIGGER IF EXISTS trg_bte_updated_at ON public.belt_test_events;
CREATE TRIGGER trg_bte_updated_at
    BEFORE UPDATE ON public.belt_test_events
    FOR EACH ROW EXECUTE FUNCTION public.tr_bte_updated_at();

CREATE OR REPLACE FUNCTION public.tr_btc_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END; $$;

DROP TRIGGER IF EXISTS trg_btc_updated_at ON public.belt_test_candidates;
CREATE TRIGGER trg_btc_updated_at
    BEFORE UPDATE ON public.belt_test_candidates
    FOR EACH ROW EXECUTE FUNCTION public.tr_btc_updated_at();

-- ── 3. RLS ────────────────────────────────────────────────────────────────────

ALTER TABLE public.belt_test_events     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.belt_test_candidates ENABLE ROW LEVEL SECURITY;

-- belt_test_events: everyone reads; admin manages
DROP POLICY IF EXISTS "bte_all_read"     ON public.belt_test_events;
CREATE POLICY "bte_all_read"
    ON public.belt_test_events FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS "bte_admin_manage" ON public.belt_test_events;
CREATE POLICY "bte_admin_manage"
    ON public.belt_test_events FOR ALL
    TO authenticated
    USING     (auth_user_role() IN ('skf_admin', 'admin'))
    WITH CHECK (auth_user_role() IN ('skf_admin', 'admin'));

-- belt_test_candidates: players read own; admin + referees_plus read all
DROP POLICY IF EXISTS "btc_read" ON public.belt_test_candidates;
CREATE POLICY "btc_read"
    ON public.belt_test_candidates FOR SELECT
    TO authenticated
    USING (user_id = auth.uid() OR auth_user_role() IN ('skf_admin', 'admin', 'referees_plus'));

-- players apply only when the event is open; no re-apply (UNIQUE enforces one row)
DROP POLICY IF EXISTS "btc_player_apply" ON public.belt_test_candidates;
CREATE POLICY "btc_player_apply"
    ON public.belt_test_candidates FOR INSERT
    TO authenticated
    WITH CHECK (
        user_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.belt_test_events e
            WHERE e.id = event_id AND e.status = 'open'
        )
    );

-- admin + referees_plus manage all candidate rows (approve / reject / result notes)
-- event creation/deletion stays with admin only (bte_admin_manage above)
DROP POLICY IF EXISTS "btc_admin_manage" ON public.belt_test_candidates;
CREATE POLICY "btc_admin_manage"
    ON public.belt_test_candidates FOR ALL
    TO authenticated
    USING     (auth_user_role() IN ('skf_admin', 'admin', 'referees_plus'))
    WITH CHECK (auth_user_role() IN ('skf_admin', 'admin', 'referees_plus'));

-- ── 4. RPC: record result + update canonical rank ─────────────────────────────

CREATE OR REPLACE FUNCTION public.skf_belt_test_record_result(
    p_candidate_id  UUID,
    p_result        TEXT,           -- 'passed' or 'failed'
    p_result_notes  TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    rrole TEXT;
    cand  public.belt_test_candidates%ROWTYPE;
BEGIN
    rrole := auth_user_role();
    IF rrole IS NULL OR rrole NOT IN ('skf_admin', 'admin', 'referees_plus') THEN
        RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
    END IF;

    IF p_result NOT IN ('passed', 'failed') THEN
        RAISE EXCEPTION 'result must be passed or failed' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO cand FROM public.belt_test_candidates WHERE id = p_candidate_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error', 'candidate not found');
    END IF;

    UPDATE public.belt_test_candidates
    SET status       = p_result,
        result_notes = COALESCE(p_result_notes, result_notes),
        graded_by    = auth.uid(),
        graded_at    = NOW()
    WHERE id = p_candidate_id;

    -- On pass: promote the player's canonical rank in users table
    IF p_result = 'passed'
       AND cand.requested_rank IS NOT NULL
       AND trim(cand.requested_rank) <> ''
    THEN
        UPDATE public.users
        SET rank = trim(cand.requested_rank)
        WHERE id = cand.user_id;
    END IF;

    RETURN jsonb_build_object('ok', true, 'status', p_result, 'user_id', cand.user_id);
END;
$$;

REVOKE ALL  ON FUNCTION public.skf_belt_test_record_result(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.skf_belt_test_record_result(UUID, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION public.skf_belt_test_record_result IS
'Admin or Referee+: set candidate status to passed/failed and promote users.rank on pass. SECURITY DEFINER.';

-- =============================================================================
-- Manual test checklist
-- =============================================================================
-- ADMIN PATH
--   1. Sign in as skf_admin → Admin Dashboard → Belt Tests
--   2. Click "+ New Event", fill title / date / location, set status = open → Save
--   3. Belt Tests event list shows the new row
-- PLAYER PATH
--   4. Sign in as player → Player Dashboard → Belt Test
--   5. Open event appears with "Apply" button
--   6. Click Apply, enter requested rank, submit
--   7. Refresh Belt Test section — own application shows status "pending"
-- ADMIN PATH (review)
--   8. Admin Dashboard → Belt Tests → click event row
--   9. Candidate list shows the player; click "Approve" → status = approved
--  10. Click "Pass" (enter optional notes) → candidate status = passed
--  11. Verify player's Profile → Rank updated to requested_rank
-- IDEMPOTENCY
--  12. Re-run phase21 in Supabase SQL Editor → no errors
-- =============================================================================
