using Microsoft.AspNetCore.Cors;
using Microsoft.AspNetCore.Mvc;
using RailLog.API.Services;
using System.Text.Json.Serialization;

namespace RailLog.API.Controllers;

/// <summary>
/// 历史时刻表按快照日期版本化（<c>yyyy.MM.dd</c>）。版本由 App 端按行程日期推导后传上来，
/// 这里只负责校验它确实存在。可用版本列表见 <c>GET /api/train-timetables/versions</c>。
/// </summary>
[ApiController]
[Route("api/train-timetables")]
[EnableCors("public-api")]
public sealed class TrainTimetablesController(TrainTimetableService service) : ControllerBase
{
    private const string VersionFormatMessage = "版本格式必须为 yyyy.MM.dd";
    private const string VersionUnavailableMessage = "该历史时刻表版本不存在";

    [HttpGet("versions")]
    public async Task<ActionResult<IReadOnlyList<string>>> Versions(
        CancellationToken cancellationToken)
    {
        return Ok(await service.GetVersionsAsync(cancellationToken));
    }

    [HttpGet("search")]
    public async Task<ActionResult<TrainTimetableSearchResponse>> Search(
        [FromQuery] string trainNumber,
        [FromQuery] string version,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(trainNumber))
            return BadRequest(new { message = "车次号不能为空" });
        if (!TrainTimetableService.IsValidVersion(version))
            return BadRequest(new { message = VersionFormatMessage });
        if (!await service.SupportsVersionAsync(version, cancellationToken))
            return BadRequest(new { message = VersionUnavailableMessage });

        var trains = await service.SearchAsync(trainNumber, version, cancellationToken);
        return Ok(new TrainTimetableSearchResponse(version, trains));
    }

    [HttpGet("stations")]
    public async Task<ActionResult<IReadOnlyList<string>>> Stations(
        [FromQuery] string version,
        CancellationToken cancellationToken)
    {
        if (!TrainTimetableService.IsValidVersion(version))
            return BadRequest(new { message = VersionFormatMessage });
        if (!await service.SupportsVersionAsync(version, cancellationToken))
            return BadRequest(new { message = VersionUnavailableMessage });
        return Ok(await service.GetStationsAsync(version, cancellationToken));
    }

    [HttpGet("between")]
    public async Task<ActionResult<TrainTimetableSearchResponse>> Between(
        [FromQuery] string fromStation,
        [FromQuery] string toStation,
        [FromQuery] string version,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(fromStation) || string.IsNullOrWhiteSpace(toStation))
            return BadRequest(new { message = "始发站和终到站不能为空" });
        if (!TrainTimetableService.IsValidVersion(version))
            return BadRequest(new { message = VersionFormatMessage });
        if (!await service.SupportsVersionAsync(version, cancellationToken))
            return BadRequest(new { message = VersionUnavailableMessage });
        var trains = await service.SearchBetweenAsync(fromStation, toStation, version, cancellationToken);
        return Ok(new TrainTimetableSearchResponse(version, trains));
    }

    [HttpGet]
    public async Task<ActionResult<TrainTimetableResponse>> Get(
        [FromQuery] string trainNumber,
        [FromQuery] string version,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(trainNumber))
            return BadRequest(new { message = "车次号不能为空" });
        if (!TrainTimetableService.IsValidVersion(version))
            return BadRequest(new { message = VersionFormatMessage });
        if (!await service.SupportsVersionAsync(version, cancellationToken))
            return BadRequest(new { message = VersionUnavailableMessage });

        var stops = await service.GetAsync(trainNumber, version, cancellationToken);
        return Ok(new TrainTimetableResponse(trainNumber.Trim().ToUpperInvariant(), version, stops));
    }
}

public sealed record TrainTimetableResponse(
    [property: JsonPropertyName("trainNumber")]
    string TrainNumber,
    [property: JsonPropertyName("version")]
    string Version,
    [property: JsonPropertyName("stops")]
    IReadOnlyList<TrainTimetableStop> Stops);

public sealed record TrainTimetableSearchResponse(
    [property: JsonPropertyName("version")]
    string Version,
    [property: JsonPropertyName("trains")]
    IReadOnlyList<TrainTimetableSearchItem> Trains);
