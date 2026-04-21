using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace SkfWebsite.Api.Models;

[Table("tournament_categories")]
public class TournamentCategory : BaseModel
{
    [PrimaryKey("id")]
    public string Id { get; set; } = string.Empty;

    [Column("tournament_id")]
    public string TournamentId { get; set; } = string.Empty;

    [Column("discipline")]
    public string Discipline { get; set; } = string.Empty;

    [Column("gender")]
    public string Gender { get; set; } = string.Empty;

    [Column("age_group")]
    public string AgeGroup { get; set; } = string.Empty;

    [Column("weight_class")]
    public string WeightClass { get; set; } = string.Empty;

    [Column("competition_format")]
    public string? CompetitionFormat { get; set; }

    [Column("created_at")]
    public DateTime CreatedAt { get; set; }

    [Column("updated_at")]
    public DateTime UpdatedAt { get; set; }
}
