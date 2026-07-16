using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RailLog.API.Models;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

[ApiController]
[Authorize]
[Route("api/users")]
public sealed class UsersController(RailLogDatabase database) : ControllerBase
{
    [HttpGet("{userId}")]
    public async Task<ActionResult<PublicUserDashboardResponse>> Get(string userId)
    {
        var dashboard = await database.GetPublicUserDashboardAsync(userId);
        return dashboard is null ? NotFound() : Ok(dashboard);
    }
}
