# SKF Website (Saudi Karate Federation)

This repository contains the source code for the Saudi Karate Federation (SKF) website. It includes a modern web frontend and a robust .NET 8 backend, leveraging Supabase for authentication and database management.

## Project Structure
- **/backend**: .NET 8 Web API providing authenticated endpoints and management logic.
- **/html**: The static frontend pages (index, dashboards, auth views, responsive UI).
- **/css**: Styling and visual themes for the frontend components.
- **/database**: SQL schema definitions, triggers, and Supabase functions for seamless data orchestration.
- **/supabase**: Configurations for local and remote edge functions and Supabase CLI.

## Quick Links to Documentation
- **[Setup Instructions](SETUP_INSTRUCTIONS.md)**: Detailed guide on how to configure Supabase, launch the backend, and run the website locally.
- **[Supabase Setup](SUPABASE_SETUP.md)**: Steps regarding Supabase schema execution, table setup, and storage configuration.
- **[Authentication Implementation](AUTH_IMPLEMENTATION.md)**: Breakdown of how users, roles, and profiles are wired up security-wise.
- **[Frontend Status Overview](frontend-status.md)**: Status of html pages, integration points, and overall completeness.

## Getting Started

1. **Backend**: Navigate to `backend/SkfWebsite.Api`, configure your `appsettings.json`, and run `dotnet run`.
2. **Frontend**: Launch the `/html` directory using Go Live (VS Code Live Server) or the integrated backend static file hosting at port `5000`.
3. **Database**: Import the schemas found in `/database` to your Supabase project.

For extensive details, please start with [SETUP_INSTRUCTIONS.md](SETUP_INSTRUCTIONS.md).