using SkfWebsite.Api.Models;

namespace SkfWebsite.Api.Services;

public interface ISupabaseService
{
    // Legacy convenience for controllers that use _supabaseService.Client directly.
    // Prefer GetClient() in new code (async initialization).
    Supabase.Client Client { get; }

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
    Task<Tournament> UpdateTournament(string id, Tournament tournament);
    Task<List<TournamentReferee>> GetRefereesByTournament(string tournamentId);
    Task<List<Tournament>> GetTournamentsByReferee(string refereeId);
    Task<TournamentReferee> AssignRefereeToTournament(string tournamentId, string refereeId);
    Task RemoveRefereeFromTournament(string tournamentId, string refereeId);
    Task<List<User>> GetRefereeUsers();
    Task<List<TournamentCategory>> GetCategoriesByTournament(string tournamentId);
    Task<TournamentCategory> CreateCategory(TournamentCategory category);
    Task<TournamentCategory> UpdateCategory(string categoryId, TournamentCategory category);
    Task<TournamentCategory> SetCategoryFormat(string categoryId, string format);
    Task DeleteCategory(string categoryId);
    Task<List<TournamentRegistration>> GetTournamentRegistrations(string tournamentId);
    Task<List<TournamentRegistration>> GetRegistrationsByUser(string userId);
    Task<TournamentRegistration> RegisterForTournament(TournamentRegistration registration);
}