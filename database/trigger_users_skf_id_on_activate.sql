-- When is_active flips from false → true and skf_official_id is empty, assign next 7-digit ID
-- for staff roles only (skf_admin, referees_plus, legacy admin). Table Editor / manual SQL safe.
-- Run once in Supabase SQL Editor (postgres).
--
-- Requires: public.next_skf_official_id (database/rpc_next_skf_official_id.sql).
-- Grant so trigger (SECURITY DEFINER as function owner) can call RPC:
GRANT EXECUTE ON FUNCTION public.next_skf_official_id(text) TO postgres;

CREATE OR REPLACE FUNCTION public.users_assign_skf_id_when_activated()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r text;
    new_id text;
BEGIN
    -- Activation edge only (was inactive or null, now active).
    IF NOT (COALESCE(NEW.is_active, false) AND NOT COALESCE(OLD.is_active, false)) THEN
        RETURN NEW;
    END IF;

    IF NEW.skf_official_id IS NOT NULL AND btrim(NEW.skf_official_id) <> '' THEN
        RETURN NEW;
    END IF;

    r := lower(trim(COALESCE(NEW.role, '')));
    IF r = 'admin' THEN
        r := 'skf_admin';
    END IF;
    IF r NOT IN ('skf_admin', 'referees_plus') THEN
        RETURN NEW;
    END IF;

    new_id := public.next_skf_official_id(r);
    NEW.skf_official_id := new_id;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_assign_skf_id_on_activate ON public.users;
CREATE TRIGGER users_assign_skf_id_on_activate
    BEFORE UPDATE OF is_active ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION public.users_assign_skf_id_when_activated();

COMMENT ON FUNCTION public.users_assign_skf_id_when_activated() IS
    'Fills skf_official_id when is_active becomes true for skf_admin/referees_plus if ID was empty.';
