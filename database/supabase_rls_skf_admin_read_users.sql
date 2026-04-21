-- Problem 9: allow SKF Admin (browser) to list referee profiles for assignment dropdowns.
-- Run once in Supabase SQL Editor.

DROP POLICY IF EXISTS "SKF admins can read all user profiles" ON public.users;
CREATE POLICY "SKF admins can read all user profiles" ON public.users
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users su
      WHERE su.id = auth.uid() AND su.role = 'skf_admin'
    )
  );
