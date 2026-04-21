-- SKF Admin provisioned accounts (NOT self-service registration).
-- Insert rows here + create matching Auth user + public.users (role skf_admin).
-- Login: SKF Admin ID + password (password = Supabase Auth password for that email).

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

CREATE INDEX IF NOT EXISTS idx_skf_admin_accounts_login_id_lower
    ON public.skf_admin_accounts (lower(login_id));

ALTER TABLE public.skf_admin_accounts ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.resolve_skf_admin_login_id(p_login_id TEXT)
RETURNS TABLE (email TEXT)
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT a.email::TEXT
    FROM public.skf_admin_accounts a
    WHERE lower(trim(a.login_id)) = lower(trim(p_login_id))
      AND a.is_active = TRUE
    LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.resolve_skf_admin_login_id(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_skf_admin_login_id(TEXT) TO anon, authenticated;
