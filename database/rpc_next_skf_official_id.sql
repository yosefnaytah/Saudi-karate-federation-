-- Official staff IDs: seven digits only (0000001 … 9999999), no letters.
-- Run once in Supabase SQL Editor (or re-run to replace function). Backend: POST /rest/v1/rpc/next_skf_official_id  body: {"p_role":"skf_admin"} or "referees_plus"
-- p_role is still required so only staff approvals call this; the returned ID does not encode role.

CREATE TABLE IF NOT EXISTS public.skf_official_seven_counter (
    lock char(1) PRIMARY KEY DEFAULT 'x' CHECK (lock = 'x'),
    n bigint NOT NULL DEFAULT 0 CHECK (n >= 0)
);

INSERT INTO public.skf_official_seven_counter (lock, n) VALUES ('x', 0)
    ON CONFLICT (lock) DO NOTHING;

-- Optional: continue sequence after any existing 7-digit IDs already in users or applications.
UPDATE public.skf_official_seven_counter c
SET n = GREATEST(
    c.n,
    COALESCE((SELECT MAX(skf_official_id::bigint) FROM public.users WHERE skf_official_id ~ '^\d{7}$'), 0),
    COALESCE((SELECT MAX(assigned_skf_id::bigint) FROM public.skf_applications WHERE assigned_skf_id ~ '^\d{7}$'), 0)
)
WHERE c.lock = 'x';

CREATE OR REPLACE FUNCTION public.next_skf_official_id(p_role text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    newn bigint;
BEGIN
    IF lower(trim(p_role)) NOT IN ('skf_admin', 'referees_plus') THEN
        RAISE EXCEPTION 'next_skf_official_id: invalid role %', p_role;
    END IF;

    -- Use alias `c` in SET (not bare table name) — PG errors otherwise inside ON CONFLICT DO UPDATE.
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

REVOKE ALL ON FUNCTION public.next_skf_official_id(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.next_skf_official_id(text) TO service_role;
-- DB triggers on public.users (e.g. activation) run as postgres; keep RPC callable.
GRANT EXECUTE ON FUNCTION public.next_skf_official_id(text) TO postgres;

COMMENT ON FUNCTION public.next_skf_official_id(text) IS 'Returns next 7-digit official ID (digits only). p_role must be skf_admin or referees_plus.';
