using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SkfWebsite.Api.Models;
using SkfWebsite.Api.Services;
using SkfWebsite.Api.DTOs;

namespace SkfWebsite.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class TournamentController : ControllerBase
{
    private readonly ISupabaseService _supabaseService;

    public TournamentController(ISupabaseService supabaseService)
    {
        _supabaseService = supabaseService;
    }

    [HttpGet]
    public async Task<IActionResult> GetTournaments()
    {
        try
        {
            var tournaments = await _supabaseService.GetTournaments();
            return Ok(tournaments);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to fetch tournaments", error = ex.Message });
        }
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetTournament(string id)
    {
        try
        {
            var tournament = await _supabaseService.GetTournamentById(id);
            if (tournament == null)
            {
                return NotFound(new { message = "Tournament not found" });
            }
            
            return Ok(tournament);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to fetch tournament", error = ex.Message });
        }
    }

    [HttpPost]
    [Authorize]
    public async Task<IActionResult> CreateTournament([FromBody] CreateTournamentRequest request)
    {
        try
        {
            // Get current user ID from JWT token
            var userId = User.FindFirst("sub")?.Value;
            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var tournament = new Tournament
            {
                Name = request.Name,
                Description = request.Description,
                StartDate = request.StartDate,
                EndDate = request.EndDate,
                Location = request.Location,
                Status = TournamentStatus.Upcoming.ToString().ToLower(),
                MaxParticipants = request.MaxParticipants,
                RegistrationDeadline = request.RegistrationDeadline,
                EntryFee = request.EntryFee,
                CreatedBy = userId
            };

            var result = await _supabaseService.CreateTournament(tournament);
            return Ok(result);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to create tournament", error = ex.Message });
        }
    }

    [HttpGet("{id}/registrations")]
    [Authorize]
    public async Task<IActionResult> GetTournamentRegistrations(string id)
    {
        try
        {
            var registrations = await _supabaseService.GetTournamentRegistrations(id);
            return Ok(registrations);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to fetch registrations", error = ex.Message });
        }
    }

    [HttpPost("{id}/register")]
    [Authorize]
    public async Task<IActionResult> RegisterForTournament(string id, [FromBody] TournamentRegistrationRequest request)
    {
        try
        {
            // Get current user ID from JWT token
            var userId = User.FindFirst("sub")?.Value;
            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var registration = new TournamentRegistration
            {
                TournamentId = id,
                UserId = userId,
                WeightCategory = request.WeightCategory,
                BeltLevel = request.BeltLevel,
                Status = "pending",
                PaymentStatus = "pending",
                Notes = request.Notes
            };

            var result = await _supabaseService.RegisterForTournament(registration);
            return Ok(result);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to register for tournament", error = ex.Message });
        }
    }
}