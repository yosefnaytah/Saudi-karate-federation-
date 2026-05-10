-- Optional: allow club admins to read profiles (e.g. avatar_url) for users in the same club.
-- Run after: phase3_club_admin_read_club_members.sql, sprint_a_foundations (profiles table).
-- Without this, Players management still shows users.profile_photo_url; Storage avatars may be missing.

DROP POLICY IF EXISTS "club_admin_reads_profiles_in_own_club" ON public.profiles;

CREATE POLICY "club_admin_reads_profiles_in_own_club"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.users AS me
            INNER JOIN public.users AS member ON member.id = profiles.user_id
            WHERE me.id = auth.uid()
              AND me.role = 'club_admin'
              AND me.club_id IS NOT NULL
              AND member.club_id = me.club_id
        )
    );

COMMENT ON POLICY "club_admin_reads_profiles_in_own_club" ON public.profiles IS
'Club admin can read profile rows (avatar_url) for federation users sharing the same club_id.';
