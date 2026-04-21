namespace SkfWebsite.Api.DTOs;

public class CreateTournamentRequest
{
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public string Location { get; set; } = string.Empty;
    public DateTime RegistrationOpenDate { get; set; }
    public DateTime RegistrationCloseDate { get; set; }
    public string Status { get; set; } = "draft"; // draft, registration_open, registration_closed
    public int? MaxParticipants { get; set; }
    public decimal? EntryFee { get; set; }
}

public class UpdateTournamentRequest
{
    public string? Name { get; set; }
    public string? Description { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? EndDate { get; set; }
    public string? Location { get; set; }
    public DateTime? RegistrationOpenDate { get; set; }
    public DateTime? RegistrationCloseDate { get; set; }
    public string? Status { get; set; }
    public int? MaxParticipants { get; set; }
    public decimal? EntryFee { get; set; }
}

public class CreateCategoryRequest
{
    public string Discipline { get; set; } = string.Empty; // kata, kumite
    public string Gender { get; set; } = string.Empty;     // male, female, mixed
    public string AgeGroup { get; set; } = string.Empty;   // U12, U14, U16, U18, U21, Senior, Veteran
    public string WeightClass { get; set; } = string.Empty;
}

public class UpdateCategoryRequest
{
    public string? Discipline { get; set; }
    public string? Gender { get; set; }
    public string? AgeGroup { get; set; }
    public string? WeightClass { get; set; }
}

public class SetCategoryFormatRequest
{
    public string Format { get; set; } = string.Empty; // single_elimination, round_robin
}

public class AssignRefereeRequest
{
    public string RefereeId { get; set; } = string.Empty;
}

public class TournamentRegistrationRequest
{
    public string CategoryId { get; set; } = string.Empty;
    public string? Notes { get; set; }
}
