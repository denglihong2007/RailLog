namespace RailLog.Shared.Models;

public sealed class PersonalOverlapSummaryDto
{
    public static PersonalOverlapSummaryDto Empty { get; } = new();

    public List<TrainOverlapEntryDto> TrainOverlaps { get; init; } = [];

    public List<StationOverlapEntryDto> StationOverlaps { get; init; } = [];
}

public sealed class TrainOverlapEntryDto
{
    public string UserId { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;

    public string? AvatarUrl { get; init; }

    public string TrainNumber { get; init; } = string.Empty;

    public DateOnly OtherTravelDate { get; init; }

    public int TripId { get; init; }

    public List<DateOnly> MyTravelDates { get; init; } = [];
}

public sealed class StationOverlapEntryDto
{
    public string UserId { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;

    public string? AvatarUrl { get; init; }

    public string StationName { get; init; } = string.Empty;

    public DateOnly OtherTravelDate { get; init; }

    public int TripId { get; init; }

    public List<DateOnly> MyVisitDates { get; init; } = [];
}
