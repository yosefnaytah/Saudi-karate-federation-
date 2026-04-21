using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace SkfWebsite.Api.Models;

[Table("tournament_registrations")]
public class TournamentRegistration : BaseModel
{
    [PrimaryKey("id")]
    public string Id { get; set; } = string.Empty;

    [Column("tournament_id")]
    public string TournamentId { get; set; } = string.Empty;

    [Column("category_id")]
    public string? CategoryId { get; set; }

    [Column("user_id")]
    public string UserId { get; set; } = string.Empty;

    [Column("weight_category")]
    public string? WeightCategory { get; set; }

    [Column("belt_level")]
    public string? BeltLevel { get; set; }

    [Column("registration_date")]
    public DateTime RegistrationDate { get; set; }

    [Column("status")]
    public string Status { get; set; } = "pending"; // pending, approved, rejected

    [Column("notes")]
    public string? Notes { get; set; }

    [Column("created_at")]
    public DateTime CreatedAt { get; set; }

    [Column("updated_at")]
    public DateTime UpdatedAt { get; set; }
}
