using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RailLog.API.Models;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

[ApiController]
[Authorize]
[Route("api/statistics")]
public sealed class StatisticsController(RailLogDatabase database) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<StatisticsResponse>> Get() =>
        Ok(await database.GetStatisticsAsync());
}
