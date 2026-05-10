-- Phase 2–3 — Club registration requests (SKF approves → club exists) +
--              Club admins registering players who belong to their club.
-- Run after: public.users, public.clubs, public.tournament_registrations, sprint_b (club_id).

-- -----------------------------------------------------------------------------
-- Club registration requests (Club Admin → SKF Admin workflow)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.club_registration_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    applicant_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    proposed_club_name TEXT NOT NULL,
    proposed_location TEXT,
    requested_initial_player_count INTEGER
        CHECK (requested_initial_player_count IS NULL OR requested_initial_player_count >= 0),
    notes TEXT,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'rejected', 'withdrawn')),
    reviewed_at TIMESTAMPTZ,
    reviewed_by_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    resulting_club_id UUID REFERENCES public.clubs(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_club_reg_req_applicant ON public.club_registration_requests(applicant_user_id);
CREATE INDEX IF NOT EXISTS idx_club_reg_req_status ON public.club_registration_requests(status);

COMMENT ON TABLE public.club_registration_requests IS
'Phase 2: Club Admin submits federation club setup request; SKF Admin approves and creates/links club.';

ALTER TABLE public.club_registration_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "club_reg_req_select_own_or_skf" ON public.club_registration_requests;
CREATE POLICY "club_reg_req_select_own_or_skf"
    ON public.club_registration_requests FOR SELECT
    USING (
        applicant_user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role IN ('skf_admin', 'admin')
        )
    );

DROP POLICY IF EXISTS "club_reg_req_insert_own_club_admin" ON public.club_registration_requests;
CREATE POLICY "club_reg_req_insert_own_club_admin"
    ON public.club_registration_requests FOR INSERT
    WITH CHECK (
        applicant_user_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role = 'club_admin'
        )
    );

DROP POLICY IF EXISTS "club_reg_req_update_applicant_withdraw" ON public.club_registration_requests;
CREATE POLICY "club_reg_req_update_applicant_withdraw"
    ON public.club_registration_requests FOR UPDATE
    USING (applicant_user_id = auth.uid() AND status = 'pending')
    WITH CHECK (applicant_user_id = auth.uid() AND status = 'withdrawn');

DROP POLICY IF EXISTS "club_reg_req_update_skf" ON public.club_registration_requests;
CREATE POLICY "club_reg_req_update_skf"
    ON public.club_registration_requests FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role IN ('skf_admin', 'admin')
        )
    );

-- -----------------------------------------------------------------------------
-- Tournament registration: who submitted (player self vs club admin)
-- -----------------------------------------------------------------------------
ALTER TABLE public.tournament_registrations
    ADD COLUMN IF NOT EXISTS registered_by_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.tournament_registrations.registered_by_user_id IS
'Phase 3: set to club admin user_id when they register a player; NULL when player self-registers.';

-- Club admin may insert a registration row for a player in the same club.
DROP POLICY IF EXISTS "Club admin registers club players" ON public.tournament_registrations;
CREATE POLICY "Club admin registers club players"
    ON public.tournament_registrations FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.users admin_u
            INNER JOIN public.users player_u ON player_u.id = tournament_registrations.user_id
            WHERE admin_u.id = auth.uid()
              AND admin_u.role = 'club_admin'
              AND admin_u.club_id IS NOT NULL
              AND player_u.club_id = admin_u.club_id
        )
    );

-- Allow club admin to read registrations for players in their club (operational list)
DROP POLICY IF EXISTS "Club admin reads club player registrations" ON public.tournament_registrations;
CREATE POLICY "Club admin reads club player registrations"
    ON public.tournament_registrations FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.users admin_u
            INNER JOIN public.users player_u ON player_u.id = tournament_registrations.user_id
            WHERE admin_u.id = auth.uid()
              AND admin_u.role = 'club_admin'
              AND admin_u.club_id IS NOT NULL
              AND player_u.club_id = admin_u.club_id
        )
    );
