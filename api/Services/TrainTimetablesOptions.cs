namespace RailLog.API.Services;

public sealed class TrainTimetablesOptions
{
    public TimetableSyncOptions Sync { get; init; } = new();
}

public sealed class TimetableSyncOptions
{
    /// <summary>是否每天从 GitHub Release 同步历史时刻表。</summary>
    public bool Enabled { get; init; } = true;

    /// <summary>每天同步的本地时刻（默认早上六点）。</summary>
    public int Hour { get; init; } = 6;
    public int Minute { get; init; } = 0;

    /// <summary>解释「早上六点」用的时区，默认北京时间。</summary>
    public string TimeZone { get; init; } = "Asia/Shanghai";

    public string Owner { get; init; } = "denglihong2007";
    public string Repository { get; init; } = "Timetable-Results";
    public string AssetName { get; init; } = "train_timetables.db";

    /// <summary>
    /// 读取私有仓库 Release 用的 GitHub Token。仓库是私有的，没配就取不到任何版本；
    /// 从 user-secrets 或环境变量注入，不要写进 appsettings.json。
    /// </summary>
    public string? GitHubToken { get; init; }
}
