using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Cors;
using Microsoft.AspNetCore.Mvc;
using RailLog.API.Models;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

[ApiController]
[AllowAnonymous]
[EnableCors("public-api")]
[Route("api/search")]
public sealed class SearchController(RailLogDatabase database) : ControllerBase
{
    private static readonly HashSet<string> EntityTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "station",
        "route",
        "company",
        "rollingstock",
        "train",
    };

    [HttpGet("entities")]
    public async Task<ActionResult<IReadOnlyList<EntitySearchResult>>> SearchEntities(
        [FromQuery] string type,
        [FromQuery] string q = "",
        [FromQuery] int limit = 20)
    {
        if (!EntityTypes.Contains(type.Trim()))
            return BadRequest(new MessageResponse("不支持的实体类型"));
        var query = q.Trim();
        if (query.Length == 0) return Ok(Array.Empty<EntitySearchResult>());
        if (query.Length > 100) return BadRequest(new MessageResponse("搜索关键词过长"));

        var results = await database.SearchEntitiesAsync(
            type.Trim().ToLowerInvariant(),
            query,
            Math.Clamp(limit, 1, 50));
        return Ok(results);
    }

    [HttpGet("users")]
    public async Task<ActionResult<IReadOnlyList<UserSearchResult>>> SearchUsers(
        [FromQuery] string q = "",
        [FromQuery] int limit = 20)
    {
        var query = q.Trim();
        if (query.Length == 0) return Ok(Array.Empty<UserSearchResult>());
        if (query.Length > 100) return BadRequest(new MessageResponse("搜索关键词过长"));

        var results = await database.SearchUsersAsync(query, Math.Clamp(limit, 1, 50));
        return Ok(results);
    }
}
