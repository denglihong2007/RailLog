using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

namespace RailLog.API.Services;

public sealed class OAuthTokenAuthenticationOptions : AuthenticationSchemeOptions;

/// <summary>
/// 第三方应用的 Bearer 令牌。只认 <c>OAuthAccessTokens</c>，与 App 的登录令牌
/// （<see cref="TokenAuthenticationHandler"/>）完全隔离：合作伙伴的令牌不能调用
/// 账号接口，App 的令牌也不能冒充合作伙伴访问 userinfo。
/// </summary>
public sealed class OAuthTokenAuthenticationHandler(
    IOptionsMonitor<OAuthTokenAuthenticationOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder,
    RailLogDatabase database)
    : AuthenticationHandler<OAuthTokenAuthenticationOptions>(options, logger, encoder)
{
    public const string SchemeName = "RailLogOAuth";

    public const string ClientIdClaim = "raillog:client_id";
    public const string ScopeClaim = "raillog:scope";

    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var header = Request.Headers.Authorization.ToString();
        if (!header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            return AuthenticateResult.NoResult();
        var token = header["Bearer ".Length..].Trim();
        if (token.Length == 0) return AuthenticateResult.NoResult();
        var record = await database.GetOAuthAccessTokenAsync(RailLogDatabase.HashToken(token));
        if (record is null) return AuthenticateResult.Fail("令牌无效或已过期");
        var identity = new ClaimsIdentity(
            [
                new Claim(ClaimTypes.NameIdentifier, record.UserId),
                new Claim(ClientIdClaim, record.ClientId),
                new Claim(ScopeClaim, record.Scope),
            ],
            SchemeName);
        return AuthenticateResult.Success(
            new AuthenticationTicket(new ClaimsPrincipal(identity), SchemeName));
    }
}
