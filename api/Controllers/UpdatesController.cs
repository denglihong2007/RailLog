using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using RailLog.API.Models;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

[ApiController]
[Route("api/updates")]
public sealed class UpdatesController(
    GitHubReleaseService releaseService,
    IOptions<UpdateOptions> options,
    ILogger<UpdatesController> logger) : ControllerBase
{
    private readonly UpdateOptions _options = options.Value;

    [HttpGet("downloads")]
    public ActionResult<DownloadLinksResponse> Downloads() => Ok(
        new DownloadLinksResponse(
            _options.DomesticDownloadName,
            OptionalUrl(_options.WindowsDomesticDownloadUrl),
            OptionalUrl(_options.AndroidDomesticDownloadUrl)));

    [HttpGet("latest")]
    public async Task<ActionResult<LatestReleaseResponse>> Latest(
        CancellationToken cancellationToken)
    {
        try
        {
            return Ok(await releaseService.GetLatestAsync(cancellationToken));
        }
        catch (HttpRequestException exception)
        {
            logger.LogWarning(exception, "Unable to read the latest GitHub release");
            return StatusCode(
                StatusCodes.Status503ServiceUnavailable,
                new MessageResponse("暂时无法获取最新版本信息"));
        }
        catch (InvalidDataException exception)
        {
            logger.LogError(exception, "GitHub release response was invalid");
            return StatusCode(
                StatusCodes.Status502BadGateway,
                new MessageResponse("版本信息格式异常"));
        }
    }

    private static string? OptionalUrl(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
