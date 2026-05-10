-- =============================================================================
-- Sprint B — Clubs federation status, user.club_id, player_club_contracts
-- Run AFTER database/sprint_a_foundations.sql and base public.users + public.clubs exist.
-- Paste entire file in Supabase SQL Editor and run once.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) clubs.club_status (federation / board workflow)
-- -----------------------------------------------------------------------------
ALTER TABLE public.clubs ADD COLUMN IF NOT EXISTS club_status TEXT;

UPDATE public.clubs
SET club_status = CASE
    WHEN COALESCE(is_active, TRUE) THEN 'approved'
    ELSE 'suspended'
END
WHERE club_status IS NULL;

UPDATE public.clubs SET club_status = 'pending' WHERE club_status IS NULL;

ALTER TABLE public.clubs ALTER COLUMN club_status SET NOT NULL;
ALTER TABLE public.clubs ALTER COLUMN club_status SET DEFAULT 'pending';

ALTER TABLE public.clubs DROP CONSTRAINT IF EXISTS clubs_club_status_check;
ALTER TABLE public.clubs ADD CONSTRAINT clubs_club_status_check
    CHECK (club_status IN ('pending', 'approved', 'suspended', 'rejected'));

-- -----------------------------------------------------------------------------
-- 2) users.club_id (optional FK for members / club admins)
-- -----------------------------------------------------------------------------
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS club_id UUID REFERENCES public.clubs(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_users_club_id ON public.users(club_id);

COMMENT ON COLUMN public.users.club_id IS 'Sprint B: current club link; kept in sync when an active contract is saved.';

-- -----------------------------------------------------------------------------
-- 3) player_club_contracts
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.player_club_contracts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    club_id UUID NOT NULL REFERENCES public.clubs(id) ON DELETE RESTRICT,
    effective_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    effective_to TIMESTAMPTZ,
    contract_status TEXT NOT NULL DEFAULT 'draft'
        CHECK (contract_status IN ('draft', 'active', 'ended', 'superseded')),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pcc_player ON public.player_club_contracts(player_user_id);
CREATE INDEX IF NOT EXISTS idx_pcc_club ON public.player_club_contracts(club_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_pcc_one_active_per_player
    ON public.player_club_contracts(player_user_id)
    WHERE contract_status = 'active';

DROP TRIGGER IF EXISTS tr_pcc_updated ON public.player_club_contracts;
CREATE TRIGGER tr_pcc_updated BEFORE UPDATE ON public.player_club_contracts
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

COMMENT ON TABLE public.player_club_contracts IS 'Sprint B: contractual membership; at most one active row per player.';

-- Before a row becomes active, supersede any other active contract for that player.
CREATE OR REPLACE FUNCTION public.player_club_contracts_before_activate()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.contract_status = 'active' THEN
        UPDATE public.player_club_contracts
        SET contract_status = 'superseded', updated_at = NOW()
        WHERE player_user_id = NEW.player_user_id
          AND contract_status = 'active'
          AND (TG_OP = 'INSERT' OR id IS DISTINCT FROM NEW.id);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_pcc_before_activate ON public.player_club_contracts;
CREATE TRIGGER tr_pcc_before_activate
    BEFORE INSERT OR UPDATE ON public.player_club_contracts
    FOR EACH ROW
    EXECUTE FUNCTION public.player_club_contracts_before_activate();

-- Keep users.club_id / club_name aligned with the active contract (admin-driven).
CREATE OR REPLACE FUNCTION public.sync_user_from_active_contract()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    cname TEXT;
BEGIN
    IF NEW.contract_status = 'active' THEN
        SELECT c.name INTO cname FROM public.clubs c WHERE c.id = NEW.club_id;
        UPDATE public.users u
        SET club_id = NEW.club_id,
            club_name = COALESCE(cname, u.club_name),
            updated_at = NOW()
        WHERE u.id = NEW.player_user_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_pcc_sync_user ON public.player_club_contracts;
CREATE TRIGGER tr_pcc_sync_user
    AFTER INSERT OR UPDATE ON public.player_club_contracts
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_user_from_active_contract();

-- -----------------------------------------------------------------------------
-- 4) Public read: only approved + active clubs
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Anyone can read active clubs" ON public.clubs;
DROP POLICY IF EXISTS "Anyone can read approved active clubs" ON public.clubs;

CREATE POLICY "Anyone can read approved active clubs" ON public.clubs FOR SELECT
    USING (COALESCE(is_active, TRUE) = TRUE AND club_status = 'approved');

-- -----------------------------------------------------------------------------
-- 5) RLS — player_club_contracts
-- -----------------------------------------------------------------------------
ALTER TABLE public.player_club_contracts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pcc_select_own" ON public.player_club_contracts;
CREATE POLICY "pcc_select_own" ON public.player_club_contracts FOR SELECT
    TO authenticated
    USING (auth.uid() = player_user_id);

DROP POLICY IF EXISTS "pcc_admin_all" ON public.player_club_contracts;
CREATE POLICY "pcc_admin_all" ON public.player_club_contracts FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role IN ('skf_admin', 'admin')
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role IN ('skf_admin', 'admin')
        )
    );

DROP POLICY IF EXISTS "pcc_club_admin_read" ON public.player_club_contracts;
CREATE POLICY "pcc_club_admin_read" ON public.player_club_contracts FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid()
              AND u.role = 'club_admin'
              AND u.club_id = player_club_contracts.club_id
        )
    );

-- =============================================================================
-- Done. App: admin-dashboard (clubs + contracts + reference data),
-- player-dashboard (active contract / club display).
-- =============================================================================
