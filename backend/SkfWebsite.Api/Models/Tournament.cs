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
    public string Status { get; set; } = "draft"; // draft, registration_open, registration_closed

    [Column("registration_open_date")]
    public DateTime RegistrationOpenDate { get; set; }

    [Column("registration_close_date")]
    public DateTime RegistrationCloseDate { get; set; }

    [Column("max_participants")]
    public int? MaxParticipants { get; set; }

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
    Draft,               // draft
    RegistrationOpen,    // registration_open
    RegistrationClosed   // registration_closed
}
