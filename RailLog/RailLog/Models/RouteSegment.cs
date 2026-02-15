namespace RailLog.Models;

public sealed record RouteSegment(
    string RouteName,
    string FromStation,
    string ToStation,
    int MileageKm);
