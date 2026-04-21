# Supabase setup — step by step

Do this in the **Supabase Dashboard** for the **same project** your site uses (`auth.js` URL). Use **SQL Editor** for each script unless noted.

Run scripts **once**; re-running is safe when they use `IF NOT EXISTS` / `CREATE OR REPLACE`.

---

## Part A — Database (run in this order)

### 1) Roles on `public.users` (fixes staff signup “database error”)

Open `database/users_role_add_skf_admin.sql` → copy all → **Run**.

### 2) Staff application table + RLS

Open `database/skf_applications.sql` → copy all → **Run**.

### 3) Seven-digit official ID counter + RPC

Open `database/rpc_next_skf_official_id.sql` → copy all → **Run**.

### 4) Admin login resolution (email or 7-digit ID)

Open `database/rpc_resolve_skf_admin_login_id.sql` → copy all → **Run**.

### 5) Profile row on every Auth signup

Open `database/supabase_player_profile_columns.sql` → copy all → **Run**.

### 6) Pending row in `skf_applications` on staff signup

Open `database/skf_staff_signup_application_trigger.sql` → copy all → **Run**.

### 7) Auto `skf_official_id` when you flip `is_active` to true (staff)

Open `database/trigger_users_skf_id_on_activate.sql` → copy all → **Run**.

### 8) Optional — SKF admin policies (if you use the dashboard from the browser)

Run these **after** you have at least one `skf_admin` user, if the repo documents them:

- `database/supabase_rls_skf_admin_read_users.sql`
- `database/supabase_rls_skf_admin_manage_users.sql` (if present)

If something already exists, errors like “policy already exists” → use `DROP POLICY IF EXISTS` versions from the files or skip.

---

## Part B — Sanity checks (SQL Editor)

**Triggers on `auth.users`:**

```sql
SELECT tgname
FROM pg_trigger
WHERE tgrelid = 'auth.users'::regclass
  AND NOT tgisinternal
ORDER BY 1;
```

You should see triggers such as `on_auth_user_created_profile` and `on_auth_user_skf_staff_application`.

**Trigger on `public.users` (activation ID):**

```sql
SELECT tgname
FROM pg_trigger
WHERE tgrelid = 'public.users'::regclass
  AND NOT tgisinternal
ORDER BY 1;
```

You should see `users_assign_skf_id_on_activate`.

---

## Part C — Auth settings (Dashboard clicks)

1. **Authentication → Providers → Email**  
   - Turn on **Confirm email** if you want the same behaviour as your HTML copy.

2. **Authentication → URL configuration**  
   - **Site URL**: e.g. `http://127.0.0.1:5500` or your real site.  
   - **Redirect URLs**: add every URL you use for `auth-callback.html` / `emailRedirectTo` (local + production).

3. **Authentication → Email templates** (optional)  
   - Adjust wording/branding, or leave defaults.

---

## Part D — Email when `is_active` becomes true (SKF ID)

Postgres **cannot** send mail by itself. Use **Database Webhook → Edge Function → Resend** (or another provider).

### D1 — Resend

1. Create a free account at [resend.com](https://resend.com).  
2. Create an **API key**.  
3. For quick tests you can send **from** `onboarding@resend.dev` (Resend limits **to** addresses on the free tier — read their current rules).  
4. For production, **verify your domain** in Resend and use e.g. `SKF <noreply@yourdomain.com>`.

### D2 — Deploy the Edge Function

1. Install [Supabase CLI](https://supabase.com/docs/guides/cli).  
2. In a terminal, from the **repo root** (this folder):

   ```bash
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   ```

   `YOUR_PROJECT_REF` is the short id in the Supabase URL (`https://YOUR_PROJECT_REF.supabase.co`).

3. Deploy:

   ```bash
   supabase functions deploy send-staff-activated --no-verify-jwt
   ```

   (`--no-verify-jwt` so the **Database Webhook** can POST without a user JWT. Protect with `x-hook-secret` below.)

4. In **Dashboard → Edge Functions → send-staff-activated → Secrets**, add:

   | Secret | Example |
   |--------|--------|
   | `RESEND_API_KEY` | `re_...` |
   | `RESEND_FROM` | `SKF <onboarding@resend.dev>` or your verified sender |
   | `INTERNAL_HOOK_SECRET` | long random string (optional but recommended) |

### D3 — Database Webhook

1. **Dashboard → Database → Webhooks** (or **Integrations → Database Webhooks** — name varies by UI version).  
2. **Create a new webhook**  
   - **Table**: `public.users`  
   - **Events**: **Update**  
   - **HTTP Request**: `POST`  
   - **URL**:  
     `https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-staff-activated`  
   - **HTTP Headers** (if you set `INTERNAL_HOOK_SECRET`):  
     - Name: `x-hook-secret`  
     - Value: same string as the secret  

3. Optional **filter** (reduces calls). If the UI supports a SQL condition, something like:

   ```sql
   record.is_active IS TRUE
   AND (old_record.is_active IS DISTINCT FROM TRUE)
   ```

   (Exact “condition” syntax depends on your Supabase version — if unsure, skip the filter; the function skips irrelevant rows.)

4. Save. Toggle a test **staff** user **inactive → active** in Table Editor; you should get one email with their **SKF ID**.

---

## Part E — What you do day to day

1. New **SKF admin / Referees+**: `registration.html` → staff link → `skf-staff-register.html?role=...`.  
2. Row appears in **`public.users`** (`is_active` false) and **`skf_applications`** (pending) if triggers ran.  
3. You **approve** either by:  
   - **Table Editor**: set `is_active` **true** → trigger fills **`skf_official_id`** → webhook sends email **if Part D is done**, or  
   - **Admin dashboard + API** approve flow (still recommended for consistency with `skf_applications`).

If `skf_applications` is not used for a given user, API approve is optional; the **ID + email** path still works once Part **A7** + **D** exist.

---

## If something fails

- **Auth → Logs** and **Database → Postgres logs** for the exact error.  
- Staff signup with no row in `skf_applications` → re-run **A6** and confirm staff URL has `?role=`.  
- “Could not allocate SKF ID” from API → re-run **A3**.  
- Edge function 401 → `x-hook-secret` header must match `INTERNAL_HOOK_SECRET`.  
- Resend 403 → domain / “from” address not allowed on your Resend plan.
