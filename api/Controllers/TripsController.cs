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
    [HttpPost("sync")]
    public async Task<ActionResult<SyncResponse>> Sync(SyncRequest request)
    {
        if (request.Trips.Count > 10_000)
            return BadRequest(new MessageResponse("单次同步的行程数量过多"));
        var trips = await database.SyncTripsAsync(UserId, request.Trips);
        return Ok(new SyncResponse(trips, DateTime.UtcNow));
    }

    private string UserId => User.FindFirstValue(ClaimTypes.NameIdentifier)!;
}
