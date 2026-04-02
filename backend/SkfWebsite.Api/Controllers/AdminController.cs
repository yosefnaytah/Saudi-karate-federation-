using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SkfWebsite.Api.Models;
using SkfWebsite.Api.Services;

namespace SkfWebsite.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class AdminController : ControllerBase
{
    private readonly ISupabaseService _supabaseService;

    public AdminController(ISupabaseService supabaseService)
    {
        _supabaseService = supabaseService;
    }

    // Get all users (Admin only)
    [HttpGet("users")]
    public async Task<IActionResult> GetUsers()
    {
        try
        {
            // Check if user is admin
            var currentUserId = User.FindFirst("sub")?.Value;
            if (string.IsNullOrEmpty(currentUserId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var currentUser = await _supabaseService.GetUserById(currentUserId);
            if (currentUser == null || currentUser.Role.ToLower() != "admin")
            {
                return Forbid("Only administrators can access this endpoint");
            }

            var client = await _supabaseService.GetClient();
            var result = await client
                .From<User>()
                .Get();

            return Ok(result.Models);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to fetch users", error = ex.Message });
        }
    }

    // Get user by ID
    [HttpGet("users/{id}")]
    public async Task<IActionResult> GetUser(string id)
    {
        try
        {
            var currentUserId = User.FindFirst("sub")?.Value;
            if (string.IsNullOrEmpty(currentUserId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var currentUser = await _supabaseService.GetUserById(currentUserId);
            if (currentUser == null || currentUser.Role.ToLower() != "admin")
            {
                return Forbid("Only administrators can access this endpoint");
            }

            var user = await _supabaseService.GetUserById(id);
            if (user == null)
            {
                return NotFound(new { message = "User not found" });
            }

            return Ok(user);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to fetch user", error = ex.Message });
        }
    }

    // Approve user (activate)
    [HttpPut("users/{id}/approve")]
    public async Task<IActionResult> ApproveUser(string id)
    {
        try
        {
            var currentUserId = User.FindFirst("sub")?.Value;
            if (string.IsNullOrEmpty(currentUserId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var currentUser = await _supabaseService.GetUserById(currentUserId);
            if (currentUser == null || currentUser.Role.ToLower() != "admin")
            {
                return Forbid("Only administrators can approve users");
            }

            var client = await _supabaseService.GetClient();
            var user = await _supabaseService.GetUserById(id);
            
            if (user == null)
            {
                return NotFound(new { message = "User not found" });
            }

            user.IsActive = true;
            user.UpdatedAt = DateTime.UtcNow;

            var result = await client
                .From<User>()
                .Where(x => x.Id == id)
                .Set(x => x.IsActive, true)
                .Set(x => x.UpdatedAt, DateTime.UtcNow)
                .Update();

            return Ok(new { message = "User approved successfully", user = result.Models.FirstOrDefault() });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to approve user", error = ex.Message });
        }
    }

    // Reject/Delete user
    [HttpDelete("users/{id}/reject")]
    public async Task<IActionResult> RejectUser(string id)
    {
        try
        {
            var currentUserId = User.FindFirst("sub")?.Value;
            if (string.IsNullOrEmpty(currentUserId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var currentUser = await _supabaseService.GetUserById(currentUserId);
            if (currentUser == null || currentUser.Role.ToLower() != "admin")
            {
                return Forbid("Only administrators can reject users");
            }

            var client = await _supabaseService.GetClient();
            
            // Delete from users table (this will cascade to auth.users if configured)
            await client
                .From<User>()
                .Where(x => x.Id == id)
                .Delete();

            return Ok(new { message = "User rejected and removed successfully" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to reject user", error = ex.Message });
        }
    }

    // Update user status (activate/deactivate)
    [HttpPut("users/{id}/status")]
    public async Task<IActionResult> UpdateUserStatus(string id, [FromBody] UpdateUserStatusRequest request)
    {
        try
        {
            var currentUserId = User.FindFirst("sub")?.Value;
            if (string.IsNullOrEmpty(currentUserId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var currentUser = await _supabaseService.GetUserById(currentUserId);
            if (currentUser == null || currentUser.Role.ToLower() != "admin")
            {
                return Forbid("Only administrators can update user status");
            }

            var client = await _supabaseService.GetClient();
            
            var result = await client
                .From<User>()
                .Where(x => x.Id == id)
                .Set(x => x.IsActive, request.IsActive)
                .Set(x => x.UpdatedAt, DateTime.UtcNow)
                .Update();

            return Ok(new { message = "User status updated successfully", user = result.Models.FirstOrDefault() });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to update user status", error = ex.Message });
        }
    }
}

// DTO for update user status request
public class UpdateUserStatusRequest
{
    public bool IsActive { get; set; }
}
