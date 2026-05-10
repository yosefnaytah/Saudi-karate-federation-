-- =============================================================================
-- phase16_rr_save_rpc.sql — Round Robin + RLS recursion fix (RUN THIS IN SUPABASE)
-- =============================================================================
-- Problem: DELETE on tournament_matches failed with
--   "infinite recursion detected in policy for relation 'tournament_matches'".
--   Cause: tm_* policies queried public.users, while "Player reads match
--   opponents" on public.users queries tournament_matches — a cycle.
--   Fix: use auth_user_role() (SECURITY DEFINER, reads users WITHOUT RLS) in
--   tournament_matches policies instead of EXISTS (SELECT ... FROM users).
--
-- Also installs Round Robin RPCs that register all approved players.
-- Safe to re-run.
-- =============================================================================

-- ── 0. Role helper — bypasses users RLS (must not use users in policy subqueries)
CREATE OR REPLACE FUNCTION public.auth_user_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(u.role::text, '')
  FROM public.users u
  WHERE u.id = auth.uid()
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.auth_user_role() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.auth_user_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.auth_user_role() TO anon;

-- ── 1. tournament_matches — replace users subqueries (fixes infinite recursion) ─
DROP POLICY IF EXISTS "tm_select_participants_ref_staff" ON public.tournament_matches;
CREATE POLICY "tm_select_participants_ref_staff"
    ON public.tournament_matches FOR SELECT
    USING (
        auth.uid() = red_user_id
        OR auth.uid() = blue_user_id
        OR EXISTS (
            SELECT 1 FROM public.tournament_referees tr
            WHERE tr.tournament_id = tournament_matches.tournament_id
              AND tr.referee_id = auth.uid()
        )
        OR auth_user_role() IN (
            'referee', 'referees', 'referee_plus', 'referees_plus',
            'skf_admin', 'admin'
        )
        OR EXISTS (
            SELECT 1 FROM public.tournaments t
            WHERE t.id = tournament_matches.tournament_id AND t.is_active = TRUE
        )
    );

DROP POLICY IF EXISTS "tm_update_operators" ON public.tournament_matches;
CREATE POLICY "tm_update_operators"
    ON public.tournament_matches FOR UPDATE
    USING (
        auth_user_role() IN (
            'referee', 'referees', 'referee_plus', 'referees_plus',
            'skf_admin', 'admin'
        )
        OR EXISTS (
            SELECT 1 FROM public.tournament_referees tr
            WHERE tr.tournament_id = tournament_matches.tournament_id
              AND tr.referee_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "tm_insert_operators" ON public.tournament_matches;
CREATE POLICY "tm_insert_operators"
    ON public.tournament_matches FOR INSERT
    WITH CHECK (
        auth_user_role() IN (
            'referee', 'referees', 'referee_plus', 'referees_plus',
            'skf_admin', 'admin'
        )
        OR EXISTS (
            SELECT 1 FROM public.tournament_referees tr
            WHERE tr.tournament_id = tournament_matches.tournament_id
              AND tr.referee_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "tm_delete_skf_only" ON public.tournament_matches;
CREATE POLICY "tm_delete_skf_only"
    ON public.tournament_matches FOR DELETE
    USING (
        auth_user_role() IN (
            'referee', 'referees', 'referee_plus', 'referees_plus',
            'skf_admin', 'admin'
        )
    );

-- ── 2. Canonical Round Robin generator ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.referee_plus_generate_league_round_robin(p_category_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    rrole text;
    cat   public.tournament_categories%ROWTYPE;
    tid   uuid;
    tstate text;
    reg_ids uuid[];
    n int;
    i int;
    j int;
    pos int;
    total_ins int;
BEGIN
    SELECT role INTO rrole FROM public.users WHERE id = auth.uid();
    IF rrole IS NULL OR rrole NOT IN (
        'referee', 'referees', 'referee_plus', 'referees_plus',
        'skf_admin', 'admin'
    ) THEN
        RAISE EXCEPTION 'forbidden';
    END IF;

    SELECT * INTO cat FROM public.tournament_categories WHERE id = p_category_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'category not found'; END IF;

    tid := cat.tournament_id;

    SELECT t.competition_state INTO tstate FROM public.tournaments t WHERE t.id = tid;
    IF NOT FOUND THEN RAISE EXCEPTION 'tournament not found'; END IF;
    IF tstate = 'live' THEN
        RAISE EXCEPTION 'cannot regenerate schedule while tournament is live';
    END IF;

    SELECT COALESCE(array_agg(s.user_id ORDER BY s.registration_date, s.user_id), ARRAY[]::uuid[])
    INTO reg_ids
    FROM (
        SELECT DISTINCT ON (tr.user_id) tr.user_id, tr.registration_date
        FROM public.tournament_registrations tr
        WHERE (tr.category_id = p_category_id OR tr.tournament_category_id = p_category_id)
          AND tr.status = 'approved'
        ORDER BY tr.user_id, tr.registration_date
    ) s;

    n := COALESCE(array_length(reg_ids, 1), 0);
    IF n < 2 THEN
        RAISE EXCEPTION 'need at least 2 approved registrations in this category (got %)', n;
    END IF;

    DELETE FROM public.tournament_matches
    WHERE category_id = p_category_id AND tournament_id = tid;

    pos := 0;
    FOR i IN 1..(n - 1) LOOP
        FOR j IN (i + 1)..n LOOP
            pos := pos + 1;
            INSERT INTO public.tournament_matches (
                tournament_id, category_id, round_number, bracket_position,
                red_user_id, blue_user_id, status
            ) VALUES (
                tid, p_category_id, 1, pos,
                reg_ids[i], reg_ids[j], 'scheduled'
            );
        END LOOP;
    END LOOP;

    SELECT COUNT(*)::int INTO total_ins FROM public.tournament_matches
    WHERE tournament_id = tid AND category_id = p_category_id;

    RETURN json_build_object(
        'ok', true,
        'category_id', p_category_id,
        'players', n,
        'matches_created', total_ins,
        'format', 'single_round_robin'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.referee_plus_generate_league_round_robin(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.referee_plus_generate_league_round_robin(uuid) TO authenticated;

-- ── 3. Fallback RPC ──────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.bracket_rr_save_matches(uuid, uuid, jsonb);

CREATE OR REPLACE FUNCTION public.bracket_rr_save_matches(
    p_tournament_id  uuid,
    p_category_id    uuid,
    p_pairs          jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_role text;
    v_pair        jsonb;
    v_inserted    int := 0;
BEGIN
    SELECT role INTO v_caller_role FROM public.users WHERE id = auth.uid();
    IF v_caller_role NOT IN (
        'skf_admin', 'admin',
        'referee', 'referees',
        'referee_plus', 'referees_plus'
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'Unauthorized');
    END IF;

    DELETE FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id AND category_id = p_category_id;

    FOR v_pair IN SELECT * FROM jsonb_array_elements(p_pairs)
    LOOP
        INSERT INTO public.tournament_matches (
            tournament_id, category_id,
            red_user_id, blue_user_id,
            round_number, bracket_position, status
        ) VALUES (
            p_tournament_id, p_category_id,
            (v_pair->>'red_player_id')::uuid,
            (v_pair->>'blue_player_id')::uuid,
            1,
            (v_pair->>'match_number')::int,
            'scheduled'
        );
        v_inserted := v_inserted + 1;
    END LOOP;

    RETURN jsonb_build_object('ok', true, 'inserted', v_inserted);
END;
$$;

REVOKE ALL ON FUNCTION public.bracket_rr_save_matches(uuid, uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bracket_rr_save_matches(uuid, uuid, jsonb) TO authenticated;
