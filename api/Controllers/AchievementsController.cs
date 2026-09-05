using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RailLog.API.Models;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

[ApiController]
[Authorize]
[Route("api/achievements")]
public sealed class AchievementsController(RailLogDatabase database) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<AchievementsResponse>> Get() =>
        Ok(await database.GetAchievementsAsync(UserId));

    [HttpGet("{achievementId}/trips")]
    public async Task<ActionResult<AchievementUnlockTripsResponse>> GetTrips(
        string achievementId) =>
        Ok(await database.GetAchievementUnlockTripsAsync(achievementId, UserId));

    private string UserId => User.FindFirstValue(ClaimTypes.NameIdentifier)!;
}
