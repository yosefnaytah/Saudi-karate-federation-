using System.Net;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using SkfWebsite.Api.Controllers;
using SkfWebsite.Api.DTOs;
using Xunit;

namespace SkfWebsite.Api.Tests;

public class AuthControllerTests
{
    [Fact]
    public async Task Register_WithInvalidRole_ReturnsBadRequest()
    {
        var controller = CreateController();

        var result = await controller.Register(new RegisterRequest
        {
            Email = "member@example.com",
            Password = "secret123",
            Role = "owner"
        });

        var badRequest = Assert.IsType<BadRequestObjectResult>(result);
        Assert.Contains("Invalid role", badRequest.Value?.ToString());
    }

    [Fact]
    public async Task DevRegister_WhenNotDevelopment_ReturnsNotFound()
    {
        var controller = CreateController(environmentName: "Production", bypassEmailConfirmation: true);

        var result = await controller.DevRegister(ValidDevRegisterRequest());

        Assert.IsType<NotFoundResult>(result);
    }

    [Fact]
    public async Task DevRegister_WhenBypassDisabled_ReturnsNotFound()
    {
        var controller = CreateController(environmentName: "Development", bypassEmailConfirmation: false);

        var result = await controller.DevRegister(ValidDevRegisterRequest());

        Assert.IsType<NotFoundResult>(result);
    }

    [Theory]
    [InlineData("", "secret123", "player", "Email is required.")]
    [InlineData("member@example.com", "short", "player", "Password must be at least 6 characters.")]
    [InlineData("member@example.com", "secret123", "referee", "Role must be player, coach, or club_admin.")]
    public async Task DevRegister_WithInvalidInput_ReturnsBadRequest(
        string email,
        string password,
        string role,
        string expectedMessage)
    {
        var controller = CreateController();

        var result = await controller.DevRegister(new DevRegisterRequest
        {
            Email = email,
            Password = password,
            Role = role
        });

        var badRequest = Assert.IsType<BadRequestObjectResult>(result);
        Assert.Contains(expectedMessage, badRequest.Value?.ToString());
    }

    [Fact]
    public async Task DevRegister_WhenServiceRoleKeyMissing_ReturnsServerError()
    {
        var controller = CreateController(serviceRoleKey: "");

        var result = await controller.DevRegister(ValidDevRegisterRequest());

        var status = Assert.IsType<ObjectResult>(result);
        Assert.Equal(500, status.StatusCode);
        Assert.Contains("missing Supabase service role key", status.Value?.ToString());
    }

    [Fact]
    public async Task DevRegister_WhenSupabaseSaysAlreadyRegistered_ReturnsConflict()
    {
        var controller = CreateController(
            httpClient: StubHttpMessageHandler.CreateClient(
                HttpStatusCode.BadRequest,
                "{\"message\":\"User already registered\"}",
                out _));

        var result = await controller.DevRegister(ValidDevRegisterRequest());

        var conflict = Assert.IsType<ConflictObjectResult>(result);
        Assert.Contains("already registered", conflict.Value?.ToString());
    }

    [Fact]
    public async Task DevRegister_WithValidPlayer_CallsSupabaseAdminEndpointAndReturnsUser()
    {
        var httpClient = StubHttpMessageHandler.CreateClient(
            HttpStatusCode.OK,
            "{\"id\":\"auth-user-1\"}",
            out var handler);
        var controller = CreateController(httpClient: httpClient);

        var result = await controller.DevRegister(ValidDevRegisterRequest());

        var ok = Assert.IsType<OkObjectResult>(result);
        Assert.Contains("auth-user-1", ok.Value?.ToString());

        Assert.NotNull(handler.LastRequest);
        Assert.Equal(HttpMethod.Post, handler.LastRequest.Method);
        Assert.Equal("https://example.supabase.co/auth/v1/admin/users", handler.LastRequest.RequestUri?.ToString());
        Assert.Equal("service-role-key", handler.LastRequest.Headers.Authorization?.Parameter);
        Assert.True(handler.LastRequest.Headers.TryGetValues("apikey", out var apiKeys));
        Assert.Equal("service-role-key", Assert.Single(apiKeys));

        using var doc = JsonDocument.Parse(handler.LastRequestBody!);
        Assert.Equal("member@example.com", doc.RootElement.GetProperty("email").GetString());
        Assert.True(doc.RootElement.GetProperty("email_confirm").GetBoolean());

        var metadata = doc.RootElement.GetProperty("user_metadata");
        Assert.Equal("player", metadata.GetProperty("role").GetString());
        Assert.Equal("Senior", metadata.GetProperty("age_group").GetString());
        Assert.Equal("Black Belt", metadata.GetProperty("rank").GetString());
        Assert.Equal("Kumite", metadata.GetProperty("player_category").GetString());
    }

    private static AuthController CreateController(
        string environmentName = "Development",
        bool bypassEmailConfirmation = true,
        string serviceRoleKey = "service-role-key",
        HttpClient? httpClient = null)
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["DevAuth:BypassEmailConfirmation"] = bypassEmailConfirmation.ToString(),
                ["Supabase:Url"] = "https://example.supabase.co",
                ["Supabase:ServiceRoleKey"] = serviceRoleKey
            })
            .Build();

        httpClient ??= StubHttpMessageHandler.CreateClient(HttpStatusCode.OK, "{\"id\":\"auth-user-1\"}", out _);

        return new AuthController(
            new FakeSupabaseService(),
            configuration,
            new FakeHttpClientFactory(httpClient),
            new FakeWebHostEnvironment { EnvironmentName = environmentName });
    }

    private static DevRegisterRequest ValidDevRegisterRequest() => new()
    {
        FullName = "SKF Member",
        NationalId = "1234567890",
        Phone = "+966500000000",
        Email = " Member@Example.com ",
        Password = "secret123",
        Role = " PLAYER ",
        AgeGroup = "Senior",
        Rank = "Black Belt",
        PlayerCategory = "Kumite"
    };
}
