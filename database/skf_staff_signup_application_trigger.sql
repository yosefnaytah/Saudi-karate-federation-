-- When a staff member registers via skf-staff-register.html, Supabase Auth creates the user first.
-- This trigger inserts public.skf_applications (pending) even if email confirmation is ON
-- (no browser session yet), so the federation always sees the request in Supabase.
--
-- Prerequisite: skf_applications table exists (database/skf_applications.sql).
-- Prerequisite: public.users.role must allow 'skf_admin' (see handle_new_auth_user_profile / your CHECK).

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
    -- Same as CSV column `notes` (optional); accept `notes` or legacy `staff_notes` from user_metadata
    nt   text := NULLIF(trim(COALESCE(
        NULLIF(NEW.raw_user_meta_data->>'notes', ''),
        NULLIF(NEW.raw_user_meta_data->>'staff_notes', '')
    )), '');
    flag text := COALESCE(NEW.raw_user_meta_data->>'skf_staff_application', '');
BEGIN
    IF flag IS DISTINCT FROM 'true' THEN
        RETURN NEW;
    END IF;
    IF req NOT IN ('skf_admin', 'referees_plus') THEN
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

DROP TRIGGER IF EXISTS on_auth_user_skf_staff_application ON auth.users;
CREATE TRIGGER on_auth_user_skf_staff_application
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_skf_staff_signup_application();
