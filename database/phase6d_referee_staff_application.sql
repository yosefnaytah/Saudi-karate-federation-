-- Phase 6d — Allow regular referee in SKF staff applications (signup + approval + SKF ID)
-- Run once in Supabase SQL Editor after skf_applications + skf_staff_signup_application trigger exist.
-- Fixes: applicants choosing "Referee" were not inserted into skf_applications (trigger rejected role).

-- 1) requested_role may be referee (match officials) or referees_plus (draw + ops)
ALTER TABLE public.skf_applications DROP CONSTRAINT IF EXISTS skf_applications_requested_role_check;
ALTER TABLE public.skf_applications ADD CONSTRAINT skf_applications_requested_role_check
    CHECK (requested_role IN ('skf_admin', 'referees_plus', 'referee'));

-- 2) Auth trigger: accept referee in metadata for pending application row
CREATE OR REPLACE FUNCTION public.handle_skf_staff_signup_application()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    req  text := lower(trim(COALESCE(NEW.raw_user_meta_data->>'role', '')));
    fn   text := COALESCE(NULLIF(trim(NEW.raw_user_meta_data->>'full_name'), ''), split_part(NEW.email, '@', 1));
    ph   text := NULLIF(trim(NEW.raw_user_meta_data->>'phone'), '');
    nid  text := NULLIF(trim(NEW.raw_user_meta_data->>'national_id'), '');
    nt   text := NULLIF(trim(COALESCE(
        NULLIF(NEW.raw_user_meta_data->>'notes', ''),
        NULLIF(NEW.raw_user_meta_data->>'staff_notes', '')
    )), '');
    flag text := COALESCE(NEW.raw_user_meta_data->>'skf_staff_application', '');
BEGIN
    IF flag IS DISTINCT FROM 'true' THEN
        RETURN NEW;
    END IF;
    IF req NOT IN ('skf_admin', 'referees_plus', 'referee') THEN
        RETURN NEW;
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.skf_applications sa
        WHERE sa.auth_user_id = NEW.id AND sa.status = 'pending'
    ) THEN
        RETURN NEW;
    END IF;
    INSERT INTO public.skf_applications (
        email, full_name, phone, national_id, notes, requested_role, status, auth_user_id
    ) VALUES (
        NEW.email, fn, ph, nid, nt, req, 'pending', NEW.id
    );
    RETURN NEW;
END;
$$;

-- 3) Seven-digit official ID: allow referee (same counter as other staff)
CREATE OR REPLACE FUNCTION public.next_skf_official_id(p_role text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    newn bigint;
BEGIN
    IF lower(trim(p_role)) NOT IN ('skf_admin', 'referees_plus', 'referee') THEN
        RAISE EXCEPTION 'next_skf_official_id: invalid role %', p_role;
    END IF;

    INSERT INTO public.skf_official_seven_counter AS c (lock, n)
    VALUES ('x', 1)
    ON CONFLICT (lock) DO UPDATE
    SET n = c.n + 1
    RETURNING n INTO newn;

    IF newn > 9999999 THEN
        RAISE EXCEPTION 'next_skf_official_id: counter exceeded 7 digits (9999999)';
    END IF;

    RETURN lpad(newn::text, 7, '0');
END;
$$;

COMMENT ON FUNCTION public.next_skf_official_id(text) IS
'Returns next 7-digit official ID. p_role must be skf_admin, referees_plus, or referee.';

-- 4) Optional auto-ID on activate (if you use this trigger)
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
    IF r NOT IN ('skf_admin', 'referees_plus', 'referee') THEN
        RETURN NEW;
    END IF;

    new_id := public.next_skf_official_id(r);
    NEW.skf_official_id := new_id;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.users_assign_skf_id_when_activated() IS
'Fills skf_official_id when is_active becomes true for skf_admin, referees_plus, or referee if ID was empty.';
