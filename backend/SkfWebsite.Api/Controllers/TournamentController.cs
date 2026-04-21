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

    private static readonly HashSet<string> AllowedStatuses = new()
    {
        "draft", "registration_open", "registration_closed"
    };

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
                return NotFound(new { message = "Tournament not found" });

            return Ok(tournament);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to fetch tournament", error = ex.Message });
        }
    }

    // SKF Admin only – create a tournament
    [HttpPost]
    [Authorize]
    public async Task<IActionResult> CreateTournament([FromBody] CreateTournamentRequest request)
    {
        try
        {
            var userId = User.FindFirst("sub")?.Value;
            if (string.IsNullOrEmpty(userId))
                return Unauthorized(new { message = "User not authenticated" });

            // Validate status
            var status = (request.Status ?? "draft").Trim().ToLower();
            if (!AllowedStatuses.Contains(status))
                return BadRequest(new { message = $"Invalid status '{status}'. Allowed: draft, registration_open, registration_closed." });

            // Date logic validation
            if (request.EndDate <= request.StartDate)
                return BadRequest(new { message = "End date must be after start date." });

            if (request.RegistrationCloseDate <= request.RegistrationOpenDate)
                return BadRequest(new { message = "Registration close date must be after registration open date." });

            if (request.RegistrationCloseDate > request.StartDate)
                return BadRequest(new { message = "Registration must close before the tournament starts." });

            var tournament = new Tournament
            {
                Name = request.Name,
                Description = request.Description,
                StartDate = request.StartDate,
                EndDate = request.EndDate,
                Location = request.Location,
                Status = status,
                RegistrationOpenDate = request.RegistrationOpenDate,
                RegistrationCloseDate = request.RegistrationCloseDate,
                MaxParticipants = request.MaxParticipants,
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

    // SKF Admin only – edit an existing tournament
    [HttpPut("{id}")]
    [Authorize]
    public async Task<IActionResult> UpdateTournament(string id, [FromBody] UpdateTournamentRequest request)
    {
        try
        {
            var userId = User.FindFirst("sub")?.Value;
            if (string.IsNullOrEmpty(userId))
                return Unauthorized(new { message = "User not authenticated" });

            var existing = await _supabaseService.GetTournamentById(id);
            if (existing == null)
                return NotFound(new { message = "Tournament not found" });

            // Apply only the fields that were sent
            if (request.Name != null) existing.Name = request.Name;
            if (request.Description != null) existing.Description = request.Description;
            if (request.Location != null) existing.Location = request.Location;
            if (request.StartDate.HasValue) existing.StartDate = request.StartDate.Value;
            if (request.EndDate.HasValue) existing.EndDate = request.EndDate.Value;
            if (request.RegistrationOpenDate.HasValue) existing.RegistrationOpenDate = request.RegistrationOpenDate.Value;
            if (request.RegistrationCloseDate.HasValue) existing.RegistrationCloseDate = request.RegistrationCloseDate.Value;
            if (request.MaxParticipants.HasValue) existing.MaxParticipants = request.MaxParticipants;
            if (request.EntryFee.HasValue) existing.EntryFee = request.EntryFee;

            if (request.Status != null)
            {
                var status = request.Status.Trim().ToLower();
                if (!AllowedStatuses.Contains(status))
                    return BadRequest(new { message = $"Invalid status '{status}'. Allowed: draft, registration_open, registration_closed." });
                existing.Status = status;
            }

            // Re-validate dates after applying patches
            if (existing.EndDate <= existing.StartDate)
                return BadRequest(new { message = "End date must be after start date." });

            if (existing.RegistrationCloseDate <= existing.RegistrationOpenDate)
                return BadRequest(new { message = "Registration close date must be after registration open date." });

            if (existing.RegistrationCloseDate > existing.StartDate)
                return BadRequest(new { message = "Registration must close before the tournament starts." });

            var result = await _supabaseService.UpdateTournament(id, existing);
            return Ok(result);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to update tournament", error = ex.Message });
        }
    }

    // ── Referee assignment endpoints ────────────────────────────────────────

    // Returns all tournaments assigned to a specific referee
    [HttpGet("by-referee/{refereeId}")]
    public async Task<IActionResult> GetTournamentsByReferee(string refereeId)
    {
        try
        {
            var tournaments = await _supabaseService.GetTournamentsByReferee(refereeId);
            return Ok(tournaments);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to fetch referee tournaments", error = ex.Message });
        }
    }

    // Returns all referees assigned to a tournament (with user details)
    [HttpGet("{id}/referees")]
    public async Task<IActionResult> GetTournamentReferees(string id)
    {
        try
        {
            var assignments = await _supabaseService.GetRefereesByTournament(id);
            var result = new List<object>();
            foreach (var a in assignments)
            {
                var user = await _supabaseService.GetUserById(a.RefereeId);
                result.Add(new
                {
                    refereeId  = a.RefereeId,
                    fullName   = user?.FullName ?? "Unknown",
                    email      = user?.Email ?? string.Empty,
                    role       = user?.Role ?? string.Empty,
                    assignedAt = a.AssignedAt
                });
            }
            return Ok(result);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to fetch tournament referees", error = ex.Message });
        }
    }

    // Returns referee users NOT yet assigned to this tournament
    [HttpGet("{id}/available-referees")]
    [Authorize]
    public async Task<IActionResult> GetAvailableReferees(string id)
    {
        try
        {
            var allReferees = await _supabaseService.GetRefereeUsers();
            var assigned = await _supabaseService.GetRefereesByTournament(id);
            var assignedIds = assigned.Select(a => a.RefereeId).ToHashSet();

            var available = allReferees
                .Where(u => !assignedIds.Contains(u.Id))
                .Select(u => new { id = u.Id, fullName = u.FullName, email = u.Email, role = u.Role });

            return Ok(available);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to fetch available referees", error = ex.Message });
        }
    }

    // Assign a referee to a tournament
    [HttpPost("{id}/referees")]
    [Authorize]
    public async Task<IActionResult> AssignReferee(string id, [FromBody] AssignRefereeRequest request)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(request.RefereeId))
                return BadRequest(new { message = "RefereeId is required." });

            var tournament = await _supabaseService.GetTournamentById(id);
            if (tournament == null)
                return NotFound(new { message = "Tournament not found." });

            var referee = await _supabaseService.GetUserById(request.RefereeId);
            if (referee == null || (referee.Role != "referee" && referee.Role != "referees_plus"))
                return BadRequest(new { message = "User is not a referee." });

            var result = await _supabaseService.AssignRefereeToTournament(id, request.RefereeId);
            return Ok(new
            {
                refereeId  = result.RefereeId,
                fullName   = referee.FullName,
                email      = referee.Email,
                role       = referee.Role,
                assignedAt = result.AssignedAt
            });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to assign referee", error = ex.Message });
        }
    }

    // Remove a referee from a tournament
    [HttpDelete("{id}/referees/{refereeId}")]
    [Authorize]
    public async Task<IActionResult> RemoveReferee(string id, string refereeId)
    {
        try
        {
            await _supabaseService.RemoveRefereeFromTournament(id, refereeId);
            return NoContent();
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to remove referee", error = ex.Message });
        }
    }

    // ── Category endpoints ─────────────────────────────────────────────────

    [HttpGet("{id}/categories")]
    public async Task<IActionResult> GetCategories(string id)
    {
        try
        {
            var categories = await _supabaseService.GetCategoriesByTournament(id);
            return Ok(categories);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to fetch categories", error = ex.Message });
        }
    }

    [HttpPost("{id}/categories")]
    [Authorize]
    public async Task<IActionResult> CreateCategory(string id, [FromBody] CreateCategoryRequest request)
    {
        try
        {
            var userId = User.FindFirst("sub")?.Value;
            if (string.IsNullOrEmpty(userId))
                return Unauthorized(new { message = "User not authenticated" });

            var allowedDisciplines = new HashSet<string> { "kata", "kumite" };
            var allowedGenders = new HashSet<string> { "male", "female", "mixed" };

            var discipline = (request.Discipline ?? "").Trim().ToLower();
            var gender = (request.Gender ?? "").Trim().ToLower();

            if (!allowedDisciplines.Contains(discipline))
                return BadRequest(new { message = "Discipline must be 'kata' or 'kumite'." });

            if (!allowedGenders.Contains(gender))
                return BadRequest(new { message = "Gender must be 'male', 'female', or 'mixed'." });

            if (string.IsNullOrWhiteSpace(request.AgeGroup))
                return BadRequest(new { message = "Age group is required." });

            if (string.IsNullOrWhiteSpace(request.WeightClass))
                return BadRequest(new { message = "Weight class is required." });

            var tournament = await _supabaseService.GetTournamentById(id);
            if (tournament == null)
                return NotFound(new { message = "Tournament not found" });

            var category = new Models.TournamentCategory
            {
                TournamentId = id,
                Discipline = discipline,
                Gender = gender,
                AgeGroup = request.AgeGroup.Trim(),
                WeightClass = request.WeightClass.Trim()
            };

            var result = await _supabaseService.CreateCategory(category);
            return Ok(result);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to create category", error = ex.Message });
        }
    }

    [HttpPut("{id}/categories/{categoryId}")]
    [Authorize]
    public async Task<IActionResult> UpdateCategory(string id, string categoryId, [FromBody] UpdateCategoryRequest request)
    {
        try
        {
            var userId = User.FindFirst("sub")?.Value;
            if (string.IsNullOrEmpty(userId))
                return Unauthorized(new { message = "User not authenticated" });

            var existing = (await _supabaseService.GetCategoriesByTournament(id))
                .FirstOrDefault(c => c.Id == categoryId);

            if (existing == null)
                return NotFound(new { message = "Category not found" });

            var allowedDisciplines = new HashSet<string> { "kata", "kumite" };
            var allowedGenders = new HashSet<string> { "male", "female", "mixed" };

            if (request.Discipline != null)
            {
                var d = request.Discipline.Trim().ToLower();
                if (!allowedDisciplines.Contains(d))
                    return BadRequest(new { message = "Discipline must be 'kata' or 'kumite'." });
                existing.Discipline = d;
            }
            if (request.Gender != null)
            {
                var g = request.Gender.Trim().ToLower();
                if (!allowedGenders.Contains(g))
                    return BadRequest(new { message = "Gender must be 'male', 'female', or 'mixed'." });
                existing.Gender = g;
            }
            if (request.AgeGroup != null) existing.AgeGroup = request.AgeGroup.Trim();
            if (request.WeightClass != null) existing.WeightClass = request.WeightClass.Trim();

            var result = await _supabaseService.UpdateCategory(categoryId, existing);
            return Ok(result);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to update category", error = ex.Message });
        }
    }

    [HttpDelete("{id}/categories/{categoryId}")]
    [Authorize]
    public async Task<IActionResult> DeleteCategory(string id, string categoryId)
    {
        try
        {
            var userId = User.FindFirst("sub")?.Value;
            if (string.IsNullOrEmpty(userId))
                return Unauthorized(new { message = "User not authenticated" });

            await _supabaseService.DeleteCategory(categoryId);
            return NoContent();
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to delete category", error = ex.Message });
        }
    }

    // Returns categories for all tournaments assigned to the logged-in referee
    [HttpGet("assigned-categories")]
    [Authorize]
    public async Task<IActionResult> GetAssignedCategories()
    {
        try
        {
            var userId = User.FindFirst("sub")?.Value;
            if (string.IsNullOrEmpty(userId))
                return Unauthorized(new { message = "User not authenticated." });

            var tournaments = await _supabaseService.GetTournamentsByReferee(userId);
            var result = new List<object>();

            foreach (var t in tournaments)
            {
                var categories = await _supabaseService.GetCategoriesByTournament(t.Id);
                foreach (var c in categories)
                {
                    result.Add(new
                    {
                        id                = c.Id,
                        tournamentId      = t.Id,
                        tournamentName    = t.Name,
                        discipline        = c.Discipline,
                        gender            = c.Gender,
                        ageGroup          = c.AgeGroup,
                        weightClass       = c.WeightClass,
                        competitionFormat = c.CompetitionFormat
                    });
                }
            }

            return Ok(result);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to fetch assigned categories", error = ex.Message });
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private static string Capitalize(string s) =>
        string.IsNullOrEmpty(s) ? s : char.ToUpper(s[0]) + s[1..];

    // ── Category format endpoint ───────────────────────────────────────────

    private static readonly HashSet<string> AllowedFormats = new()
    {
        "single_elimination", "round_robin"
    };

    [HttpPatch("{id}/categories/{categoryId}/format")]
    [Authorize]
    public async Task<IActionResult> SetCategoryFormat(
        string id, string categoryId, [FromBody] SetCategoryFormatRequest request)
    {
        try
        {
            var userId = User.FindFirst("sub")?.Value;
            if (string.IsNullOrEmpty(userId))
                return Unauthorized(new { message = "User not authenticated." });

            // Verify the caller is a referee
            var user = await _supabaseService.GetUserById(userId);
            if (user == null || (user.Role != "referee" && user.Role != "referees_plus"))
                return StatusCode(403, new { message = "Only referees can set category formats." });

            // Verify the referee is assigned to this tournament
            var assignments = await _supabaseService.GetRefereesByTournament(id);
            if (!assignments.Any(a => a.RefereeId == userId))
                return StatusCode(403, new { message = "You are not assigned to this tournament." });

            // Validate format value
            var fmt = (request.Format ?? "").Trim().ToLower();
            if (!AllowedFormats.Contains(fmt))
                return BadRequest(new { message = "Format must be 'single_elimination' or 'round_robin'." });

            var result = await _supabaseService.SetCategoryFormat(categoryId, fmt);
            return Ok(new
            {
                id               = result.Id,
                tournamentId     = result.TournamentId,
                discipline       = result.Discipline,
                gender           = result.Gender,
                ageGroup         = result.AgeGroup,
                weightClass      = result.WeightClass,
                competitionFormat = result.CompetitionFormat
            });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to set category format", error = ex.Message });
        }
    }

    // ── Registration endpoints ─────────────────────────────────────────────

    // Returns all registrations for the currently logged-in player, enriched with
    // tournament name and category label.
    [HttpGet("my-registrations")]
    [Authorize]
    public async Task<IActionResult> GetMyRegistrations()
    {
        try
        {
            var userId = User.FindFirst("sub")?.Value;
            if (string.IsNullOrEmpty(userId))
                return Unauthorized(new { message = "User not authenticated." });

            var registrations = await _supabaseService.GetRegistrationsByUser(userId);

            var enriched = new List<object>();
            foreach (var reg in registrations)
            {
                var tournament = await _supabaseService.GetTournamentById(reg.TournamentId);
                string? categoryLabel = null;
                if (!string.IsNullOrEmpty(reg.CategoryId))
                {
                    var cats = await _supabaseService.GetCategoriesByTournament(reg.TournamentId);
                    var cat  = cats.FirstOrDefault(c => c.Id == reg.CategoryId);
                    if (cat != null)
                        categoryLabel = $"{Capitalize(cat.Discipline)} — {Capitalize(cat.Gender)} — {cat.AgeGroup} — {cat.WeightClass}";
                }

                enriched.Add(new
                {
                    id             = reg.Id,
                    tournamentId   = reg.TournamentId,
                    tournamentName = tournament?.Name ?? "Unknown",
                    startDate      = tournament?.StartDate,
                    categoryId     = reg.CategoryId,
                    categoryLabel,
                    status         = reg.Status,
                    registeredOn   = reg.CreatedAt
                });
            }

            return Ok(enriched);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = "Failed to fetch registrations", error = ex.Message });
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
            var userId = User.FindFirst("sub")?.Value;
            if (string.IsNullOrEmpty(userId))
                return Unauthorized(new { message = "User not authenticated" });

            if (string.IsNullOrWhiteSpace(request.CategoryId))
                return BadRequest(new { message = "CategoryId is required." });

            // Verify the category belongs to this tournament
            var categories = await _supabaseService.GetCategoriesByTournament(id);
            if (!categories.Any(c => c.Id == request.CategoryId))
                return BadRequest(new { message = "Category does not belong to this tournament." });

            var registration = new TournamentRegistration
            {
                TournamentId = id,
                CategoryId   = request.CategoryId,
                UserId       = userId,
                Status       = "pending",
                Notes        = request.Notes
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
