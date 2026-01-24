# Saudi Karate Federation Website

A modern web platform for the Saudi Karate Federation built with C# ASP.NET Core and Supabase.

## 🏗️ Technology Stack

- **Backend**: C# ASP.NET Core 8.0
- **Database**: Supabase (PostgreSQL)
- **Authentication**: Supabase Auth with JWT
- **Frontend**: HTML/CSS/JavaScript (to be migrated to React Native)
- **Real-time**: Supabase Realtime for live tournament updates

## 🚀 Features

- ✅ User registration and authentication
- ✅ Role-based access control (Player, Referee, Coach, Administrator)
- ✅ Tournament management with real-time updates
- ✅ Tournament registration system
- ✅ Club management
- ✅ News and media center
- ✅ Bilingual support (Arabic/English)

## 📦 Setup Instructions

### 1. Supabase Setup

1. Create a new project at [supabase.com](https://supabase.com)
2. Run the SQL schema in `database/supabase_schema.sql` in your Supabase SQL Editor
3. Get your project URL, anon key, and JWT secret from Project Settings > API

### 2. Backend Setup

1. Update `appsettings.json` with your Supabase credentials:
```json
{
  "Supabase": {
    "Url": "https://your-project.supabase.co",
    "Key": "your-anon-key",
    "JwtSecret": "your-jwt-secret"
  }
}
```

2. Run the backend:
```bash
cd backend/SkfWebsite.Api
dotnet restore
dotnet run
```

### 3. Frontend Setup

The frontend is currently in the `html/` folder. Update the API URLs to point to your backend.

## 🔑 API Endpoints

### Authentication
- `POST /api/auth/register` - User registration
- `POST /api/auth/login` - User login
- `POST /api/auth/logout` - User logout

### Tournaments
- `GET /api/tournament` - Get all tournaments
- `GET /api/tournament/{id}` - Get tournament details
- `POST /api/tournament` - Create tournament (admin only)
- `POST /api/tournament/{id}/register` - Register for tournament

## 🗃️ Database Schema

### Users Table
- Personal information (name, national ID, player ID)
- Contact details (phone, email)
- Club affiliation
- Role-based permissions

### Tournaments Table
- Tournament details and scheduling
- Status tracking (upcoming, live, completed)
- Registration deadlines and fees

### Tournament Registrations Table
- User tournament registrations
- Weight categories and belt levels
- Payment status tracking

## 🔒 Security Features

- Row Level Security (RLS) policies
- JWT token authentication
- Role-based access control
- Input validation and sanitization

## 📱 Future Enhancements

- React Native mobile app
- Payment integration
- Real-time tournament brackets
- Live scoring system
- Push notifications

## 👨‍💻 Development Team

**Yosef Naytah**
- ID: 2143380
- Email: yosef.h.naytah@gmail.com

## 📄 License

© 2025 Saudi Karate Federation - All Rights Reserved