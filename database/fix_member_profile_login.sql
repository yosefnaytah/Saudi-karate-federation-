-- Fix: member login loads profile from public.users after Supabase Auth.
-- Prefer the all-in-one script: 00_COPY_PASTE_INTO_SUPABASE_SQL_LOGIN_FIX.sql
-- Run once in Supabase SQL Editor (postgres) if login succeeds but "profile missing" persists.
--
-- 1) Ensures authenticated users can SELECT their own row (RLS).
-- 2) Adds get_my_profile() so the app can load the row even if other policies misbehave.

-- ── RLS: self-read (idempotent) ─────────────────────────────────────────────
DROP POLICY IF EXISTS "Users can read own data" ON public.users;
CREATE POLICY "Users can read own data"
    ON public.users
    FOR SELECT
    USING (auth.uid() = id);

-- ── RPC: always returns the caller's row from public.users ─────────────────
CREATE OR REPLACE FUNCTION public.get_my_profile()
RETURNS SETOF public.users
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
    SELECT *
    FROM public.users
    WHERE id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.get_my_profile() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_profile() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_profile() TO service_role;

COMMENT ON FUNCTION public.get_my_profile() IS
'Returns public.users rows for auth.uid(); used by member portal when direct SELECT is blocked by RLS.';
