-- Phase 3 — Club admins can read federation user rows for members of their own club.
-- Required for club-dashboard “Players in your club” and registration picker.
-- Run after: public.users has club_id (sprint_b), club_admin role in use.

DROP POLICY IF EXISTS "club_admin_reads_users_in_own_club" ON public.users;

CREATE POLICY "club_admin_reads_users_in_own_club"
    ON public.users FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.users AS me
            WHERE me.id = auth.uid()
              AND me.role = 'club_admin'
              AND me.club_id IS NOT NULL
              AND me.club_id = public.users.club_id
        )
    );

COMMENT ON POLICY "club_admin_reads_users_in_own_club" ON public.users IS
'Phase 3: club admin can list players/staff sharing the same club_id for operations UI.';
