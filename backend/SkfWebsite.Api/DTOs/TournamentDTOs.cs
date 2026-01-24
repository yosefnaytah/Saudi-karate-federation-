namespace SkfWebsite.Api.DTOs;

public class CreateTournamentRequest
{
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public string Location { get; set; } = string.Empty;
    public int? MaxParticipants { get; set; }
    public DateTime RegistrationDeadline { get; set; }
    public decimal? EntryFee { get; set; }
}

public class TournamentRegistrationRequest
{
    public string? WeightCategory { get; set; }
    public string? BeltLevel { get; set; }
    public string? Notes { get; set; }
}