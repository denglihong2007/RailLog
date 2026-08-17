using Microsoft.AspNetCore.Cors;
using Microsoft.AspNetCore.Mvc;
using RailLog.API.Models;

namespace RailLog.API.Controllers;

[ApiController]
[Route("api/partners")]
[EnableCors("public-api")]
public sealed class PartnersController(IWebHostEnvironment environment) : ControllerBase
{
    private const int HiddenAdvertisementWeight = 40;

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
            30),
        new(
            "railgo",
            "RailGo",
            "RailGo 铁路行",
            "一个多功能铁路信息查询工具。",
            "https://railgo.dev/",
            "RailGo.png",
            "RailGo_icon.png",
            "使用RailGo快捷查询铁路信息",
            20),
        new(
            "crsim",
            "CRSim",
            "CRSim 车站信息显示模拟",
            "铁路信息显示仿真工具，支持引导屏、购票网站模拟等。",
            "https://home.crsim.raillog.top/",
            "CRSim.png",
            "CRSim_icon.png",
            "使用CRSim模拟家乡的火车站",
            10),
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
    public ActionResult<PartnerAdvertisementConfigResponse> GetAdvertisements()
    {
        return Ok(new PartnerAdvertisementConfigResponse(
            HiddenAdvertisementWeight,
            Partners.Select(partner => new PartnerAdvertisementResponse(
                partner.Id,
                partner.AdvertisementText,
                partner.AdvertisementWeight)).ToArray()));
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
