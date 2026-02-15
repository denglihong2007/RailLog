namespace RailLog.Models;

public sealed class TrainTicketOcrDto
{
    public string TrainNumber { get; set; } = string.Empty;
    public DateOnly? TravelDate { get; set; }
    public TimeOnly? DepartureTime { get; set; }
    public string FromStation { get; set; } = string.Empty;
    public string ToStation { get; set; } = string.Empty;
    public string SeatType { get; set; } = string.Empty;
    public string SeatNumber { get; set; } = string.Empty;
    public decimal? Price { get; set; }
}
