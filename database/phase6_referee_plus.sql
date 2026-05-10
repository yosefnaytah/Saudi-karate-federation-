-- Phase 6 — Referee+ (referees_plus): tournament setup, bracket format, knockout draw from real registrations
-- Prerequisites: phase4_tournament_matches.sql, auth_user_role()
-- Run in Supabase SQL Editor after prior phases.

-- -----------------------------------------------------------------------------
-- Tournament lifecycle (operational — separate from registration marketing status)
-- -----------------------------------------------------------------------------
ALTER TABLE public.tournaments
    ADD COLUMN IF NOT EXISTS competition_state TEXT NOT NULL DEFAULT 'setup'
        CHECK (competition_state IN ('setup', 'ready', 'live', 'completed'));

COMMENT ON COLUMN public.tournaments.competition_state IS
'Referee+ / SKF: setup = structure not finalized; ready = draw locked for referee ops; live = in progress; completed = closed.';

CREATE INDEX IF NOT EXISTS idx_tournaments_competition_state ON public.tournaments (competition_state);

-- -----------------------------------------------------------------------------
-- Category bracket type (Referee+ selects; maps old competition_format for display)
-- -----------------------------------------------------------------------------
ALTER TABLE public.tournament_categories
    ADD COLUMN IF NOT EXISTS bracket_type TEXT NOT NULL DEFAULT 'knockout'
        CHECK (bracket_type IN ('knockout', 'league', 'pools'));

COMMENT ON COLUMN public.tournament_categories.bracket_type IS
'knockout = single elimination; league = round robin (draw TBD); pools = pool play (draw TBD).';

UPDATE public.tournament_categories tc
SET bracket_type = CASE
        WHEN tc.competition_format = 'round_robin' THEN 'league'
        ELSE 'knockout'
    END
WHERE EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'tournament_categories'
      AND column_name = 'competition_format'
)
AND tc.competition_format IS NOT NULL;

-- -----------------------------------------------------------------------------
-- RLS: Referee+ reads all registrations (for draw verification)
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Referee plus read tournament registrations" ON public.tournament_registrations;
CREATE POLICY "Referee plus read tournament registrations"
    ON public.tournament_registrations FOR SELECT TO authenticated
    USING (auth_user_role() = 'referees_plus');

-- -----------------------------------------------------------------------------
-- RLS: Referee+ updates categories (format / bracket type during setup)
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Referee plus update tournament categories" ON public.tournament_categories;
CREATE POLICY "Referee plus update tournament categories"
    ON public.tournament_categories FOR UPDATE TO authenticated
    USING (auth_user_role() = 'referees_plus')
    WITH CHECK (auth_user_role() = 'referees_plus');

-- -----------------------------------------------------------------------------
-- RLS: Referee+ updates tournament competition_state (not full admin replace)
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Referee plus update tournament competition state" ON public.tournaments;
CREATE POLICY "Referee plus update tournament competition state"
    ON public.tournaments FOR UPDATE TO authenticated
    USING (
        auth_user_role() = 'referees_plus'
        AND is_active IS TRUE
    )
    WITH CHECK (
        auth_user_role() = 'referees_plus'
        AND is_active IS TRUE
    );

-- -----------------------------------------------------------------------------
-- Knockout bracket: power-of-2 count, real approved registrants only
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.referee_plus_generate_knockout_bracket(p_category_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    rrole text;
    cat tournament_categories%ROWTYPE;
    tid uuid;
    tstate text;
    reg_ids uuid[];
    n int; -- approved player count (= bracket size for power-of-two MVP)
    rmax int;
    r int;
    p int;
    nmatches int;
    mid uuid;
    next_id uuid;
    slots uuid[];
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
        RAISE EXCEPTION 'cannot regenerate bracket while tournament is live';
    END IF;

    IF cat.bracket_type IS DISTINCT FROM 'knockout' THEN
        RAISE EXCEPTION 'bracket_type must be knockout for this generator';
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

    -- Power-of-two MVP (clear operator expectation; extend later for byes)
    IF (n & (n - 1)) != 0 THEN
        RAISE EXCEPTION 'knockout MVP requires player count to be a power of 2 (got %). Use 4, 8, 16, …', n;
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
                tournament_id, category_id, round_number, bracket_position,
                status
            ) VALUES (
                tid, p_category_id, r, p, 'scheduled'
            )
            RETURNING id INTO mid;
            INSERT INTO _tm_bracket_ids (rnd, pos, match_id) VALUES (r, p, mid);
        END LOOP;
    END LOOP;

    -- Link advances (winner slot: odd position → red, even → blue)
    FOR r IN 1..(rmax - 1) LOOP
        nmatches := (n / (power(2, r))::int)::int;
        FOR p IN 1..nmatches LOOP
            SELECT match_id INTO mid FROM _tm_bracket_ids WHERE rnd = r AND pos = p;
            SELECT match_id INTO next_id FROM _tm_bracket_ids WHERE rnd = r + 1 AND pos = (p + 1) / 2;
            UPDATE public.tournament_matches
            SET advances_to_match_id = next_id,
                winner_goes_red = (p % 2 = 1),
                updated_at = NOW()
            WHERE id = mid;
        END LOOP;
    END LOOP;

    slots := array_fill(NULL::uuid, ARRAY[n]);
    FOR ins IN 1..n LOOP
        slots[ins] := reg_ids[ins];
    END LOOP;

    FOR p IN 1..(n / 2) LOOP
        UPDATE public.tournament_matches
        SET red_user_id = slots[2 * p - 1],
            blue_user_id = slots[2 * p],
            updated_at = NOW()
        WHERE tournament_id = tid AND category_id = p_category_id AND round_number = 1 AND bracket_position = p;
    END LOOP;

    SELECT COUNT(*)::int INTO total_ins FROM public.tournament_matches
    WHERE tournament_id = tid AND category_id = p_category_id;

    RETURN json_build_object(
        'ok', true,
        'category_id', p_category_id,
        'players', n,
        'matches_created', total_ins,
        'rounds', rmax
    );
END;
$$;

REVOKE ALL ON FUNCTION public.referee_plus_generate_knockout_bracket(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.referee_plus_generate_knockout_bracket(uuid) TO authenticated;

COMMENT ON FUNCTION public.referee_plus_generate_knockout_bracket(uuid) IS
'Referee+ / SKF: rebuild single-elimination bracket from approved registrations; power-of-2 count only (MVP).';
