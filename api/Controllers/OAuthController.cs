using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Cors;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.WebUtilities;
using RailLog.API.Models;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

/// <summary>
/// OAuth 2.0 授权服务器（授权码 + PKCE）。
///
/// 授权页本身由 <c>www.raillog.top/oauth/</c> 的 Vue 页面承担，这里只提供接口：
/// <list type="bullet">
/// <item><c>GET authorize</c>：校验应用与回调地址，返回展示信息</item>
/// <item><c>POST authorize/decision</c>：已登录用户在授权页确认后签发授权码</item>
/// <item><c>POST token</c>：授权码换令牌、刷新令牌轮换</item>
/// <item><c>POST revoke</c>：撤销令牌</item>
/// <item><c>GET userinfo</c>：返回当前令牌对应的用户 ID</item>
/// </list>
/// 所有凭据（授权码、令牌、client_secret）都只在数据库里保存 SHA-256。
/// </summary>
[ApiController]
[Route("api/oauth")]
public sealed class OAuthController(RailLogDatabase database) : ControllerBase
{
    private static readonly TimeSpan AuthorizationCodeLifetime = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan AccessTokenLifetime = TimeSpan.FromHours(1);
    private static readonly TimeSpan RefreshTokenLifetime = TimeSpan.FromDays(90);

    /// <summary>目前只开放 profile（用户 ID、昵称、头像）；行程数据仍走公开接口。</summary>
    private static readonly HashSet<string> KnownScopes = ["profile"];

    [HttpGet("authorize")]
    [AllowAnonymous]
    [EnableRateLimiting("oauth-authorize")]
    public async Task<ActionResult<OAuthClientInfoResponse>> Authorize(
        [FromQuery(Name = "client_id")] string? clientId,
        [FromQuery(Name = "redirect_uri")] string? redirectUri,
        [FromQuery(Name = "response_type")] string? responseType,
        [FromQuery(Name = "scope")] string? scope,
        [FromQuery(Name = "state")] string? state,
        [FromQuery(Name = "code_challenge")] string? codeChallenge,
        [FromQuery(Name = "code_challenge_method")] string? codeChallengeMethod)
    {
        Response.Headers.CacheControl = "no-store";
        Response.Headers.Pragma = "no-cache";
        var validation = await ValidateAuthorizeRequestAsync(
            clientId, redirectUri, responseType, scope, state,
            codeChallenge, codeChallengeMethod);
        if (validation.Error is not null)
            return OAuthError(400, validation.Error, DescribeAuthorizeError(validation.Error));
        return Ok(new OAuthClientInfoResponse(
            validation.Client!.ClientId,
            validation.Client.Name,
            validation.Client.LogoUrl,
            validation.Scope.Split(' ')));
    }

    [HttpPost("authorize/decision")]
    [Authorize]
    [EnableRateLimiting("oauth-authorize")]
    public async Task<ActionResult<OAuthRedirectResponse>> Decide(
        [FromBody] OAuthAuthorizeDecisionRequest request)
    {
        var validation = await ValidateAuthorizeRequestAsync(
            request.ClientId, request.RedirectUri, "code", request.Scope, request.State,
            request.CodeChallenge, request.CodeChallengeMethod);
        if (validation.Error is not null)
            return OAuthError(400, validation.Error, DescribeAuthorizeError(validation.Error));

        if (!request.Approved)
        {
            return Ok(new OAuthRedirectResponse(
                BuildRedirectUrl(request.RedirectUri, null, "access_denied", request.State)));
        }

        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userId)) return Unauthorized();
        if (await database.GetProfileAsync(userId) is null) return Unauthorized();

        var code = OAuthCrypto.NewToken();
        await database.CreateOAuthAuthorizationCodeAsync(
            RailLogDatabase.HashToken(code),
            validation.Client!.ClientId,
            userId,
            request.RedirectUri,
            validation.Scope,
            request.CodeChallenge!,
            DateTime.Now.Add(AuthorizationCodeLifetime));
        await database.UpsertOAuthConsentAsync(
            userId, validation.Client.ClientId, validation.Scope);

        return Ok(new OAuthRedirectResponse(
            BuildRedirectUrl(request.RedirectUri, code, null, request.State)));
    }

    [HttpPost("token")]
    [AllowAnonymous]
    [EnableCors("oauth-public")]
    [EnableRateLimiting("oauth-token")]
    public async Task<IActionResult> Token()
    {
        Response.Headers.CacheControl = "no-store";
        Response.Headers.Pragma = "no-cache";
        if (!Request.HasFormContentType)
            return OAuthError(400, "invalid_request", "需要使用 application/x-www-form-urlencoded");

        var form = Request.Form;
        var (clientId, clientSecret) = ReadClientCredentials(form);
        var client = await AuthenticateClientAsync(clientId, clientSecret);
        if (client is null)
        {
            Response.Headers.WWWAuthenticate = "Basic realm=\"raillog\"";
            return OAuthError(401, "invalid_client", "客户端认证失败");
        }

        var grantType = form["grant_type"].ToString();
        return grantType switch
        {
            "authorization_code" => await ExchangeAuthorizationCodeAsync(client, form),
            "refresh_token" => await ExchangeRefreshTokenAsync(client, form),
            _ => OAuthError(400, "unsupported_grant_type", "不支持的授权类型"),
        };
    }

    [HttpPost("revoke")]
    [AllowAnonymous]
    [EnableCors("oauth-public")]
    [EnableRateLimiting("oauth-token")]
    public async Task<IActionResult> Revoke()
    {
        if (!Request.HasFormContentType)
            return OAuthError(400, "invalid_request", "需要使用 application/x-www-form-urlencoded");
        var form = Request.Form;
        var (clientId, clientSecret) = ReadClientCredentials(form);
        var client = await AuthenticateClientAsync(clientId, clientSecret);
        if (client is null)
        {
            Response.Headers.WWWAuthenticate = "Basic realm=\"raillog\"";
            return OAuthError(401, "invalid_client", "客户端认证失败");
        }

        var token = form["token"].ToString().Trim();
        if (token.Length > 0)
            await database.RevokeOAuthTokenAsync(RailLogDatabase.HashToken(token), client.ClientId);
        // RFC 7009：无论令牌是否存在都返回 200，避免泄露令牌状态。
        return Ok();
    }

    [HttpGet("userinfo")]
    [EnableCors("oauth-public")]
    [Authorize(AuthenticationSchemes = OAuthTokenAuthenticationHandler.SchemeName)]
    public async Task<ActionResult<OAuthUserInfoResponse>> UserInfo()
    {
        Response.Headers.CacheControl = "no-store";
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        var scope = User.FindFirstValue(OAuthTokenAuthenticationHandler.ScopeClaim) ?? string.Empty;
        if (string.IsNullOrEmpty(userId)) return Unauthorized();
        if (!HasScope(scope, "profile"))
            return StatusCode(403, new OAuthErrorResponse("insufficient_scope", "令牌缺少 profile 权限"));
        var profile = await database.GetProfileAsync(userId);
        if (profile is null) return Unauthorized();
        return Ok(new OAuthUserInfoResponse(profile.Id, profile.DisplayName, profile.AvatarUrl));
    }

    /// <summary>App 或网页展示「已授权的应用」。</summary>
    [HttpGet("consents")]
    [Authorize]
    public async Task<ActionResult<IReadOnlyList<OAuthConsentResponse>>> Consents()
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userId)) return Unauthorized();
        var consents = await database.GetOAuthConsentsAsync(userId);
        return Ok(consents
            .Select(item => new OAuthConsentResponse(
                item.ClientId,
                item.Name,
                item.LogoUrl,
                item.Scope.Split(' '),
                item.CreatedAt))
            .ToList());
    }

    [HttpDelete("consents/{clientId}")]
    [Authorize]
    public async Task<IActionResult> RevokeConsent(string clientId)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userId)) return Unauthorized();
        await database.RevokeOAuthConsentAsync(userId, clientId);
        return NoContent();
    }

    private async Task<IActionResult> ExchangeAuthorizationCodeAsync(
        OAuthClientRecord client,
        IFormCollection form)
    {
        var code = form["code"].ToString().Trim();
        var redirectUri = form["redirect_uri"].ToString();
        var verifier = form["code_verifier"].ToString();
        if (code.Length == 0 || redirectUri.Length == 0 || verifier.Length == 0)
            return OAuthError(400, "invalid_request", "缺少 code、redirect_uri 或 code_verifier");

        var codeHash = RailLogDatabase.HashToken(code);
        var record = await database.GetOAuthAuthorizationCodeAsync(codeHash);
        if (record is null ||
            record.ConsumedAt is not null ||
            record.ExpiresAt <= DateTime.Now ||
            !string.Equals(record.ClientId, client.ClientId, StringComparison.Ordinal) ||
            !string.Equals(record.RedirectUri, redirectUri, StringComparison.Ordinal) ||
            !VerifyPkce(verifier, record.CodeChallenge))
        {
            return OAuthError(400, "invalid_grant", "授权码无效、已过期或参数不匹配");
        }
        // 原子消费：并发换码时只有一个请求能成功。
        if (!await database.ConsumeOAuthAuthorizationCodeAsync(codeHash))
            return OAuthError(400, "invalid_grant", "授权码已被使用");

        return await IssueTokensAsync(client, record.UserId, record.Scope);
    }

    private async Task<IActionResult> ExchangeRefreshTokenAsync(
        OAuthClientRecord client,
        IFormCollection form)
    {
        var refreshToken = form["refresh_token"].ToString().Trim();
        if (refreshToken.Length == 0)
            return OAuthError(400, "invalid_request", "缺少 refresh_token");

        var tokenHash = RailLogDatabase.HashToken(refreshToken);
        var record = await database.GetOAuthRefreshTokenAsync(tokenHash);
        if (record is null || !string.Equals(record.ClientId, client.ClientId, StringComparison.Ordinal))
            return OAuthError(400, "invalid_grant", "刷新令牌无效或已过期");
        if (!await database.RotateOAuthRefreshTokenAsync(tokenHash))
            return OAuthError(400, "invalid_grant", "刷新令牌已使用或已撤销");

        return await IssueTokensAsync(client, record.UserId, record.Scope);
    }

    private async Task<IActionResult> IssueTokensAsync(
        OAuthClientRecord client,
        string userId,
        string scope)
    {
        var accessToken = OAuthCrypto.NewToken();
        var refreshToken = OAuthCrypto.NewToken();
        var now = DateTime.Now;
        await database.CreateOAuthTokensAsync(
            RailLogDatabase.HashToken(accessToken),
            RailLogDatabase.HashToken(refreshToken),
            client.ClientId,
            userId,
            scope,
            now.Add(AccessTokenLifetime),
            now.Add(RefreshTokenLifetime));
        return Ok(new OAuthTokenResponse(
            accessToken,
            "Bearer",
            (int)AccessTokenLifetime.TotalSeconds,
            refreshToken,
            scope));
    }

    private async Task<OAuthClientRecord?> AuthenticateClientAsync(
        string? clientId,
        string? clientSecret)
    {
        if (string.IsNullOrWhiteSpace(clientId)) return null;
        var client = await database.GetOAuthClientAsync(clientId);
        if (client is null || client.RevokedAt is not null) return null;
        if (client.ClientSecretHash is null) return client;
        if (string.IsNullOrEmpty(clientSecret)) return null;
        return FixedTimeEquals(RailLogDatabase.HashToken(clientSecret), client.ClientSecretHash)
            ? client
            : null;
    }

    private async Task<(OAuthClientRecord? Client, string Scope, string? Error)>
        ValidateAuthorizeRequestAsync(
            string? clientId,
            string? redirectUri,
            string? responseType,
            string? scope,
            string? state,
            string? codeChallenge,
            string? codeChallengeMethod)
    {
        if (string.IsNullOrWhiteSpace(clientId) ||
            string.IsNullOrWhiteSpace(redirectUri) ||
            string.IsNullOrWhiteSpace(state) ||
            state.Length > 1024)
        {
            return (null, string.Empty, "invalid_request");
        }
        if (!string.Equals(responseType, "code", StringComparison.Ordinal))
            return (null, string.Empty, "unsupported_response_type");
        // 只接受 PKCE S256，不接受 plain，也不允许省略。
        if (!string.Equals(codeChallengeMethod, "S256", StringComparison.Ordinal) ||
            codeChallenge is null ||
            codeChallenge.Length is < 43 or > 128 ||
            !codeChallenge.All(IsBase64UrlChar))
        {
            return (null, string.Empty, "invalid_request");
        }

        var client = await database.GetOAuthClientAsync(clientId);
        if (client is null || client.RevokedAt is not null)
            return (null, string.Empty, "invalid_client");
        if (!client.RedirectUris.Contains(redirectUri, StringComparer.Ordinal))
            return (null, string.Empty, "invalid_redirect_uri");

        var (normalizedScope, scopeError) = NormalizeScope(scope, client);
        if (scopeError is not null) return (null, string.Empty, scopeError);
        return (client, normalizedScope, null);
    }

    private static (string Scope, string? Error) NormalizeScope(
        string? requested,
        OAuthClientRecord client)
    {
        var scopes = (requested ?? string.Empty)
            .Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Distinct(StringComparer.Ordinal)
            .ToList();
        if (scopes.Count == 0)
        {
            return client.Scopes.Contains("profile", StringComparer.Ordinal)
                ? ("profile", null)
                : (string.Empty, "invalid_scope");
        }
        foreach (var item in scopes)
        {
            if (!KnownScopes.Contains(item) ||
                !client.Scopes.Contains(item, StringComparer.Ordinal))
            {
                return (string.Empty, "invalid_scope");
            }
        }
        return (string.Join(' ', scopes), null);
    }

    private (string? ClientId, string? ClientSecret) ReadClientCredentials(IFormCollection form)
    {
        var header = Request.Headers.Authorization.ToString();
        if (header.StartsWith("Basic ", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                var decoded = Encoding.UTF8.GetString(
                    Convert.FromBase64String(header["Basic ".Length..].Trim()));
                var separator = decoded.IndexOf(':');
                if (separator > 0)
                {
                    return (
                        UnescapeCredential(decoded[..separator]),
                        UnescapeCredential(decoded[(separator + 1)..]));
                }
            }
            catch (FormatException)
            {
                // 不是合法的 Basic 头，退回表单参数。
            }
        }
        var clientId = form["client_id"].ToString();
        var clientSecret = form["client_secret"].ToString();
        return (
            clientId.Length == 0 ? null : clientId,
            clientSecret.Length == 0 ? null : clientSecret);
    }

    private static string UnescapeCredential(string value) =>
        Uri.UnescapeDataString(value.Replace('+', ' '));

    private static bool VerifyPkce(string verifier, string challenge)
    {
        if (verifier.Length is < 43 or > 128) return false;
        foreach (var character in verifier)
        {
            if (!IsUnreserved(character)) return false;
        }
        var computed = OAuthCrypto.Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));
        return FixedTimeEquals(computed, challenge);
    }

    private static bool IsUnreserved(char value) =>
        char.IsAsciiLetterOrDigit(value) || value is '-' or '.' or '_' or '~';

    private static bool IsBase64UrlChar(char value) =>
        char.IsAsciiLetterOrDigit(value) || value is '-' or '_';

    private static bool HasScope(string scope, string expected) =>
        scope.Split(' ', StringSplitOptions.RemoveEmptyEntries).Contains(expected, StringComparer.Ordinal);

    private static bool FixedTimeEquals(string left, string right) =>
        CryptographicOperations.FixedTimeEquals(
            Encoding.ASCII.GetBytes(left),
            Encoding.ASCII.GetBytes(right));

    private static string BuildRedirectUrl(
        string redirectUri,
        string? code,
        string? error,
        string? state)
    {
        var parameters = new List<KeyValuePair<string, string?>>();
        if (!string.IsNullOrEmpty(code)) parameters.Add(new("code", code));
        if (!string.IsNullOrEmpty(error)) parameters.Add(new("error", error));
        if (!string.IsNullOrEmpty(state)) parameters.Add(new("state", state));
        return QueryHelpers.AddQueryString(redirectUri, parameters);
    }

    private ObjectResult OAuthError(int status, string error, string? description) =>
        StatusCode(status, new OAuthErrorResponse(error, description));

    private static string? DescribeAuthorizeError(string error) => error switch
    {
        "invalid_client" => "应用不存在或已停用",
        "invalid_redirect_uri" => "回调地址与应用登记的信息不一致",
        "unsupported_response_type" => "仅支持授权码模式（response_type=code）",
        "invalid_scope" => "请求的权限超出应用允许范围",
        _ => "授权请求参数不完整或不受支持",
    };
}
