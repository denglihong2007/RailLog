using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RailLog.API.Models;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

[ApiController]
[Authorize]
[Route("api/intersections")]
public sealed class IntersectionsController(RailLogDatabase database) : ControllerBase
{
    [HttpGet("{type}/{key}")]
    [Authorize]
    public async Task<ActionResult<IntersectionsResponse>> Get(string type, string key)
    {
        var intersections = await database.GetEntityIntersectionsAsync(UserId, type, key);
        return Ok(new IntersectionsResponse(intersections));
    }

    private string UserId => User.FindFirstValue(ClaimTypes.NameIdentifier)!;
}
