# SKF Implementation Plan — Remaining Modules

**Document type:** Implementation plan (planning only — no code in this file)  
**Project:** Saudi Karate Federation (SKF) digital platform  
**Scope:** Missing work only; assumes auth, basic registration, and tournament scaffolding may already exist.  
**Last updated:** For step-by-step execution — each section can become a standalone implementation prompt.

---

## Table of contents

1. [Architecture notes](#1-architecture-notes)  
2. [Dependency overview](#2-dependency-overview)  
3. [Module breakdown](#3-module-breakdown)  
4. [Sprint plan](#4-sprint-plan)  
5. [User stories](#5-user-stories)  
6. [Technical documentation checklist](#6-technical-documentation-checklist)  
7. [Priority legend](#7-priority-legend)  
8. [Recommended implementation order](#8-recommended-implementation-order)  
9. [First sprint to start](#9-first-sprint-to-start)  
10. [Safest dependency-based build sequence](#10-safest-dependency-based-build-sequence)

---

## 1. Architecture notes

- **Identity:** Supabase `auth.users` + `public.users` remain the source of truth for accounts and roles.  
- **Profiles:** Shared `profiles` table (e.g. `avatar_url` only in DB; files in Storage). Role-specific tables (`player_profiles`, etc.) hold non-global fields.  
- **Clubs:** First-class `clubs` entity with status; no player “club” as a single free-text field for authoritative membership.  
- **Player–club link:** **Contracts** table(s) as the only authoritative link; history via contract lifecycle, not overwrites.  
- **Time:** Store `timestamptz` in UTC in Postgres; **display** and **business rules** for “day” in **Asia/Riyadh** (`Asia/Riyadh`).  
- **Ranking:** Derived from tournament **results** + **category** dimensions (age + weight); materialized or computed leaderboard tables optional for performance.  
- **Dashboard:** SKF Admin is a **hub** — reads/writes across users, clubs, contracts, tournaments, and rankings via RLS + service role where appropriate.

---

## 2. Dependency overview

| Must exist first | Enables |
|------------------|---------|
| Profile + Storage (avatars) | Match UI, search by photo context, consistent player cards |
| Categories (age + weight) canonical tables | Tournament brackets, registrations, ranking dimensions |
| Clubs + status + Club Admin link | Contracts, filters, club-scoped admin |
| Contracts + approval workflow | Current club, history, transfers |
| Tournament results (structured) | Ranking engine |
| Riyadh time + event state rules | Upcoming / live / finished UX |

**Rule of thumb:** Data model and RLS before heavy UI; categories before ranking; contracts before “current club” business logic.

---

## 3. Module breakdown

### Module 1 — Profile system

| Aspect | Detail |
|--------|--------|
| **Purpose** | Single shared presentation layer per user; role-specific extensions; avatars only as URLs pointing to Storage. |
| **What to build** | `profiles` (shared); `player_profiles` / optional `referee_profiles` / `coach_profiles` / `club_admin_profiles`; migration path from any legacy columns on `users`; post-login upload flow for images. |
| **Backend** | Supabase Storage buckets + policies; RPC or direct `update` to `profiles.avatar_url`; optional Edge Function for virus scan / size limits later. |
| **Frontend** | Remove or disable registration-time image upload if still present; “Complete profile” / avatar step after login for **players** (required); optional for other roles. |
| **Database** | Tables above; FK `user_id` → `public.users(id)`; RLS: user owns row; SKF Admin read/update where policy allows. |
| **Integration** | Match UI and search consume `avatar_url`; fallback image if null (non-players). |
| **Priority** | **Critical** |

---

### Module 2 — Club management

| Aspect | Detail |
|--------|--------|
| **Purpose** | Clubs are managed entities, not arbitrary text; only SKF Admin creates/approves; Club Admin tied to one club. |
| **What to build** | `clubs` with `status` (e.g. `pending`, `approved`, `suspended`, `rejected`); optional metadata (name, city, license); `club_admin` ↔ `club_id` on profile or junction table. |
| **Backend** | Insert/update clubs restricted to SKF Admin (RLS + role check); audit fields. |
| **Frontend** | SKF Admin: create/edit club, change status; Club Admin: read own club, no create club. |
| **Database** | `clubs` table; indexes on `status`, `name`; FK from club admin profile to `clubs.id`. |
| **Integration** | Contract module references `club_id`; player never “picks club” without contract flow. |
| **Priority** | **Critical** |

---

### Module 3 — Player–club relationship (contracts)

| Aspect | Detail |
|--------|--------|
| **Purpose** | Authoritative membership and history via **contracts**, not `users.club_name` alone. |
| **What to build** | Contract records: player, club, effective dates, status (`draft`, `active`, `ended`, `superseded`); history queryable (no destructive overwrite of past). |
| **Backend** | Queries: “current contract” = active row per player; list previous by end date. |
| **Frontend** | Player sees current club from contract; history read-only list. |
| **Database** | `player_club_contracts` (or `contracts`) with constraints: one **active** per player at a time (partial unique index). |
| **Integration** | Transfer module creates new contract and ends old; admin dashboard filters “by club” use contract, not text field. |
| **Priority** | **Critical** |

---

### Module 4 — Contract / transfer system

| Aspect | Detail |
|--------|--------|
| **Purpose** | Controlled moves between clubs with documents and SKF approval. |
| **What to build** | Transfer **requests** table: player, target club, documents Storage paths, status (`pending`, `approved`, `rejected`); on approve: transaction — end old contract, insert new active contract, optional notifications. |
| **Backend** | Approval action callable only by SKF Admin; idempotent approve; audit log optional. |
| **Frontend** | Player: submit request + upload; Admin: queue + detail + approve/reject. |
| **Database** | `transfer_requests` + FKs; Storage URLs in DB only. |
| **Integration** | Depends on Module 2 (clubs) and Module 3 (contract schema). |
| **Priority** | **Critical** |

---

### Module 5 — SKF Admin dashboard (core)

| Aspect | Detail |
|--------|--------|
| **Purpose** | Single operational surface for users, clubs, contracts, approvals, and discovery. |
| **What to build** | Sections/pages: Users (search, filters), Clubs, Transfer requests, Contracts overview, Pending approvals (users + transfers), Tournament hooks; reuse existing dashboard shell where possible. |
| **Backend** | Supabase queries with filters (club, weight, category from **canonical** fields / contracts / registrations); respect RLS or service role for admin-only aggregates. |
| **Frontend** | Data tables, filters, detail drawers, action buttons; loading/error states. |
| **Database** | No single new table if modules 1–4 exist; may need **views** for “current club per player” for fast filtering. |
| **Integration** | Wires all modules; search system (Module 11) may power same API layer. |
| **Priority** | **Critical** |

---

### Module 6 — Tournament system (integration)

| Aspect | Detail |
|--------|--------|
| **Purpose** | Existing tournaments feed **results** into **ranking** and **match UI**. |
| **What to build** | Normalize result entry (winner, positions, category id); link registration to age/weight category IDs; avoid duplicate category strings across features. |
| **Backend** | Result write endpoints or RPCs; validation against tournament category. |
| **Frontend** | Admin/referee result capture; public read for schedules/results. |
| **Database** | Result tables or extension of `tournament_registrations` / match tables — align with Module 7. |
| **Integration** | Ranking job reads results + category keys. |
| **Priority** | **Important** |

---

### Module 7 — Categories system

| Aspect | Detail |
|--------|--------|
| **Purpose** | Canonical **age** and **weight** (and discipline if needed) for players, tournaments, and rankings. |
| **What to build** | Reference tables or enums: `age_categories`, `weight_categories` (or combined `competition_categories` with type); map player eligibility; tournament categories FK to same. |
| **Backend** | CRUD (SKF Admin); seed defaults (SKF rules). |
| **Frontend** | Dropdowns driven by DB; admin maintenance page. |
| **Database** | FKs from `player_profiles` / registrations / results to category IDs. |
| **Integration** | Required before ranking (Module 10) and clean tournament integration (Module 6). |
| **Priority** | **Critical** (foundational) |

---

### Module 8 — Time system

| Aspect | Detail |
|--------|--------|
| **Purpose** | Consistent **Asia/Riyadh** behavior for display and “what is live now.” |
| **What to build** | Convention: `timestamptz` storage; client (and server if any) format with `Asia/Riyadh`; helpers for “start of day” in Riyadh for queries if needed. |
| **Backend** | Document; optional DB session `SET TIME ZONE` only if generating local reports in SQL. |
| **Frontend** | `Intl` / `date-fns-tz` (or similar) for labels; countdowns for upcoming. |
| **Database** | All event/match columns `timestamptz`. |
| **Integration** | Match UI (Module 9) and tournament lists use same helpers. |
| **Priority** | **Important** |

---

### Module 9 — Upcoming matches UI

| Aspect | Detail |
|--------|--------|
| **Purpose** | Show **P1 vs P2** cards with **avatars** from profile, **time** (Riyadh), **status**, **results** when done. |
| **What to build** | `matches` or reuse tournament structure; read `profiles.avatar_url`; state machine: scheduled → live → completed. |
| **Backend** | Queries joining users + profiles + match row; optional realtime subscription. |
| **Frontend** | Card component; responsive layout; loading states. |
| **Database** | Match rows linked to tournament and category; FK to players. |
| **Integration** | Depends on Module 1 (avatars) and Module 8 (time display). |
| **Priority** | **Important** |

---

### Module 10 — Ranking system (core)

| Aspect | Detail |
|--------|--------|
| **Purpose** | Points from **placement** at tournaments; leaderboard **per weight** and **per age** (and combined rules as SKF defines). |
| **What to build** | Points table by rank (configurable); `ranking_snapshots` or `player_ranking_points` + aggregation job (trigger or cron); UI: leaderboard + player detail ranking history. |
| **Backend** | Idempotent “recalculate after results import”; tie-break rules documented. |
| **Frontend** | Leaderboard pages; filters by category dimensions. |
| **Database** | Fact table for event results; summary tables for fast reads. |
| **Integration** | Depends on Module 6 (results), Module 7 (categories). |
| **Priority** | **Critical** (product differentiator) |

---

### Module 11 — Search system

| Aspect | Detail |
|--------|--------|
| **Purpose** | SKF Admin (and optionally public) **full player database search** with filters. |
| **What to build** | Search by name, SKF ID, email, club (via contract), category; pagination; debounced queries. |
| **Backend** | Postgres `ILIKE` + trigram (`pg_trgm`) optional; or Supabase full-text; indexes on searched columns. |
| **Frontend** | Search bar + filter chips; results table/cards. |
| **Database** | Indexes; views for “searchable player” including current club from contract. |
| **Integration** | Admin dashboard embeds same component. |
| **Priority** | **Important** |

---

### Module 12 — File system

| Aspect | Detail |
|--------|--------|
| **Purpose** | **Secure** uploads for **avatars** and **contract documents**; URLs in DB only. |
| **What to build** | Buckets: e.g. `avatars`, `contracts`; path rules `{user_id}/...`; signed URL for private docs; size/MIME policies; RLS Storage policies aligned with `auth.uid()`. |
| **Backend** | Upload via client SDK with limited token; optional Edge Function for scanning later. |
| **Frontend** | Upload components with progress and validation. |
| **Database** | Columns store path or public URL only. |
| **Integration** | Module 1 and Module 4 consume this. |
| **Priority** | **Critical** |

---

## 4. Sprint plan

### Sprint A — Foundations: profile, storage, categories, time

| Field | Content |
|-------|---------|
| **Name** | Sprint A — Data foundations |
| **Goal** | Establish canonical profile and category data and secure files so all other modules have stable FKs and URLs. |
| **Features** | Shared + role profile tables; Storage buckets/policies; age/weight category tables + seed; Riyadh display helpers spec; remove registration-time photo if applicable. |
| **Deliverables** | SQL migrations applied; Storage tested; player mandatory avatar after login; category CRUD for admin; short README for timezone convention. |
| **Priority mix** | Critical: 1, 7, 12, 8. |

---

### Sprint B — Clubs & contracts

| Field | Content |
|-------|---------|
| **Name** | Sprint B — Clubs and contractual membership |
| **Goal** | SKF Admin controls clubs; player membership only through contracts with history. |
| **Features** | `clubs` + status; club admin link; contract table + “current club” logic; migration from legacy `club_name` if needed. |
| **Deliverables** | Admin club UI; data migration script optional; read APIs/views for current club. |
| **Priority mix** | Critical: 2, 3. |

---

### Sprint C — Transfers & approvals

| Field | Content |
|-------|---------|
| **Name** | Sprint C — Transfer pipeline |
| **Goal** | End-to-end transfer requests with documents and approval updating contracts automatically. |
| **Features** | `transfer_requests`; upload to Storage; approve/reject; transactional contract update. |
| **Deliverables** | Player request UI; admin queue; audit trail optional. |
| **Priority mix** | Critical: 4. |

---

### Sprint D — Admin dashboard & search

| Field | Content |
|-------|---------|
| **Name** | Sprint D — SKF Admin control surface |
| **Goal** | One dashboard to manage users, clubs, contracts, and find players quickly. |
| **Features** | Unified search; filters by club/category; embed approval flows; contract list. |
| **Deliverables** | Dashboard pages wired to DB; performance baseline on search. |
| **Priority mix** | Critical: 5; Important: 11. |

---

### Sprint E — Tournaments, matches, results

| Field | Content |
|-------|---------|
| **Name** | Sprint E — Competition layer |
| **Goal** | Tournaments integrated with category IDs and structured results for downstream ranking. |
| **Features** | Result entry; match entities; upcoming/live/finished; PvP cards with avatars. |
| **Deliverables** | Result import path; match UI; time display in Riyadh. |
| **Priority mix** | Important: 6, 9; depends on 1, 7, 8. |

---

### Sprint F — Ranking & leaderboards

| Field | Content |
|-------|---------|
| **Name** | Sprint F — Rankings |
| **Goal** | Points from placements; leaderboards per age and weight; player history. |
| **Features** | Configurable points; recompute job; leaderboard UI. |
| **Deliverables** | Ranking tables populated from tournament results; public or admin-facing boards as required. |
| **Priority mix** | Critical: 10; depends on 6, 7. |

---

## 5. User stories

### Profile & files

- **As a Player**, I want to upload my profile photo after I log in so my identity is visible in matches and lists, and I understand it is required to participate.  
- **As an SKF Admin**, I want all player avatars stored consistently so search and match cards show the correct image.  
- **As a Referee**, I want my photo to be optional so I can use the system without uploading an image.

### Clubs & contracts

- **As an SKF Admin**, I want to create clubs and set their status so only approved clubs appear in official flows.  
- **As a Club Admin**, I want to be associated with exactly my club so I see club-scoped data.  
- **As a Player**, I want my club membership to follow federation rules via contracts so my history is clear when I transfer.

### Transfers

- **As a Player**, I want to submit a transfer request with documents so SKF can approve my move to another club.  
- **As an SKF Admin**, I want to approve or reject requests so the system updates contracts without manual DB edits.

### Dashboard & search

- **As an SKF Admin**, I want to search and filter players by club, category, and status so I can run the federation efficiently.  
- **As an SKF Admin**, I want to open transfer requests and user approvals from one place.

### Tournaments & ranking

- **As an SKF Admin**, I want tournament results to feed rankings so points and leaderboards stay fair and automatic.  
- **As a Player**, I want to see my ranking by age and weight category so I understand my standing.

### Matches UI

- **As a spectator**, I want to see both players, photos, time in Riyadh, and results so I can follow the event.

---

## 6. Technical documentation checklist

When implementing, produce or update:

| Section | Contents |
|---------|----------|
| **Architecture** | Diagram: Auth → users → profiles → contracts → clubs; event flow for transfers. |
| **Database** | ERD; indexes; RLS summary; views for current club and search. |
| **API / services** | Supabase RPC list; Edge Functions list; what runs client-side only. |
| **UI** | Component map (dashboard, player flow, match card); design tokens for SKF branding. |
| **Security** | Storage policies; admin-only mutations; document access for contracts. |
| **Testing** | E2E: approve transfer; upload avatar; ranking recompute after mock result; timezone spot checks. |

---

## 7. Priority legend

| Label | Meaning |
|-------|---------|
| **Critical** | Blocks other modules or core federation integrity (profiles, clubs, contracts, transfers, admin hub, categories, ranking, files). |
| **Important** | Strong user value; can follow once foundations exist (tournament integration, match UI, search polish, time UX). |
| **Later** | Nice-to-have extensions (advanced analytics, exports, mobile app-specific). |

*Everything in this plan’s scope is at least **Important** or **Critical**; “Later” reserved for items you add outside this document.*

---

## 8. Recommended implementation order

1. **Module 12** (file system) + **Module 1** (profiles) — minimal vertical slice: upload avatar after login.  
2. **Module 7** (categories) — reference data for everything else.  
3. **Module 8** (time) — conventions before match/tournament UI hardens.  
4. **Module 2** (clubs) + **Module 3** (contracts) — club truth and membership model.  
5. **Module 4** (transfers) — approval pipeline on top of contracts.  
6. **Module 5** (dashboard) + **Module 11** (search) — operational control.  
7. **Module 6** (tournament integration) + **Module 9** (match UI).  
8. **Module 10** (ranking) — after results exist in structured form.

---

## 9. First sprint to start

**Start with Sprint A — Data foundations** (profile + Storage + categories + time + file rules).

**Why:** It does not depend on contracts or clubs yet, but every later module depends on **avatars**, **categories**, and **secure files**. Completing Sprint A first avoids rework when connecting tournaments and rankings.

---

## 10. Safest dependency-based build sequence

```text
Storage (12) ─┬─► Profile avatars (1)
              └─► Contract docs (4)

Categories (7) ─► Tournament integration (6) ─► Results shape ─► Ranking (10)
                └► Player/eligibility filters (5, 11)

Clubs (2) ─► Contracts (3) ─► Transfers (4) ─► Dashboard approvals (5)

Profile avatars (1) ─► Match cards (9)
Time convention (8) ─► Match & tournament lists (6, 9)
```

**Linear “safe” chain for core federation logic:**  
**(12 → 1) → 7 → 2 → 3 → 4 → 5 → (6 → 9) → 10**, with **8** parallel once DB timestamps are consistent.

---

## Appendix — Using this document

- Copy **one module section** (or one sprint) into a new implementation prompt when you are ready to build.  
- Keep **database migrations** versioned and applied in order per Section 8.  
- Revisit **dependencies** before starting each sprint to avoid blocking work.

---

*End of SKF Implementation Plan (remaining modules only).*
