using Microsoft.AspNetCore.Cors;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

[ApiController]
[Route("api/amap")]
[EnableCors("amap-proxy")]
[EnableRateLimiting("amap-proxy")]
public sealed class AmapController(
    AmapProxyService proxy,
    ILogger<AmapController> logger) : ControllerBase
{
    [HttpGet("sdk/maps.js")]
    public Task MapsSdk(CancellationToken cancellationToken) =>
        CopyResponseAsync(proxy.GetMapsSdkAsync, cancellationToken);

    [HttpGet("sdk/loca.js")]
    public Task LocaSdk(CancellationToken cancellationToken) =>
        CopyResponseAsync(proxy.GetLocaSdkAsync, cancellationToken);

    private async Task CopyResponseAsync(
        Func<CancellationToken, Task<HttpResponseMessage>> request,
        CancellationToken cancellationToken)
    {
        try
        {
            using var upstream = await request(cancellationToken);
            Response.StatusCode = (int)upstream.StatusCode;
            Response.ContentType = upstream.Content.Headers.ContentType?.ToString()
                ?? "application/javascript; charset=utf-8";
            if (upstream.Headers.CacheControl is not null)
                Response.Headers.CacheControl = upstream.Headers.CacheControl.ToString();
            await upstream.Content.CopyToAsync(Response.Body, cancellationToken);
        }
        catch (InvalidOperationException exception)
        {
            logger.LogError(exception, "AMap proxy configuration is missing");
            Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
        }
        catch (HttpRequestException exception)
        {
            logger.LogWarning(exception, "AMap upstream request failed");
            Response.StatusCode = StatusCodes.Status502BadGateway;
        }
    }
}
