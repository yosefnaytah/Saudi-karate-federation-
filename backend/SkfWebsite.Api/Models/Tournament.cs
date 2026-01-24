using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace SkfWebsite.Api.Models;

[Table("tournaments")]
public class Tournament : BaseModel
{
    [PrimaryKey("id")]
    public string Id { get; set; } = string.Empty;

    [Column("name")]
    public string Name { get; set; } = string.Empty;

    [Column("description")]
    public string? Description { get; set; }

    [Column("start_date")]
    public DateTime StartDate { get; set; }

    [Column("end_date")]
    public DateTime EndDate { get; set; }

    [Column("location")]
    public string Location { get; set; } = string.Empty;

    [Column("status")]
    public string Status { get; set; } = string.Empty; // upcoming, live, completed, cancelled

    [Column("max_participants")]
    public int? MaxParticipants { get; set; }

    [Column("registration_deadline")]
    public DateTime RegistrationDeadline { get; set; }

    [Column("entry_fee")]
    public decimal? EntryFee { get; set; }

    [Column("created_by")]
    public string CreatedBy { get; set; } = string.Empty;

    [Column("created_at")]
    public DateTime CreatedAt { get; set; }

    [Column("updated_at")]
    public DateTime UpdatedAt { get; set; }

    [Column("is_active")]
    public bool IsActive { get; set; } = true;
}

public enum TournamentStatus
{
    Upcoming,
    Live,
    Completed,
    Cancelled
}