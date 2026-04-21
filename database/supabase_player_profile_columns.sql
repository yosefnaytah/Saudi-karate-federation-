-- Player profile fields: club (already club_name), age group, rank, category, bio, face photo URL.
-- Run once in Supabase SQL Editor after public.users exists.

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS age_group TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS rank TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS player_category TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS profile_bio TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS profile_photo_url TEXT;

COMMENT ON COLUMN public.users.age_group IS 'Competition age band (e.g. U12, Cadet, Senior).';
COMMENT ON COLUMN public.users.rank IS 'Belt / dan rank (e.g. 3rd Kyu, 1st Dan).';
COMMENT ON COLUMN public.users.player_category IS 'Primary competition category (kata / weight class label).';
COMMENT ON COLUMN public.users.profile_bio IS 'Short player bio or extra information.';
COMMENT ON COLUMN public.users.profile_photo_url IS 'Public URL or data URL; should be a clear face photo for ID-style profile.';

-- Keep auth trigger in sync: copy metadata into these columns on signup.
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
  cn  text := COALESCE(NULLIF(trim(NEW.raw_user_meta_data->>'club_name'), ''), '');
  ag  text := NULLIF(trim(NEW.raw_user_meta_data->>'age_group'), '');
  rk  text := NULLIF(trim(NEW.raw_user_meta_data->>'rank'), '');
  cat text := NULLIF(trim(NEW.raw_user_meta_data->>'player_category'), '');
  bio text := NULLIF(trim(NEW.raw_user_meta_data->>'profile_bio'), '');
  pic text := NULLIF(trim(NEW.raw_user_meta_data->>'profile_photo_url'), '');
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

  -- Staff signups often omit club_name in metadata; keep NOT NULL happy.
  IF cn = '' AND COALESCE(NEW.raw_user_meta_data->>'skf_staff_application', '') = 'true' THEN
    cn := 'SKF Federation';
  END IF;
  IF cn = '' THEN
    cn := '—';
  END IF;

  INSERT INTO public.users (
    id, full_name, national_id, player_id, phone, club_name, email, username, role, is_active,
    age_group, rank, player_category, profile_bio, profile_photo_url
  ) VALUES (
    NEW.id,
    fn,
    nid,
    nid,
    ph,
    cn,
    NEW.email,
    NEW.email,
    r,
    CASE WHEN r = 'player' THEN true ELSE false END,
    NULLIF(ag, ''),
    NULLIF(rk, ''),
    NULLIF(cat, ''),
    NULLIF(bio, ''),
    NULLIF(pic, '')
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
