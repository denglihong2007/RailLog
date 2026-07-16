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
    [HttpGet]
    public async Task<ActionResult<IntersectionsResponse>> Get()
    {
        var intersections = await database.GetIntersectionsAsync(UserId);
        return Ok(new IntersectionsResponse(intersections));
    }

    private string UserId => User.FindFirstValue(ClaimTypes.NameIdentifier)!;
}
