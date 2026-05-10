-- Phase 6b — Referee+: round-robin (league) draw from approved registrations
-- Run after phase6_referee_plus.sql and phase4_tournament_matches.sql

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

    IF cat.bracket_type IS DISTINCT FROM 'league' THEN
        RAISE EXCEPTION 'bracket_type must be league for this generator';
    END IF;

    SELECT COALESCE(array_agg(s.user_id ORDER BY s.registration_date, s.user_id), ARRAY[]::uuid[])
    INTO reg_ids
    FROM (
        SELECT tr.user_id, tr.registration_date
        FROM public.tournament_registrations tr
        WHERE tr.category_id = p_category_id
          AND tr.status = 'approved'
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

COMMENT ON FUNCTION public.referee_plus_generate_league_round_robin(uuid) IS
'Referee+ / SKF: single round-robin (each pair once) from approved registrations; advances_to_match_id unused.';
