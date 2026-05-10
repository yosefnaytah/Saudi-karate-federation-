-- Phase 4 — Minimal real match rows (single-elimination ready).
-- Draw generation (populate red/blue + advances_to_match_id) is a separate step (Referee+ / admin tool).
-- Run after: tournaments, tournament_categories, users exist.

CREATE TABLE IF NOT EXISTS public.tournament_matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id UUID NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES public.tournament_categories(id) ON DELETE CASCADE,
    round_number INTEGER NOT NULL CHECK (round_number >= 1),
    bracket_position INTEGER NOT NULL CHECK (bracket_position >= 1),
    red_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    blue_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    winner_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    red_score INTEGER,
    blue_score INTEGER,
    status TEXT NOT NULL DEFAULT 'scheduled'
        CHECK (status IN ('scheduled', 'live', 'completed', 'walkover', 'cancelled')),
    scheduled_start TIMESTAMPTZ,
    mat_label TEXT,
    advances_to_match_id UUID REFERENCES public.tournament_matches(id) ON DELETE SET NULL,
    winner_goes_red BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tournament_id, category_id, round_number, bracket_position)
);

CREATE INDEX IF NOT EXISTS idx_tm_tournament ON public.tournament_matches(tournament_id);
CREATE INDEX IF NOT EXISTS idx_tm_category ON public.tournament_matches(category_id);
CREATE INDEX IF NOT EXISTS idx_tm_red ON public.tournament_matches(red_user_id);
CREATE INDEX IF NOT EXISTS idx_tm_blue ON public.tournament_matches(blue_user_id);
CREATE INDEX IF NOT EXISTS idx_tm_scheduled ON public.tournament_matches(scheduled_start);

COMMENT ON TABLE public.tournament_matches IS
'Phase 4: one row per bout; winner advancement uses advances_to_match_id + winner_goes_red.';

DROP TRIGGER IF EXISTS tr_tournament_matches_updated ON public.tournament_matches;
CREATE TRIGGER tr_tournament_matches_updated
    BEFORE UPDATE ON public.tournament_matches
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- When a match is completed and winner is set, push winner into the next slot (if linked).
CREATE OR REPLACE FUNCTION public.tournament_match_advance_winner()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM 'completed' OR NEW.winner_user_id IS NULL THEN
        RETURN NULL;
    END IF;
    IF NEW.advances_to_match_id IS NULL THEN
        RETURN NULL;
    END IF;
    IF OLD.status = 'completed' AND OLD.winner_user_id IS NOT NULL THEN
        RETURN NULL;
    END IF;
    IF NEW.winner_user_id IS NOT DISTINCT FROM OLD.winner_user_id
       AND NEW.status IS NOT DISTINCT FROM OLD.status THEN
        RETURN NULL;
    END IF;

    IF NEW.winner_goes_red IS TRUE THEN
        UPDATE public.tournament_matches
        SET red_user_id = NEW.winner_user_id,
            updated_at = NOW()
        WHERE id = NEW.advances_to_match_id;
    ELSE
        UPDATE public.tournament_matches
        SET blue_user_id = NEW.winner_user_id,
            updated_at = NOW()
        WHERE id = NEW.advances_to_match_id;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS tr_tournament_match_advance ON public.tournament_matches;
CREATE TRIGGER tr_tournament_match_advance
    AFTER UPDATE OF winner_user_id, status ON public.tournament_matches
    FOR EACH ROW
    EXECUTE FUNCTION public.tournament_match_advance_winner();

ALTER TABLE public.tournament_matches ENABLE ROW LEVEL SECURITY;

-- Read: participants, assigned referees, federation staff, or anyone if tournament active (public follow)
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
        OR EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid()
              AND u.role IN ('skf_admin', 'admin', 'referees_plus')
        )
        OR EXISTS (
            SELECT 1 FROM public.tournaments t
            WHERE t.id = tournament_matches.tournament_id AND t.is_active = TRUE
        )
    );

-- Write: SKF admin, Referee+, or assigned referee for that tournament
DROP POLICY IF EXISTS "tm_update_operators" ON public.tournament_matches;
CREATE POLICY "tm_update_operators"
    ON public.tournament_matches FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid()
              AND u.role IN ('skf_admin', 'admin', 'referees_plus')
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
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid()
              AND u.role IN ('skf_admin', 'admin', 'referees_plus')
        )
    );

DROP POLICY IF EXISTS "tm_delete_skf_only" ON public.tournament_matches;
CREATE POLICY "tm_delete_skf_only"
    ON public.tournament_matches FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role IN ('skf_admin', 'admin')
        )
    );
