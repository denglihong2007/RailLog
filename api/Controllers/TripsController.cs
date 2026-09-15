using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Cors;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.Sqlite;
using RailLog.API.Models;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

[ApiController]
[Authorize]
[Route("api/trips")]
public sealed class TripsController(
    RailLogDatabase database,
    SensitiveWordService sensitiveWords,
    ILogger<TripsController> logger) : ControllerBase
{
    [HttpGet("{ticketId:long}")]
    [AllowAnonymous]
    [EnableCors("public-api")]
    public async Task<ActionResult<PublicTripDetailsResponse>> Get(long ticketId)
    {
        var details = await database.GetPublicTripDetailsAsync(ticketId);
        return details is null ? NotFound() : Ok(details);
    }

    [HttpGet("{ticketId:long}/reviews")]
    [AllowAnonymous]
    [EnableCors("public-api")]
    public async Task<ActionResult<IReadOnlyList<EntityReviewResponse>>> GetReviews(long ticketId) =>
        Ok(await database.GetTripReviewsAsync(
            ticketId,
            User.FindFirstValue(ClaimTypes.NameIdentifier)));

    [HttpGet("{ticketId:long}/travel-guide")]
    public async Task<ActionResult<IReadOnlyList<EntityReviewResponse>>> GetTravelGuide(long ticketId)
    {
        var reviews = await database.GetTravelGuideReviewsAsync(ticketId, UserId);
        return reviews is null ? NotFound() : Ok(reviews);
    }

    [HttpGet("travel-guide")]
    public async Task<ActionResult<IReadOnlyList<EntityReviewResponse>>> GetHomeTravelGuide() =>
        Ok(await database.GetHomeTravelGuideReviewsAsync(UserId));

    [HttpPost("sync")]
    public async Task<ActionResult<SyncResponse>> Sync(SyncRequest request)
    {
        if (request.Trips.Count > 10_000)
            return BadRequest(new MessageResponse("单次同步的行程数量过多"));
        if (request.Trips.Any(trip => sensitiveWords.ContainsSensitiveWord(trip.Notes)))
            return BadRequest(new MessageResponse("内容不合法"));
        var serverTime = DateTime.UtcNow;
        try
        {
            var result = await database.SyncTripsAsync(
                UserId,
                request.Trips,
                request.Since,
                request.SinceVersion,
                serverTime);
            return Ok(new SyncResponse(result.Trips, serverTime, result.ServerVersion));
        }
        catch (SqliteException exception)
            when (exception.SqliteErrorCode is 5 or 6)
        {
            logger.LogWarning(exception, "Trip sync database remained busy for user {UserId}", UserId);
            return StatusCode(
                StatusCodes.Status503ServiceUnavailable,
                new MessageResponse("同步服务繁忙，请稍后重试"));
        }
    }

    private string UserId => User.FindFirstValue(ClaimTypes.NameIdentifier)!;
}
