-- Phase 9 — Ranking points (MVP)
-- Derive ranking points from completed tournament matches per category.
--
-- Notes:
-- - Knockout: points awarded when the FINAL is completed (1st/2nd + two 3rds from semi-final losers).
-- - League (round-robin): points awarded to top 3 by wins (tie-break: user_id).
-- - This is an MVP; later phases can add official SKF/WKF point rules + tie-breaks.
--
-- Safe to re-run.

-- -----------------------------------------------------------------------------
-- 1) Points rules
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ranking_points_rules (
    placement INTEGER PRIMARY KEY CHECK (placement IN (1, 2, 3)),
    points INTEGER NOT NULL CHECK (points >= 0),
    label TEXT
);

INSERT INTO public.ranking_points_rules (placement, points, label)
VALUES
  (1, 100, 'Gold'),
  (2, 70,  'Silver'),
  (3, 50,  'Bronze')
ON CONFLICT (placement) DO UPDATE
SET points = EXCLUDED.points,
    label  = EXCLUDED.label;

-- -----------------------------------------------------------------------------
-- 2) Points fact table
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.player_ranking_points (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    tournament_id UUID NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
    tournament_category_id UUID NOT NULL REFERENCES public.tournament_categories(id) ON DELETE CASCADE,
    placement INTEGER NOT NULL CHECK (placement IN (1, 2, 3)),
    points INTEGER NOT NULL CHECK (points >= 0),
    computed_from TEXT NOT NULL DEFAULT 'knockout' CHECK (computed_from IN ('knockout', 'league')),
    computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tournament_category_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_prp_user ON public.player_ranking_points(user_id);
CREATE INDEX IF NOT EXISTS idx_prp_tournament ON public.player_ranking_points(tournament_id);
CREATE INDEX IF NOT EXISTS idx_prp_category ON public.player_ranking_points(tournament_category_id);

-- Ensure composite key exists for integrity convenience
CREATE UNIQUE INDEX IF NOT EXISTS ux_tournament_categories_id_tournament
    ON public.tournament_categories (id, tournament_id);

-- Tournament/category integrity on points table (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.player_ranking_points'::regclass
      AND contype = 'f'
      AND conname = 'fk_prp_category_tournament'
  ) THEN
    ALTER TABLE public.player_ranking_points
      ADD CONSTRAINT fk_prp_category_tournament
      FOREIGN KEY (tournament_category_id, tournament_id)
      REFERENCES public.tournament_categories (id, tournament_id)
      ON DELETE CASCADE;
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 3) RLS (read for all authenticated; write via staff roles / functions)
-- -----------------------------------------------------------------------------
ALTER TABLE public.player_ranking_points ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "prp_read_authenticated" ON public.player_ranking_points;
CREATE POLICY "prp_read_authenticated"
  ON public.player_ranking_points FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "prp_manage_staff" ON public.player_ranking_points;
CREATE POLICY "prp_manage_staff"
  ON public.player_ranking_points FOR ALL TO authenticated
  USING (auth_user_role() IN ('skf_admin', 'admin', 'referees_plus'))
  WITH CHECK (auth_user_role() IN ('skf_admin', 'admin', 'referees_plus'));

-- -----------------------------------------------------------------------------
-- 4) Helpers: points lookup
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.points_for_placement(p_placement int)
RETURNS int
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((SELECT r.points FROM public.ranking_points_rules r WHERE r.placement = p_placement), 0);
$$;

-- -----------------------------------------------------------------------------
-- 5) Recalculate points for one tournament category
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.recalculate_category_ranking_points(p_category_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rrole text;
  cat public.tournament_categories%ROWTYPE;
  tid uuid;
  bt text;
  rmax int;
  final_m public.tournament_matches%ROWTYPE;
  winner uuid;
  runner uuid;
  semi public.tournament_matches%ROWTYPE;
  loser uuid;
  ins_count int := 0;
BEGIN
  rrole := auth_user_role();
  IF rrole IS NULL OR rrole NOT IN ('referees_plus', 'referee', 'skf_admin', 'admin') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO cat FROM public.tournament_categories WHERE id = p_category_id;
  IF NOT FOUND THEN
    RETURN json_build_object('ok', false, 'error', 'category not found');
  END IF;

  tid := cat.tournament_id;
  bt := COALESCE(cat.bracket_type, 'knockout');

  -- Clear existing points for this category (rebuild)
  DELETE FROM public.player_ranking_points
  WHERE tournament_id = tid AND tournament_category_id = p_category_id;

  IF bt = 'knockout' THEN
    SELECT MAX(round_number) INTO rmax
    FROM public.tournament_matches
    WHERE tournament_id = tid AND category_id = p_category_id;

    IF rmax IS NULL THEN
      RETURN json_build_object('ok', true, 'category_id', p_category_id, 'computed', false, 'reason', 'no matches');
    END IF;

    SELECT * INTO final_m
    FROM public.tournament_matches
    WHERE tournament_id = tid AND category_id = p_category_id
      AND round_number = rmax AND bracket_position = 1
    LIMIT 1;

    IF NOT FOUND OR final_m.status IS DISTINCT FROM 'completed' OR final_m.winner_user_id IS NULL THEN
      RETURN json_build_object('ok', true, 'category_id', p_category_id, 'computed', false, 'reason', 'final not completed');
    END IF;

    winner := final_m.winner_user_id;
    runner := CASE
      WHEN winner IS NOT NULL AND final_m.red_user_id IS NOT NULL AND winner = final_m.red_user_id THEN final_m.blue_user_id
      WHEN winner IS NOT NULL AND final_m.blue_user_id IS NOT NULL AND winner = final_m.blue_user_id THEN final_m.red_user_id
      ELSE NULL
    END;

    IF winner IS NOT NULL THEN
      INSERT INTO public.player_ranking_points (user_id, tournament_id, tournament_category_id, placement, points, computed_from)
      VALUES (winner, tid, p_category_id, 1, public.points_for_placement(1), 'knockout');
      ins_count := ins_count + 1;
    END IF;

    IF runner IS NOT NULL THEN
      INSERT INTO public.player_ranking_points (user_id, tournament_id, tournament_category_id, placement, points, computed_from)
      VALUES (runner, tid, p_category_id, 2, public.points_for_placement(2), 'knockout');
      ins_count := ins_count + 1;
    END IF;

    -- Two bronzes from semi-final losers (when semis completed)
    IF rmax >= 2 THEN
      FOR semi IN
        SELECT *
        FROM public.tournament_matches
        WHERE tournament_id = tid AND category_id = p_category_id
          AND round_number = (rmax - 1)
        ORDER BY bracket_position
      LOOP
        IF semi.status = 'completed' AND semi.winner_user_id IS NOT NULL THEN
          loser := CASE
            WHEN semi.winner_user_id = semi.red_user_id THEN semi.blue_user_id
            WHEN semi.winner_user_id = semi.blue_user_id THEN semi.red_user_id
            ELSE NULL
          END;
          IF loser IS NOT NULL THEN
            INSERT INTO public.player_ranking_points (user_id, tournament_id, tournament_category_id, placement, points, computed_from)
            VALUES (loser, tid, p_category_id, 3, public.points_for_placement(3), 'knockout')
            ON CONFLICT (tournament_category_id, user_id) DO NOTHING;
            ins_count := ins_count + 1;
          END IF;
        END IF;
      END LOOP;
    END IF;

    RETURN json_build_object('ok', true, 'category_id', p_category_id, 'computed', true, 'inserted', ins_count, 'mode', 'knockout');
  END IF;

  -- League: top 3 by wins in completed matches
  IF bt = 'league' THEN
    WITH cm AS (
      SELECT *
      FROM public.tournament_matches m
      WHERE m.tournament_id = tid
        AND m.category_id = p_category_id
        AND m.status = 'completed'
        AND m.winner_user_id IS NOT NULL
    ),
    players AS (
      SELECT red_user_id AS user_id FROM cm WHERE red_user_id IS NOT NULL
      UNION
      SELECT blue_user_id AS user_id FROM cm WHERE blue_user_id IS NOT NULL
    ),
    wins AS (
      SELECT p.user_id,
             COALESCE((SELECT COUNT(*) FROM cm WHERE winner_user_id = p.user_id), 0) AS win_count
      FROM players p
    ),
    ranked AS (
      SELECT user_id,
             win_count,
             ROW_NUMBER() OVER (ORDER BY win_count DESC, user_id ASC) AS rn
      FROM wins
    )
    INSERT INTO public.player_ranking_points (user_id, tournament_id, tournament_category_id, placement, points, computed_from)
    SELECT
      r.user_id,
      tid,
      p_category_id,
      r.rn AS placement,
      public.points_for_placement(r.rn) AS points,
      'league'
    FROM ranked r
    WHERE r.rn IN (1,2,3);

    GET DIAGNOSTICS ins_count = ROW_COUNT;

    RETURN json_build_object('ok', true, 'category_id', p_category_id, 'computed', true, 'inserted', ins_count, 'mode', 'league');
  END IF;

  RETURN json_build_object('ok', true, 'category_id', p_category_id, 'computed', false, 'reason', 'unsupported bracket_type', 'bracket_type', bt);
END;
$$;

REVOKE ALL ON FUNCTION public.recalculate_category_ranking_points(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.recalculate_category_ranking_points(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- 6) Trigger: on match completion, try to refresh category points (safe no-op until final is done)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tr_refresh_points_on_match_complete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'completed' AND NEW.winner_user_id IS NOT NULL THEN
    PERFORM public.recalculate_category_ranking_points(NEW.category_id);
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS tr_refresh_points_on_match_complete ON public.tournament_matches;
CREATE TRIGGER tr_refresh_points_on_match_complete
  AFTER UPDATE OF status, winner_user_id ON public.tournament_matches
  FOR EACH ROW
  EXECUTE FUNCTION public.tr_refresh_points_on_match_complete();

-- -----------------------------------------------------------------------------
-- 7) Totals view (used by dashboards)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_player_points_totals AS
SELECT
  user_id,
  SUM(points)::int AS total_points
FROM public.player_ranking_points
GROUP BY user_id;

GRANT SELECT ON public.v_player_points_totals TO authenticated;

-- Phase 9 — Ranking points (MVP)
-- Derive ranking points from completed tournament matches per category.
--
-- Notes:
-- - Knockout: points awarded when the FINAL is completed (1st/2nd + two 3rds from semi-final losers).
-- - League (round-robin): points awarded to top 3 by wins (tie-break: user_id).
-- - This is an MVP; later phases can add official SKF/WKF point rules + tie-breaks.
--
-- Safe to re-run.

-- -----------------------------------------------------------------------------
-- 1) Points rules
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ranking_points_rules (
    placement INTEGER PRIMARY KEY CHECK (placement IN (1, 2, 3)),
    points INTEGER NOT NULL CHECK (points >= 0),
    label TEXT
);

INSERT INTO public.ranking_points_rules (placement, points, label)
VALUES
  (1, 100, 'Gold'),
  (2, 70,  'Silver'),
  (3, 50,  'Bronze')
ON CONFLICT (placement) DO UPDATE
SET points = EXCLUDED.points,
    label  = EXCLUDED.label;

-- -----------------------------------------------------------------------------
-- 2) Points fact table
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.player_ranking_points (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    tournament_id UUID NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
    tournament_category_id UUID NOT NULL REFERENCES public.tournament_categories(id) ON DELETE CASCADE,
    placement INTEGER NOT NULL CHECK (placement IN (1, 2, 3)),
    points INTEGER NOT NULL CHECK (points >= 0),
    computed_from TEXT NOT NULL DEFAULT 'knockout' CHECK (computed_from IN ('knockout', 'league')),
    computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tournament_category_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_prp_user ON public.player_ranking_points(user_id);
CREATE INDEX IF NOT EXISTS idx_prp_tournament ON public.player_ranking_points(tournament_id);
CREATE INDEX IF NOT EXISTS idx_prp_category ON public.player_ranking_points(tournament_category_id);

-- Ensure composite key exists for integrity convenience
CREATE UNIQUE INDEX IF NOT EXISTS ux_tournament_categories_id_tournament
    ON public.tournament_categories (id, tournament_id);

-- Tournament/category integrity on points table (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.player_ranking_points'::regclass
      AND contype = 'f'
      AND conname = 'fk_prp_category_tournament'
  ) THEN
    ALTER TABLE public.player_ranking_points
      ADD CONSTRAINT fk_prp_category_tournament
      FOREIGN KEY (tournament_category_id, tournament_id)
      REFERENCES public.tournament_categories (id, tournament_id)
      ON DELETE CASCADE;
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 3) RLS (read for all authenticated; write via staff roles / functions)
-- -----------------------------------------------------------------------------
ALTER TABLE public.player_ranking_points ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "prp_read_authenticated" ON public.player_ranking_points;
CREATE POLICY "prp_read_authenticated"
  ON public.player_ranking_points FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "prp_manage_staff" ON public.player_ranking_points;
CREATE POLICY "prp_manage_staff"
  ON public.player_ranking_points FOR ALL TO authenticated
  USING (auth_user_role() IN ('skf_admin', 'admin', 'referees_plus'))
  WITH CHECK (auth_user_role() IN ('skf_admin', 'admin', 'referees_plus'));

-- -----------------------------------------------------------------------------
-- 4) Helpers: points lookup
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.points_for_placement(p_placement int)
RETURNS int
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((SELECT r.points FROM public.ranking_points_rules r WHERE r.placement = p_placement), 0);
$$;

-- -----------------------------------------------------------------------------
-- 5) Recalculate points for one tournament category
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.recalculate_category_ranking_points(p_category_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rrole text;
  cat public.tournament_categories%ROWTYPE;
  tid uuid;
  bt text;
  rmax int;
  final_m public.tournament_matches%ROWTYPE;
  winner uuid;
  runner uuid;
  semi public.tournament_matches%ROWTYPE;
  loser uuid;
  ins_count int := 0;
BEGIN
  rrole := auth_user_role();
  IF rrole IS NULL OR rrole NOT IN ('referees_plus', 'referee', 'skf_admin', 'admin') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO cat FROM public.tournament_categories WHERE id = p_category_id;
  IF NOT FOUND THEN
    RETURN json_build_object('ok', false, 'error', 'category not found');
  END IF;

  tid := cat.tournament_id;
  bt := COALESCE(cat.bracket_type, 'knockout');

  -- Clear existing points for this category (rebuild)
  DELETE FROM public.player_ranking_points
  WHERE tournament_id = tid AND tournament_category_id = p_category_id;

  IF bt = 'knockout' THEN
    SELECT MAX(round_number) INTO rmax
    FROM public.tournament_matches
    WHERE tournament_id = tid AND category_id = p_category_id;

    IF rmax IS NULL THEN
      RETURN json_build_object('ok', true, 'category_id', p_category_id, 'computed', false, 'reason', 'no matches');
    END IF;

    SELECT * INTO final_m
    FROM public.tournament_matches
    WHERE tournament_id = tid AND category_id = p_category_id
      AND round_number = rmax AND bracket_position = 1
    LIMIT 1;

    IF NOT FOUND OR final_m.status IS DISTINCT FROM 'completed' OR final_m.winner_user_id IS NULL THEN
      RETURN json_build_object('ok', true, 'category_id', p_category_id, 'computed', false, 'reason', 'final not completed');
    END IF;

    winner := final_m.winner_user_id;
    runner := CASE
      WHEN winner IS NOT NULL AND final_m.red_user_id IS NOT NULL AND winner = final_m.red_user_id THEN final_m.blue_user_id
      WHEN winner IS NOT NULL AND final_m.blue_user_id IS NOT NULL AND winner = final_m.blue_user_id THEN final_m.red_user_id
      ELSE NULL
    END;

    IF winner IS NOT NULL THEN
      INSERT INTO public.player_ranking_points (user_id, tournament_id, tournament_category_id, placement, points, computed_from)
      VALUES (winner, tid, p_category_id, 1, public.points_for_placement(1), 'knockout');
      ins_count := ins_count + 1;
    END IF;

    IF runner IS NOT NULL THEN
      INSERT INTO public.player_ranking_points (user_id, tournament_id, tournament_category_id, placement, points, computed_from)
      VALUES (runner, tid, p_category_id, 2, public.points_for_placement(2), 'knockout');
      ins_count := ins_count + 1;
    END IF;

    -- Two bronzes from semi-final losers (when semis completed)
    IF rmax >= 2 THEN
      FOR semi IN
        SELECT *
        FROM public.tournament_matches
        WHERE tournament_id = tid AND category_id = p_category_id
          AND round_number = (rmax - 1)
        ORDER BY bracket_position
      LOOP
        IF semi.status = 'completed' AND semi.winner_user_id IS NOT NULL THEN
          loser := CASE
            WHEN semi.winner_user_id = semi.red_user_id THEN semi.blue_user_id
            WHEN semi.winner_user_id = semi.blue_user_id THEN semi.red_user_id
            ELSE NULL
          END;
          IF loser IS NOT NULL THEN
            INSERT INTO public.player_ranking_points (user_id, tournament_id, tournament_category_id, placement, points, computed_from)
            VALUES (loser, tid, p_category_id, 3, public.points_for_placement(3), 'knockout')
            ON CONFLICT (tournament_category_id, user_id) DO NOTHING;
            ins_count := ins_count + 1;
          END IF;
        END IF;
      END LOOP;
    END IF;

    RETURN json_build_object('ok', true, 'category_id', p_category_id, 'computed', true, 'inserted', ins_count, 'mode', 'knockout');
  END IF;

  -- League: top 3 by wins in completed matches
  IF bt = 'league' THEN
    WITH cm AS (
      SELECT *
      FROM public.tournament_matches m
      WHERE m.tournament_id = tid
        AND m.category_id = p_category_id
        AND m.status = 'completed'
        AND m.winner_user_id IS NOT NULL
    ),
    players AS (
      SELECT red_user_id AS user_id FROM cm WHERE red_user_id IS NOT NULL
      UNION
      SELECT blue_user_id AS user_id FROM cm WHERE blue_user_id IS NOT NULL
    ),
    wins AS (
      SELECT p.user_id,
             COALESCE((SELECT COUNT(*) FROM cm WHERE winner_user_id = p.user_id), 0) AS win_count
      FROM players p
    ),
    ranked AS (
      SELECT user_id,
             win_count,
             ROW_NUMBER() OVER (ORDER BY win_count DESC, user_id ASC) AS rn
      FROM wins
    )
    INSERT INTO public.player_ranking_points (user_id, tournament_id, tournament_category_id, placement, points, computed_from)
    SELECT
      r.user_id,
      tid,
      p_category_id,
      r.rn AS placement,
      public.points_for_placement(r.rn) AS points,
      'league'
    FROM ranked r
    WHERE r.rn IN (1,2,3);

    GET DIAGNOSTICS ins_count = ROW_COUNT;

    RETURN json_build_object('ok', true, 'category_id', p_category_id, 'computed', true, 'inserted', ins_count, 'mode', 'league');
  END IF;

  RETURN json_build_object('ok', true, 'category_id', p_category_id, 'computed', false, 'reason', 'unsupported bracket_type', 'bracket_type', bt);
END;
$$;

REVOKE ALL ON FUNCTION public.recalculate_category_ranking_points(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.recalculate_category_ranking_points(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- 6) Trigger: on match completion, try to refresh category points (safe no-op until final is done)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tr_refresh_points_on_match_complete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'completed' AND NEW.winner_user_id IS NOT NULL THEN
    PERFORM public.recalculate_category_ranking_points(NEW.category_id);
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS tr_refresh_points_on_match_complete ON public.tournament_matches;
CREATE TRIGGER tr_refresh_points_on_match_complete
  AFTER UPDATE OF status, winner_user_id ON public.tournament_matches
  FOR EACH ROW
  EXECUTE FUNCTION public.tr_refresh_points_on_match_complete();

-- -----------------------------------------------------------------------------
-- 7) Totals view (used by dashboards)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_player_points_totals AS
SELECT
  user_id,
  SUM(points)::int AS total_points
FROM public.player_ranking_points
GROUP BY user_id;

GRANT SELECT ON public.v_player_points_totals TO authenticated;

