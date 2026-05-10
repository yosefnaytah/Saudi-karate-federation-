-- Phase 23: SKF Highlights / News Banner
-- SKF Admin posts images + captions → shown to all authenticated users.
-- Run after: supabase_schema.sql (users table must exist).

-- ── Table ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.skf_highlights (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    title       TEXT        NOT NULL,
    caption     TEXT,
    image_url   TEXT        NOT NULL,
    is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
    sort_order  INTEGER     NOT NULL DEFAULT 0,
    created_by  UUID        REFERENCES public.users(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_highlights_active_sort
    ON public.skf_highlights (is_active, sort_order, created_at DESC);

DROP TRIGGER IF EXISTS tr_highlights_updated ON public.skf_highlights;
CREATE TRIGGER tr_highlights_updated
    BEFORE UPDATE ON public.skf_highlights
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ── RLS ─────────────────────────────────────────────────────────────────────
ALTER TABLE public.skf_highlights ENABLE ROW LEVEL SECURITY;

-- All authenticated users can read active highlights
DROP POLICY IF EXISTS "hl_read_all" ON public.skf_highlights;
CREATE POLICY "hl_read_all"
    ON public.skf_highlights FOR SELECT
    USING (auth.uid() IS NOT NULL AND is_active = TRUE);

-- SKF admin can read all (including inactive, for management)
DROP POLICY IF EXISTS "hl_admin_read_all" ON public.skf_highlights;
CREATE POLICY "hl_admin_read_all"
    ON public.skf_highlights FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role IN ('skf_admin', 'admin')
        )
    );

-- SKF admin can insert
DROP POLICY IF EXISTS "hl_admin_insert" ON public.skf_highlights;
CREATE POLICY "hl_admin_insert"
    ON public.skf_highlights FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role IN ('skf_admin', 'admin')
        )
    );

-- SKF admin can update
DROP POLICY IF EXISTS "hl_admin_update" ON public.skf_highlights;
CREATE POLICY "hl_admin_update"
    ON public.skf_highlights FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role IN ('skf_admin', 'admin')
        )
    );

-- SKF admin can delete
DROP POLICY IF EXISTS "hl_admin_delete" ON public.skf_highlights;
CREATE POLICY "hl_admin_delete"
    ON public.skf_highlights FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role IN ('skf_admin', 'admin')
        )
    );

-- ── Storage bucket (paste separately if needed) ──────────────────────────────
-- Run this block in Supabase SQL Editor to create the highlights storage bucket:
/*
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('skf-highlights', 'skf-highlights', true, 5242880, ARRAY['image/jpeg','image/png','image/webp','image/gif'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "highlights_public_read" ON storage.objects;
CREATE POLICY "highlights_public_read" ON storage.objects
    FOR SELECT USING (bucket_id = 'skf-highlights');

DROP POLICY IF EXISTS "highlights_admin_write" ON storage.objects;
CREATE POLICY "highlights_admin_write" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'skf-highlights'
        AND EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role IN ('skf_admin', 'admin')
        )
    );

DROP POLICY IF EXISTS "highlights_admin_update" ON storage.objects;
CREATE POLICY "highlights_admin_update" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'skf-highlights'
        AND EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role IN ('skf_admin', 'admin')
        )
    );

DROP POLICY IF EXISTS "highlights_admin_delete_obj" ON storage.objects;
CREATE POLICY "highlights_admin_delete_obj" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'skf-highlights'
        AND EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role IN ('skf_admin', 'admin')
        )
    );
*/
