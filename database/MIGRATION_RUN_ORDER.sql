-- =============================================================================
-- SKF Supabase — migration run order (safe to run in SQL Editor)
-- =============================================================================
-- This file is valid SQL: documentation is in comments only.
-- The SELECTs at the bottom verify objects after you run the real migrations.
--
-- Do NOT paste README_MIGRATIONS.md into the editor — that file is Markdown.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Core foundation (run each file’s contents as its own query, in this order)
-- -----------------------------------------------------------------------------
--  1  supabase_schema.sql              — users, tournaments, categories, registrations, clubs, news, base RLS
--  1b rls_helpers_auth_users.sql     — optional one-shot: all auth helpers if you skipped updated supabase_schema/sprint_b
--      (normally auth_user_role is created in supabase_schema; club_id helpers are created in sprint_b after users.club_id).
--      If you see "infinite recursion detected in policy for relation users", run fix_rls_users_infinite_recursion.sql once.
--  2  users_role_add_skf_admin.sql    — role constraint if DB predates skf_admin
--  3  supabase_player_profile_columns.sql — age_group, rank, bio, profile_photo_url on users
--  4  skf_applications.sql            — SKF staff applications
--  5  sprint_a_foundations.sql        — age_categories, weight_categories, profiles, player_profiles, storage
--  6  sprint_b_clubs_and_contracts.sql — club_status, users.club_id, player_club_contracts
--  7  supabase_rls_skf_admin_*.sql   — extra SKF policies as needed

-- -----------------------------------------------------------------------------
-- Recommendation track (this repo)
-- -----------------------------------------------------------------------------
--  8  phase1_player_profile_view.sql   — view public.v_player_profile
--  9  phase2_3_club_and_registration.sql — club_registration_requests, registration RLS
-- 10  phase4_tournament_matches.sql    — tournament_matches + advancement trigger
-- 10b phase17_match_status_paused_and_loser.sql — status CHECK adds paused; loser_user_id column
-- 11  phase3_club_admin_read_club_members.sql — club admin SELECT users in same club
-- 12  phase3b_club_admin_read_member_profiles.sql — optional: club admin SELECT profiles.avatar_url for same club
-- 13  phase5_transfer_market.sql — transfer listings, offers, SKF approval RPCs; player clubmate/opponent RLS for avatars
-- 14  phase6_referee_plus.sql — competition_state, bracket_type, Referee+ RLS, knockout draw RPC (power-of-two MVP)
-- 15  phase6b_referee_plus_league_rr.sql — league / round-robin match generator RPC
-- 16  phase6c_referee_read_match_athletes.sql — RLS: referee / Referee+ read athlete names for match ops
-- 16b phase11_referee_read_users_for_registrations.sql — superseded by phase12 (still safe if run; phase12 replaces policy names)
-- 16c phase12_bracket_setup_read_registered_players.sql — **RUN THIS** for Bracket Setup player list (role-normalized RLS on users via registrations)
-- 16d phase18_referee_match_fetch_athletes.sql — Match Control / crowd display: SECURITY DEFINER RPC for athlete names + photos (requires users.profile_photo_url + phase12 helpers)
-- 17  phase6d_referee_staff_application.sql — skf_applications.requested_role includes referee; trigger + SKF ID RPC
-- 18  phase7_categories_master.sql — master categories table + tournament_categories.category_id linking (Part 3)
-- 19  phase7_wkf_categories.sql — upgrade categories to WKF official structure + seed official categories (Cadet/Junior/U21/Senior)
-- 20  phase8_registration_category_integrity.sql — enforce registration category belongs to tournament; require categories
-- 21  phase9_ranking_points.sql — ranking points MVP (from completed matches; totals view)
-- 22  phase21_belt_tests.sql   — belt_test_events + belt_test_candidates tables, RLS, skf_belt_test_record_result RPC
-- 23  phase22_auto_advance.sql — skf_force_advance_winner RPC: advances winner even when advances_to_match_id is NULL
-- 24  phase23_highlights.sql  — skf_highlights table + RLS; storage bucket block in comments

-- -----------------------------------------------------------------------------
-- Phase 1 — profile data rule of thumb (for app developers)
-- -----------------------------------------------------------------------------
-- Identity, email, phone, role     → public.users
-- Avatar (canonical)               → public.profiles.avatar_url, else users.profile_photo_url
-- Competition age/weight (FK)    → public.player_profiles; fallback users.age_group / registration fields
-- Prefer SELECT from v_player_profile for player cards when possible.

-- =============================================================================
-- Verification (run this block after migrations)
-- =============================================================================

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'users',
    'profiles',
    'player_profiles',
    'clubs',
    'player_club_contracts',
    'club_registration_requests',
    'tournament_matches',
    'tournament_registrations'
  )
ORDER BY table_name;

SELECT schemaname, viewname
FROM pg_views
WHERE schemaname = 'public'
  AND viewname = 'v_player_profile';

SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename = 'tournament_matches';

