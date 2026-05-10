-- Fix: phase6c required tournaments.is_active = TRUE inside the EXISTS, which could
-- block referee reads of public.users for match athletes. This version drops that join.
-- Run in Supabase SQL Editor (after phase6c, safe to re-run).

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
'Referee reads athlete rows for red/blue in assigned tournaments; Referee+ for any match.';
