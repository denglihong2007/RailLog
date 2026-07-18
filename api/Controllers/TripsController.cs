using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RailLog.API.Models;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

[ApiController]
[Authorize]
[Route("api/trips")]
public sealed class TripsController(RailLogDatabase database) : ControllerBase
{
    [HttpGet("{ticketId:long}")]
    [AllowAnonymous]
    public async Task<ActionResult<PublicTripDetailsResponse>> Get(long ticketId)
    {
        var details = await database.GetPublicTripDetailsAsync(ticketId);
        return details is null ? NotFound() : Ok(details);
    }

    [HttpPost("sync")]
    public async Task<ActionResult<SyncResponse>> Sync(SyncRequest request)
    {
        if (request.Trips.Count > 10_000)
            return BadRequest(new MessageResponse("单次同步的行程数量过多"));
        var trips = await database.SyncTripsAsync(UserId, request.Trips);
        return Ok(new SyncResponse(trips, DateTime.Now));
    }

    private string UserId => User.FindFirstValue(ClaimTypes.NameIdentifier)!;
}
