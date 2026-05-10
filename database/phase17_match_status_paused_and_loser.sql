-- Phase 17 — Match lifecycle: paused status + loser_user_id
-- Run after phase4_tournament_matches.sql

ALTER TABLE public.tournament_matches DROP CONSTRAINT IF EXISTS tournament_matches_status_check;
ALTER TABLE public.tournament_matches ADD CONSTRAINT tournament_matches_status_check
    CHECK (status IN ('scheduled', 'live', 'paused', 'completed', 'walkover', 'cancelled'));

ALTER TABLE public.tournament_matches ADD COLUMN IF NOT EXISTS loser_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.tournament_matches.loser_user_id IS 'Set when a bout completes with a single winner.';
