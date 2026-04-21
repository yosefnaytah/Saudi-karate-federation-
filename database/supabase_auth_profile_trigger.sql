-- Problem 2 (complete): auto-create public.users when auth.users is created.
-- Runs in the database (SECURITY DEFINER), so it works even when email confirmation
-- is ON and the browser has no session yet for the INSERT RLS policy.
--
-- Run once in Supabase SQL Editor (postgres).

CREATE OR REPLACE FUNCTION public.handle_new_auth_user_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r   text := lower(trim(COALESCE(NEW.raw_user_meta_data->>'role', 'player')));
  fn  text := COALESCE(NULLIF(trim(NEW.raw_user_meta_data->>'full_name'), ''), split_part(NEW.email, '@', 1));
  nid text := NULLIF(trim(NEW.raw_user_meta_data->>'national_id'), '');
  ph  text := NULLIF(trim(NEW.raw_user_meta_data->>'phone'), '');
BEGIN
  IF EXISTS (SELECT 1 FROM public.users WHERE id = NEW.id) THEN
    RETURN NEW;
  END IF;

  IF nid IS NULL OR length(nid) <> 10 THEN
    nid := right(replace(NEW.id::text, '-', ''), 10);
  END IF;

  IF ph IS NULL OR ph = '' THEN
    ph := '0500000000';
  END IF;

  INSERT INTO public.users (
    id, full_name, national_id, player_id, phone, club_name, email, username, role, is_active
  ) VALUES (
    NEW.id,
    fn,
    nid,
    nid,
    ph,
    COALESCE(NULLIF(trim(NEW.raw_user_meta_data->>'club_name'), ''), ''),
    NEW.email,
    NEW.email,
    r,
    CASE WHEN r = 'player' THEN true ELSE false END
  );

  RETURN NEW;
EXCEPTION
  WHEN unique_violation THEN
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_profile ON auth.users;
CREATE TRIGGER on_auth_user_created_profile
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_auth_user_profile();
