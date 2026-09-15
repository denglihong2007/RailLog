using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RailLog.API.Models;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

[ApiController]
[Authorize]
[Route("api/profile")]
public sealed class ProfileController(
    RailLogDatabase database,
    SensitiveWordService sensitiveWords) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<UserProfile>> Get()
    {
        var profile = await database.GetProfileAsync(UserId);
        return profile is null ? NotFound() : Ok(profile);
    }

    [HttpPost]
    public async Task<ActionResult<UserProfile>> Update(UpdateProfileRequest request)
    {
        if (sensitiveWords.ContainsSensitiveWord(request.DisplayName))
            return BadRequest(new MessageResponse("内容不合法"));
        if (sensitiveWords.ContainsSensitiveWord(request.Bio))
            return BadRequest(new MessageResponse("内容不合法"));
        var result = await database.UpdateProfileAsync(UserId, request);
        return result.Profile is null
            ? BadRequest(new MessageResponse(result.Error!))
            : Ok(result.Profile);
    }

    private string UserId => User.FindFirstValue(ClaimTypes.NameIdentifier)!;
}
