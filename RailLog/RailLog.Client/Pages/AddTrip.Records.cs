namespace RailLog.Client.Pages;

public partial class AddTrip
{
    private sealed record TrainStopInfo(string Station, string? Arrive, string? Depart, decimal Distance, bool HasDistance, int Order);
    private sealed record TrainRollingStockResponse(string RollingStock);
    private sealed record TrainTicketOcrResponse(
        string? TrainNumber,
        DateOnly? TravelDate,
        TimeOnly? DepartureTime,
        string? FromStation,
        string? ToStation,
        string? SeatType,
        string? SeatNumber,
        decimal? Price);
    private sealed record ApiErrorResponse(string? Message);
    private sealed record RouteStationOption(string StationName, int Mileage);
    private sealed record RoutePathResponse(
        bool Found,
        bool IsMileageMatch,
        int TotalMileageKm,
        List<RouteSegmentResponse>? RouteSegments);
    private sealed record RouteSegmentResponse(string RouteName, string FromStation, string ToStation, decimal MileageKm);
}
