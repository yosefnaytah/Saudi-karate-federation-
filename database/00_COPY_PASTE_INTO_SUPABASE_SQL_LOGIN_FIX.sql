-- =============================================================================
-- COPY THIS ENTIRE FILE → Supabase Dashboard → SQL Editor → New query → Run
-- (Files are in your project folder: database/ — not inside the Supabase UI.)
--
-- Fixes: (1) member sign-in works in Auth but app says profile missing / cannot load
--         (2) public.users row missing for some auth.users
-- Run once per Supabase project (safe to re-run; idempotent sections).
-- =============================================================================

-- ── A) Row Level Security: you must be allowed to read your own public.users row
DROP POLICY IF EXISTS "Users can read own data" ON public.users;
CREATE POLICY "Users can read own data"
    ON public.users
    FOR SELECT
    USING (auth.uid() = id);

-- ── B) RPC used by html/auth.js so profile load works even if table SELECT is picky
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
'Returns public.users for auth.uid(); member portal uses this after Supabase Auth.';

-- ── C) Allow users to insert their own profile row on sign-up (if you use client insert)
DROP POLICY IF EXISTS "Users can insert own profile" ON public.users;
CREATE POLICY "Users can insert own profile" ON public.users
  FOR INSERT WITH CHECK (auth.uid() = id);

-- ── D) Backfill: create public.users for any auth user that has no profile row yet
INSERT INTO public.users (
    id, full_name, national_id, player_id, phone, club_name, email, username, role, is_active
)
SELECT
    au.id,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'full_name'), ''), split_part(au.email, '@', 1)),
    right(replace(au.id::text, '-', ''), 10),
    right(replace(au.id::text, '-', ''), 10),
    '0500000000',
    '',
    au.email,
    au.email,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'role'), ''), 'player'),
    CASE WHEN COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'role'), ''), 'player') = 'player' THEN TRUE ELSE FALSE END
FROM auth.users au
WHERE NOT EXISTS (SELECT 1 FROM public.users pu WHERE pu.id = au.id)
ON CONFLICT (id) DO NOTHING;

-- Done. In the browser: hard refresh (Ctrl+Shift+R), sign in again.
-- Your site must load the project html/auth.js (see green “Auth build” line on login page).
