using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RailLog.API.Models;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

[ApiController]
[Route("api/entities")]
public sealed class EntityReviewsController(RailLogDatabase database) : ControllerBase
{
    [HttpGet("{type}/{key}/count")]
    [AllowAnonymous]
    public async Task<ActionResult<EntityCountResponse>> Count(string type, string key) => Ok(new EntityCountResponse(type, key, await database.GetEntityCountAsync(type, key)));

    [HttpGet("{type}/{key}/reviews")]
    [AllowAnonymous]
    public async Task<ActionResult<IReadOnlyList<EntityReviewResponse>>> Get(string type, string key) => Ok(await database.GetEntityReviewsAsync(type, key));

    [HttpPost("{type}/{key}/reviews")]
    [Authorize]
    public async Task<ActionResult<EntityReviewResponse>> Post(string type, string key, CreateEntityReviewRequest request)
    {
        if (request.Rating is < 1 or > 5 || string.IsNullOrWhiteSpace(request.Comment)) return BadRequest(new { message = "评分和评论不能为空，评分范围为 1-5" });
        if (!string.Equals(type, request.EntityType, StringComparison.OrdinalIgnoreCase) || !string.Equals(key, request.EntityKey, StringComparison.OrdinalIgnoreCase)) return BadRequest(new { message = "实体参数不匹配" });
        var result = await database.AddEntityReviewAsync(User.FindFirstValue(ClaimTypes.NameIdentifier)!, request);
        return Ok(result);
    }

    [HttpDelete("reviews/{id:long}")]
    [Authorize]
    public async Task<IActionResult> Delete(long id)
    {
        var ok = await database.DeleteEntityReviewAsync(id, User.FindFirstValue(ClaimTypes.NameIdentifier)!);
        return ok ? NoContent() : NotFound();
    }

    [HttpPatch("reviews/{id:long}")]
    [Authorize]
    public async Task<IActionResult> Put(long id, UpdateEntityReviewRequest request)
    {
        if (request.Rating is < 1 or > 5 || string.IsNullOrWhiteSpace(request.Comment)) return BadRequest(new { message = "评分和评论不能为空，评分范围为 1-5" });
        var ok = await database.UpdateEntityReviewAsync(id, User.FindFirstValue(ClaimTypes.NameIdentifier)!, request);
        return ok ? NoContent() : NotFound();
    }
}
