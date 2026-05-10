-- Phase 7b — WKF-style Official Categories (upgrade)
-- This upgrades the master categories system to official WKF-style structure.
-- It does NOT delete old data; it adds columns + constraints and seeds official rows.
--
-- Run after: phase7_categories_master.sql
-- Safe to re-run.

-- -----------------------------------------------------------------------------
-- 1) Extend public.categories with WKF-required columns
-- -----------------------------------------------------------------------------
ALTER TABLE public.categories
    ADD COLUMN IF NOT EXISTS event_type TEXT,
    ADD COLUMN IF NOT EXISTS age_category TEXT,
    ADD COLUMN IF NOT EXISTS weight_division TEXT,
    ADD COLUMN IF NOT EXISTS min_age INTEGER,
    ADD COLUMN IF NOT EXISTS max_age INTEGER,
    ADD COLUMN IF NOT EXISTS is_team_event BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

-- Map legacy columns if event_type not set yet (best-effort)
UPDATE public.categories
SET
    event_type = COALESCE(event_type,
        CASE
            WHEN lower(type) = 'kumite' THEN 'kumite'
            WHEN lower(type) = 'kata' THEN 'kata_individual'
            ELSE NULL
        END
    ),
    age_category = COALESCE(age_category, NULLIF(age_group, '')),
    weight_division = COALESCE(weight_division, NULLIF(weight_label, '')),
    is_active = COALESCE(is_active, (status = 'active'))
WHERE event_type IS NULL OR age_category IS NULL OR weight_division IS NULL OR is_active IS NULL;

-- Normalize age_category labels to official names when possible
UPDATE public.categories
SET age_category = CASE
    WHEN lower(age_category) IN ('u14', 'under 14') THEN 'cadet'
    WHEN lower(age_category) IN ('u16', 'under 16') THEN 'cadet'
    WHEN lower(age_category) IN ('u18', 'under 18') THEN 'junior'
    WHEN lower(age_category) IN ('u21', 'under 21') THEN 'u21'
    WHEN lower(age_category) IN ('senior') THEN 'senior'
    WHEN lower(age_category) IN ('cadet','junior','u21','senior') THEN lower(age_category)
    ELSE age_category
END
WHERE age_category IS NOT NULL;

-- Constraints / validation (WKF rules)
ALTER TABLE public.categories
    ADD CONSTRAINT categories_event_type_check
    CHECK (event_type IN ('kumite', 'kata_individual', 'kata_team')) NOT VALID;

ALTER TABLE public.categories
    ADD CONSTRAINT categories_age_category_check
    CHECK (age_category IN ('cadet', 'junior', 'u21', 'senior')) NOT VALID;

ALTER TABLE public.categories
    ADD CONSTRAINT categories_gender_check
    CHECK (gender IS NULL OR gender IN ('male', 'female')) NOT VALID;

ALTER TABLE public.categories
    ADD CONSTRAINT categories_kata_weight_null_check
    CHECK (
        (event_type = 'kumite' AND weight_division IS NOT NULL AND btrim(weight_division) <> '')
        OR (event_type IN ('kata_individual', 'kata_team') AND (weight_division IS NULL OR btrim(weight_division) = ''))
        OR event_type IS NULL
    ) NOT VALID;

-- Uniqueness to prevent duplicates (active categories)
CREATE UNIQUE INDEX IF NOT EXISTS ux_categories_wkf_unique
    ON public.categories (
        lower(coalesce(event_type, '')),
        lower(coalesce(age_category, '')),
        lower(coalesce(gender, '')),
        lower(coalesce(weight_division, '')),
        is_team_event
    )
    WHERE is_active IS TRUE;

-- -----------------------------------------------------------------------------
-- 2) Extend public.tournament_categories to carry WKF semantics (for display)
-- -----------------------------------------------------------------------------
ALTER TABLE public.tournament_categories
    ADD COLUMN IF NOT EXISTS event_type TEXT,
    ADD COLUMN IF NOT EXISTS age_category TEXT,
    ADD COLUMN IF NOT EXISTS is_team_event BOOLEAN NOT NULL DEFAULT FALSE;

-- -----------------------------------------------------------------------------
-- 3) Seed official WKF categories (idempotent)
-- -----------------------------------------------------------------------------
-- Helper: insert row only if not exists (uses unique index)
-- Kumite / Cadet / Male
INSERT INTO public.categories (name, type, event_type, age_category, gender, weight_division, weight_label, age_group, status, is_active, is_team_event, min_age, max_age)
VALUES
('Male Cadet Kumite -52 kg', 'kumite', 'kumite', 'cadet', 'male', '-52 kg', '-52 kg', 'cadet', 'active', true, false, 14, 15),
('Male Cadet Kumite -57 kg', 'kumite', 'kumite', 'cadet', 'male', '-57 kg', '-57 kg', 'cadet', 'active', true, false, 14, 15),
('Male Cadet Kumite -63 kg', 'kumite', 'kumite', 'cadet', 'male', '-63 kg', '-63 kg', 'cadet', 'active', true, false, 14, 15),
('Male Cadet Kumite -70 kg', 'kumite', 'kumite', 'cadet', 'male', '-70 kg', '-70 kg', 'cadet', 'active', true, false, 14, 15),
('Male Cadet Kumite +70 kg', 'kumite', 'kumite', 'cadet', 'male', '+70 kg', '+70 kg', 'cadet', 'active', true, false, 14, 15)
ON CONFLICT DO NOTHING;

-- Kumite / Cadet / Female
INSERT INTO public.categories (name, type, event_type, age_category, gender, weight_division, weight_label, age_group, status, is_active, is_team_event, min_age, max_age)
VALUES
('Female Cadet Kumite -47 kg', 'kumite', 'kumite', 'cadet', 'female', '-47 kg', '-47 kg', 'cadet', 'active', true, false, 14, 15),
('Female Cadet Kumite -54 kg', 'kumite', 'kumite', 'cadet', 'female', '-54 kg', '-54 kg', 'cadet', 'active', true, false, 14, 15),
('Female Cadet Kumite -61 kg', 'kumite', 'kumite', 'cadet', 'female', '-61 kg', '-61 kg', 'cadet', 'active', true, false, 14, 15),
('Female Cadet Kumite +61 kg', 'kumite', 'kumite', 'cadet', 'female', '+61 kg', '+61 kg', 'cadet', 'active', true, false, 14, 15)
ON CONFLICT DO NOTHING;

-- Kumite / Junior / Male
INSERT INTO public.categories (name, type, event_type, age_category, gender, weight_division, weight_label, age_group, status, is_active, is_team_event, min_age, max_age)
VALUES
('Male Junior Kumite -55 kg', 'kumite', 'kumite', 'junior', 'male', '-55 kg', '-55 kg', 'junior', 'active', true, false, 16, 17),
('Male Junior Kumite -61 kg', 'kumite', 'kumite', 'junior', 'male', '-61 kg', '-61 kg', 'junior', 'active', true, false, 16, 17),
('Male Junior Kumite -68 kg', 'kumite', 'kumite', 'junior', 'male', '-68 kg', '-68 kg', 'junior', 'active', true, false, 16, 17),
('Male Junior Kumite -76 kg', 'kumite', 'kumite', 'junior', 'male', '-76 kg', '-76 kg', 'junior', 'active', true, false, 16, 17),
('Male Junior Kumite +76 kg', 'kumite', 'kumite', 'junior', 'male', '+76 kg', '+76 kg', 'junior', 'active', true, false, 16, 17)
ON CONFLICT DO NOTHING;

-- Kumite / Junior / Female
INSERT INTO public.categories (name, type, event_type, age_category, gender, weight_division, weight_label, age_group, status, is_active, is_team_event, min_age, max_age)
VALUES
('Female Junior Kumite -48 kg', 'kumite', 'kumite', 'junior', 'female', '-48 kg', '-48 kg', 'junior', 'active', true, false, 16, 17),
('Female Junior Kumite -53 kg', 'kumite', 'kumite', 'junior', 'female', '-53 kg', '-53 kg', 'junior', 'active', true, false, 16, 17),
('Female Junior Kumite -59 kg', 'kumite', 'kumite', 'junior', 'female', '-59 kg', '-59 kg', 'junior', 'active', true, false, 16, 17),
('Female Junior Kumite -66 kg', 'kumite', 'kumite', 'junior', 'female', '-66 kg', '-66 kg', 'junior', 'active', true, false, 16, 17),
('Female Junior Kumite +66 kg', 'kumite', 'kumite', 'junior', 'female', '+66 kg', '+66 kg', 'junior', 'active', true, false, 16, 17)
ON CONFLICT DO NOTHING;

-- Kumite / U21 / Male
INSERT INTO public.categories (name, type, event_type, age_category, gender, weight_division, weight_label, age_group, status, is_active, is_team_event, min_age, max_age)
VALUES
('Male U21 Kumite -60 kg', 'kumite', 'kumite', 'u21', 'male', '-60 kg', '-60 kg', 'u21', 'active', true, false, 18, 20),
('Male U21 Kumite -67 kg', 'kumite', 'kumite', 'u21', 'male', '-67 kg', '-67 kg', 'u21', 'active', true, false, 18, 20),
('Male U21 Kumite -75 kg', 'kumite', 'kumite', 'u21', 'male', '-75 kg', '-75 kg', 'u21', 'active', true, false, 18, 20),
('Male U21 Kumite -84 kg', 'kumite', 'kumite', 'u21', 'male', '-84 kg', '-84 kg', 'u21', 'active', true, false, 18, 20),
('Male U21 Kumite +84 kg', 'kumite', 'kumite', 'u21', 'male', '+84 kg', '+84 kg', 'u21', 'active', true, false, 18, 20)
ON CONFLICT DO NOTHING;

-- Kumite / U21 / Female
INSERT INTO public.categories (name, type, event_type, age_category, gender, weight_division, weight_label, age_group, status, is_active, is_team_event, min_age, max_age)
VALUES
('Female U21 Kumite -50 kg', 'kumite', 'kumite', 'u21', 'female', '-50 kg', '-50 kg', 'u21', 'active', true, false, 18, 20),
('Female U21 Kumite -55 kg', 'kumite', 'kumite', 'u21', 'female', '-55 kg', '-55 kg', 'u21', 'active', true, false, 18, 20),
('Female U21 Kumite -61 kg', 'kumite', 'kumite', 'u21', 'female', '-61 kg', '-61 kg', 'u21', 'active', true, false, 18, 20),
('Female U21 Kumite -68 kg', 'kumite', 'kumite', 'u21', 'female', '-68 kg', '-68 kg', 'u21', 'active', true, false, 18, 20),
('Female U21 Kumite +68 kg', 'kumite', 'kumite', 'u21', 'female', '+68 kg', '+68 kg', 'u21', 'active', true, false, 18, 20)
ON CONFLICT DO NOTHING;

-- Kumite / Senior / Male
INSERT INTO public.categories (name, type, event_type, age_category, gender, weight_division, weight_label, age_group, status, is_active, is_team_event, min_age, max_age)
VALUES
('Male Senior Kumite -60 kg', 'kumite', 'kumite', 'senior', 'male', '-60 kg', '-60 kg', 'senior', 'active', true, false, 18, NULL),
('Male Senior Kumite -67 kg', 'kumite', 'kumite', 'senior', 'male', '-67 kg', '-67 kg', 'senior', 'active', true, false, 18, NULL),
('Male Senior Kumite -75 kg', 'kumite', 'kumite', 'senior', 'male', '-75 kg', '-75 kg', 'senior', 'active', true, false, 18, NULL),
('Male Senior Kumite -84 kg', 'kumite', 'kumite', 'senior', 'male', '-84 kg', '-84 kg', 'senior', 'active', true, false, 18, NULL),
('Male Senior Kumite +84 kg', 'kumite', 'kumite', 'senior', 'male', '+84 kg', '+84 kg', 'senior', 'active', true, false, 18, NULL)
ON CONFLICT DO NOTHING;

-- Kumite / Senior / Female
INSERT INTO public.categories (name, type, event_type, age_category, gender, weight_division, weight_label, age_group, status, is_active, is_team_event, min_age, max_age)
VALUES
('Female Senior Kumite -50 kg', 'kumite', 'kumite', 'senior', 'female', '-50 kg', '-50 kg', 'senior', 'active', true, false, 18, NULL),
('Female Senior Kumite -55 kg', 'kumite', 'kumite', 'senior', 'female', '-55 kg', '-55 kg', 'senior', 'active', true, false, 18, NULL),
('Female Senior Kumite -61 kg', 'kumite', 'kumite', 'senior', 'female', '-61 kg', '-61 kg', 'senior', 'active', true, false, 18, NULL),
('Female Senior Kumite -68 kg', 'kumite', 'kumite', 'senior', 'female', '-68 kg', '-68 kg', 'senior', 'active', true, false, 18, NULL),
('Female Senior Kumite +68 kg', 'kumite', 'kumite', 'senior', 'female', '+68 kg', '+68 kg', 'senior', 'active', true, false, 18, NULL)
ON CONFLICT DO NOTHING;

-- Kata Individual (no weight) — Cadet/Junior/U21/Senior (Male/Female)
INSERT INTO public.categories (name, type, event_type, age_category, gender, weight_division, weight_label, age_group, status, is_active, is_team_event, min_age, max_age)
VALUES
('Male Cadet Kata', 'kata', 'kata_individual', 'cadet', 'male', NULL, NULL, 'cadet', 'active', true, false, 14, 15),
('Female Cadet Kata', 'kata', 'kata_individual', 'cadet', 'female', NULL, NULL, 'cadet', 'active', true, false, 14, 15),
('Male Junior Kata', 'kata', 'kata_individual', 'junior', 'male', NULL, NULL, 'junior', 'active', true, false, 16, 17),
('Female Junior Kata', 'kata', 'kata_individual', 'junior', 'female', NULL, NULL, 'junior', 'active', true, false, 16, 17),
('Male U21 Kata', 'kata', 'kata_individual', 'u21', 'male', NULL, NULL, 'u21', 'active', true, false, 18, 20),
('Female U21 Kata', 'kata', 'kata_individual', 'u21', 'female', NULL, NULL, 'u21', 'active', true, false, 18, 20),
('Male Senior Kata', 'kata', 'kata_individual', 'senior', 'male', NULL, NULL, 'senior', 'active', true, false, 18, NULL),
('Female Senior Kata', 'kata', 'kata_individual', 'senior', 'female', NULL, NULL, 'senior', 'active', true, false, 18, NULL)
ON CONFLICT DO NOTHING;

-- Kata Team (no weight) — Cadet/Junior/U21/Senior (Male/Female)
INSERT INTO public.categories (name, type, event_type, age_category, gender, weight_division, weight_label, age_group, status, is_active, is_team_event, min_age, max_age)
VALUES
('Male Cadet Team Kata', 'kata', 'kata_team', 'cadet', 'male', NULL, NULL, 'cadet', 'active', true, true, 14, 15),
('Female Cadet Team Kata', 'kata', 'kata_team', 'cadet', 'female', NULL, NULL, 'cadet', 'active', true, true, 14, 15),
('Male Junior Team Kata', 'kata', 'kata_team', 'junior', 'male', NULL, NULL, 'junior', 'active', true, true, 16, 17),
('Female Junior Team Kata', 'kata', 'kata_team', 'junior', 'female', NULL, NULL, 'junior', 'active', true, true, 16, 17),
('Male U21 Team Kata', 'kata', 'kata_team', 'u21', 'male', NULL, NULL, 'u21', 'active', true, true, 18, 20),
('Female U21 Team Kata', 'kata', 'kata_team', 'u21', 'female', NULL, NULL, 'u21', 'active', true, true, 18, 20),
('Male Senior Team Kata', 'kata', 'kata_team', 'senior', 'male', NULL, NULL, 'senior', 'active', true, true, 18, NULL),
('Female Senior Team Kata', 'kata', 'kata_team', 'senior', 'female', NULL, NULL, 'senior', 'active', true, true, 18, NULL)
ON CONFLICT DO NOTHING;

COMMENT ON TABLE public.categories IS
'Phase7b: WKF official categories. event_type + age_category + gender + weight_division (kumite only).';

