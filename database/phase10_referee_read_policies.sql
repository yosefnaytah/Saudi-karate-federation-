-- Phase 10 — Referee read access policies (CORRECTED — no recursion)
-- Uses auth_user_role() SECURITY DEFINER function instead of querying public.users
-- This avoids infinite recursion in RLS policies.
--
-- Run this in your Supabase SQL Editor.

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. DROP the broken policies created in the first run (removes recursion)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Referee staff read all registrations"    ON public.tournament_registrations;
DROP POLICY IF EXISTS "Referee staff read all user profiles"    ON public.users;
DROP POLICY IF EXISTS "Referee plain read matches"              ON public.tournament_matches;
DROP POLICY IF EXISTS "Referee plain update matches"            ON public.tournament_matches;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. tournament_registrations: allow referees to read ALL registrations
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Referee plus read tournament registrations" ON public.tournament_registrations;

CREATE POLICY "Referee staff read all registrations"
    ON public.tournament_registrations
    FOR SELECT
    TO authenticated
    USING (
        auth_user_role() IN ('referee', 'referees_plus', 'skf_admin', 'admin')
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. public.users: allow referees to read ALL user profiles
--    Uses auth_user_role() — SECURITY DEFINER — does NOT query public.users
--    so there is no infinite recursion.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "Referee staff read all user profiles"
    ON public.users
    FOR SELECT
    TO authenticated
    USING (
        auth_user_role() IN ('referee', 'referees_plus', 'skf_admin', 'admin')
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. tournament_matches: plain 'referee' role read + update
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "Referee plain read matches"
    ON public.tournament_matches
    FOR SELECT
    TO authenticated
    USING (
        auth_user_role() IN ('referee', 'referees_plus', 'skf_admin', 'admin')
    );

CREATE POLICY "Referee plain update matches"
    ON public.tournament_matches
    FOR UPDATE
    TO authenticated
    USING (
        auth_user_role() IN ('referee', 'referees_plus', 'skf_admin', 'admin')
    );

