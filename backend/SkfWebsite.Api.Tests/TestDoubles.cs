using System.Net;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.FileProviders;
using SkfWebsite.Api.Models;
using SkfWebsite.Api.Services;

namespace SkfWebsite.Api.Tests;

internal sealed class FakeSupabaseService : ISupabaseService
{
    private readonly Dictionary<string, User> _usersById = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, Tournament> _tournamentsById = new(StringComparer.OrdinalIgnoreCase);
    private readonly List<TournamentReferee> _refereeAssignments = [];
    private readonly List<TournamentCategory> _categories = [];
    private readonly List<TournamentRegistration> _registrations = [];

    public Supabase.Client Client => throw new NotSupportedException("Supabase client is not available in unit tests.");

    public List<string> DeletedUserIds { get; } = [];
    public List<(string UserId, bool IsActive)> StatusUpdates { get; } = [];
    public List<Tournament> CreatedTournaments { get; } = [];
    public List<Tournament> UpdatedTournaments { get; } = [];
    public List<TournamentCategory> CreatedCategories { get; } = [];
    public List<TournamentRegistration> CreatedRegistrations { get; } = [];

    public void AddUser(User user) => _usersById[user.Id] = user;
    public void AddTournament(Tournament tournament) => _tournamentsById[tournament.Id] = tournament;
    public void AddRefereeAssignment(TournamentReferee assignment) => _refereeAssignments.Add(assignment);
    public void AddCategory(TournamentCategory category) => _categories.Add(category);
    public void AddRegistration(TournamentRegistration registration) => _registrations.Add(registration);

    public Task<Supabase.Client> GetClient() =>
        throw new NotSupportedException("Supabase client is not available in unit tests.");

    public Task<User?> GetUserByEmail(string email) =>
        Task.FromResult(_usersById.Values.FirstOrDefault(u => string.Equals(u.Email, email, StringComparison.OrdinalIgnoreCase)));

    public Task<User?> GetUserById(string id) =>
        Task.FromResult(_usersById.GetValueOrDefault(id));

    public Task<List<User>> GetAllUsers() => Task.FromResult(_usersById.Values.ToList());

    public Task<List<User>> GetPendingUsers() =>
        Task.FromResult(_usersById.Values.Where(u => !u.IsActive).ToList());

    public Task UpdateUserStatus(string userId, bool isActive)
    {
        StatusUpdates.Add((userId, isActive));
        if (_usersById.TryGetValue(userId, out var user))
        {
            user.IsActive = isActive;
        }
        return Task.CompletedTask;
    }

    public Task DeleteUser(string userId)
    {
        DeletedUserIds.Add(userId);
        _usersById.Remove(userId);
        return Task.CompletedTask;
    }

    public Task<List<Tournament>> GetTournaments() => Task.FromResult(_tournamentsById.Values.ToList());

    public Task<Tournament?> GetTournamentById(string id) =>
        Task.FromResult(_tournamentsById.GetValueOrDefault(id));

    public Task<Tournament> CreateTournament(Tournament tournament)
    {
        tournament.Id = string.IsNullOrWhiteSpace(tournament.Id) ? $"tournament-{CreatedTournaments.Count + 1}" : tournament.Id;
        CreatedTournaments.Add(tournament);
        _tournamentsById[tournament.Id] = tournament;
        return Task.FromResult(tournament);
    }

    public Task<Tournament> UpdateTournament(string id, Tournament tournament)
    {
        UpdatedTournaments.Add(tournament);
        _tournamentsById[id] = tournament;
        return Task.FromResult(tournament);
    }

    public Task<List<TournamentReferee>> GetRefereesByTournament(string tournamentId) =>
        Task.FromResult(_refereeAssignments.Where(a => a.TournamentId == tournamentId).ToList());

    public Task<List<Tournament>> GetTournamentsByReferee(string refereeId)
    {
        var tournamentIds = _refereeAssignments
            .Where(a => a.RefereeId == refereeId)
            .Select(a => a.TournamentId)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        return Task.FromResult(_tournamentsById.Values.Where(t => tournamentIds.Contains(t.Id)).ToList());
    }

    public Task<TournamentReferee> AssignRefereeToTournament(string tournamentId, string refereeId)
    {
        var assignment = new TournamentReferee
        {
            Id = $"assignment-{_refereeAssignments.Count + 1}",
            TournamentId = tournamentId,
            RefereeId = refereeId,
            AssignedAt = DateTime.UtcNow
        };
        _refereeAssignments.Add(assignment);
        return Task.FromResult(assignment);
    }

    public Task RemoveRefereeFromTournament(string tournamentId, string refereeId) => Task.CompletedTask;

    public Task<List<User>> GetRefereeUsers() =>
        Task.FromResult(_usersById.Values.Where(u => u.Role is "referee" or "referees_plus").ToList());

    public Task<List<TournamentCategory>> GetCategoriesByTournament(string tournamentId) =>
        Task.FromResult(_categories.Where(c => c.TournamentId == tournamentId).ToList());

    public Task<TournamentCategory> CreateCategory(TournamentCategory category)
    {
        category.Id = string.IsNullOrWhiteSpace(category.Id) ? $"category-{_categories.Count + 1}" : category.Id;
        CreatedCategories.Add(category);
        _categories.Add(category);
        return Task.FromResult(category);
    }

    public Task<TournamentCategory> UpdateCategory(string categoryId, TournamentCategory category)
    {
        category.Id = categoryId;
        var index = _categories.FindIndex(c => c.Id == categoryId);
        if (index >= 0) _categories[index] = category;
        return Task.FromResult(category);
    }

    public Task<TournamentCategory> SetCategoryFormat(string categoryId, string format)
    {
        var category = _categories.First(c => c.Id == categoryId);
        category.CompetitionFormat = format;
        return Task.FromResult(category);
    }

    public Task DeleteCategory(string categoryId)
    {
        _categories.RemoveAll(c => c.Id == categoryId);
        return Task.CompletedTask;
    }

    public Task<List<TournamentRegistration>> GetTournamentRegistrations(string tournamentId) =>
        Task.FromResult(_registrations.Where(r => r.TournamentId == tournamentId).ToList());

    public Task<List<TournamentRegistration>> GetRegistrationsByUser(string userId) =>
        Task.FromResult(_registrations.Where(r => r.UserId == userId).ToList());

    public Task<TournamentRegistration> RegisterForTournament(TournamentRegistration registration)
    {
        registration.Id = string.IsNullOrWhiteSpace(registration.Id) ? $"registration-{_registrations.Count + 1}" : registration.Id;
        CreatedRegistrations.Add(registration);
        _registrations.Add(registration);
        return Task.FromResult(registration);
    }
}

internal sealed class FakeWebHostEnvironment : IWebHostEnvironment
{
    public string EnvironmentName { get; set; } = "Development";
    public string ApplicationName { get; set; } = "SkfWebsite.Api.Tests";
    public string WebRootPath { get; set; } = string.Empty;
    public IFileProvider WebRootFileProvider { get; set; } = new NullFileProvider();
    public string ContentRootPath { get; set; } = Directory.GetCurrentDirectory();
    public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
}

internal sealed class FakeHttpClientFactory : IHttpClientFactory
{
    private readonly HttpClient _client;

    public FakeHttpClientFactory(HttpClient client)
    {
        _client = client;
    }

    public HttpClient CreateClient(string name) => _client;
}

internal sealed class StubHttpMessageHandler : HttpMessageHandler
{
    private readonly Func<HttpRequestMessage, HttpResponseMessage> _send;

    public StubHttpMessageHandler(Func<HttpRequestMessage, HttpResponseMessage> send)
    {
        _send = send;
    }

    public HttpRequestMessage? LastRequest { get; private set; }
    public string? LastRequestBody { get; private set; }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        LastRequest = request;
        LastRequestBody = request.Content == null
            ? null
            : await request.Content.ReadAsStringAsync(cancellationToken);
        return _send(request);
    }

    public static HttpClient CreateClient(HttpStatusCode statusCode, string content, out StubHttpMessageHandler handler)
    {
        handler = new StubHttpMessageHandler(_ => new HttpResponseMessage(statusCode)
        {
            Content = new StringContent(content)
        });
        return new HttpClient(handler);
    }
}
