using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using SkfWebsite.Api.Controllers;
using SkfWebsite.Api.Models;
using Xunit;

namespace SkfWebsite.Api.Tests;

public class UserControllerTests
{
    [Fact]
    public async Task GetAllUsers_WithoutAuthenticatedUser_ReturnsForbid()
    {
        var controller = CreateController(new FakeSupabaseService());

        var result = await controller.GetAllUsers();

        Assert.IsType<ForbidResult>(result);
    }

    [Fact]
    public async Task GetPendingUsers_WhenCurrentUserIsNotAdmin_ReturnsForbid()
    {
        var service = new FakeSupabaseService();
        service.AddUser(new User { Id = "current-user", Role = "player" });
        var controller = CreateController(service, "current-user");

        var result = await controller.GetPendingUsers();

        Assert.IsType<ForbidResult>(result);
    }

    [Fact]
    public async Task GetPendingUsers_WhenCurrentUserIsAdmin_ReturnsInactiveUsers()
    {
        var service = new FakeSupabaseService();
        service.AddUser(new User { Id = "current-user", Role = "admin", Email = "admin@example.com" });
        service.AddUser(new User { Id = "pending-user", Role = "player", IsActive = false });
        service.AddUser(new User { Id = "active-user", Role = "coach", IsActive = true });
        var controller = CreateController(service, "current-user");

        var result = await controller.GetPendingUsers();

        var ok = Assert.IsType<OkObjectResult>(result);
        var users = Assert.IsAssignableFrom<List<User>>(ok.Value);
        var user = Assert.Single(users);
        Assert.Equal("pending-user", user.Id);
    }

    [Fact]
    public async Task ApproveUser_WhenCurrentUserIsAdmin_ActivatesTargetUser()
    {
        var service = new FakeSupabaseService();
        service.AddUser(new User { Id = "current-user", Role = "admin" });
        service.AddUser(new User { Id = "target-user", Role = "player", IsActive = false });
        var controller = CreateController(service, "current-user");

        var result = await controller.ApproveUser("target-user");

        Assert.IsType<OkObjectResult>(result);
        Assert.Equal(("target-user", true), Assert.Single(service.StatusUpdates));
    }

    [Fact]
    public async Task RejectUser_WhenCurrentUserIsAdmin_DeletesTargetUser()
    {
        var service = new FakeSupabaseService();
        service.AddUser(new User { Id = "current-user", Role = "admin" });
        service.AddUser(new User { Id = "target-user", Role = "player" });
        var controller = CreateController(service, "current-user");

        var result = await controller.RejectUser("target-user");

        Assert.IsType<OkObjectResult>(result);
        Assert.Equal("target-user", Assert.Single(service.DeletedUserIds));
    }

    [Theory]
    [InlineData(true, "activated")]
    [InlineData(false, "deactivated")]
    public async Task ToggleUserStatus_WhenCurrentUserIsAdmin_UpdatesStatus(bool isActive, string expectedMessage)
    {
        var service = new FakeSupabaseService();
        service.AddUser(new User { Id = "current-user", Role = "admin" });
        service.AddUser(new User { Id = "target-user", Role = "player", IsActive = !isActive });
        var controller = CreateController(service, "current-user");

        var result = await controller.ToggleUserStatus("target-user", isActive);

        var ok = Assert.IsType<OkObjectResult>(result);
        Assert.Contains(expectedMessage, ok.Value?.ToString());
        Assert.Equal(("target-user", isActive), Assert.Single(service.StatusUpdates));
    }

    private static UserController CreateController(FakeSupabaseService service, string? userId = null)
    {
        var controller = new UserController(service)
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
}
