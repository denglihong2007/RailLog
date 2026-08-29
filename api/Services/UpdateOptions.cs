namespace RailLog.API.Services;

public sealed class UpdateOptions
{
    public string GitHubOwner { get; init; } = "denglihong2007";
    public string GitHubRepository { get; init; } = "RailLog";
    public int CacheMinutes { get; init; } = 15;
    public string DownloadPageUrl { get; init; } = "https://www.raillog.top/download";
    public string DomesticDownloadName { get; init; } = "国内网盘";
    public string? AndroidDomesticDownloadUrl { get; init; }

    public const string WindowsDomesticDownloadUrl = "https://apps.microsoft.com/detail/9P2XGJRHLZXS";
}
