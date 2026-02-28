namespace RailLog.Shared.Models;

public sealed class GlobalLeaderboardDto
{
    public static GlobalLeaderboardDto Empty { get; } = new();

    public List<LeaderboardEntryDto> TopBySpend { get; init; } = [];

    public List<LeaderboardEntryDto> TopByTrips { get; init; } = [];

    public List<LeaderboardEntryDto> TopByMileage { get; init; } = [];

    public List<TripLeaderboardEntryDto> TopSingleBySpend { get; init; } = [];

    public List<TripLeaderboardEntryDto> TopSingleByMileage { get; init; } = [];

    public List<TripLeaderboardEntryDto> TopSingleLatest { get; init; } = [];

    public List<ElementLeaderboardEntryDto> TopStationsByVisits { get; init; } = [];

    public List<ElementLeaderboardEntryDto> TopTrainsByTrips { get; init; } = [];

    public List<ElementLeaderboardEntryDto> TopRoutesByTrips { get; init; } = [];
}

public sealed class LeaderboardEntryDto
{
    public string UserId { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;

    public string? AvatarUrl { get; init; }

    public decimal TotalSpend { get; init; }

    public int TotalTrips { get; init; }

    public decimal TotalMileageKm { get; init; }
}

public sealed class TripLeaderboardEntryDto
{
    public int TripId { get; init; }

    public string UserId { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;

    public string? AvatarUrl { get; init; }

    public string TrainNumber { get; init; } = string.Empty;

    public string FromStation { get; init; } = string.Empty;

    public string ToStation { get; init; } = string.Empty;

    public DateOnly TravelDate { get; init; }

    public DateTime CreatedAt { get; init; }

    public decimal Price { get; init; }

    public decimal MileageKm { get; init; }
}

public sealed class ElementLeaderboardEntryDto
{
    public string Name { get; init; } = string.Empty;

    public int Count { get; init; }
}
