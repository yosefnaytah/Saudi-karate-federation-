using SkfWebsite.Api.Models;
using Supabase;

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
            AutoConnectRealtime = true
        };

        _supabaseClient = new Client(
            _configuration["Supabase:Url"]!,
            _configuration["Supabase:Key"]!,
            options);
    }

    public async Task<Client> GetClient()
    {
        if (!_supabaseClient.Auth.CurrentUser?.IsAuthenticated ?? true)
        {
            await _supabaseClient.InitializeAsync();
        }
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

    public async Task<List<Tournament>> GetTournaments()
    {
        var client = await GetClient();
        var result = await client
            .From<Tournament>()
            .Where(x => x.IsActive == true)
            .Order(x => x.StartDate, Postgrest.Constants.Ordering.Descending)
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