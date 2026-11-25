namespace RailLog.API.Models;

/// <summary>授权页展示给用户的应用信息，只包含请求的 scope，不下发其他配置。</summary>
public sealed record OAuthClientInfoResponse(
    string ClientId,
    string Name,
    string? LogoUrl,
    IReadOnlyList<string> Scopes);

public sealed record OAuthAuthorizeDecisionRequest(
    string ClientId,
    string RedirectUri,
    string? Scope,
    string? State,
    string CodeChallenge,
    string CodeChallengeMethod,
    bool Approved);

public sealed record OAuthRedirectResponse(string RedirectUrl);

public sealed record OAuthTokenResponse(
    string AccessToken,
    string TokenType,
    int ExpiresIn,
    string? RefreshToken,
    string Scope);

/// <summary>OIDC 风格的 userinfo 响应：sub 就是 RailLog 用户 ID。</summary>
public sealed record OAuthUserInfoResponse(string Sub, string Name, string? Picture);

public sealed record OAuthErrorResponse(string Error, string? ErrorDescription = null);

public sealed record OAuthConsentResponse(
    string ClientId,
    string Name,
    string? LogoUrl,
    IReadOnlyList<string> Scopes,
    DateTime CreatedAt);

public sealed record CreateOAuthClientRequest(
    string Name,
    string? LogoUrl,
    IReadOnlyList<string>? RedirectUris,
    IReadOnlyList<string>? Scopes,
    bool PublicClient = false);

public sealed record CreateOAuthClientResponse(
    string ClientId,
    string? ClientSecret,
    string Name,
    IReadOnlyList<string> RedirectUris,
    IReadOnlyList<string> Scopes,
    bool PublicClient);

public sealed record OAuthClientSummary(
    string ClientId,
    string Name,
    string? LogoUrl,
    IReadOnlyList<string> RedirectUris,
    IReadOnlyList<string> Scopes,
    bool PublicClient,
    DateTime CreatedAt,
    DateTime? RevokedAt);
