using Microsoft.AspNetCore.Mvc;
using SkfWebsite.Api.Services;
using SkfWebsite.Api.DTOs;

namespace SkfWebsite.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly ISupabaseService _supabaseService;
    private readonly IConfiguration _configuration;

    public AuthController(ISupabaseService supabaseService, IConfiguration configuration)
    {
        _supabaseService = supabaseService;
        _configuration = configuration;
    }

    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] RegisterRequest request)
    {
        try
        {
            var client = await _supabaseService.GetClient();

            // Create user account in Supabase Auth
            var authResponse = await client.Auth.SignUp(request.Email, request.Password);
            
            if (authResponse.User == null)
            {
                return BadRequest(new { message = "Failed to create user account" });
            }

            // Insert additional user data into our custom users table
            var user = new Models.User
            {
                Id = authResponse.User.Id,
                FullName = request.FullName,
                NationalId = request.NationalId,
                PlayerId = request.PlayerId,
                Phone = request.Phone,
                ClubName = request.ClubName,
                Email = request.Email,
                Username = request.Username,
                Role = request.Role.ToLower(),
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            };

            var result = await client.From<Models.User>().Insert(user);

            return Ok(new { 
                message = "User registered successfully",
                user = new {
                    id = authResponse.User.Id,
                    email = authResponse.User.Email,
                    fullName = request.FullName,
                    role = request.Role
                }
            });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Registration failed", error = ex.Message });
        }
    }

    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] LoginRequest request)
    {
        try
        {
            var client = await _supabaseService.GetClient();

            // Authenticate with Supabase
            var authResponse = await client.Auth.SignIn(request.Email, request.Password);
            
            if (authResponse.User == null)
            {
                return Unauthorized(new { message = "Invalid credentials" });
            }

            // Get additional user data
            var user = await _supabaseService.GetUserByEmail(request.Email);

            return Ok(new {
                message = "Login successful",
                token = authResponse.Session?.AccessToken,
                user = new {
                    id = authResponse.User.Id,
                    email = authResponse.User.Email,
                    fullName = user?.FullName,
                    role = user?.Role,
                    username = user?.Username
                }
            });
        }
        catch (Exception ex)
        {
            return Unauthorized(new { message = "Invalid credentials", error = ex.Message });
        }
    }

    [HttpPost("logout")]
    public async Task<IActionResult> Logout()
    {
        try
        {
            var client = await _supabaseService.GetClient();
            await client.Auth.SignOut();
            
            return Ok(new { message = "Logged out successfully" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Logout failed", error = ex.Message });
        }
    }
}