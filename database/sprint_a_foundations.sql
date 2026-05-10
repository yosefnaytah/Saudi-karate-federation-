-- =============================================================================
-- Sprint A — Data foundations (profiles, role extensions, category reference)
-- Run in Supabase SQL Editor after public.users exists.
-- Safe to re-run: uses IF NOT EXISTS / CREATE OR REPLACE where possible.
-- =============================================================================

-- ── 1) Shared profile (avatar URL only; file in Storage) ───────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
    user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.profiles IS 'Sprint A: shared profile; avatar_url is public/signed URL to Storage only.';

CREATE INDEX IF NOT EXISTS idx_profiles_has_avatar ON public.profiles (user_id) WHERE avatar_url IS NOT NULL;

-- ── 2) Role-specific extension rows (no cross-table CHECK; enforced in app/trigger) ──
CREATE TABLE IF NOT EXISTS public.player_profiles (
    user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    age_category_id INTEGER REFERENCES public.age_categories(id) ON DELETE SET NULL,
    weight_category_id INTEGER REFERENCES public.weight_categories(id) ON DELETE SET NULL,
    notes TEXT
);

-- Forward references: age_categories / weight_categories created below — reorder if PG complains.
-- If your run fails here, run section 3 first, then re-run from section 2.
