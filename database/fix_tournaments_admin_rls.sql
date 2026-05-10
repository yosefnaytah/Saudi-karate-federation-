-- Fix: "new row violates row-level security policy for table tournaments" when SKF Admin creates a tournament.
-- Cause: policy missing, or FOR ALL without explicit WITH CHECK / role mismatch on some setups.
-- Run once in Supabase SQL Editor (postgres). Idempotent.

DROP POLICY IF EXISTS "Administrators can manage tournaments" ON public.tournaments;

CREATE POLICY "Administrators can manage tournaments"
    ON public.tournaments
    FOR ALL
    TO authenticated
    USING (auth_user_role() IN ('skf_admin', 'club_admin', 'admin'))
    WITH CHECK (auth_user_role() IN ('skf_admin', 'club_admin', 'admin'));

COMMENT ON POLICY "Administrators can manage tournaments" ON public.tournaments IS
'SKF Admin, legacy admin, and club admin can SELECT/INSERT/UPDATE/DELETE tournaments (WITH CHECK explicit for INSERT).';
