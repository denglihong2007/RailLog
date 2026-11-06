using System.Net.Http.Headers;
using System.Text.Json;
using Microsoft.Extensions.Options;
using RailLog.API.Models;

namespace RailLog.API.Services;

/// <summary>
/// 每天把 GitHub Release 里的历史时刻表同步到本地。
/// <para>
/// Timetable-Results 每个版本发一个 Release，资产是只含该版本时刻表的
/// <c>train_timetables.db</c>（<c>trains</c> / <c>stops</c> 两张表）。下载校验后原样保存成
/// <c>timetables/{yyyy.MM.dd}.db</c>，查询侧直接读，不做格式转换。已存在的版本直接跳过。
/// 首次部署时会把仓库里全部历史版本（约 260 个）补齐，之后每天只下新增的一两个。
/// </para>
/// <para>
/// 私有仓库需要 <c>TrainTimetables:Sync:GitHubToken</c>（user-secrets 或环境变量）；
/// 公开仓库可以不配，下载走 <c>browser_download_url</c>。
/// </para>
/// </summary>
public sealed class TimetableSyncService(
    IOptions<TrainTimetablesOptions> options,
    IHttpClientFactory httpClientFactory,
    TrainTimetableService timetables,
    IWebHostEnvironment environment,
    ILogger<TimetableSyncService> logger) : BackgroundService
{
    private const string HttpClientName = "timetable-sync";

    private readonly TrainTimetablesOptions _options = options.Value;
    private readonly string _timetablesDirectory =
        TimetableDatabasePath.ResolveDirectory(environment);

    // 定时同步与后台「立即同步」共用同一个闸门，避免并发写同一批文件。
    private readonly SemaphoreSlim _runGate = new(1, 1);
    private readonly object _stateGate = new();
    private bool _running;
    private DateTime? _lastStartedAt;
    private DateTime? _lastFinishedAt;
    private string? _lastError;
    private int _lastSyncedCount;
    private int _lastMissingCount;
    private string? _lastTrigger;
    private DateTime? _nextRunAt;

    public bool IsRunning
    {
        get
        {
            lock (_stateGate) return _running;
        }
    }

    /// <summary>
    /// 执行一轮同步（定时或手动）。已经有同步在跑时立即返回 false。
    /// 异常已在本方法内记录到状态里，不会向外抛（取消除外）。
    /// </summary>
    public async Task<bool> TryRunAsync(string trigger, CancellationToken cancellationToken)
    {
        if (!await _runGate.WaitAsync(0, cancellationToken)) return false;
        lock (_stateGate)
        {
            _running = true;
            _lastStartedAt = DateTime.Now;
            _lastTrigger = trigger;
            _lastError = null;
        }

        try
        {
            var (synced, missing) = await SyncOnceAsync(_options.Sync, cancellationToken);
            lock (_stateGate)
            {
                _lastSyncedCount = synced;
                _lastMissingCount = missing;
                _lastFinishedAt = DateTime.Now;
            }
            return true;
        }
        catch (Exception exception) when (
            exception is not OperationCanceledException ||
            !cancellationToken.IsCancellationRequested)
        {
            lock (_stateGate)
            {
                _lastError = exception.Message.Length > 500
                    ? exception.Message[..500]
                    : exception.Message;
                _lastFinishedAt = DateTime.Now;
            }
            logger.LogError(exception, "Historical timetable sync failed.");
            return true;
        }
        finally
        {
            lock (_stateGate) _running = false;
            _runGate.Release();
        }
    }

    /// <summary>后台管理页用的同步状态：配置、本地快照与最近一次运行结果。</summary>
    public AdminTimetableSyncStatus GetStatus()
    {
        var settings = _options.Sync;
        var versions = ListLocalVersions();

        bool running;
        DateTime? startedAt;
        DateTime? finishedAt;
        DateTime? nextRunAt;
        string? lastError;
        string? lastTrigger;
        int synced;
        int missing;
        lock (_stateGate)
        {
            running = _running;
            startedAt = _lastStartedAt;
            finishedAt = _lastFinishedAt;
            nextRunAt = _nextRunAt;
            lastError = _lastError;
            lastTrigger = _lastTrigger;
            synced = _lastSyncedCount;
            missing = _lastMissingCount;
        }

        return new AdminTimetableSyncStatus(
            settings.Enabled,
            running,
            !string.IsNullOrWhiteSpace(settings.GitHubToken),
            settings.Owner,
            settings.Repository,
            settings.AssetName,
            settings.Hour,
            settings.Minute,
            settings.TimeZone,
            _timetablesDirectory,
            versions.Count,
            versions.Sum(item => item.SizeBytes),
            versions.FirstOrDefault()?.Version,
            versions.LastOrDefault()?.Version,
            startedAt,
            finishedAt,
            nextRunAt,
            lastError,
            synced,
            missing,
            lastTrigger,
            versions);
    }

    /// <summary>
    /// 只读地列出 GitHub 上的版本并与本地快照比对，不下载任何文件。
    /// 用于后台的「检查上游更新」。
    /// </summary>
    public async Task<AdminTimetableUpstream> CheckUpstreamAsync(
        CancellationToken cancellationToken)
    {
        var settings = _options.Sync;
        var local = ReadExistingVersions();
        try
        {
            var releases = await ListReleasesAsync(settings, cancellationToken);
            var upstream = releases
                .Select(release => release.Version)
                .ToHashSet(StringComparer.Ordinal);
            var missing = upstream
                .Where(version => !local.Contains(version))
                .OrderByDescending(version => version, StringComparer.Ordinal)
                .ToList();
            return new AdminTimetableUpstream(
                settings.Repository, local.Count, upstream.Count, missing, null);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            logger.LogWarning(exception, "Failed to check upstream timetable releases.");
            return new AdminTimetableUpstream(
                settings.Repository, local.Count, 0, [], exception.Message);
        }
    }

    private List<AdminTimetableVersion> ListLocalVersions()
    {
        if (!Directory.Exists(_timetablesDirectory)) return [];
        return new DirectoryInfo(_timetablesDirectory)
            .EnumerateFiles("*.db", SearchOption.TopDirectoryOnly)
            .Select(file => (File: file, Version: Path.GetFileNameWithoutExtension(file.Name)))
            .Where(item => TrainTimetableService.IsValidVersion(item.Version))
            .Select(item => new AdminTimetableVersion(
                item.Version, item.File.Length, item.File.LastWriteTime))
            .OrderByDescending(item => item.Version, StringComparer.Ordinal)
            .ToList();
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // 先让 Web 主机开始监听；首次同步可能很久，不能挡住启动。
        await Task.Yield();

        var settings = _options.Sync;
        if (!settings.Enabled)
        {
            logger.LogInformation("Historical timetable sync is disabled.");
            return;
        }

        var timeZone = ResolveTimeZone(settings.TimeZone);

        try
        {
            do
            {
                // 手动同步正在进行时跳过本轮，下一轮按原定时间继续。
                await TryRunAsync("scheduled", stoppingToken);

                var delay = GetDelayUntilNextRun(settings, timeZone);
                lock (_stateGate) _nextRunAt = DateTime.Now + delay;
                logger.LogInformation(
                    "Next historical timetable sync in {Delay} (daily at {Hour:00}:{Minute:00} {TimeZone}).",
                    delay,
                    settings.Hour,
                    settings.Minute,
                    timeZone.Id);
                await Task.Delay(delay, stoppingToken);
            }
            while (!stoppingToken.IsCancellationRequested);
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            // Normal application shutdown.
        }
    }

    private async Task<(int Synced, int Missing)> SyncOnceAsync(
        TimetableSyncOptions settings,
        CancellationToken cancellationToken)
    {
        var existing = ReadExistingVersions();
        var releases = await ListReleasesAsync(settings, cancellationToken);
        var missing = releases
            .Where(release => !existing.Contains(release.Version))
            .OrderByDescending(release => release.Version, StringComparer.Ordinal)
            .ToList();

        if (missing.Count == 0)
        {
            logger.LogInformation(
                "Historical timetable database is up to date ({Count} versions).",
                existing.Count);
            return (0, 0);
        }

        logger.LogInformation(
            "Syncing {Count} new historical timetable version(s), newest {Newest} .. oldest {Oldest}.",
            missing.Count,
            missing[0].Version,
            missing[^1].Version);

        var synced = 0;
        foreach (var release in missing)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                await SyncReleaseAsync(settings, release, cancellationToken);
                synced++;
                // 每写完一版就让查询侧重新读版本列表，首次补齐期间也能陆续用上新版本。
                await timetables.InvalidateVersionsAsync(cancellationToken);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception)
            {
                logger.LogError(
                    exception,
                    "Failed to sync historical timetable version {Version}.",
                    release.Version);
            }
        }

        logger.LogInformation(
            "Historical timetable sync finished: {Synced}/{Total} version(s) synced.",
            synced,
            missing.Count);
        return (synced, missing.Count);
    }

    private HashSet<string> ReadExistingVersions() =>
        ListLocalVersions()
            .Select(item => item.Version)
            .ToHashSet(StringComparer.Ordinal);

    private async Task<List<ReleaseVersion>> ListReleasesAsync(
        TimetableSyncOptions settings,
        CancellationToken cancellationToken)
    {
        var client = httpClientFactory.CreateClient(HttpClientName);
        var releases = new List<ReleaseVersion>();
        var seen = new HashSet<string>(StringComparer.Ordinal);

        // 264 个版本按每页 100 条要 3 页；上限只防接口异常时死循环。
        for (var page = 1; page <= 100; page++)
        {
            using var request = CreateRequest(
                settings,
                $"repos/{Uri.EscapeDataString(settings.Owner)}/" +
                $"{Uri.EscapeDataString(settings.Repository)}/releases?per_page=100&page={page}",
                "application/vnd.github+json");
            using var response = await client.SendAsync(request, cancellationToken);
            EnsureSuccess(response, settings);

            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            using var document = await JsonDocument.ParseAsync(
                stream, cancellationToken: cancellationToken);
            if (document.RootElement.ValueKind != JsonValueKind.Array)
                throw new InvalidDataException("GitHub releases response is not an array.");

            var count = 0;
            foreach (var element in document.RootElement.EnumerateArray())
            {
                count++;
                var tag = element.TryGetProperty("tag_name", out var tagElement)
                    ? tagElement.GetString()
                    : null;
                if (string.IsNullOrWhiteSpace(tag)) continue;

                var version = tag.Trim();
                if (version.StartsWith('v') || version.StartsWith('V'))
                    version = version[1..];
                if (!TrainTimetableService.IsValidVersion(version)) continue;
                if (!seen.Add(version)) continue;

                var asset = FindAsset(element, settings.AssetName);
                if (asset is null)
                {
                    logger.LogWarning(
                        "Release {Tag} has no {Asset}; skipping.",
                        tag,
                        settings.AssetName);
                    continue;
                }

                releases.Add(new ReleaseVersion(
                    version,
                    tag,
                    asset.Value.DownloadUrl,
                    asset.Value.ApiUrl,
                    asset.Value.Size));
            }

            if (count < 100) break;
        }

        return releases;
    }

    private async Task SyncReleaseAsync(
        TimetableSyncOptions settings,
        ReleaseVersion release,
        CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(_timetablesDirectory);
        var finalPath = TimetableDatabasePath.Resolve(environment, release.Version);
        var downloadPath = Path.Combine(
            _timetablesDirectory, $".{release.Version}.download.db");

        try
        {
            await DownloadAsync(settings, release, downloadPath, cancellationToken);
            await TimetableReleaseValidator.ValidateAsync(
                downloadPath, release.Version, cancellationToken);
            // 校验通过才换名，查询服务不会读到半个文件（同目录 rename 是原子的）。
            File.Move(downloadPath, finalPath, overwrite: true);
            logger.LogInformation(
                "Synced historical timetable version {Version} to {Path}.",
                release.Version,
                finalPath);
        }
        finally
        {
            try
            {
                if (File.Exists(downloadPath)) File.Delete(downloadPath);
            }
            catch (IOException exception)
            {
                logger.LogWarning(exception, "Could not delete {Path}.", downloadPath);
            }
        }
    }

    private async Task DownloadAsync(
        TimetableSyncOptions settings,
        ReleaseVersion release,
        string destination,
        CancellationToken cancellationToken)
    {
        var client = httpClientFactory.CreateClient(HttpClientName);
        var token = settings.GitHubToken?.Trim();
        // 私有仓库只能走 API 资产地址；公开仓库用 browser_download_url，不占 API 配额。
        var url = string.IsNullOrEmpty(token) ? release.DownloadUrl : release.ApiUrl;
        using var request = CreateRequest(settings, url, "application/octet-stream");
        using var response = await client.SendAsync(
            request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        EnsureSuccess(response, settings);

        await using (var source = await response.Content.ReadAsStreamAsync(cancellationToken))
        await using (var target = File.Create(destination))
        {
            await source.CopyToAsync(target, cancellationToken);
        }

        var length = new FileInfo(destination).Length;
        if (release.Size > 0 && length != release.Size)
        {
            throw new InvalidDataException(
                $"Downloaded {length} bytes for {release.Version}, expected {release.Size}.");
        }

        logger.LogInformation(
            "Downloaded timetable version {Version} ({Bytes} bytes, release {Tag}).",
            release.Version,
            length,
            release.Tag);
    }

    private static (string DownloadUrl, string ApiUrl, long Size)? FindAsset(
        JsonElement release,
        string assetName)
    {
        if (!release.TryGetProperty("assets", out var assets) ||
            assets.ValueKind != JsonValueKind.Array)
        {
            return null;
        }

        foreach (var asset in assets.EnumerateArray())
        {
            if (!asset.TryGetProperty("name", out var name) ||
                !string.Equals(name.GetString(), assetName, StringComparison.Ordinal))
            {
                continue;
            }

            var downloadUrl = asset.TryGetProperty("browser_download_url", out var browser)
                ? browser.GetString()
                : null;
            var apiUrl = asset.TryGetProperty("url", out var url) ? url.GetString() : null;
            if (string.IsNullOrEmpty(downloadUrl) || string.IsNullOrEmpty(apiUrl)) return null;

            var size = asset.TryGetProperty("size", out var sizeElement) &&
                       sizeElement.TryGetInt64(out var value)
                ? value
                : 0;
            return (downloadUrl, apiUrl, size);
        }

        return null;
    }

    private static HttpRequestMessage CreateRequest(
        TimetableSyncOptions settings,
        string url,
        string accept)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Accept.ParseAdd(accept);
        var token = settings.GitHubToken?.Trim();
        if (!string.IsNullOrEmpty(token))
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return request;
    }

    private static void EnsureSuccess(HttpResponseMessage response, TimetableSyncOptions settings)
    {
        if (response.IsSuccessStatusCode) return;

        var hint = (int)response.StatusCode switch
        {
            401 => "（GitHub Token 无效或已过期，请更新 TrainTimetables:Sync:GitHubToken）",
            403 when string.IsNullOrWhiteSpace(settings.GitHubToken) =>
                "（仓库可能是私有的，请用 user-secrets 配置 TrainTimetables:Sync:GitHubToken）",
            403 => "（可能是 GitHub API 速率限制）",
            404 when string.IsNullOrWhiteSpace(settings.GitHubToken) =>
                "（仓库可能是私有的，请用 user-secrets 配置 TrainTimetables:Sync:GitHubToken）",
            _ => string.Empty,
        };
        throw new HttpRequestException(
            $"GitHub request failed with {(int)response.StatusCode} " +
            $"{response.ReasonPhrase}{hint}.",
            null,
            response.StatusCode);
    }

    private TimeZoneInfo ResolveTimeZone(string configured)
    {
        foreach (var candidate in new[] { configured, "Asia/Shanghai", "China Standard Time" })
        {
            if (string.IsNullOrWhiteSpace(candidate)) continue;
            if (TimeZoneInfo.TryFindSystemTimeZoneById(candidate, out var timeZone))
                return timeZone;
        }

        logger.LogWarning(
            "Time zone {TimeZone} was not found; falling back to the server time zone.",
            configured);
        return TimeZoneInfo.Local;
    }

    private static TimeSpan GetDelayUntilNextRun(
        TimetableSyncOptions settings,
        TimeZoneInfo timeZone)
    {
        var localNow = TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, timeZone).DateTime;
        var nextLocal = localNow.Date
            .AddHours(Math.Clamp(settings.Hour, 0, 23))
            .AddMinutes(Math.Clamp(settings.Minute, 0, 59));
        if (nextLocal <= localNow) nextLocal = nextLocal.AddDays(1);

        var nextUtc = TimeZoneInfo.ConvertTimeToUtc(
            DateTime.SpecifyKind(nextLocal, DateTimeKind.Unspecified),
            timeZone);
        var delay = nextUtc - DateTime.UtcNow;
        return delay > TimeSpan.Zero ? delay : TimeSpan.Zero;
    }

    private readonly record struct ReleaseVersion(
        string Version,
        string Tag,
        string DownloadUrl,
        string ApiUrl,
        long Size);
}
