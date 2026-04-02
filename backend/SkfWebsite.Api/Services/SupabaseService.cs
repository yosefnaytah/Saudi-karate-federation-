using SkfWebsite.Api.Models;
using Supabase;
using static Supabase.Postgrest.Constants;

namespace SkfWebsite.Api.Services;

public class SupabaseService : ISupabaseService
{
    private readonly IConfiguration _configuration;
    private readonly Client _supabaseClient;

    public SupabaseService(IConfiguration configuration)
    {
        _configuration = configuration;
        
        var options = new SupabaseOptions
        {
            AutoConnectRealtime = false
        };

        _supabaseClient = new Client(
            _configuration["Supabase:Url"]!,
            _configuration["Supabase:Key"]!,
            options);
    }

    public async Task<Client> GetClient()
    {
        // Initialize client if needed - no need to check CurrentUser
        await _supabaseClient.InitializeAsync();
        return _supabaseClient;
    }

    public async Task<User?> GetUserByEmail(string email)
    {
        var client = await GetClient();
        var result = await client
            .From<User>()
            .Where(x => x.Email == email)
            .Single();
        
        return result;
    }

    public async Task<User?> GetUserById(string id)
    {
        var client = await GetClient();
        var result = await client
            .From<User>()
            .Where(x => x.Id == id)
            .Single();
        
        return result;
    }

    public async Task<List<User>> GetAllUsers()
    {
        var client = await GetClient();
        var result = await client
            .From<User>()
            .Order(x => x.CreatedAt, Ordering.Descending)
            .Get();
        
        return result.Models;
    }

    public async Task<List<User>> GetPendingUsers()
    {
        var client = await GetClient();
        var result = await client
            .From<User>()
            .Where(x => x.IsActive == false)
            .Order(x => x.CreatedAt, Ordering.Descending)
            .Get();
        
        return result.Models;
    }

    public async Task UpdateUserStatus(string userId, bool isActive)
    {
        var client = await GetClient();
        var user = await GetUserById(userId);
        
        if (user != null)
        {
            user.IsActive = isActive;
            user.UpdatedAt = DateTime.UtcNow;
            
            await client
                .From<User>()
                .Where(x => x.Id == userId)
                .Update(user);
        }
    }

    public async Task DeleteUser(string userId)
    {
        var client = await GetClient();
        
        // Delete from custom users table
        await client
            .From<User>()
            .Where(x => x.Id == userId)
            .Delete();
        
        // Note: Supabase Auth user deletion requires admin API key
        // For now, we just mark them as inactive in the custom table
    }

    public async Task<List<Tournament>> GetTournaments()
    {
        var client = await GetClient();
        var result = await client
            .From<Tournament>()
            .Where(x => x.IsActive == true)
            .Order(x => x.StartDate, Ordering.Descending)
            .Get();
        
        return result.Models;
    }

    public async Task<Tournament?> GetTournamentById(string id)
    {
        var client = await GetClient();
        var result = await client
            .From<Tournament>()
            .Where(x => x.Id == id)
            .Single();
        
        return result;
    }

    public async Task<Tournament> CreateTournament(Tournament tournament)
    {
        var client = await GetClient();
        tournament.Id = Guid.NewGuid().ToString();
        tournament.CreatedAt = DateTime.UtcNow;
        tournament.UpdatedAt = DateTime.UtcNow;
        
        var result = await client
            .From<Tournament>()
            .Insert(tournament);
        
        return result.Models.First();
    }

    public async Task<List<TournamentRegistration>> GetTournamentRegistrations(string tournamentId)
    {
        var client = await GetClient();
        var result = await client
            .From<TournamentRegistration>()
            .Where(x => x.TournamentId == tournamentId)
            .Get();
        
        return result.Models;
    }

    public async Task<TournamentRegistration> RegisterForTournament(TournamentRegistration registration)
    {
        var client = await GetClient();
        registration.Id = Guid.NewGuid().ToString();
        registration.RegistrationDate = DateTime.UtcNow;
        registration.CreatedAt = DateTime.UtcNow;
        registration.UpdatedAt = DateTime.UtcNow;
        
        var result = await client
            .From<TournamentRegistration>()
            .Insert(registration);
        
        return result.Models.First();
    }
}