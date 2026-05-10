using Microsoft.AspNetCore.Mvc;
using SkfWebsite.Api.Services;
using SkfWebsite.Api.DTOs;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace SkfWebsite.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly ISupabaseService _supabaseService;
    private readonly IConfiguration _configuration;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IWebHostEnvironment _env;

    public AuthController(ISupabaseService supabaseService, IConfiguration configuration, IHttpClientFactory httpClientFactory, IWebHostEnvironment env)
    {
        _supabaseService = supabaseService;
        _configuration = configuration;
        _httpClientFactory = httpClientFactory;
        _env = env;
    }

    // -------------------------------------------------------------------------
    // DEV ONLY: bypass email confirmation during local testing
    //
    // Why: Supabase email confirmation + repeated retries can hit "email rate limit exceeded".
    // This endpoint creates an Auth user as *already confirmed* (no confirmation email),
    // but only when:
    // - ASPNETCORE_ENVIRONMENT=Development AND
    // - DevAuth:BypassEmailConfirmation=true AND
    // - Supabase:ServiceRoleKey is provided (env var or config).
    //
    // Do NOT enable this in production.
    // -------------------------------------------------------------------------
    [HttpPost("dev-register")]
    public async Task<IActionResult> DevRegister([FromBody] DevRegisterRequest request)
    {
        if (!_env.IsDevelopment() || !_configuration.GetValue<bool>("DevAuth:BypassEmailConfirmation"))
        {
            return NotFound();
        }

        var email = (request.Email ?? string.Empty).Trim().ToLowerInvariant();
        var password = request.Password ?? string.Empty;
        var role = (request.Role ?? string.Empty).Trim().ToLowerInvariant();

        if (string.IsNullOrWhiteSpace(email) || !email.Contains('@'))
            return BadRequest(new { message = "Email is required." });
        if (password.Length < 6)
            return BadRequest(new { message = "Password must be at least 6 characters." });
        if (role != "player" && role != "coach" && role != "club_admin")
            return BadRequest(new { message = "Role must be player, coach, or club_admin." });

        var supabaseUrl = _configuration["Supabase:Url"] ?? string.Empty;
        var serviceKey = GetServiceRoleKey();
        if (string.IsNullOrWhiteSpace(supabaseUrl) || string.IsNullOrWhiteSpace(serviceKey))
        {
            return StatusCode(500, new
            {
                message = "Dev register is enabled but server is missing Supabase service role key.",
                hint = "Set Supabase:ServiceRoleKey (appsettings.Development.json) or env SUPABASE_SERVICE_ROLE_KEY."
            });
        }

        var meta = new Dictionary<string, object?>
        {
            ["full_name"] = (request.FullName ?? string.Empty).Trim(),
            ["role"] = role,
            ["national_id"] = (request.NationalId ?? string.Empty).Trim(),
            ["phone"] = (request.Phone ?? string.Empty).Trim(),
            ["club_name"] = ""
        };
        if (role == "player")
        {
            if (!string.IsNullOrWhiteSpace(request.AgeGroup)) meta["age_group"] = request.AgeGroup.Trim();
            if (!string.IsNullOrWhiteSpace(request.Rank)) meta["rank"] = request.Rank.Trim();
            if (!string.IsNullOrWhiteSpace(request.PlayerCategory)) meta["player_category"] = request.PlayerCategory.Trim();
        }

        var payload = new
        {
            email,
            password,
            email_confirm = true,
            user_metadata = meta
        };

        var http = _httpClientFactory.CreateClient();
        var url = supabaseUrl.TrimEnd('/') + "/auth/v1/admin/users";
        using var msg = new HttpRequestMessage(HttpMethod.Post, url);
        msg.Headers.TryAddWithoutValidation("apikey", serviceKey);
        msg.Headers.Authorization = new AuthenticationHeaderValue("Bearer", serviceKey);
        msg.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

        using var resp = await http.SendAsync(msg);
        var body = await resp.Content.ReadAsStringAsync();

        if (!resp.IsSuccessStatusCode)
        {
            // Common case: already registered → avoid spamming emails by retrying via normal signup
            if (body != null && body.ToLowerInvariant().Contains("already registered"))
                return Conflict(new { message = "This email is already registered." });

            return StatusCode((int)resp.StatusCode, new { message = "Dev register failed", details = body });
        }

        string? userId = null;
        try
        {
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.TryGetProperty("id", out var idEl) && idEl.ValueKind == JsonValueKind.String)
            {
                userId = idEl.GetString();
            }
        }
        catch { /* ignore parse */ }

        return Ok(new
        {
            message = "Dev registration successful (email confirmation bypassed).",
            user = new { id = userId, email, role }
        });
    }

    private string GetServiceRoleKey()
    {
        var cfg = _configuration["Supabase:ServiceRoleKey"];
        if (!string.IsNullOrWhiteSpace(cfg)) return cfg;
        var env = Environment.GetEnvironmentVariable("SUPABASE_SERVICE_ROLE_KEY");
        return env ?? string.Empty;
    }

    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] RegisterRequest request)
    {
        try
        {
            var normalizedRole = (request.Role ?? string.Empty).Trim().ToLower();
            var allowedPublicRoles = new HashSet<string>
            {
                "skf_admin",
                "player",
                "coach",
                "referee",
                "club_admin",
                "referees_plus"
            };

            if (!allowedPublicRoles.Contains(normalizedRole))
            {
                return BadRequest(new { message = "Invalid role. Public registration is limited to player, coach, referee, club admin, and referees plus." });
            }

            var client = await _supabaseService.GetClient();

            // Create user account in Supabase Auth
            var authResponse = await client.Auth.SignUp(request.Email, request.Password);
            
            if (authResponse?.User == null)
            {
                return BadRequest(new { message = "Failed to create user account" });
            }

            // Insert additional user data into our custom users table
            var user = new Models.User
            {
                Id = authResponse.User.Id ?? string.Empty,
                FullName = request.FullName,
                NationalId = request.NationalId,
                PlayerId = request.PlayerId,
                Phone = request.Phone,
                ClubName = request.ClubName,
                Email = request.Email,
                Username = request.Username,
                Role = normalizedRole,
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
            
            if (authResponse?.User == null)
            {
                return Unauthorized(new { message = "Invalid credentials" });
            }

            // Get additional user data
            var user = await _supabaseService.GetUserByEmail(request.Email);

            // Extract access token - try multiple methods for Supabase 1.0.0 compatibility
            string? accessToken = null;
            
            // Method 1: Try CurrentSession (most reliable after SignIn)
            var session = client.Auth.CurrentSession;
            if (session != null && !string.IsNullOrEmpty(session.AccessToken))
            {
                accessToken = session.AccessToken;
            }

            return Ok(new {
                message = "Login successful",
                token = accessToken,
                user = new {
                    id = authResponse.User.Id,
                    email = authResponse.User.Email ?? string.Empty,
                    fullName = user?.FullName ?? string.Empty,
                    role = user?.Role ?? string.Empty,
                    username = user?.Username ?? string.Empty
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