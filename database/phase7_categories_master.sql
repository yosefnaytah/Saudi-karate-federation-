-- Phase 7 — Master Categories + Tournament Linking (non-breaking)
-- هدف: ربط فئات الوزن/العمر/النوع بالبطولات من قاعدة البيانات بدل الكتابة اليدوية
--
-- This migration is additive:
-- - Creates a master reference table: public.categories
-- - Extends existing public.tournament_categories with category_id (FK) + status
-- - Keeps existing tournament_categories columns (discipline/gender/age_group/weight_class)
--   so current UI pages keep working unchanged.
--
-- Safe to re-run.

-- -----------------------------------------------------------------------------
-- 1) Master categories reference table
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    type TEXT NOT NULL, -- maps to tournament_categories.discipline (kata/kumite)
    gender TEXT,        -- male/female/mixed
    age_group TEXT,
    weight_min DECIMAL(6,2),
    weight_max DECIMAL(6,2),
    weight_label TEXT,  -- e.g. -67kg, +84kg, Open
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_categories_status ON public.categories(status);
CREATE INDEX IF NOT EXISTS idx_categories_type_gender_age ON public.categories(type, gender, age_group);

-- updated_at trigger (reuse existing function if present)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'update_updated_at_column' AND pg_function_is_visible(oid)) THEN
        DROP TRIGGER IF EXISTS update_categories_updated_at ON public.categories;
        CREATE TRIGGER update_categories_updated_at
            BEFORE UPDATE ON public.categories
            FOR EACH ROW
            EXECUTE FUNCTION public.update_updated_at_column();
    END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 2) Extend tournament_categories to reference master categories
-- -----------------------------------------------------------------------------
ALTER TABLE public.tournament_categories
    ADD COLUMN IF NOT EXISTS category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL;

ALTER TABLE public.tournament_categories
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'inactive'));

-- Prevent duplicate linking when category_id is used (ignore legacy rows where category_id is null)
CREATE UNIQUE INDEX IF NOT EXISTS ux_tournament_categories_tournament_category
    ON public.tournament_categories(tournament_id, category_id)
    WHERE category_id IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 3) RLS policies for master categories
-- -----------------------------------------------------------------------------
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

-- Read: any authenticated user can read active categories
DROP POLICY IF EXISTS "Categories read active" ON public.categories;
CREATE POLICY "Categories read active"
    ON public.categories FOR SELECT TO authenticated
    USING (status = 'active');

-- Manage: SKF admins only
DROP POLICY IF EXISTS "Categories manage by SKF admins" ON public.categories;
CREATE POLICY "Categories manage by SKF admins"
    ON public.categories FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role IN ('skf_admin', 'admin')
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role IN ('skf_admin', 'admin')
        )
    );

COMMENT ON TABLE public.categories IS
'Phase7: master reference categories; tournaments attach via tournament_categories.category_id.';

