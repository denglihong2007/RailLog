namespace RailLog.Models;

public sealed record RoutePathResult(
    IReadOnlyList<string> Stations,
    IReadOnlyList<string> Routes,
    IReadOnlyList<RouteSegment> RouteSegments,
    int TotalMileageKm,
    bool IsMileageMatch)
{
    public string StationsText => string.Join(" -> ", Stations);
    public string RoutesText => string.Join(" -> ", Routes);
}
