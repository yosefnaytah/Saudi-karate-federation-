using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;
using System;

namespace SkfWebsite.Api.Models;

[Table("contracts")]
public class Contract : BaseModel
{
    [PrimaryKey("id")]
    public string Id { get; set; } = string.Empty;

    [Column("player_id")]
    public string PlayerId { get; set; } = string.Empty;

    [Column("club_id")]
    public string ClubId { get; set; } = string.Empty;

    [Column("start_date")]
    public DateTime StartDate { get; set; }

    [Column("end_date")]
    public DateTime EndDate { get; set; }

    [Column("status")]
    public string Status { get; set; } = "active"; // active, expired, terminated, pending

    [Column("document_url")]
    public string? DocumentUrl { get; set; }

    [Column("created_at")]
    public DateTime CreatedAt { get; set; }

    [Column("updated_at")]
    public DateTime UpdatedAt { get; set; }
}
