namespace RailLog.Shared.Models;

public sealed class ProfilePageDto
{
    public required PublicUserProfileDto Profile { get; init; }

    public DashboardStatsDto Stats { get; init; } = DashboardStatsDto.Empty;

    public List<AchievementItemDto> Achievements { get; init; } = [];

    public List<TripRecordDto> Trips { get; init; } = [];
}
