using Microsoft.AspNetCore.Mvc;
using SkfWebsite.Api.Models;
using SkfWebsite.Api.Services;

namespace SkfWebsite.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ClubController : ControllerBase
{
    private readonly ISupabaseService _supabaseService;

    public ClubController(ISupabaseService supabaseService)
    {
        _supabaseService = supabaseService;
    }

    [HttpGet]
    public async Task<IActionResult> GetAllClubs()
    {
        try
        {
            var userRole = HttpContext.Items["UserRole"]?.ToString();
            // Note: SKF Admins and Club Admins can read, or allow public active clubs
            var client = await _supabaseService.GetClient();
            var clubs = await client.From<Club>()
                .Where(c => c.IsActive == true)
                .Get();
            return Ok(clubs.Models);
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = "Error retrieving clubs", error = ex.Message });
        }
    }

    [HttpPost]
    public async Task<IActionResult> CreateClub([FromBody] Club clubDetails)
    {
        try
        {
            var userRole = HttpContext.Items["UserRole"]?.ToString();
            if (userRole != "skf_admin")
            {
                return Unauthorized(new { message = "Only SKF Admin can create clubs" });
            }

            clubDetails.CreatedAt = DateTime.UtcNow;
            clubDetails.UpdatedAt = DateTime.UtcNow;
            clubDetails.IsActive = true;

            var client = await _supabaseService.GetClient();
            var response = await client.From<Club>().Insert(clubDetails);
            return Ok(response.Models.FirstOrDefault());
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = "Error creating club", error = ex.Message });
        }
    }
}
