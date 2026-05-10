-- Phase 6c — Referee / Referee+ can read minimal user rows for athletes in matches they may operate
-- Prerequisites: phase4_tournament_matches.sql, tournament_referees, auth_user_role()
-- Run after phase6_referee_plus.sql (order does not matter vs phase6b).

-- Referee: assigned to the tournament via tournament_referees.
-- Referee+: matches in any tournament (policy does not filter on tournaments.is_active).

DROP POLICY IF EXISTS "referee_staff_reads_athletes_in_assigned_matches" ON public.users;
CREATE POLICY "referee_staff_reads_athletes_in_assigned_matches"
    ON public.users FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.tournament_matches m
            WHERE (m.red_user_id = users.id OR m.blue_user_id = users.id)
              AND (
                  auth_user_role() IN ('referees_plus', 'skf_admin', 'admin')
                  OR (
                      auth_user_role() = 'referee'
                      AND EXISTS (
                          SELECT 1 FROM public.tournament_referees tr
                          WHERE tr.tournament_id = m.tournament_id
                            AND tr.referee_id = auth.uid()
                      )
                  )
              )
        )
    );

COMMENT ON POLICY "referee_staff_reads_athletes_in_assigned_matches" ON public.users IS
'Referee sees names for red/blue in matches for assigned tournaments; Referee+ / SKF admin for any tournament.';
