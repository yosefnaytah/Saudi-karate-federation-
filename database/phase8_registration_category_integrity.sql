-- Phase 8 — Registration category integrity (WKF tournament operations)
-- Goal:
-- 1) A registration's category_id MUST belong to the same tournament_id
-- 2) Prevent registration if tournament has no linked categories
-- 3) Prevent registration with NULL category_id (official categories only)
--
-- Safe to re-run.

-- -----------------------------------------------------------------------------
-- 1) Composite FK: (category_id, tournament_id) -> tournament_categories(id, tournament_id)
-- -----------------------------------------------------------------------------
-- Ensure referenced composite key exists
CREATE UNIQUE INDEX IF NOT EXISTS ux_tournament_categories_id_tournament
    ON public.tournament_categories (id, tournament_id);

-- Drop old single-column FK if it exists (name may differ by environment)
DO $$
DECLARE
  fk_name text;
BEGIN
  SELECT conname INTO fk_name
  FROM pg_constraint
  WHERE conrelid = 'public.tournament_registrations'::regclass
    AND contype = 'f'
    AND pg_get_constraintdef(oid) ILIKE '%FOREIGN KEY (category_id)%REFERENCES public.tournament_categories(id)%';

  IF fk_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.tournament_registrations DROP CONSTRAINT %I;', fk_name);
  END IF;
END $$;

-- Add composite FK (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.tournament_registrations'::regclass
      AND contype = 'f'
      AND conname = 'fk_tr_category_tournament'
  ) THEN
    ALTER TABLE public.tournament_registrations
      ADD CONSTRAINT fk_tr_category_tournament
      FOREIGN KEY (category_id, tournament_id)
      REFERENCES public.tournament_categories (id, tournament_id)
      ON DELETE RESTRICT;
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 2) Enforce "tournament must have categories" and "category_id required"
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_registration_requires_category()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  has_cats boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.tournament_categories tc
    WHERE tc.tournament_id = NEW.tournament_id
      AND COALESCE(tc.status, 'active') = 'active'
  ) INTO has_cats;

  IF NOT has_cats THEN
    RAISE EXCEPTION 'Tournament has no linked categories. SKF Admin must attach official categories before registration.';
  END IF;

  IF NEW.category_id IS NULL THEN
    RAISE EXCEPTION 'Category is required for registration.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_enforce_registration_requires_category ON public.tournament_registrations;
CREATE TRIGGER tr_enforce_registration_requires_category
  BEFORE INSERT OR UPDATE OF tournament_id, category_id
  ON public.tournament_registrations
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_registration_requires_category();

-- Phase 8 — Registration category integrity (WKF tournament operations)
-- Goal:
-- 1) A registration's category_id MUST belong to the same tournament_id
-- 2) Prevent registration if tournament has no linked categories
-- 3) Prevent registration with NULL category_id (official categories only)
--
-- Safe to re-run.

-- -----------------------------------------------------------------------------
-- 1) Composite FK: (category_id, tournament_id) -> tournament_categories(id, tournament_id)
-- -----------------------------------------------------------------------------
-- Ensure referenced composite key exists
CREATE UNIQUE INDEX IF NOT EXISTS ux_tournament_categories_id_tournament
    ON public.tournament_categories (id, tournament_id);

-- Drop old single-column FK if it exists (name may differ by environment)
DO $$
DECLARE
  fk_name text;
BEGIN
  SELECT conname INTO fk_name
  FROM pg_constraint
  WHERE conrelid = 'public.tournament_registrations'::regclass
    AND contype = 'f'
    AND pg_get_constraintdef(oid) ILIKE '%FOREIGN KEY (category_id)%REFERENCES public.tournament_categories(id)%';

  IF fk_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.tournament_registrations DROP CONSTRAINT %I;', fk_name);
  END IF;
END $$;

-- Add composite FK (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.tournament_registrations'::regclass
      AND contype = 'f'
      AND conname = 'fk_tr_category_tournament'
  ) THEN
    ALTER TABLE public.tournament_registrations
      ADD CONSTRAINT fk_tr_category_tournament
      FOREIGN KEY (category_id, tournament_id)
      REFERENCES public.tournament_categories (id, tournament_id)
      ON DELETE RESTRICT;
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 2) Enforce "tournament must have categories" and "category_id required"
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_registration_requires_category()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  has_cats boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.tournament_categories tc
    WHERE tc.tournament_id = NEW.tournament_id
      AND COALESCE(tc.status, 'active') = 'active'
  ) INTO has_cats;

  IF NOT has_cats THEN
    RAISE EXCEPTION 'Tournament has no linked categories. SKF Admin must attach official categories before registration.';
  END IF;

  IF NEW.category_id IS NULL THEN
    RAISE EXCEPTION 'Category is required for registration.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_enforce_registration_requires_category ON public.tournament_registrations;
CREATE TRIGGER tr_enforce_registration_requires_category
  BEFORE INSERT OR UPDATE OF tournament_id, category_id
  ON public.tournament_registrations
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_registration_requires_category();

