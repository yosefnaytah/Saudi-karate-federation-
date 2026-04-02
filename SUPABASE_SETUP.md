# Supabase Setup Guide

## Your Supabase Project Details

✅ **Supabase URL**: `https://uqlpxdphikmmpdsuojil.supabase.co`

## Step 1: Get Your Supabase API Keys

1. Go to your Supabase Dashboard: https://supabase.com/dashboard
2. Select your project: `uqlpxdphikmmpdsuojil`
3. Go to **Settings** → **API**
4. You'll find:
   - **Project URL**: `https://uqlpxdphikmmpdsuojil.supabase.co` ✅ (Already configured)
   - **anon/public key**: This is your `Key` (starts with `eyJ...`)
   - **service_role key**: This is for admin operations (keep secret!)

## Step 2: Get Your JWT Secret

1. In Supabase Dashboard, go to **Settings** → **API**
2. Scroll down to **JWT Settings**
3. Copy the **JWT Secret** (this is a long string)

## Step 3: Update appsettings.json

Open `backend/SkfWebsite.Api/appsettings.json` and replace:

```json
{
  "Supabase": {
    "Url": "https://uqlpxdphikmmpdsuojil.supabase.co",
    "Key": "PASTE_YOUR_ANON_KEY_HERE",
    "JwtSecret": "PASTE_YOUR_JWT_SECRET_HERE"
  }
}
```

**Example:**
```json
{
  "Supabase": {
    "Url": "https://uqlpxdphikmmpdsuojil.supabase.co",
    "Key": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxbHB4ZHBoaWttbXBkc3VvamlsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MTIzNDU2NzgsImV4cCI6MjAyNzkyMTY3OH0.xxxxxxxxxxxx",
    "JwtSecret": "your-jwt-secret-string-here-very-long-random-string"
  }
}
```

## Step 4: Set Up Database Tables

1. Go to Supabase Dashboard → **SQL Editor**
2. Click **New Query**
3. Copy and paste the entire content from `database/supabase_schema.sql`
4. Click **Run** (or press Ctrl+Enter)
5. Verify tables are created:
   - Go to **Table Editor** → You should see:
     - `users`
     - `tournaments`
     - `tournament_registrations`
     - `clubs`
     - `news`

## Step 5: Test the Connection

1. Start your backend:
```bash
cd backend/SkfWebsite.Api
dotnet run
```

2. Check the console for any Supabase connection errors
3. If successful, you should see:
   - Backend running on `http://localhost:5000`
   - Swagger UI at `https://localhost:5001/swagger`

## Step 6: Create Your First Admin User

### Option A: Via Registration (Recommended)
1. Open `html/REGISTER.html` in browser
2. Fill in the form
3. Select role: **"Admin (SKF Admin)"**
4. Submit registration
5. Go to Supabase Dashboard → **Table Editor** → `users` table
6. Find your admin user
7. Set `is_active` to `true` (click the checkbox)
8. Now you can login!

### Option B: Direct Database Insert (Advanced)
1. Go to Supabase Dashboard → **Authentication** → **Users**
2. Create a new user manually
3. Copy the user ID
4. Go to **SQL Editor** and run:
```sql
INSERT INTO public.users (
    id, full_name, national_id, player_id, phone, 
    club_name, email, username, role, is_active
) VALUES (
    'USER_ID_FROM_AUTH', 
    'Admin User', 
    '1234567890', 
    'ADMIN001', 
    '0501234567', 
    'SKF', 
    'admin@skf.com', 
    'admin', 
    'admin', 
    true
);
```

## Troubleshooting

### Error: "Invalid API key"
- Make sure you're using the **anon/public key**, not the service_role key
- Check that the key is copied completely (they're very long)

### Error: "JWT Secret invalid"
- Make sure you copied the entire JWT Secret from Settings → API → JWT Settings
- It should be a long random string

### Error: "Table does not exist"
- Run the SQL schema script in Supabase SQL Editor
- Check that all tables are created in Table Editor

### Error: "Connection failed"
- Verify your Supabase URL is correct
- Check your internet connection
- Make sure Supabase project is active (not paused)

## Security Notes

⚠️ **IMPORTANT**: 
- Never commit `appsettings.json` with real keys to Git
- The `appsettings.json` file should be in `.gitignore`
- Use environment variables or `appsettings.Development.json` for local development
- Keep your JWT Secret and service_role key secret!

## Next Steps

Once connected:
1. ✅ Test registration endpoint
2. ✅ Test login endpoint  
3. ✅ Create admin user
4. ✅ Test admin dashboard
5. ✅ Start building features!
