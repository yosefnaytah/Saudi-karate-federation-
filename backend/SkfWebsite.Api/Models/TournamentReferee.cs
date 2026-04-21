using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace SkfWebsite.Api.Models;

[Table("tournament_referees")]
public class TournamentReferee : BaseModel
{
    [PrimaryKey("id")]
    public string Id { get; set; } = string.Empty;

    [Column("tournament_id")]
    public string TournamentId { get; set; } = string.Empty;

    [Column("referee_id")]
    public string RefereeId { get; set; } = string.Empty;

    [Column("assigned_at")]
    public DateTime AssignedAt { get; set; }
}
