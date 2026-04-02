using SkfWebsite.Api.Models;

namespace SkfWebsite.Api.Services;

public interface ISupabaseService
{
    Task<Supabase.Client> GetClient();
    Task<User?> GetUserByEmail(string email);
    Task<User?> GetUserById(string id);
    Task<List<User>> GetAllUsers();
    Task<List<User>> GetPendingUsers();
    Task UpdateUserStatus(string userId, bool isActive);
    Task DeleteUser(string userId);
    Task<List<Tournament>> GetTournaments();
    Task<Tournament?> GetTournamentById(string id);
    Task<Tournament> CreateTournament(Tournament tournament);
    Task<List<TournamentRegistration>> GetTournamentRegistrations(string tournamentId);
    Task<TournamentRegistration> RegisterForTournament(TournamentRegistration registration);
}