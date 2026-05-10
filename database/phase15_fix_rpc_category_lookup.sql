-- =============================================================================
-- Phase 15 — Fix RPC category lookup: check both category_id AND tournament_category_id
-- =============================================================================
-- Problem: tournament_registrations rows may store the category reference in
--   EITHER the `category_id` column OR the `tournament_category_id` column
--   depending on when/how the registration was created.
--   Both generate-bracket RPCs only filtered by `category_id`, so registrations
--   stored under `tournament_category_id` were invisible to the draw generator,
--   causing "1 match instead of 6" for a 4-player Round Robin group.
--
-- Fix: update the registration query in both RPCs to use COALESCE / OR:
--   WHERE (tr.category_id = p_category_id
--          OR tr.tournament_category_id = p_category_id)
--     AND tr.status = 'approved'
--
-- Safe to re-run (CREATE OR REPLACE).
-- =============================================================================

-- ── Fix 1: Round Robin generator ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.referee_plus_generate_league_round_robin(p_category_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    rrole text;
    cat public.tournament_categories%ROWTYPE;
    tid uuid;
    tstate text;
    reg_ids uuid[];
    n int;
    i int;
    j int;
    pos int;
    total_ins int;
BEGIN
    rrole := auth_user_role();
    IF rrole IS NULL OR rrole NOT IN ('referees_plus', 'skf_admin', 'admin') THEN
        RAISE EXCEPTION 'forbidden';
    END IF;

    SELECT * INTO cat FROM public.tournament_categories WHERE id = p_category_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'category not found';
    END IF;

    tid := cat.tournament_id;

    SELECT t.competition_state INTO tstate FROM public.tournaments t WHERE t.id = tid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'tournament not found';
    END IF;
    IF tstate = 'live' THEN
        RAISE EXCEPTION 'cannot regenerate schedule while tournament is live';
    END IF;

    -- Accept both league and null bracket_type (allow referee to set format to league before generating)
    -- (removed strict bracket_type check so referee can generate without pre-setting it)

    -- ── Collect approved registrations checking BOTH category columns ──
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

    DELETE FROM public.tournament_matches WHERE category_id = p_category_id AND tournament_id = tid;

    pos := 0;
    FOR i IN 1..(n - 1) LOOP
        FOR j IN (i + 1)..n LOOP
            pos := pos + 1;
            INSERT INTO public.tournament_matches (
                tournament_id,
                category_id,
                round_number,
                bracket_position,
                red_user_id,
                blue_user_id,
                status
            ) VALUES (
                tid,
                p_category_id,
                1,
                pos,
                reg_ids[i],
                reg_ids[j],
                'scheduled'
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

-- ── Fix 2: Knockout bracket generator ────────────────────────────────────────
-- (same dual-column fix for the registration lookup)
CREATE OR REPLACE FUNCTION public.referee_plus_generate_knockout_bracket(p_category_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    rrole  text;
    cat    public.tournament_categories%ROWTYPE;
    tid    uuid;
    tstate text;
    reg_ids uuid[];
    n    int;
    rmax int;
    r    int;
    p    int;
    mid  uuid;
    next_id uuid;
    nmatches int;
    slots uuid[];
    ins  int;
    total_ins int;
BEGIN
    rrole := auth_user_role();
    IF rrole IS NULL OR rrole NOT IN ('referees_plus', 'skf_admin', 'admin') THEN
        RAISE EXCEPTION 'forbidden';
    END IF;

    SELECT * INTO cat FROM public.tournament_categories WHERE id = p_category_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'category not found'; END IF;

    tid := cat.tournament_id;

    SELECT t.competition_state INTO tstate FROM public.tournaments t WHERE t.id = tid;
    IF NOT FOUND THEN RAISE EXCEPTION 'tournament not found'; END IF;
    IF tstate = 'live' THEN
        RAISE EXCEPTION 'cannot regenerate bracket while tournament is live';
    END IF;

    -- ── Collect approved registrations checking BOTH category columns ──
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

    IF (n & (n - 1)) != 0 THEN
        RAISE EXCEPTION 'knockout requires a power-of-2 player count (got %). Use 4, 8, 16, …', n;
    END IF;

    rmax := (ln(n::numeric) / ln(2::numeric))::int;

    DELETE FROM public.tournament_matches WHERE category_id = p_category_id AND tournament_id = tid;

    DROP TABLE IF EXISTS _tm_bracket_ids;
    CREATE TEMP TABLE _tm_bracket_ids (
        rnd int NOT NULL,
        pos int NOT NULL,
        match_id uuid NOT NULL,
        PRIMARY KEY (rnd, pos)
    ) ON COMMIT DROP;

    FOR r IN 1..rmax LOOP
        nmatches := (n / (power(2, r))::int)::int;
        FOR p IN 1..nmatches LOOP
            INSERT INTO public.tournament_matches (
                tournament_id, category_id, round_number, bracket_position, status
            ) VALUES (
                tid, p_category_id, r, p, 'scheduled'
            )
            RETURNING id INTO mid;
            INSERT INTO _tm_bracket_ids (rnd, pos, match_id) VALUES (r, p, mid);
        END LOOP;
    END LOOP;

    FOR r IN 1..(rmax - 1) LOOP
        nmatches := (n / (power(2, r))::int)::int;
        FOR p IN 1..nmatches LOOP
            SELECT match_id INTO mid     FROM _tm_bracket_ids WHERE rnd = r     AND pos = p;
            SELECT match_id INTO next_id FROM _tm_bracket_ids WHERE rnd = r + 1 AND pos = (p + 1) / 2;
            UPDATE public.tournament_matches
            SET advances_to_match_id = next_id,
                winner_goes_red      = (p % 2 = 1),
                updated_at           = NOW()
            WHERE id = mid;
        END LOOP;
    END LOOP;

    slots := array_fill(NULL::uuid, ARRAY[n]);
    FOR ins IN 1..n LOOP
        slots[ins] := reg_ids[ins];
    END LOOP;

    FOR p IN 1..(n / 2) LOOP
        UPDATE public.tournament_matches
        SET red_user_id  = slots[2 * p - 1],
            blue_user_id = slots[2 * p],
            updated_at   = NOW()
        WHERE tournament_id = tid AND category_id = p_category_id
          AND round_number = 1 AND bracket_position = p;
    END LOOP;

    SELECT COUNT(*)::int INTO total_ins
    FROM public.tournament_matches
    WHERE tournament_id = tid AND category_id = p_category_id;

    RETURN json_build_object(
        'ok',             true,
        'category_id',    p_category_id,
        'players',        n,
        'matches_created', total_ins,
        'format',         'single_elimination'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.referee_plus_generate_knockout_bracket(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.referee_plus_generate_knockout_bracket(uuid) TO authenticated;

COMMENT ON FUNCTION public.referee_plus_generate_league_round_robin(uuid)  IS 'Phase 15: checks both category_id and tournament_category_id for registrations.';
COMMENT ON FUNCTION public.referee_plus_generate_knockout_bracket(uuid)    IS 'Phase 15: checks both category_id and tournament_category_id for registrations.';
