using SkfWebsite.Api.Models;
using Supabase;
using static Supabase.Postgrest.Constants;

namespace SkfWebsite.Api.Services;

public class SupabaseService : ISupabaseService
{
    private readonly IConfiguration _configuration;
    private readonly Client _supabaseClient;

    public Client Client
    {
        get
        {
            // Some controllers use _supabaseService.Client directly (sync path).
            // Ensure the client is initialized to avoid runtime failures.
            _supabaseClient.InitializeAsync().GetAwaiter().GetResult();
            return _supabaseClient;
        }
    }

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

    public async Task<Tournament> UpdateTournament(string id, Tournament tournament)
    {
        var client = await GetClient();
        tournament.UpdatedAt = DateTime.UtcNow;

        var result = await client
            .From<Tournament>()
            .Where(x => x.Id == id)
            .Update(tournament);

        return result.Models.First();
    }

    public async Task<List<TournamentReferee>> GetRefereesByTournament(string tournamentId)
    {
        var client = await GetClient();
        var result = await client
            .From<TournamentReferee>()
            .Where(x => x.TournamentId == tournamentId)
            .Get();
        return result.Models;
    }

    public async Task<List<Tournament>> GetTournamentsByReferee(string refereeId)
    {
        var client = await GetClient();
        var assignments = await client
            .From<TournamentReferee>()
            .Where(x => x.RefereeId == refereeId)
            .Get();

        var ids = assignments.Models.Select(a => a.TournamentId).ToHashSet();
        if (!ids.Any()) return new List<Tournament>();

        var allTournaments = await client.From<Tournament>().Where(x => x.IsActive == true).Get();
        return allTournaments.Models.Where(t => ids.Contains(t.Id)).ToList();
    }

    public async Task<TournamentReferee> AssignRefereeToTournament(string tournamentId, string refereeId)
    {
        var client = await GetClient();
        var assignment = new TournamentReferee
        {
            Id = Guid.NewGuid().ToString(),
            TournamentId = tournamentId,
            RefereeId = refereeId,
            AssignedAt = DateTime.UtcNow
        };
        var result = await client.From<TournamentReferee>().Insert(assignment);
        return result.Models.First();
    }

    public async Task RemoveRefereeFromTournament(string tournamentId, string refereeId)
    {
        var client = await GetClient();
        var existing = await client
            .From<TournamentReferee>()
            .Where(x => x.TournamentId == tournamentId)
            .Where(x => x.RefereeId == refereeId)
            .Get();

        if (existing.Models.Any())
        {
            await client
                .From<TournamentReferee>()
                .Where(x => x.Id == existing.Models.First().Id)
                .Delete();
        }
    }

    public async Task<List<User>> GetRefereeUsers()
    {
        var client = await GetClient();
        var result = await client.From<User>().Get();
        return result.Models
            .Where(u => u.Role == "referee" || u.Role == "referees_plus")
            .ToList();
    }

    public async Task<List<TournamentCategory>> GetCategoriesByTournament(string tournamentId)
    {
        var client = await GetClient();
        var result = await client
            .From<TournamentCategory>()
            .Where(x => x.TournamentId == tournamentId)
            .Order(x => x.CreatedAt, Ordering.Ascending)
            .Get();

        return result.Models;
    }

    public async Task<TournamentCategory> CreateCategory(TournamentCategory category)
    {
        var client = await GetClient();
        category.Id = Guid.NewGuid().ToString();
        category.CreatedAt = DateTime.UtcNow;
        category.UpdatedAt = DateTime.UtcNow;

        var result = await client
            .From<TournamentCategory>()
            .Insert(category);

        return result.Models.First();
    }

    public async Task<TournamentCategory> UpdateCategory(string categoryId, TournamentCategory category)
    {
        var client = await GetClient();
        category.UpdatedAt = DateTime.UtcNow;

        var result = await client
            .From<TournamentCategory>()
            .Where(x => x.Id == categoryId)
            .Update(category);

        return result.Models.First();
    }

    public async Task<TournamentCategory> SetCategoryFormat(string categoryId, string format)
    {
        var client = await GetClient();

        var existing = (await client
            .From<TournamentCategory>()
            .Where(x => x.Id == categoryId)
            .Get()).Models.FirstOrDefault()
            ?? throw new Exception("Category not found.");

        existing.CompetitionFormat = format;
        existing.UpdatedAt = DateTime.UtcNow;

        var result = await client
            .From<TournamentCategory>()
            .Where(x => x.Id == categoryId)
            .Update(existing);

        return result.Models.First();
    }

    public async Task DeleteCategory(string categoryId)
    {
        var client = await GetClient();
        await client
            .From<TournamentCategory>()
            .Where(x => x.Id == categoryId)
            .Delete();
    }

    public async Task<List<TournamentRegistration>> GetRegistrationsByUser(string userId)
    {
        var client = await GetClient();
        var result = await client
            .From<TournamentRegistration>()
            .Where(x => x.UserId == userId)
            .Get();
        return result.Models;
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