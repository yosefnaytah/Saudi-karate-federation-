-- phase24_belt_test_names_rls.sql
-- Allow referees_plus (belt test examiners) to read the name/email of
-- users who have a belt test candidate row — so the examiner can see
-- who applied when they open the candidates list.
-- Safe to re-run (idempotent).

DROP POLICY IF EXISTS "users_ref_plus_belt_read" ON public.users;
CREATE POLICY "users_ref_plus_belt_read"
    ON public.users FOR SELECT
    TO authenticated
    USING (
        auth_user_role() IN ('referees_plus', 'skf_admin', 'admin')
        AND EXISTS (
            SELECT 1 FROM public.belt_test_candidates btc
            WHERE btc.user_id = users.id
        )
    );

-- Verify
SELECT policyname, cmd, qual
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename  = 'users'
  AND policyname = 'users_ref_plus_belt_read';
