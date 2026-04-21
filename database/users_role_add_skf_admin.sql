-- If staff sign-up fails with: new row violates check constraint on public.users.role
-- (role must include 'skf_admin' for federation admins), run once in Supabase SQL Editor.

ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_check;

ALTER TABLE public.users ADD CONSTRAINT users_role_check
    CHECK (role IN ('admin', 'skf_admin', 'player', 'coach', 'referee', 'club_admin', 'referees_plus'));
