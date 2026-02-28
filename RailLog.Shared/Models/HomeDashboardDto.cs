namespace RailLog.Shared.Models;

public sealed class HomeDashboardDto
{
    public DashboardStatsDto Stats { get; init; } = DashboardStatsDto.Empty;

    public List<AchievementItemDto> Achievements { get; init; } = [];

    public PersonalOverlapSummaryDto OverlapSummary { get; init; } = PersonalOverlapSummaryDto.Empty;
}
