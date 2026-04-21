-- One-time fix: create public.users rows for auth.users with no profile (RLS failed on register).
-- Run in Supabase SQL Editor as postgres.

DROP POLICY IF EXISTS "Users can insert own profile" ON public.users;
CREATE POLICY "Users can insert own profile" ON public.users
  FOR INSERT WITH CHECK (auth.uid() = id);

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
