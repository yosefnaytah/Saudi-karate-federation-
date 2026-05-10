# SKF Website — Bug-fix & Integration Plan (Tournaments / Transfers / Brackets / Rankings)

## Scope rules (must not break UI)

- **Do not redesign**: keep existing colors, layout, navigation, animations, and page structure.
- **Do not delete** any working pages/features.
- Only **fix rendering bugs** + **connect missing logic** (Supabase tables/RPC/RLS + existing UI).

This plan is written to match the **current repo**:

- Frontend uses **Supabase JS SDK directly** (`html/auth.js` → `getSupabase()`), plus SQL/RPC “phase” scripts.
- Existing key pages:
  - `html/transfers.html` (transfer market + offers + SKF approval queue mini-view)
  - `html/admin-dashboard.html` (SKF admin: users, tournaments, categories, registrations, transfer approvals)
  - `html/club-dashboard.html` (club admin: roster + register players into tournament categories)
  - `html/referee-dashboard.html` (referee/referee+: setup + bracket gen + match operations)
  - `html/tournament.html` (public tournament list + view categories)
- Existing match/bracket MVP is implemented via:
  - `database/phase4_tournament_matches.sql` (table + auto-advance trigger)
  - `database/phase6_referee_plus.sql` (bracket_type + RPC generator)
  - `database/phase6b_referee_plus_league_rr.sql` (league RR generator)
  - `database/phase6c_referee_read_match_athletes.sql` (read match athletes)

## Architecture decision (backend or not?)

### Recommendation
Continue with **Supabase-first** integration (tables + RLS + RPC) because the current UI already depends on it.

### When to add the .NET backend
Use `backend/SkfWebsite.Api` only for:
- Secrets / service-role operations (server-side)
- Complex reporting/export
- File processing (e.g., validation/virus scan)

For this scope, Supabase + RPC is enough and matches your current implementation.

---

## Current DB model (what exists now)

From `database/supabase_schema.sql` (summary):

- `public.users` includes: `role`, `player_id_card` (TEXT), `profile_image_url`/`profile_photo_url` patterns, `is_active`, plus federation-specific columns used by dashboards.
- `public.tournaments`
- `public.tournament_categories` (**per-tournament**, currently stores: `discipline`, `gender`, `age_group`, `weight_class`, `bracket_type`, etc.)
- `public.tournament_registrations` includes `category_id` → `tournament_categories.id`
- `public.tournament_matches` (phase4) includes knockout advancement (`advances_to_match_id`)
- Transfer market appears to rely on additional tables/RPC created by `phase5_transfer_market.sql` (referenced by UI).

### Gap vs required target
You want a reusable **master categories table** (global), and a linking table so tournaments attach categories by ID.
Right now, categories are stored per tournament directly in `tournament_categories`.

To avoid breaking current UI (which expects `tournament_categories.discipline/gender/age_group/weight_class`), we will **extend** the schema instead of replacing it.

---

## Plan overview (phases)

### Phase A — Stabilize rendering + permissions (fast wins)
- Fix transfer offer “raw/broken/unreadable user data”
- Fix admin approval image/document rendering and sizing
- Ensure RLS allows required reads (without exposing private data)

### Phase B — Normalize categories without breaking existing UI
- Add `public.categories` (master reference)
- Extend `public.tournament_categories` to link to master `categories.id`
- Update admin tournament category selection UI to **select from DB**, not manual typing

### Phase C — End-to-end tournament operation
- Club admin registration → category-linked rows only
- Referee+ bracket generation category-by-category
- Referee match operations + validation messages

### Phase D — Ranking system (points + visibility)
- Add stats tables + triggers/RPC to update after match completion
- Add read queries used by player/club/admin dashboards (no UI redesign)

---

## PART 1 — Fix Club Admin Transfer Offer UI (player card shows broken/raw data)

### Likely root cause (based on current code)
In `html/transfers.html`, the club admin view loads listings, then tries to load listing players:

- `sb.from('users').select('id,full_name,email,profile_photo_url,profiles(avatar_url)').in('id', ids)`

If **RLS denies** reading other users’ rows, the UI falls back to IDs, which looks like “random/unreadable data”.

### Fix approach (no redesign)

#### A) Database / RLS (recommended)
Add a **safe public view** or policy that allows club admins to read a limited set of fields for:
- players that are **listed in transfer_market_listings**
- players in the **same club** (already needed for roster ranking in `player-dashboard.html`)

Example strategy:
- Create `public.public_user_cards` VIEW (id, full_name, club_id, club_name, age_group, rank, avatar_url/profile_photo_url)
- RLS: `SELECT` allowed when:
  - viewer role = `club_admin` AND the target user is listed as `active` in `transfer_market_listings`
  - OR viewer role in (`skf_admin`, `admin`, `referees_plus`) (already allowed in many policies)

#### B) Frontend rendering guardrails (required by spec)
In `html/transfers.html`:
- Show **loading** state while fetching player info for listings
- Show **error** state when user card data query fails
- Disable “Send offer” button until:
  - listing exists
  - the associated player card data has loaded successfully
- If profile photo missing → show existing placeholder

Deliverable: Club admin always sees a clean player card (photo + readable name + club + age/rank where available) before sending an offer.

Files to touch:
- `html/transfers.html` (club admin listing rendering + submit guard)
- SQL: add view/policy in a new migration file (see “DB migration files” section)

---

## PART 2 — Fix SKF Admin Approval Page image size + PDF/document handling

### Where this appears
Admin user detail modal exists in `html/admin-dashboard.html` (`viewUserDetails()`).
Transfer approvals queue exists in `admin-dashboard.html` and `transfers.html`.

### Fix requirements (no redesign)

#### A) CSS hard limits
Ensure any avatar/photo in approval/detail views uses a fixed avatar class:
- `width: 100px; height: 100px; object-fit: cover; border-radius: 50%; max-width: 100%;`

Note: `admin-dashboard.html` already has `.user-detail-hero img { width:120px; height:120px; object-fit:cover; border-radius:50% }`.
We will **reuse these** and apply the same pattern in any approval detail modal that currently uses raw `<img>` without constraints.

#### B) Detect PDFs / documents
If a stored URL is a document (PDF) or unknown type:
- **Do not render as `<img>`**
- Render as: “Open document” button/link

Implementation pattern (frontend):
- `isImageUrl(url)` → allow only `data:image/...` or `https://...` images (png/jpg) if you store that convention
- `isPdfUrl(url)` → `\.pdf($|\?)` OR `content-type` stored metadata

Files to touch:
- `html/admin-dashboard.html` (wherever approvals/details show documents)
- Potentially `html/transfers.html` SKF approval detail modal if it exists/gets added

---

## PART 3 — Tournament Categories Integration (DB-linked selection, not manual typing)

### Current state
Categories are currently stored in `public.tournament_categories` as per-tournament rows:
- `discipline`, `gender`, `age_group`, `weight_class` (+ `bracket_type`)

Admin dashboard includes category management UI (modal) that writes to `tournament_categories`.
Club dashboard already loads categories per tournament:
- `club-dashboard.html` → `sb.from('tournament_categories').select(...).eq('tournament_id', tid)`
Tournament public page also reads per-tournament categories:
- `tournament.html` → `sb.from('tournament_categories').select(...).eq('tournament_id', tournamentId)`

### Required target
Add a master `categories` table (global), then link tournaments to these category IDs.

### Non-breaking migration strategy (recommended)

#### A) Add master table
Create `public.categories`:
- `id uuid pk`
- `name text`
- `type text` (kata/kumite/etc)
- `gender text`
- `age_group text`
- `weight_min numeric null`
- `weight_max numeric null`
- `weight_label text`
- `status text` (active/inactive)
- timestamps

#### B) Extend existing `public.tournament_categories`
Instead of replacing the table, **extend it**:
- add `category_ref_id uuid null references public.categories(id)`
- keep existing `discipline/gender/age_group/weight_class` as a **snapshot** for UI compatibility

Rule:
- New tournament category rows should be inserted from the master category selection:
  - set `category_ref_id`
  - also copy snapshot fields

#### C) Update admin “create tournament categories” flow
In `html/admin-dashboard.html`:
- Replace “manual typing” with **checkbox/multi-select list** loaded from `public.categories` (active only).
- On save:
  - insert rows into `public.tournament_categories` for selected categories (per tournament)
  - enforce at least 1 category before tournament can be activated (see validation section)

Files to touch:
- `html/admin-dashboard.html` (category selection UI + save logic)
- DB migration: create `public.categories`, add `category_ref_id`, add indexes + RLS

---

## PART 4 — Club Admin registration into categories (must be tournament-linked)

### Current state (already close)
`html/club-dashboard.html` already:
- Loads categories filtered by tournament: `tournament_categories where tournament_id = tid`
- Saves registration with `category_id`
- Validates required category selection when categories exist

### Required enhancements

#### A) Strong validation (DB-level)
Add/ensure constraint: selected `tournament_registrations.category_id` must belong to the same `tournament_id`.

Implementation:
- Add a trigger OR use a composite foreign key pattern with a unique constraint:
  - Create unique key on `tournament_categories (id, tournament_id)`
  - Reference `(category_id, tournament_id)` from registrations

#### B) UI validation improvements (no redesign)
In `club-dashboard.html`:
- If categories exist: keep category required (already done)
- If categories missing: show existing hint and prevent submission (or allow pending without category only if federation rules allow; spec says **must select valid category**)

Files to touch:
- `html/club-dashboard.html` (small guard so it cannot submit if categories are required but not loaded)
- DB migration: enforce category↔tournament consistency

---

## PART 5 — Referee+ format selection + bracket generation category-by-category

### Current state
`html/referee-dashboard.html` already supports:
- bracket type per category (`tournament_categories.bracket_type`)
- generator RPCs:
  - `referee_plus_generate_knockout_bracket(p_category_id)`
  - `referee_plus_generate_league_round_robin(p_category_id)` (phase6b)

### Gaps vs required spec
- Knockout generator currently enforces **power-of-two** player count (MVP).
- Spec requires **bye logic** for odd/non-power-of-two.

### Fix plan

#### A) Extend knockout generator to support byes
Update/replace the RPC in Supabase:
- Allow any \(n \ge 2\)
- Compute bracket size = next power of two \(N = 2^{\lceil \log_2(n)\rceil}\)
- Assign \(N-n\) byes in round 1 (auto-advance players or create walkover matches)
- Generate matches and `advances_to_match_id` links accordingly

#### B) UI messaging (no redesign)
In `referee-dashboard.html`:
- If generator returns “need at least 2” → show friendly message
- If generator can’t run (e.g., tournament live) → show clear error

Files to touch:
- `database/phase6_referee_plus.sql` (RPC logic)
- `html/referee-dashboard.html` (error messages only if needed)

---

## PART 6 — Regular Referee match operations (must be category-linked + bracket required)

### Current state
`referee-dashboard.html` already has “Match operations” with:
- tournament select
- category select (filtered by tournament)
- match table UI

### Required validations
- If no bracket/matches exist for selected category → show:
  - **“No bracket has been generated for this category yet.”**
- Block score/winner submit if no match row exists.

Implementation:
- In match load query, if `tournament_matches` returns empty → render the message.
- Ensure write policies allow assigned referees / Referee+ / SKF.

Files to touch:
- `html/referee-dashboard.html` (empty state + guardrails)
- DB policies already in `phase4_tournament_matches.sql` (confirm alignment)

---

## PART 7 — Ranking system integration (points from matches/results)

### Current state
No ranking tables/scripts exist in `database/` yet.
Player/club dashboards currently show “ranking” as **club roster sorted by belt** (not points).

### Plan (additive, no UI redesign)

#### A) Add tables
Create:
- `public.player_stats`
  - `(player_id, tournament_id, category_id)` unique
  - matches_played, wins, losses, points_scored, points_conceded, ranking_points, updated_at
- `public.rankings`
  - `(player_id, category_id)` unique
  - total_points, total_wins, total_losses, tournaments_played, rank_position, last_updated

#### B) Update stats on match completion
Add a trigger on `public.tournament_matches` after update when:
- `status = 'completed'`
- `winner_user_id` is set
- scores exist (optional)

The trigger function should:
- upsert `player_stats` for red and blue players
- add points:
  - participation: +5 (on first approved registration OR first match played; choose one consistent)
  - match win: +10
  - match loss: +0
  - champion/placing bonuses: computed when final is completed (optional in v1)

#### C) Compute category standings
Create an RPC `get_rankings(p_category_id, p_club_id null, p_gender null, ...)` returning rows sorted by points/wins.
Dashboards can call this and render into existing tables **without redesign**.

#### D) Visibility rules (RLS)
- Players can read rankings (public)
- Club admin can read rankings for club players
- SKF admin can read all

Files to touch:
- New SQL migration for ranking tables + trigger + RPC + RLS
- `html/player-dashboard.html` (replace belt-sort roster ranking with points ranking when available; fallback if table missing)
- `html/club-dashboard.html` (players ranking section uses ranking RPC; keep same table layout)
- `html/admin-dashboard.html` (add rankings view section or reuse existing “Reference/Reports” area; no layout changes)

---

## PART 8 — End-to-end flow mapping (what must work)

1. SKF Admin creates master categories (`public.categories`)
2. SKF Admin creates tournament (`public.tournaments`)
3. SKF Admin attaches categories (writes `public.tournament_categories` rows with `category_ref_id`)
4. Club Admin registers players per tournament/category (`public.tournament_registrations.category_id`)
5. Referee+ selects bracket type per category and generates matches (`public.tournament_matches`)
6. Referee operates matches (updates scores/status/winner)
7. DB auto-advances winners (existing trigger) and updates ranking/stat tables (new triggers)
8. Player/Coach/Club/SKF dashboards show rankings (read-only views)

---

## PART 9 — Validation rules (where to enforce)

### Tournament
- Tournament cannot be moved to “registration_open” unless at least **one** category exists.
  - Enforce via trigger on `tournaments.status` update.

### Registration
- Club Admin cannot register without a **valid tournament category**.
  - Enforce in UI (already mostly done) and DB constraint (tournament_id/category_id consistency).

### Brackets
- Referee+ cannot generate bracket if < 2 approved registrations.
  - Enforce in RPC (already for knockout; extend for byes).

### Match ops
- Referee cannot operate if no bracket exists.
  - Enforce in UI empty state + keep DB update policy limited to assigned refs.

### Ranking update
- Do not update ranking/stats if winner missing.
  - Enforce in trigger.

### Images/documents
- No image/document should ever break layout.
  - Enforce by CSS max sizes + PDF-as-link rule.

### Transfer offers
- No offer submit if player data not loaded.
  - Enforce UI disable + RLS read fix.

---

## DB migration files to add (recommended names)

Add new SQL files (do not delete existing):

- `database/phase7_categories_master.sql`
  - create `public.categories`
  - add `tournament_categories.category_ref_id`
  - indexes + RLS policies

- `database/phase7_registrations_category_fk.sql`
  - enforce `(tournament_id, category_id)` consistency

- `database/phase8_rankings.sql`
  - create `player_stats`, `rankings`
  - trigger on `tournament_matches` completion
  - RPC(s) for ranking views

- `database/phase8_transfer_public_cards.sql`
  - safe view/policies for club admins to read listing player cards

---

## Implementation order (recommended)

1. **PART 1 + PART 2** (UI bugs + safe rendering)
2. **PART 3 + PART 4** (categories normalization + registration validation)
3. **PART 5 + PART 6** (bracket generation byes + referee ops empty states)
4. **PART 7** (ranking + stats)

---

## Acceptance checklist (what you will test manually)

- Club admin: selecting a listed player always shows a readable player card and offer submit is blocked until loaded
- SKF admin: approval/detail pages never show oversized images; PDFs appear as links
- SKF admin: tournament categories come from DB selection (not manual typing), and saving attaches IDs
- Club admin: can register player only into categories linked to that tournament
- Referee+: can generate knockout bracket for odd counts (bye logic)
- Referee: cannot start ops without bracket; sees clear message
- After match completion: player stats + ranking points update and show in dashboards

