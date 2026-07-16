using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

namespace RailLog.API.Services;

public sealed class TokenAuthenticationOptions : AuthenticationSchemeOptions;

public sealed class TokenAuthenticationHandler(
    IOptionsMonitor<TokenAuthenticationOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder,
    RailLogDatabase database)
    : AuthenticationHandler<TokenAuthenticationOptions>(options, logger, encoder)
{
    public const string SchemeName = "RailLogToken";

    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var header = Request.Headers.Authorization.ToString();
        if (!header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            return AuthenticateResult.NoResult();
        var token = header["Bearer ".Length..].Trim();
        var userId = await database.ValidateTokenAsync(token);
        if (userId is null) return AuthenticateResult.Fail("登录已失效");
        var identity = new ClaimsIdentity(
            [new Claim(ClaimTypes.NameIdentifier, userId)], SchemeName);
        return AuthenticateResult.Success(
            new AuthenticationTicket(new ClaimsPrincipal(identity), SchemeName));
    }
}
