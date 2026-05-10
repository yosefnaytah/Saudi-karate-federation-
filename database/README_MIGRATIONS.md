# SKF Supabase migrations — run order

**Important:** This file is **Markdown** for humans. **Do not paste it into the Supabase SQL Editor** — Postgres will error on `#` and tables.

- To run **documentation + verification checks** as real SQL, open and run **`MIGRATION_RUN_ORDER.sql`** (comments + verification `SELECT`s only).
- To apply schema changes, open each **`*.sql`** migration file below and run **that file’s contents** as a separate query.

Run migration scripts in order. If a file was already applied, re-running safe scripts (`IF NOT EXISTS`, `DROP POLICY IF EXISTS`) is usually fine; always test on a branch/project copy first.

## 1. Core foundation

| Order | File | Purpose |
|------:|------|---------|
| 1 | `supabase_schema.sql` | `users`, `tournaments`, categories, registrations, clubs, news, base RLS |
| 2 | `users_role_add_skf_admin.sql` | Role constraint updates if your DB predates `skf_admin` |
| 3 | `supabase_player_profile_columns.sql` | Extra `users` columns: age_group, rank, bio, profile_photo_url |
| 4 | `skf_applications.sql` | Staff applications (SKF admin / Referee+ signup flow) |
| 5 | `sprint_a_foundations.sql` | `age_categories`, `weight_categories`, `profiles`, `player_profiles`, avatar storage |
| 6 | `sprint_b_clubs_and_contracts.sql` | `club_status`, `users.club_id`, `player_club_contracts` |
| 7 | `supabase_rls_skf_admin_*.sql` | Extra SKF admin policies (as needed) |

## 2. New work (this recommendation track)

| Order | File | Purpose |
|------:|------|---------|
| — | **`MIGRATION_RUN_ORDER.sql`** | **Safe in SQL Editor:** comments + verification `SELECT`s only (not the schema itself) |
| 8 | `phase1_player_profile_view.sql` | Read-model view: documents where profile data lives |
| 9 | `phase2_3_club_and_registration.sql` | Club registration requests + club-admin tournament registration |
| 10 | `phase4_tournament_matches.sql` | Real `tournament_matches` + winner advancement |
| 11 | `phase3_club_admin_read_club_members.sql` | Club admin can read `users` rows in same `club_id` (players list) |

## Verification (run after migrations)

```sql
-- Tables exist
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'users', 'profiles', 'player_profiles', 'clubs', 'player_club_contracts',
    'club_registration_requests', 'tournament_matches', 'tournament_registrations'
  )
ORDER BY table_name;

-- View exists
SELECT * FROM pg_views WHERE schemaname = 'public' AND viewname = 'v_player_profile';

-- Sample: matches RLS enabled
SELECT tablename, rowsecurity FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'tournament_matches';
```

## Profile data (Phase 1 rule of thumb)

| Data | Primary location | Fallback |
|------|------------------|----------|
| Identity, email, phone, federation role | `public.users` | — |
| Avatar (canonical) | `public.profiles.avatar_url` | `users.profile_photo_url` |
| Competition age/weight (FK) | `public.player_profiles` | `users.age_group` / registration fields |

UI and APIs should read **`v_player_profile`** for player cards when possible.
