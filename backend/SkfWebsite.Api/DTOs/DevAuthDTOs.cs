namespace SkfWebsite.Api.DTOs;

public class DevRegisterRequest
{
    public string FullName { get; set; } = string.Empty;
    public string NationalId { get; set; } = string.Empty;
    public string Phone { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty; // player | coach | club_admin

    // Optional player-only fields (mirrors auth.js metadata keys)
    public string? AgeGroup { get; set; }
    public string? Rank { get; set; }
    public string? PlayerCategory { get; set; }
}

