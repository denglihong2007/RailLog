namespace RailLog.Models;

public sealed record TrainTicketOcrResult(bool Success, string Message, TrainTicketOcrDto? Data)
{
    public static TrainTicketOcrResult Succeeded(TrainTicketOcrDto data) => new(true, "识别成功。", data);
    public static TrainTicketOcrResult Failed(string message) => new(false, message, null);
}
