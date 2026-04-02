using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace SkfWebsite.Api.Models;

[Table("users")]
public class User : BaseModel
{
    [PrimaryKey("id")]
    public string Id { get; set; } = string.Empty;

    [Column("full_name")]
    public string FullName { get; set; } = string.Empty;

    [Column("national_id")]
    public string NationalId { get; set; } = string.Empty;

    [Column("player_id")]
    public string PlayerId { get; set; } = string.Empty;

    [Column("player_id_card")]
    public string? PlayerIdCard { get; set; }

    [Column("phone")]
    public string Phone { get; set; } = string.Empty;

    [Column("club_name")]
    public string ClubName { get; set; } = string.Empty;

    [Column("email")]
    public string Email { get; set; } = string.Empty;

    [Column("username")]
    public string Username { get; set; } = string.Empty;

    [Column("role")]
    public string Role { get; set; } = string.Empty; // admin, player, coach, referee, club_admin, referees_plus

    [Column("created_at")]
    public DateTime CreatedAt { get; set; }

    [Column("updated_at")]
    public DateTime UpdatedAt { get; set; }

    [Column("is_active")]
    public bool IsActive { get; set; } = true;
}

public enum UserRole
{
    Admin,          // SKF Admin
    Player,
    Coach,
    Referee,
    ClubAdmin,      // Club Admin
    RefereesPlus    // Referees +
}