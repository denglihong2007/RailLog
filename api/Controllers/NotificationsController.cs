using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RailLog.API.Models;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

[ApiController]
[Authorize]
[Route("api/notifications")]
public sealed class NotificationsController(RailLogDatabase database) : ControllerBase
{
    private string CurrentUserId =>
        User.FindFirstValue(ClaimTypes.NameIdentifier)!;

    [HttpGet]
    public async Task<ActionResult<NotificationPageResponse>> Get(
        [FromQuery] int offset = 0,
        [FromQuery] int limit = 20) =>
        Ok(await database.GetNotificationsAsync(CurrentUserId, offset, limit));

    [HttpGet("unread-count")]
    public async Task<ActionResult<NotificationUnreadCountResponse>> GetUnreadCount() =>
        Ok(new NotificationUnreadCountResponse(
            await database.GetNotificationUnreadCountAsync(CurrentUserId)));

    /// <summary>ids 为空表示全部标为已读。</summary>
    [HttpPost("read")]
    public async Task<IActionResult> MarkRead(MarkNotificationsReadRequest request)
    {
        await database.MarkNotificationsReadAsync(CurrentUserId, request.Ids);
        return NoContent();
    }
}
