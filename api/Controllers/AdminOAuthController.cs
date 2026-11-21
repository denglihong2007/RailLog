using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RailLog.API.Models;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

/// <summary>合作应用（OAuth 客户端）的登记与停用。</summary>
[ApiController]
[Authorize(AuthenticationSchemes = AdminAuthenticationHandler.SchemeName)]
[Route("api/admin/oauth")]
public sealed class AdminOAuthController(
    RailLogDatabase database,
    ILogger<AdminOAuthController> logger) : ControllerBase
{
    private string? AdminUserId => User.FindFirstValue(ClaimTypes.NameIdentifier);

    [HttpGet("clients")]
    public async Task<ActionResult<IReadOnlyList<OAuthClientSummary>>> GetClients()
    {
        var clients = await database.GetOAuthClientsAsync();
        return Ok(clients
            .Select(client => new OAuthClientSummary(
                client.ClientId,
                client.Name,
                client.LogoUrl,
                client.RedirectUris,
                client.Scopes,
                client.CreatedAt,
                client.RevokedAt))
            .ToList());
    }

    /// <summary>登记一个合作应用。client_secret 只在创建时返回一次，数据库只存哈希。</summary>
    [HttpPost("clients")]
    public async Task<ActionResult<CreateOAuthClientResponse>> CreateClient(
        CreateOAuthClientRequest request)
    {
        var name = request.Name?.Trim() ?? string.Empty;
        if (name.Length is < 1 or > 80)
            return BadRequest(new MessageResponse("应用名称长度应为 1 至 80 个字符"));

        var redirectUris = (request.RedirectUris ?? [])
            .Select(item => item?.Trim() ?? string.Empty)
            .Where(item => item.Length > 0)
            .Distinct(StringComparer.Ordinal)
            .ToList();
        if (redirectUris.Count is < 1 or > 10)
            return BadRequest(new MessageResponse("需要 1 至 10 个回调地址"));
        foreach (var uri in redirectUris)
        {
            if (!IsValidRedirectUri(uri))
                return BadRequest(new MessageResponse($"回调地址不合法：{uri}"));
        }

        var scopes = (request.Scopes ?? [])
            .Select(item => item?.Trim() ?? string.Empty)
            .Where(item => item.Length > 0)
            .Distinct(StringComparer.Ordinal)
            .ToList();
        if (scopes.Count == 0) scopes = ["profile"];
        if (scopes.Any(scope => scope != "profile"))
            return BadRequest(new MessageResponse("目前只支持 profile 权限"));

        var logoUrl = request.LogoUrl?.Trim();
        if (!string.IsNullOrEmpty(logoUrl) && !IsValidHttpsUrl(logoUrl))
            return BadRequest(new MessageResponse("图标地址必须是 https 链接"));

        var clientId = OAuthCrypto.NewClientId();
        var clientSecret = OAuthCrypto.NewToken();
        await database.CreateOAuthClientAsync(
            clientId,
            name,
            string.IsNullOrEmpty(logoUrl) ? null : logoUrl,
            RailLogDatabase.HashToken(clientSecret),
            redirectUris,
            scopes);
        await AuditAsync("oauth-client.create", clientId, name);
        return Ok(new CreateOAuthClientResponse(
            clientId, clientSecret, name, redirectUris, scopes));
    }

    [HttpPost("clients/{clientId}/revoke")]
    public async Task<IActionResult> RevokeClient(string clientId)
    {
        if (!await database.RevokeOAuthClientAsync(clientId))
            return NotFound(new MessageResponse("没有找到该应用"));
        await AuditAsync("oauth-client.revoke", clientId);
        return NoContent();
    }

    private async Task AuditAsync(string action, string? target = null, string? detail = null)
    {
        var adminUserId = AdminUserId;
        if (string.IsNullOrWhiteSpace(adminUserId)) return;
        try
        {
            await database.WriteAdminAuditAsync(adminUserId, action, target, detail);
        }
        catch (Exception exception)
        {
            // 审计失败不影响已经完成的业务操作。
            logger.LogError(exception, "Failed to write admin audit entry {Action}", action);
        }
    }

    private static bool IsValidRedirectUri(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri)) return false;
        if (uri.Fragment.Length > 0) return false;
        return uri.Scheme switch
        {
            "https" => uri.Host.Length > 0,
            "http" => uri.Host is "localhost" or "127.0.0.1",
            // 移动端的私有 scheme，例如 railkale://oauth/callback
            _ => uri.Scheme.Length > 1 && uri.Host.Length > 0,
        };
    }

    private static bool IsValidHttpsUrl(string value) =>
        Uri.TryCreate(value, UriKind.Absolute, out var uri) &&
        uri.Scheme == Uri.UriSchemeHttps &&
        uri.Host.Length > 0;
}
