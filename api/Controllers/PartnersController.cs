using Microsoft.AspNetCore.Cors;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using RailLog.API.Models;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

[ApiController]
[Route("api/partners")]
[EnableCors("public-api")]
public sealed class PartnersController(
    IWebHostEnvironment environment,
    RailLogDatabase database,
    IOptions<AnnouncementOptions> announcementOptions) : ControllerBase
{
    private const int HiddenAdvertisementWeight = 0;

    private readonly AnnouncementOptions _announcements = announcementOptions.Value;

    private static readonly IReadOnlyList<PartnerDefinition> Partners =
    [
        new(
            "ct-photos",
            "CT Photos",
            "CT Photos 中国铁路摄影平台",
            "面向国内铁路摄影爱好者的垂直影像归档与分享平台。",
            "https://train.idcmoss.cn/",
            "CTPhotos.jpg",
            "CTPhotos_icon.png",
            "在CT Photos看见火车迷们拍摄的列车图片",
            15),
        new(
            "railgo",
            "RailGo",
            "RailGo 铁路行",
            "一个多功能铁路信息查询工具。",
            "https://railgo.dev/",
            "RailGo.png",
            "RailGo_icon.png",
            "使用RailGo快捷查询铁路信息",
            10),
        new(
            "crsim",
            "CRSim",
            "CRSim 车站信息显示模拟",
            "铁路信息显示仿真工具，支持引导屏、购票网站模拟等。",
            "https://home.crsim.raillog.top/",
            "CRSim.png",
            "CRSim_icon.png",
            "使用CRSim模拟家乡的火车站",
            5),
    ];

    [HttpGet]
    public ActionResult<IReadOnlyList<PartnerApplicationResponse>> Get()
    {
        return Ok(Partners.Select(partner => new PartnerApplicationResponse(
            partner.Id,
            partner.Name,
            partner.Title,
            partner.Description,
            partner.WebsiteUrl,
            $"/api/partners/{partner.Id}/poster",
            $"/api/partners/{partner.Id}/icon")));
    }

    [HttpGet("advertisements")]
    public async Task<ActionResult<PartnerAdvertisementConfigResponse>> GetAdvertisements()
    {
        // 公告以管理员后台维护的数据库记录为准；只有表里一条记录都没有时
        // 才回退到 appsettings，避免升级瞬间丢掉已有公告。若管理员把所有
        // 公告都下线，数据库仍算「已接管」，不会再回退。
        var stored = await database.GetActiveAnnouncementsAsync();
        var useStored = stored.Count > 0 || await database.HasAnnouncementsAsync();
        var announcements = useStored
            ? stored.ToArray()
            : _announcements.Items
                .Select(text => text?.Trim() ?? string.Empty)
                .Where(text => text.Length > 0)
                .Select(text => new SystemAnnouncementResponse(
                    text, Math.Max(0, _announcements.Weight)))
                .ToArray();
        return Ok(new PartnerAdvertisementConfigResponse(
            HiddenAdvertisementWeight,
            Partners.Select(partner => new PartnerAdvertisementResponse(
                partner.Id,
                partner.AdvertisementText,
                partner.AdvertisementWeight)).ToArray(),
            announcements));
    }

    [HttpGet("{id}/poster")]
    public IActionResult Poster(string id) => Asset(id, partner => partner.PosterFile);

    [HttpGet("{id}/icon")]
    public IActionResult Icon(string id) => Asset(id, partner => partner.IconFile);

    private IActionResult Asset(string id, Func<PartnerDefinition, string> selectFile)
    {
        var partner = Partners.FirstOrDefault(
            item => string.Equals(item.Id, id, StringComparison.OrdinalIgnoreCase));
        if (partner is null) return NotFound();

        var fileName = selectFile(partner);
        var path = Path.Combine(environment.ContentRootPath, "Assets", "ads", fileName);
        if (!System.IO.File.Exists(path)) return NotFound();
        var contentType = Path.GetExtension(fileName).Equals(".jpg", StringComparison.OrdinalIgnoreCase)
            ? "image/jpeg"
            : "image/png";
        return PhysicalFile(path, contentType, enableRangeProcessing: true);
    }

    private sealed record PartnerDefinition(
        string Id,
        string Name,
        string Title,
        string Description,
        string WebsiteUrl,
        string PosterFile,
        string IconFile,
        string AdvertisementText,
        int AdvertisementWeight);
}
