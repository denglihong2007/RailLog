using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

namespace RailLog.API.Services;

public sealed class AdminAuthenticationOptions : AuthenticationSchemeOptions;

/// <summary>
/// 管理员权限复用 App 的登录令牌：先按普通用户令牌校验，再检查账户 ID 是否在
/// <see cref="AdminOptions.UserIds"/> 白名单里。这样管理员不需要维护第二套密码，
/// 也不会出现「只知道密码、不知道是谁」的会话。
/// </summary>
public sealed class AdminAuthenticationHandler(
    IOptionsMonitor<AdminAuthenticationOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder,
    RailLogDatabase database,
    IOptionsMonitor<AdminOptions> adminOptions)
    : AuthenticationHandler<AdminAuthenticationOptions>(options, logger, encoder)
{
    public const string SchemeName = "RailLogAdmin";

    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var header = Request.Headers.Authorization.ToString();
        if (!header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            return AuthenticateResult.NoResult();
        var token = header["Bearer ".Length..].Trim();
        var userId = await database.ValidateTokenAsync(token);
        if (userId is null)
            return AuthenticateResult.Fail("登录已失效");
        if (!adminOptions.CurrentValue.IsAdmin(userId))
            return AuthenticateResult.Fail("该账户没有管理员权限");
        var identity = new ClaimsIdentity(
            [
                new Claim(ClaimTypes.NameIdentifier, userId),
                new Claim(ClaimTypes.Name, userId),
                new Claim(ClaimTypes.Role, "admin"),
            ],
            SchemeName);
        return AuthenticateResult.Success(
            new AuthenticationTicket(new ClaimsPrincipal(identity), SchemeName));
    }
}
