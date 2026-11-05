using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RailLog.API.Models;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

/// <summary>
/// App 启动时读一次的用户等级分界线。公开接口：等级门槛不涉及任何用户数据，
/// 客户端拿到后会覆盖内置默认值并持久化。
/// </summary>
[ApiController]
[AllowAnonymous]
[Route("api/user-levels")]
public sealed class UserLevelsController(RailLogDatabase database) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<UserLevelThresholdsResponse>> Get()
    {
        var (thresholds, updatedAt) = await database.GetUserLevelThresholdsAsync();
        // 后台改完最多一分钟内生效；对客户端来说足够快，又不会每次启动都打库。
        Response.Headers.CacheControl = "public, max-age=60";
        return Ok(new UserLevelThresholdsResponse(thresholds, updatedAt));
    }
}
