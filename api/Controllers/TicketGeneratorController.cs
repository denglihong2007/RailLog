using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using RailLog.API.Models;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

[ApiController]
[Authorize]
[Route("api/ticket-generator")]
public sealed class TicketGeneratorController(
    TicketGeneratorService generator,
    ILogger<TicketGeneratorController> logger) : ControllerBase
{
    [HttpPost("image")]
    public Task<IActionResult> Image(GenerateTicketRequest request, CancellationToken cancellationToken) =>
        Generate(request, pdf: false, cancellationToken);

    [HttpPost("pdf-key")]
    public async Task<IActionResult> PdfKey(CreateTicketPdfKeyRequest request)
    {
        try
        {
            var result = await generator.CreatePdfKeyAsync(request);
            if (result is null) return NotFound(new MessageResponse("未找到所选行程记录"));
            Response.Headers.CacheControl = "private, no-store";
            return Ok(result);
        }
        catch (TicketRequestException exception)
        {
            return BadRequest(new MessageResponse(exception.Message));
        }
    }

    [AllowAnonymous]
    [EnableRateLimiting("ticket-pdf")]
    [HttpPost("web-pdf")]
    public async Task<IActionResult> WebPdf(
        DownloadTicketPdfRequest request,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await generator.GenerateWebDownloadAsync(request, cancellationToken);
            if (result is null) return NotFound(new MessageResponse("未找到所选行程记录"));
            Response.Headers.CacheControl = "private, no-store";
            var stream = new FileStream(
                result.FilePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 64 * 1024,
                options: FileOptions.DeleteOnClose | FileOptions.SequentialScan);
            return File(stream, result.ContentType, result.FileName);
        }
        catch (TicketPdfPasswordException)
        {
            return Unauthorized(new MessageResponse("下载密码错误"));
        }
        catch (TicketPdfKeyException)
        {
            return NotFound(new MessageResponse("Key 无效或已过期"));
        }
        catch (TicketRequestException exception)
        {
            return BadRequest(new MessageResponse(exception.Message));
        }
        catch (TicketAssetException exception)
        {
            logger.LogError(exception, "Ticket PDF generator is unavailable");
            return StatusCode(
                StatusCodes.Status503ServiceUnavailable,
                new MessageResponse("PDF 下载服务未配置或暂不可用"));
        }
        catch (HttpRequestException)
        {
            return StatusCode(StatusCodes.Status502BadGateway, new MessageResponse("二维码服务暂时不可用"));
        }
    }

    private async Task<IActionResult> Generate(
        GenerateTicketRequest request,
        bool pdf,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await generator.GenerateAsync(request, pdf, cancellationToken);
            if (result is null) return NotFound(new MessageResponse("未找到这条行程记录"));
            var extension = pdf ? "pdf" : "png";
            var contentType = pdf ? "application/pdf" : "image/png";
            Response.Headers.CacheControl = "private, no-store";
            return File(result.Bytes, contentType, $"RailLog_{result.TicketNumber}.{extension}");
        }
        catch (TicketRequestException exception)
        {
            return BadRequest(new MessageResponse(exception.Message));
        }
        catch (TicketAssetException exception)
        {
            logger.LogError(exception, "Ticket generator assets are unavailable");
            return StatusCode(
                StatusCodes.Status503ServiceUnavailable,
                new MessageResponse("服务端车票素材未配置或不可用"));
        }
        catch (HttpRequestException)
        {
            return StatusCode(StatusCodes.Status502BadGateway, new MessageResponse("二维码服务暂时不可用"));
        }
    }
}
