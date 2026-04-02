using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SkfWebsite.Api.Models;
using SkfWebsite.Api.Services;

namespace SkfWebsite.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class UserController : ControllerBase
{
    private readonly ISupabaseService _supabaseService;

    public UserController(ISupabaseService supabaseService)
    {
        _supabaseService = supabaseService;
    }

    [HttpGet]
    [Authorize]
    public async Task<IActionResult> GetAllUsers()
    {
        try
        {
            // Only admins can view all users
            var currentUser = await GetCurrentUser();
            if (currentUser?.Role != "admin")
            {
                return Forbid();
            }

            var users = await _supabaseService.GetAllUsers();
            return Ok(users);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to fetch users", error = ex.Message });
        }
    }

    [HttpGet("pending")]
    [Authorize]
    public async Task<IActionResult> GetPendingUsers()
    {
        try
        {
            // Only admins can view pending users
            var currentUser = await GetCurrentUser();
            if (currentUser?.Role != "admin")
            {
                return Forbid();
            }

            var users = await _supabaseService.GetPendingUsers();
            return Ok(users);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to fetch pending users", error = ex.Message });
        }
    }

    [HttpPut("{id}/approve")]
    [Authorize]
    public async Task<IActionResult> ApproveUser(string id)
    {
        try
        {
            // Only admins can approve users
            var currentUser = await GetCurrentUser();
            if (currentUser?.Role != "admin")
            {
                return Forbid();
            }

            await _supabaseService.UpdateUserStatus(id, true);
            return Ok(new { message = "User approved successfully" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to approve user", error = ex.Message });
        }
    }

    [HttpDelete("{id}/reject")]
    [Authorize]
    public async Task<IActionResult> RejectUser(string id)
    {
        try
        {
            // Only admins can reject users
            var currentUser = await GetCurrentUser();
            if (currentUser?.Role != "admin")
            {
                return Forbid();
            }

            await _supabaseService.DeleteUser(id);
            return Ok(new { message = "User rejected and removed" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to reject user", error = ex.Message });
        }
    }

    [HttpPut("{id}/toggle-status")]
    [Authorize]
    public async Task<IActionResult> ToggleUserStatus(string id, [FromBody] bool isActive)
    {
        try
        {
            // Only admins can toggle user status
            var currentUser = await GetCurrentUser();
            if (currentUser?.Role != "admin")
            {
                return Forbid();
            }

            await _supabaseService.UpdateUserStatus(id, isActive);
            return Ok(new { message = $"User {(isActive ? "activated" : "deactivated")} successfully" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to update user status", error = ex.Message });
        }
    }

    private async Task<User?> GetCurrentUser()
    {
        var userId = User.FindFirst("sub")?.Value;
        if (string.IsNullOrEmpty(userId))
        {
            return null;
        }

        return await _supabaseService.GetUserById(userId);
    }
}
