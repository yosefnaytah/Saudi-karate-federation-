-- Phase 22: Force Winner Advancement RPC
-- Handles brackets where advances_to_match_id is NULL (generated before the link was set)
-- by computing the next round / position from standard single-elimination math.
-- Run after: phase4_tournament_matches.sql
-- Idempotent — safe to re-run.

CREATE OR REPLACE FUNCTION public.skf_force_advance_winner(p_match_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_match      RECORD;
    v_next_round INTEGER;
    v_next_pos   INTEGER;
    v_next_match RECORD;
    v_goes_red   BOOLEAN;
BEGIN
    -- Permission: referees and above only
    IF NOT EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = auth.uid()
          AND u.role IN ('skf_admin', 'admin', 'referees_plus', 'referee')
    ) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'permission_denied');
    END IF;

    SELECT * INTO v_match
    FROM public.tournament_matches
    WHERE id = p_match_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error', 'match_not_found');
    END IF;

    IF v_match.status <> 'completed' OR v_match.winner_user_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'match_not_completed_or_no_winner');
    END IF;

    -- Case 1: link already exists — re-apply the slot fill idempotently.
    IF v_match.advances_to_match_id IS NOT NULL THEN
        IF COALESCE(v_match.winner_goes_red, TRUE) THEN
            UPDATE public.tournament_matches
               SET red_user_id = v_match.winner_user_id, updated_at = NOW()
             WHERE id = v_match.advances_to_match_id;
        ELSE
            UPDATE public.tournament_matches
               SET blue_user_id = v_match.winner_user_id, updated_at = NOW()
             WHERE id = v_match.advances_to_match_id;
        END IF;
        RETURN jsonb_build_object(
            'ok', true, 'method', 'linked',
            'next_match_id', v_match.advances_to_match_id::TEXT);
    END IF;

    -- Case 2: NULL advances_to_match_id — compute from bracket math.
    -- Single-elimination: next round = round_number + 1
    --                     next position = CEIL(bracket_position / 2)
    --                     odd position  → red slot; even position → blue slot
    v_next_round := v_match.round_number + 1;
    v_next_pos   := CEIL(v_match.bracket_position::NUMERIC / 2)::INTEGER;
    v_goes_red   := (v_match.bracket_position % 2 = 1);

    SELECT * INTO v_next_match
    FROM public.tournament_matches
    WHERE tournament_id    = v_match.tournament_id
      AND category_id      = v_match.category_id
      AND round_number     = v_next_round
      AND bracket_position = v_next_pos;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false, 'error', 'next_match_not_found',
            'expected_round', v_next_round,
            'expected_position', v_next_pos);
    END IF;

    -- Persist the link so the trigger works going forward (self-repair).
    UPDATE public.tournament_matches
       SET advances_to_match_id = v_next_match.id,
           winner_goes_red      = v_goes_red,
           updated_at           = NOW()
     WHERE id = p_match_id;

    -- Place winner in the correct slot of the next match.
    IF v_goes_red THEN
        UPDATE public.tournament_matches
           SET red_user_id = v_match.winner_user_id, updated_at = NOW()
         WHERE id = v_next_match.id;
    ELSE
        UPDATE public.tournament_matches
           SET blue_user_id = v_match.winner_user_id, updated_at = NOW()
         WHERE id = v_next_match.id;
    END IF;

    RETURN jsonb_build_object(
        'ok', true, 'method', 'computed',
        'next_match_id', v_next_match.id::TEXT,
        'winner_slot', CASE WHEN v_goes_red THEN 'red' ELSE 'blue' END);
END;
$$;

GRANT EXECUTE ON FUNCTION public.skf_force_advance_winner(UUID) TO authenticated;
