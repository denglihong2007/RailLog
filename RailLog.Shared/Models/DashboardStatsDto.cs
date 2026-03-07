namespace RailLog.Shared.Models;

public sealed class DashboardStatsDto
{
    public static DashboardStatsDto Empty { get; } = new();

    public int OverallTotalTrips { get; init; }

    public decimal OverallTotalMileageKm { get; init; }

    public int NonRailTrips { get; init; }

    public decimal NonRailMileageKm { get; init; }

    public int TotalTrips { get; init; }

    public decimal TotalSpend { get; init; }

    public decimal HighestFare { get; init; }

    public decimal TotalMileageKm { get; init; }

    public decimal LongestTripMileageKm { get; init; }

    public int UniqueRoutes { get; init; }

    public string RouteStatHint { get; init; } = "按经由线路去重";

    public int UniqueRollingStockTypes { get; init; }

    public int RollingStockRecords { get; init; }

    public int UniqueStations { get; init; }

    public List<VisitRankItemDto> TopRouteVisits { get; init; } = [];

    public List<VisitRankItemDto> TopStationVisits { get; init; } = [];

    public int UniqueTrainNumbers { get; init; }

    public int UniqueSeatTypes { get; init; }

    public DateOnly? FirstTripDate { get; init; }

    public DateOnly? LatestTripDate { get; init; }

    public string ExplorerLevel { get; init; } = "见习铁路迷";
}

public sealed class VisitRankItemDto
{
    public string Name { get; init; } = string.Empty;

    public int Count { get; init; }
}

public sealed class AchievementItemDto
{
    public string Name { get; init; } = string.Empty;

    public string IconClass { get; init; } = string.Empty;

    public int Tier { get; init; }

    public string TierName { get; init; } = string.Empty;

    public bool Unlocked { get; init; }

    public string CurrentText { get; init; } = string.Empty;

    public string NextLevelText { get; init; } = string.Empty;

    public string TargetText { get; init; } = string.Empty;
}
