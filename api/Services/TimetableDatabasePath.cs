namespace RailLog.API.Services;

/// <summary>
/// 历史时刻表库放在哪里。同步服务与查询服务必须用同一套规则，否则会出现
/// 「同步写进 A、查询读 B」的假故障。
/// <para>
/// 每个快照一个文件：<c>{ContentRoot}/timetables/{yyyy.MM.dd}.db</c>，
/// 与 GitHub Release 里的资产一一对应，下载后原样使用。
/// </para>
/// </summary>
public static class TimetableDatabasePath
{
    public static string ResolveDirectory(IWebHostEnvironment environment) =>
        Path.Combine(environment.ContentRootPath, "timetables");

    public static string Resolve(IWebHostEnvironment environment, string version) =>
        Path.Combine(ResolveDirectory(environment), version + ".db");
}
