-- Option C: staff register (password on skf-staff-register.html) → pending in skf_applications → approve assigns SKF ID + activates (same password).
-- Also run database/skf_staff_signup_application_trigger.sql so pending rows are created from Auth signup metadata.
-- Run once in Supabase SQL Editor (postgres).

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS skf_official_id TEXT UNIQUE;

COMMENT ON COLUMN public.users.skf_official_id IS 'Official SKF ID: seven digits only (e.g. 0000001), used for admin login resolution.';

CREATE TABLE IF NOT EXISTS public.skf_applications (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    email TEXT NOT NULL,
    full_name TEXT NOT NULL,
    phone TEXT,
    national_id TEXT,
    notes TEXT,
    requested_role TEXT NOT NULL DEFAULT 'skf_admin'
        CHECK (requested_role IN ('skf_admin', 'referees_plus')),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    assigned_skf_id TEXT UNIQUE,
    auth_user_id UUID REFERENCES auth.users (id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES public.users (id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_skf_applications_status ON public.skf_applications (status);
CREATE INDEX IF NOT EXISTS idx_skf_applications_email ON public.skf_applications (lower(email));

ALTER TABLE public.skf_applications ENABLE ROW LEVEL SECURITY;

-- Public can submit an application (direct Supabase from browser if you use anon key + this policy).
DROP POLICY IF EXISTS "Anyone can submit SKF application" ON public.skf_applications;
CREATE POLICY "Anyone can submit SKF application" ON public.skf_applications
    FOR INSERT TO anon, authenticated
    WITH CHECK (status = 'pending');

-- Only service role / backend bypasses RLS; for skf_admin reading from browser, add:
DROP POLICY IF EXISTS "SKF admins read applications" ON public.skf_applications;
CREATE POLICY "SKF admins read applications" ON public.skf_applications
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'skf_admin')
    );

DROP POLICY IF EXISTS "SKF admins update applications" ON public.skf_applications;
CREATE POLICY "SKF admins update applications" ON public.skf_applications
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'skf_admin')
    );
