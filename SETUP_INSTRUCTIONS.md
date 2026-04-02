# SKF Website Setup Instructions

## Prerequisites
1. .NET 8.0 SDK installed
2. Supabase account and project created
3. Node.js (optional, for frontend dev server)

## Step 1: Configure Supabase

1. Go to your Supabase project dashboard
2. Get your project URL and API keys:
   - Project URL: Found in Settings > API
   - Anon Key: Found in Settings > API
   - JWT Secret: Found in Settings > API > JWT Settings

3. Update `backend/SkfWebsite.Api/appsettings.json`:
```json
{
  "Supabase": {
    "Url": "https://your-project.supabase.co",
    "Key": "your-anon-key-here",
    "JwtSecret": "your-jwt-secret-here"
  }
}
```

## Step 2: Set Up Database

1. Go to Supabase SQL Editor
2. Run the SQL script from `database/supabase_schema.sql`
3. This will create all necessary tables and policies

## Step 3: Run the Backend

1. Open terminal in the backend folder:
```bash
cd backend/SkfWebsite.Api
```

2. Restore packages:
```bash
dotnet restore
```

3. Run the backend:
```bash
dotnet run
```

The backend will start on:
- HTTP: `http://localhost:5000`
- HTTPS: `https://localhost:5001`
- Swagger UI: `https://localhost:5001/swagger`

## Step 4: Update Frontend API URL (if needed)

If your backend runs on a different port, update:
- `html/auth.js` - Line 2: `const API_BASE_URL = 'http://localhost:5000/api';`
- `html/admin-dashboard.html` - Line 560: `const API_BASE_URL = 'http://localhost:5000/api';`

## Step 5: Access the Website

### Option A: Using Backend (Recommended)
The backend serves static files, so you can access:
- `http://localhost:5000/index.html` (Login)
- `http://localhost:5000/admin-dashboard.html` (Admin Dashboard)

### Option B: Using Live Server (VS Code)
1. Install "Live Server" extension in VS Code
2. Right-click on `html/index.html`
3. Select "Open with Live Server"
4. The frontend will run on `http://127.0.0.1:5500`

## Step 6: Create Admin User

1. Go to registration page: `REGISTER.html`
2. Fill in the form
3. Select role: **"Admin (SKF Admin)"**
4. Submit registration
5. **Important**: For admin users, you need to manually set `is_active = true` in Supabase database, OR use the admin approval feature once you have one admin account active.

### Quick Admin Setup via Supabase:
1. Go to Supabase Dashboard > Table Editor > `users` table
2. Find your admin user
3. Set `is_active` to `true`
4. Now you can login as admin!

## Testing the Admin Dashboard

1. Make sure backend is running (`dotnet run`)
2. Login with admin credentials at `index.html`
3. You should be redirected to `admin-dashboard.html`
4. The dashboard will show:
   - Total users
   - Pending approvals
   - Active tournaments
   - All management sections

## Troubleshooting

### CORS Errors
- Make sure backend CORS is configured correctly in `Program.cs`
- Check that your frontend origin is in the allowed origins list

### Authentication Errors
- Verify Supabase credentials in `appsettings.json`
- Check that JWT secret matches your Supabase project
- Ensure database tables are created correctly

### API Connection Errors
- Verify backend is running on correct port
- Check API_BASE_URL in frontend files matches backend port
- Test API endpoints in Swagger UI: `https://localhost:5001/swagger`

### Admin Dashboard Shows "Please Login"
- Make sure you logged in through `index.html` first (this sets localStorage token)
- Check browser console for errors
- Verify token is stored: Open DevTools > Application > Local Storage

## API Endpoints

### Auth
- `POST /api/auth/register` - Register new user
- `POST /api/auth/login` - Login user
- `POST /api/auth/logout` - Logout user

### Admin (Requires Admin Role)
- `GET /api/admin/users` - Get all users
- `GET /api/admin/users/{id}` - Get user by ID
- `PUT /api/admin/users/{id}/approve` - Approve user
- `DELETE /api/admin/users/{id}/reject` - Reject user
- `PUT /api/admin/users/{id}/status` - Update user status

### Tournaments
- `GET /api/tournament` - Get all tournaments
- `GET /api/tournament/{id}` - Get tournament by ID
- `POST /api/tournament` - Create tournament (requires auth)
- `GET /api/tournament/{id}/registrations` - Get tournament registrations
- `POST /api/tournament/{id}/register` - Register for tournament

## Next Steps

1. Test all admin features
2. Create test users with different roles
3. Test approval workflow
4. Add more features as needed
