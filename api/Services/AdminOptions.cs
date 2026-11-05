namespace RailLog.API.Services;

public sealed class AdminOptions
{
    /// <summary>
    /// 拥有管理后台权限的 RailLog 账户 ID。比较时会忽略 GUID 的连字符和大小写，
    /// 因此 appsettings 里写成 32 位十六进制或标准 GUID 都可以。
    /// </summary>
    public string[] UserIds { get; init; } = [];

    public bool IsAdmin(string? userId) =>
        !string.IsNullOrWhiteSpace(userId) &&
        UserIds?.Any(id => string.Equals(
            Normalize(id), Normalize(userId), StringComparison.Ordinal)) == true;

    private static string Normalize(string value) =>
        value.Replace("-", string.Empty, StringComparison.Ordinal).Trim().ToLowerInvariant();
}
