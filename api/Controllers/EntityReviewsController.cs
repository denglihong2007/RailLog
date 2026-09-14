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
    private static readonly HashSet<string> AllowedReviewReactions =
        ["👍", "❤️", "😂", "😮", "😢", "🎉", "🥵", "🤔", "❔"];

    [HttpGet("{type}/{key}/count")]
    [AllowAnonymous]
    public async Task<ActionResult<EntityCountResponse>> Count(string type, string key) => Ok(new EntityCountResponse(type, key, await database.GetEntityCountAsync(type, key)));

    [HttpGet("{type}/{key}/reviews")]
    [AllowAnonymous]
    public async Task<ActionResult<IReadOnlyList<EntityReviewResponse>>> Get(string type, string key) =>
        Ok(await database.GetEntityReviewsAsync(
            type,
            key,
            User.FindFirstValue(ClaimTypes.NameIdentifier)));

    [HttpPost("{type}/{key}/reviews")]
    [Authorize]
    public async Task<ActionResult<EntityReviewResponse>> Post(string type, string key, CreateEntityReviewRequest request)
    {
        if (request.Rating is < 1 or > 5 || string.IsNullOrWhiteSpace(request.Comment)) return BadRequest(new { message = "评分和评论不能为空，评分范围为 1-5" });
        if (!string.Equals(type, request.EntityType, StringComparison.OrdinalIgnoreCase) || !string.Equals(key, request.EntityKey, StringComparison.OrdinalIgnoreCase)) return BadRequest(new { message = "实体参数不匹配" });
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier)!;
        if (!await database.AreReviewTripsValidAsync(userId, request.TripId, request.SecondTripId))
            return BadRequest(new { message = "关联行程不存在或不属于当前用户" });
        var result = await database.AddEntityReviewAsync(userId, request);
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
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier)!;
        if (!await database.AreReviewTripsValidAsync(userId, request.TripId, request.SecondTripId))
            return BadRequest(new { message = "关联行程不存在或不属于当前用户" });
        var ok = await database.UpdateEntityReviewAsync(id, userId, request);
        return ok ? NoContent() : NotFound();
    }

    [HttpPut("reviews/{id:long}/reaction")]
    [Authorize]
    public async Task<IActionResult> SetReaction(
        long id,
        SetEntityReviewReactionRequest request)
    {
        if (!AllowedReviewReactions.Contains(request.Emoji))
            return BadRequest(new { message = "请选择有效的表情" });
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier)!;
        var ok = await database.SetEntityReviewReactionAsync(
            id,
            userId,
            request.Emoji);
        return ok
            ? NoContent()
            : BadRequest(new { message = "不能回复自己的评价或评价不存在" });
    }

    [HttpDelete("reviews/{id:long}/reaction")]
    [Authorize]
    public async Task<IActionResult> RemoveReaction(long id)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier)!;
        var ok = await database.RemoveEntityReviewReactionAsync(id, userId);
        return ok ? NoContent() : NotFound();
    }
}
