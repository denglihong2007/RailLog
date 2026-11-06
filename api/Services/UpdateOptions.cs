namespace RailLog.API.Services;

public sealed class UpdateOptions
{
    public string GitHubOwner { get; init; } = "denglihong2007";
    public string GitHubRepository { get; init; } = "RailLog";
    public int CacheMinutes { get; init; } = 15;
    public string DownloadPageUrl { get; init; } = "https://www.raillog.top/download";
    public string DomesticDownloadName { get; init; } = "国内网盘";

    // ≤2.7.1 的 App 用这个地址渲染「国内网盘」按钮；Android 取不到时会回退到
    // Windows 的微软商店链接。留空时由 GitHubReleaseService 按发布版本拼出
    // 对象存储里的 APK，旧客户端也能拿到官方下载。
    public string? AndroidDomesticDownloadUrl { get; init; }
    public string StorageBaseUrl { get; init; } = "https://raillog.cn-nb2.rains3.com";

    public const string WindowsDomesticDownloadUrl = "https://apps.microsoft.com/detail/9P2XGJRHLZXS";
}
