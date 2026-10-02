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
        [FromQuery] int? limit,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(trainNumber))
            return BadRequest(new { message = "车次号不能为空" });
        if (!TrainTimetableService.IsValidVersion(version))
            return BadRequest(new { message = VersionFormatMessage });
        if (!await service.SupportsVersionAsync(version, cancellationToken))
            return BadRequest(new { message = VersionUnavailableMessage });

        // limit 不传就是不截断（旧行为）；要收敛结果集的调用方自己传。
        var trains = await service.SearchAsync(trainNumber, version, limit, cancellationToken);
        return Ok(new TrainTimetableSearchResponse(version, trains));
    }

    /// <summary>某一站停靠的全部车次，附在该站的到发时刻。</summary>
    [HttpGet("at-station")]
    public async Task<ActionResult<TrainTimetableAtStationResponse>> AtStation(
        [FromQuery] string station,
        [FromQuery] string version,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(station))
            return BadRequest(new { message = "车站名不能为空" });
        if (!TrainTimetableService.IsValidVersion(version))
            return BadRequest(new { message = VersionFormatMessage });
        if (!await service.SupportsVersionAsync(version, cancellationToken))
            return BadRequest(new { message = VersionUnavailableMessage });

        var trains = await service.GetTrainsAtStationAsync(station, version, cancellationToken);
        return Ok(new TrainTimetableAtStationResponse(version, trains));
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
    public async Task<ActionResult<TrainTimetableBetweenResponse>> Between(
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
        return Ok(new TrainTimetableBetweenResponse(version, trains));
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

        var schedule = await service.GetAsync(trainNumber, version, cancellationToken);
        return Ok(new TrainTimetableResponse(
            trainNumber.Trim().ToUpperInvariant(),
            version,
            schedule.TrainCodes,
            schedule.Stops));
    }
}

/// <summary>
/// 单车次站序。<c>trainNumber</c> 复述请求里的号（这趟车可能挂好几个号），
/// <c>train_codes</c> 才是展示用的号对 <c>D111/D114</c>。
/// </summary>
public sealed record TrainTimetableResponse(
    [property: JsonPropertyName("trainNumber")]
    string TrainNumber,
    [property: JsonPropertyName("version")]
    string Version,
    [property: JsonPropertyName("train_codes")]
    string TrainCodes,
    [property: JsonPropertyName("stops")]
    IReadOnlyList<TrainTimetableStop> Stops);

public sealed record TrainTimetableSearchResponse(
    [property: JsonPropertyName("version")]
    string Version,
    [property: JsonPropertyName("trains")]
    IReadOnlyList<TrainTimetableSearchItem> Trains);

public sealed record TrainTimetableAtStationResponse(
    [property: JsonPropertyName("version")]
    string Version,
    [property: JsonPropertyName("trains")]
    IReadOnlyList<TrainTimetableAtStationItem> Trains);

public sealed record TrainTimetableBetweenResponse(
    [property: JsonPropertyName("version")]
    string Version,
    [property: JsonPropertyName("trains")]
    IReadOnlyList<TrainTimetableBetweenItem> Trains);
