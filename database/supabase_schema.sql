-- Saudi Karate Federation Database Schema
-- Run this script in your Supabase SQL Editor

-- Enable Row Level Security
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;

-- Users table (extends Supabase auth.users)
CREATE TABLE IF NOT EXISTS public.users (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    full_name TEXT NOT NULL,
    national_id TEXT UNIQUE NOT NULL,
    player_id TEXT UNIQUE NOT NULL,
    player_id_card TEXT,
    phone TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    username TEXT UNIQUE NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('skf_admin', 'player', 'coach', 'referee', 'club_admin', 'referees_plus')),
    profile_image_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE
);

-- Specific Role Profiles
CREATE TABLE IF NOT EXISTS public.player_profiles (
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE PRIMARY KEY,
    weight DECIMAL(5,2),
    date_of_birth DATE,
    belt_level TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.coach_profiles (
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE PRIMARY KEY,
    coaching_license_level TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.referee_profiles (
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE PRIMARY KEY,
    referee_license_level TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tournaments table
CREATE TABLE IF NOT EXISTS public.tournaments (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    start_date TIMESTAMPTZ NOT NULL,
    end_date TIMESTAMPTZ NOT NULL,
    location TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'registration_open', 'registration_closed')),
    registration_open_date TIMESTAMPTZ NOT NULL,
    registration_close_date TIMESTAMPTZ NOT NULL,
    max_participants INTEGER,
    entry_fee DECIMAL(10,2),
    created_by UUID REFERENCES public.users(id) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE
);

-- Tournament referees junction table
CREATE TABLE IF NOT EXISTS public.tournament_referees (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tournament_id UUID REFERENCES public.tournaments(id) ON DELETE CASCADE NOT NULL,
    referee_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    assigned_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(tournament_id, referee_id)
);

-- Tournament categories table
CREATE TABLE IF NOT EXISTS public.tournament_categories (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tournament_id UUID REFERENCES public.tournaments(id) ON DELETE CASCADE NOT NULL,
    discipline TEXT NOT NULL CHECK (discipline IN ('kata', 'kumite')),
    gender TEXT NOT NULL CHECK (gender IN ('male', 'female', 'mixed')),
    age_group TEXT NOT NULL,
    weight_class TEXT NOT NULL,
    competition_format TEXT CHECK (competition_format IN ('single_elimination', 'round_robin')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tournament registrations table
CREATE TABLE IF NOT EXISTS public.tournament_registrations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tournament_id UUID REFERENCES public.tournaments(id) ON DELETE CASCADE NOT NULL,
    category_id UUID REFERENCES public.tournament_categories(id) ON DELETE SET NULL,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    weight_category TEXT,
    belt_level TEXT,
    registration_date TIMESTAMPTZ DEFAULT NOW(),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(tournament_id, category_id, user_id)
);

-- Clubs table
CREATE TABLE IF NOT EXISTS public.clubs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    location TEXT NOT NULL,
    contact_person TEXT,
    contact_email TEXT,
    contact_phone TEXT,
    established_date DATE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Players to Clubs Contracts Table
CREATE TABLE IF NOT EXISTS public.contracts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    player_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    club_id UUID REFERENCES public.clubs(id) ON DELETE CASCADE NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired', 'terminated', 'pending')),
    document_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(player_id, club_id, status)
);

-- Club Admin Profile Mapping
CREATE TABLE IF NOT EXISTS public.club_admin_profiles (
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE PRIMARY KEY,
    club_id UUID REFERENCES public.clubs(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- News/Media table
CREATE TABLE IF NOT EXISTS public.news (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    summary TEXT,
    featured_image_url TEXT,
    published_date TIMESTAMPTZ DEFAULT NOW(),
    author_id UUID REFERENCES public.users(id) NOT NULL,
    is_published BOOLEAN DEFAULT FALSE,
    is_featured BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_users_role ON public.users(role);
CREATE INDEX IF NOT EXISTS idx_tournaments_status ON public.tournaments(status);
CREATE INDEX IF NOT EXISTS idx_tournaments_start_date ON public.tournaments(start_date);
CREATE INDEX IF NOT EXISTS idx_tournament_referees_tournament_id ON public.tournament_referees(tournament_id);
CREATE INDEX IF NOT EXISTS idx_tournament_referees_referee_id ON public.tournament_referees(referee_id);
CREATE INDEX IF NOT EXISTS idx_tournament_categories_tournament_id ON public.tournament_categories(tournament_id);
CREATE INDEX IF NOT EXISTS idx_tournament_registrations_tournament_id ON public.tournament_registrations(tournament_id);
CREATE INDEX IF NOT EXISTS idx_tournament_registrations_user_id ON public.tournament_registrations(user_id);

-- Row Level Security Policies

-- Users can read their own data and public tournament info
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read own data" ON public.users FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own data" ON public.users FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON public.users FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "SKF admins can read all user profiles" ON public.users FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.users su WHERE su.id = auth.uid() AND su.role = 'skf_admin')
);

-- Tournament policies
ALTER TABLE public.tournaments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read active tournaments" ON public.tournaments FOR SELECT USING (is_active = TRUE);
CREATE POLICY "Administrators can manage tournaments" ON public.tournaments FOR ALL USING (
    EXISTS (
        SELECT 1 FROM public.users 
        WHERE id = auth.uid() AND role IN ('skf_admin', 'club_admin')
    )
);

-- Tournament referee assignment policies
ALTER TABLE public.tournament_referees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Referees can read own assignments" ON public.tournament_referees FOR SELECT USING (auth.uid() = referee_id);
CREATE POLICY "Anyone can read tournament referee list" ON public.tournament_referees FOR SELECT USING (TRUE);
CREATE POLICY "SKF Admins can manage referee assignments" ON public.tournament_referees FOR ALL USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'skf_admin')
);

-- Tournament category policies
ALTER TABLE public.tournament_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read tournament categories" ON public.tournament_categories FOR SELECT USING (TRUE);
CREATE POLICY "SKF Admins can manage categories" ON public.tournament_categories FOR ALL USING (
    EXISTS (
        SELECT 1 FROM public.users
        WHERE id = auth.uid() AND role = 'skf_admin'
    )
);
-- Allows assigned referees to set the competition_format column only
CREATE POLICY "Assigned referees can update category format" ON public.tournament_categories FOR UPDATE USING (
    EXISTS (
        SELECT 1 FROM public.tournament_referees tr
        WHERE tr.tournament_id = public.tournament_categories.tournament_id
          AND tr.referee_id = auth.uid()
    )
) WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.tournament_referees tr
        WHERE tr.tournament_id = public.tournament_categories.tournament_id
          AND tr.referee_id = auth.uid()
    )
);

-- Tournament registration policies
ALTER TABLE public.tournament_registrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read own registrations" ON public.tournament_registrations FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can register themselves" ON public.tournament_registrations FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Administrators can manage registrations" ON public.tournament_registrations FOR ALL USING (
    EXISTS (
        SELECT 1 FROM public.users 
        WHERE id = auth.uid() AND role IN ('skf_admin', 'club_admin')
    )
);

-- Clubs policies
ALTER TABLE public.clubs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read active clubs" ON public.clubs FOR SELECT USING (is_active = TRUE);
CREATE POLICY "Administrators can manage clubs" ON public.clubs FOR ALL USING (
    EXISTS (
        SELECT 1 FROM public.users 
        WHERE id = auth.uid() AND role IN ('skf_admin', 'club_admin')
    )
);

-- News policies
ALTER TABLE public.news ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read published news" ON public.news FOR SELECT USING (is_published = TRUE);
CREATE POLICY "Administrators can manage news" ON public.news FOR ALL USING (
    EXISTS (
        SELECT 1 FROM public.users 
        WHERE id = auth.uid() AND role IN ('skf_admin', 'club_admin')
    )
);

-- Functions for updated_at triggers
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for updated_at
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_tournaments_updated_at BEFORE UPDATE ON public.tournaments FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_tournament_categories_updated_at BEFORE UPDATE ON public.tournament_categories FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_tournament_registrations_updated_at BEFORE UPDATE ON public.tournament_registrations FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_clubs_updated_at BEFORE UPDATE ON public.clubs FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_news_updated_at BEFORE UPDATE ON public.news FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- MIGRATION: Add competition_format to tournament_categories
-- (Skip if running schema for the first time — column is in CREATE TABLE above)
-- ============================================================
-- ALTER TABLE public.tournament_categories
--     ADD COLUMN IF NOT EXISTS competition_format TEXT
--         CHECK (competition_format IN ('single_elimination', 'round_robin'));

-- ============================================================
-- MIGRATION: Add category_id to tournament_registrations
-- (Skip if running schema for the first time — column is in CREATE TABLE below)
-- ============================================================
-- ALTER TABLE public.tournament_registrations
--     ADD COLUMN IF NOT EXISTS category_id UUID REFERENCES public.tournament_categories(id) ON DELETE SET NULL;

-- ============================================================
-- MIGRATION: Run these if upgrading an existing tournaments table
-- (Skip if running schema for the first time)
-- ============================================================
-- ALTER TABLE public.tournaments
--     DROP COLUMN IF EXISTS registration_deadline,
--     ADD COLUMN IF NOT EXISTS registration_open_date TIMESTAMPTZ,
--     ADD COLUMN IF NOT EXISTS registration_close_date TIMESTAMPTZ;
--
-- UPDATE public.tournaments SET registration_open_date = NOW() WHERE registration_open_date IS NULL;
-- UPDATE public.tournaments SET registration_close_date = start_date WHERE registration_close_date IS NULL;
--
-- ALTER TABLE public.tournaments
--     ALTER COLUMN registration_open_date SET NOT NULL,
--     ALTER COLUMN registration_close_date SET NOT NULL;
--
-- ALTER TABLE public.tournaments
--     DROP CONSTRAINT IF EXISTS tournaments_status_check,
--     ADD CONSTRAINT tournaments_status_check CHECK (status IN ('draft', 'registration_open', 'registration_closed'));
--
-- UPDATE public.tournaments SET status = 'draft' WHERE status NOT IN ('draft', 'registration_open', 'registration_closed');
--
-- ALTER TABLE public.tournaments ALTER COLUMN status SET DEFAULT 'draft';

-- ── SKF Admin provisioned logins (see also database/skf_admin_accounts.sql) ──
CREATE TABLE IF NOT EXISTS public.skf_admin_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    login_id TEXT NOT NULL UNIQUE,
    email TEXT NOT NULL UNIQUE,
    phone TEXT NOT NULL,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_skf_admin_accounts_login_id_lower ON public.skf_admin_accounts (lower(login_id));
ALTER TABLE public.skf_admin_accounts ENABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION public.resolve_skf_admin_login_id(p_login_id TEXT)
RETURNS TABLE (email TEXT) LANGUAGE SQL SECURITY DEFINER SET search_path = public AS $$
    SELECT a.email::TEXT FROM public.skf_admin_accounts a
    WHERE lower(trim(a.login_id)) = lower(trim(p_login_id)) AND a.is_active = TRUE LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.resolve_skf_admin_login_id(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_skf_admin_login_id(TEXT) TO anon, authenticated;

-- Auto-create public.users when auth.users is created (email confirmation safe)
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
  IF EXISTS (SELECT 1 FROM public.users WHERE id = NEW.id) THEN RETURN NEW; END IF;
  IF nid IS NULL OR length(nid) <> 10 THEN nid := right(replace(NEW.id::text, '-', ''), 10); END IF;
  IF ph IS NULL OR ph = '' THEN ph := '0500000000'; END IF;
  INSERT INTO public.users (id, full_name, national_id, player_id, phone, email, username, role, is_active)
  VALUES (NEW.id, fn, nid, nid, ph, NEW.email, NEW.email, r, CASE WHEN r = 'player' THEN true ELSE false END);
  
  -- Create base role profile entry based on role
  IF r = 'player' THEN
      INSERT INTO public.player_profiles (user_id) VALUES (NEW.id);
  ELSIF r = 'coach' THEN
      INSERT INTO public.coach_profiles (user_id) VALUES (NEW.id);
  ELSIF r = 'referee' OR r = 'referees_plus' THEN
      INSERT INTO public.referee_profiles (user_id) VALUES (NEW.id);
  ELSIF r = 'club_admin' THEN
      INSERT INTO public.club_admin_profiles (user_id) VALUES (NEW.id);
  END IF;

  RETURN NEW;
EXCEPTION WHEN unique_violation THEN RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created_profile ON auth.users;
CREATE TRIGGER on_auth_user_created_profile AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user_profile();