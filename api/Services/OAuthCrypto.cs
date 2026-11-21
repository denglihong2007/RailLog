using System.Security.Cryptography;

namespace RailLog.API.Services;

/// <summary>OAuth 用到的随机凭据格式。令牌统一使用无填充的 base64url。</summary>
internal static class OAuthCrypto
{
    public static string NewToken() => Base64Url(RandomNumberGenerator.GetBytes(48));

    public static string NewClientId() =>
        "rk_" + Convert.ToHexString(RandomNumberGenerator.GetBytes(8)).ToLowerInvariant();

    public static string Base64Url(byte[] value) =>
        Convert.ToBase64String(value).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
