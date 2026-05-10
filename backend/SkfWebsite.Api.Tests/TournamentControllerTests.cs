using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using SkfWebsite.Api.Controllers;
using SkfWebsite.Api.DTOs;
using SkfWebsite.Api.Models;
using Xunit;

namespace SkfWebsite.Api.Tests;

public class TournamentControllerTests
{
    private static readonly DateTime RegistrationOpen = new(2026, 6, 1, 8, 0, 0, DateTimeKind.Utc);
    private static readonly DateTime RegistrationClose = new(2026, 6, 15, 18, 0, 0, DateTimeKind.Utc);
    private static readonly DateTime TournamentStart = new(2026, 6, 20, 9, 0, 0, DateTimeKind.Utc);
    private static readonly DateTime TournamentEnd = new(2026, 6, 21, 18, 0, 0, DateTimeKind.Utc);

    [Fact]
    public async Task GetTournament_WhenTournamentDoesNotExist_ReturnsNotFound()
    {
        var controller = CreateController(new FakeSupabaseService());

        var result = await controller.GetTournament("missing-tournament");

        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task CreateTournament_WithoutAuthenticatedUser_ReturnsUnauthorized()
    {
        var controller = CreateController(new FakeSupabaseService());

        var result = await controller.CreateTournament(ValidCreateTournamentRequest());

        Assert.IsType<UnauthorizedObjectResult>(result);
    }

    [Theory]
    [InlineData("cancelled", "Invalid status")]
    [InlineData("draft", "End date must be after start date.")]
    public async Task CreateTournament_WithInvalidStatusOrDates_ReturnsBadRequest(string status, string expectedMessage)
    {
        var controller = CreateController(new FakeSupabaseService(), "admin-user");
        var request = ValidCreateTournamentRequest();
        request.Status = status;
        if (expectedMessage.StartsWith("End date", StringComparison.Ordinal))
        {
            request.EndDate = request.StartDate;
        }

        var result = await controller.CreateTournament(request);

        var badRequest = Assert.IsType<BadRequestObjectResult>(result);
        Assert.Contains(expectedMessage, badRequest.Value?.ToString());
    }

    [Fact]
    public async Task CreateTournament_WhenRegistrationClosesAfterStart_ReturnsBadRequest()
    {
        var controller = CreateController(new FakeSupabaseService(), "admin-user");
        var request = ValidCreateTournamentRequest();
        request.RegistrationCloseDate = request.StartDate.AddHours(1);

        var result = await controller.CreateTournament(request);

        var badRequest = Assert.IsType<BadRequestObjectResult>(result);
        Assert.Contains("Registration must close before", badRequest.Value?.ToString());
    }

    [Fact]
    public async Task CreateTournament_WithValidRequest_NormalizesStatusAndPersistsCreatedBy()
    {
        var service = new FakeSupabaseService();
        var controller = CreateController(service, "admin-user");
        var request = ValidCreateTournamentRequest();
        request.Status = " REGISTRATION_OPEN ";

        var result = await controller.CreateTournament(request);

        var ok = Assert.IsType<OkObjectResult>(result);
        var tournament = Assert.IsType<Tournament>(ok.Value);
        Assert.Equal("registration_open", tournament.Status);
        Assert.Equal("admin-user", tournament.CreatedBy);
        Assert.Equal(tournament, Assert.Single(service.CreatedTournaments));
    }

    [Fact]
    public async Task AssignReferee_WhenRefereeIdMissing_ReturnsBadRequest()
    {
        var controller = CreateController(new FakeSupabaseService(), "admin-user");

        var result = await controller.AssignReferee("tournament-1", new AssignRefereeRequest { RefereeId = "" });

        var badRequest = Assert.IsType<BadRequestObjectResult>(result);
        Assert.Contains("RefereeId is required", badRequest.Value?.ToString());
    }

    [Fact]
    public async Task AssignReferee_WhenTournamentMissing_ReturnsNotFound()
    {
        var controller = CreateController(new FakeSupabaseService(), "admin-user");

        var result = await controller.AssignReferee("missing-tournament", new AssignRefereeRequest { RefereeId = "referee-1" });

        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Theory]
    [InlineData("player")]
    [InlineData("coach")]
    public async Task AssignReferee_WhenUserIsNotReferee_ReturnsBadRequest(string role)
    {
        var service = new FakeSupabaseService();
        service.AddTournament(ValidTournament("tournament-1"));
        service.AddUser(new User { Id = "staff-1", Role = role });
        var controller = CreateController(service, "admin-user");

        var result = await controller.AssignReferee("tournament-1", new AssignRefereeRequest { RefereeId = "staff-1" });

        var badRequest = Assert.IsType<BadRequestObjectResult>(result);
        Assert.Contains("User is not a referee", badRequest.Value?.ToString());
    }

    [Fact]
    public async Task AssignReferee_WithValidReferee_ReturnsAssignmentDetails()
    {
        var service = new FakeSupabaseService();
        service.AddTournament(ValidTournament("tournament-1"));
        service.AddUser(new User { Id = "referee-1", Role = "referees_plus", FullName = "Referee One", Email = "referee@example.com" });
        var controller = CreateController(service, "admin-user");

        var result = await controller.AssignReferee("tournament-1", new AssignRefereeRequest { RefereeId = "referee-1" });

        var ok = Assert.IsType<OkObjectResult>(result);
        Assert.Contains("Referee One", ok.Value?.ToString());
    }

    [Theory]
    [InlineData("points", "male", "U18", "-68kg", "Discipline must be")]
    [InlineData("kata", "open", "U18", "-68kg", "Gender must be")]
    [InlineData("kata", "male", "", "-68kg", "Age group is required")]
    [InlineData("kata", "male", "U18", "", "Weight class is required")]
    public async Task CreateCategory_WithInvalidFields_ReturnsBadRequest(
        string discipline,
        string gender,
        string ageGroup,
        string weightClass,
        string expectedMessage)
    {
        var service = new FakeSupabaseService();
        service.AddTournament(ValidTournament("tournament-1"));
        var controller = CreateController(service, "admin-user");

        var result = await controller.CreateCategory("tournament-1", new CreateCategoryRequest
        {
            Discipline = discipline,
            Gender = gender,
            AgeGroup = ageGroup,
            WeightClass = weightClass
        });

        var badRequest = Assert.IsType<BadRequestObjectResult>(result);
        Assert.Contains(expectedMessage, badRequest.Value?.ToString());
    }

    [Fact]
    public async Task CreateCategory_WithValidFields_NormalizesInput()
    {
        var service = new FakeSupabaseService();
        service.AddTournament(ValidTournament("tournament-1"));
        var controller = CreateController(service, "admin-user");

        var result = await controller.CreateCategory("tournament-1", new CreateCategoryRequest
        {
            Discipline = " KATA ",
            Gender = " MIXED ",
            AgeGroup = " Senior ",
            WeightClass = " Open "
        });

        var ok = Assert.IsType<OkObjectResult>(result);
        var category = Assert.IsType<TournamentCategory>(ok.Value);
        Assert.Equal("kata", category.Discipline);
        Assert.Equal("mixed", category.Gender);
        Assert.Equal("Senior", category.AgeGroup);
        Assert.Equal("Open", category.WeightClass);
    }

    [Fact]
    public async Task SetCategoryFormat_WhenCallerIsNotReferee_ReturnsForbidden()
    {
        var service = new FakeSupabaseService();
        service.AddUser(new User { Id = "coach-user", Role = "coach" });
        var controller = CreateController(service, "coach-user");

        var result = await controller.SetCategoryFormat("tournament-1", "category-1", new SetCategoryFormatRequest { Format = "round_robin" });

        var objectResult = Assert.IsType<ObjectResult>(result);
        Assert.Equal(403, objectResult.StatusCode);
    }

    [Fact]
    public async Task SetCategoryFormat_WhenRefereeNotAssigned_ReturnsForbidden()
    {
        var service = new FakeSupabaseService();
        service.AddUser(new User { Id = "referee-1", Role = "referee" });
        var controller = CreateController(service, "referee-1");

        var result = await controller.SetCategoryFormat("tournament-1", "category-1", new SetCategoryFormatRequest { Format = "round_robin" });

        var objectResult = Assert.IsType<ObjectResult>(result);
        Assert.Equal(403, objectResult.StatusCode);
    }

    [Fact]
    public async Task SetCategoryFormat_WithInvalidFormat_ReturnsBadRequest()
    {
        var service = new FakeSupabaseService();
        service.AddUser(new User { Id = "referee-1", Role = "referee" });
        service.AddRefereeAssignment(new TournamentReferee { TournamentId = "tournament-1", RefereeId = "referee-1" });
        var controller = CreateController(service, "referee-1");

        var result = await controller.SetCategoryFormat("tournament-1", "category-1", new SetCategoryFormatRequest { Format = "pool" });

        var badRequest = Assert.IsType<BadRequestObjectResult>(result);
        Assert.Contains("single_elimination", badRequest.Value?.ToString());
    }

    [Fact]
    public async Task SetCategoryFormat_WithAssignedReferee_UpdatesFormat()
    {
        var service = new FakeSupabaseService();
        service.AddUser(new User { Id = "referee-1", Role = "referee" });
        service.AddRefereeAssignment(new TournamentReferee { TournamentId = "tournament-1", RefereeId = "referee-1" });
        service.AddCategory(new TournamentCategory { Id = "category-1", TournamentId = "tournament-1", Discipline = "kata", Gender = "male", AgeGroup = "U18", WeightClass = "Open" });
        var controller = CreateController(service, "referee-1");

        var result = await controller.SetCategoryFormat("tournament-1", "category-1", new SetCategoryFormatRequest { Format = " ROUND_ROBIN " });

        var ok = Assert.IsType<OkObjectResult>(result);
        Assert.Contains("round_robin", ok.Value?.ToString());
    }

    [Fact]
    public async Task RegisterForTournament_WithoutAuthenticatedUser_ReturnsUnauthorized()
    {
        var controller = CreateController(new FakeSupabaseService());

        var result = await controller.RegisterForTournament("tournament-1", new TournamentRegistrationRequest { CategoryId = "category-1" });

        Assert.IsType<UnauthorizedObjectResult>(result);
    }

    [Fact]
    public async Task RegisterForTournament_WhenCategoryIdMissing_ReturnsBadRequest()
    {
        var controller = CreateController(new FakeSupabaseService(), "player-1");

        var result = await controller.RegisterForTournament("tournament-1", new TournamentRegistrationRequest { CategoryId = "" });

        var badRequest = Assert.IsType<BadRequestObjectResult>(result);
        Assert.Contains("CategoryId is required", badRequest.Value?.ToString());
    }

    [Fact]
    public async Task RegisterForTournament_WhenCategoryBelongsToDifferentTournament_ReturnsBadRequest()
    {
        var service = new FakeSupabaseService();
        service.AddCategory(new TournamentCategory { Id = "category-1", TournamentId = "other-tournament" });
        var controller = CreateController(service, "player-1");

        var result = await controller.RegisterForTournament("tournament-1", new TournamentRegistrationRequest { CategoryId = "category-1" });

        var badRequest = Assert.IsType<BadRequestObjectResult>(result);
        Assert.Contains("Category does not belong", badRequest.Value?.ToString());
    }

    [Fact]
    public async Task RegisterForTournament_WithValidCategory_CreatesPendingRegistration()
    {
        var service = new FakeSupabaseService();
        service.AddCategory(new TournamentCategory { Id = "category-1", TournamentId = "tournament-1" });
        var controller = CreateController(service, "player-1");

        var result = await controller.RegisterForTournament("tournament-1", new TournamentRegistrationRequest
        {
            CategoryId = "category-1",
            Notes = "Needs medical review"
        });

        var ok = Assert.IsType<OkObjectResult>(result);
        var registration = Assert.IsType<TournamentRegistration>(ok.Value);
        Assert.Equal("pending", registration.Status);
        Assert.Equal("player-1", registration.UserId);
        Assert.Equal("Needs medical review", registration.Notes);
        Assert.Equal(registration, Assert.Single(service.CreatedRegistrations));
    }

    private static TournamentController CreateController(FakeSupabaseService service, string? userId = null)
    {
        var controller = new TournamentController(service)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext()
            }
        };

        if (!string.IsNullOrWhiteSpace(userId))
        {
            controller.ControllerContext.HttpContext.User = new ClaimsPrincipal(
                new ClaimsIdentity([new Claim("sub", userId)], "TestAuth"));
        }

        return controller;
    }

    private static CreateTournamentRequest ValidCreateTournamentRequest() => new()
    {
        Name = "SKF Championship",
        Description = "National championship",
        Location = "Riyadh",
        RegistrationOpenDate = RegistrationOpen,
        RegistrationCloseDate = RegistrationClose,
        StartDate = TournamentStart,
        EndDate = TournamentEnd,
        Status = "draft",
        MaxParticipants = 128,
        EntryFee = 50
    };

    private static Tournament ValidTournament(string id) => new()
    {
        Id = id,
        Name = "SKF Championship",
        Location = "Riyadh",
        RegistrationOpenDate = RegistrationOpen,
        RegistrationCloseDate = RegistrationClose,
        StartDate = TournamentStart,
        EndDate = TournamentEnd,
        Status = "draft"
    };
}
