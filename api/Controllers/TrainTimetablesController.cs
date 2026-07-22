using Microsoft.AspNetCore.Mvc;
using RailLog.API.Services;
using System.Text.Json.Serialization;

namespace RailLog.API.Controllers;

[ApiController]
[Route("api/train-timetables")]
public sealed class TrainTimetablesController(TrainTimetableService service) : ControllerBase
{
    [HttpGet("search")]
    public async Task<ActionResult<TrainTimetableSearchResponse>> Search(
        [FromQuery] string trainNumber,
        [FromQuery] int year,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(trainNumber))
            return BadRequest(new { message = "车次号不能为空" });
        if (year is < 2009 or > 2024)
            return BadRequest(new { message = "历史时刻表年份必须在 2009-2024 之间" });

        var trains = await service.SearchAsync(trainNumber, year, cancellationToken);
        return Ok(new TrainTimetableSearchResponse(year, trains));
    }

    [HttpGet]
    public async Task<ActionResult<TrainTimetableResponse>> Get(
        [FromQuery] string trainNumber,
        [FromQuery] int year,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(trainNumber))
            return BadRequest(new { message = "车次号不能为空" });
        if (year is < 2009 or > 2024)
            return BadRequest(new { message = "历史时刻表年份必须在 2009-2024 之间" });

        var stops = await service.GetAsync(trainNumber, year, cancellationToken);
        return Ok(new TrainTimetableResponse(trainNumber.Trim().ToUpperInvariant(), year, stops));
    }
}

public sealed record TrainTimetableResponse(
    [property: JsonPropertyName("trainNumber")] 
    string TrainNumber,
    [property: JsonPropertyName("year")]
    int Year,
    [property: JsonPropertyName("stops")]
    IReadOnlyList<TrainTimetableStop> Stops);

public sealed record TrainTimetableSearchResponse(
    int Year,
    IReadOnlyList<TrainTimetableSearchItem> Trains);
