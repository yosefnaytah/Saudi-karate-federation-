-- Maps SKF official ID (or email) to the auth email used at sign-in.
-- Run in Supabase SQL Editor after public.users.skf_official_id exists.

CREATE OR REPLACE FUNCTION public.resolve_skf_admin_login_id(p_login_id text)
RETURNS TABLE(email text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT u.email::text
    FROM public.users u
    WHERE lower(trim(u.email)) = lower(trim(p_login_id))
       OR lower(trim(u.username)) = lower(trim(p_login_id))
       OR (u.skf_official_id IS NOT NULL AND trim(u.skf_official_id) = trim(p_login_id))
    LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_skf_admin_login_id(text) TO anon, authenticated;
