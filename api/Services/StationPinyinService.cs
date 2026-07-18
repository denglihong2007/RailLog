using System.Collections.Frozen;

namespace RailLog.API.Services;

public sealed class StationPinyinService(
    IHttpClientFactory httpClientFactory,
    TicketAssetStore assets,
    ILogger<StationPinyinService> logger)
{
    private const string ClientName = "12306-stations";
    private const string StationNamesPath = "otn/resources/js/framework/station_name.js";
    private static readonly TimeSpan CacheLifetime = TimeSpan.FromHours(24);
    private static readonly TimeSpan EmptyCacheRetry = TimeSpan.FromMinutes(15);
    private static readonly TimeSpan StaleCacheRetry = TimeSpan.FromHours(1);
    private readonly SemaphoreSlim _refreshLock = new(1, 1);
    private IReadOnlyDictionary<string, string> _cache =
        FrozenDictionary<string, string>.Empty;
    private long _refreshAfterUnixMilliseconds;

    public async Task<string> ResolveAsync(string station, CancellationToken cancellationToken = default)
    {
        var normalized = NormalizeStation(station);
        var stations = await GetStationsAsync(cancellationToken);
        return ResolveFromSources(
            normalized,
            stations,
            assets.AuxiliaryStationPinyin);
    }

    private async Task<IReadOnlyDictionary<string, string>> GetStationsAsync(
        CancellationToken cancellationToken)
    {
        if (!RefreshRequired()) return _cache;
        await _refreshLock.WaitAsync(cancellationToken);
        try
        {
            if (!RefreshRequired()) return _cache;
            try
            {
                var client = httpClientFactory.CreateClient(ClientName);
                var source = await client.GetStringAsync(StationNamesPath, cancellationToken);
                var parsed = ParseStationNames(source);
                if (parsed.Count < 1000)
                    throw new InvalidDataException("12306 station_name.js entries are incomplete");
                _cache = parsed;
                SetNextRefresh(CacheLifetime);
            }
            catch (Exception exception) when (exception is not OperationCanceledException)
            {
                var hasStaleCache = _cache.Count > 0;
                logger.LogWarning(
                    exception,
                    hasStaleCache
                        ? "Unable to refresh 12306 station pinyin; using stale cache"
                        : "Unable to load 12306 station pinyin; using auxiliary resolver");
                SetNextRefresh(hasStaleCache ? StaleCacheRetry : EmptyCacheRetry);
            }
            return _cache;
        }
        finally
        {
            _refreshLock.Release();
        }
    }

    internal static string ResolveFromSources(
        string station,
        IReadOnlyDictionary<string, string> officialStations,
        Func<string, string> auxiliaryResolver)
    {
        var normalized = NormalizeStation(station);
        return officialStations.TryGetValue(normalized, out var official)
            ? TicketCase(official)
            : auxiliaryResolver(normalized);
    }

    private bool RefreshRequired() =>
        DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() >=
        Interlocked.Read(ref _refreshAfterUnixMilliseconds);

    private void SetNextRefresh(TimeSpan delay) => Interlocked.Exchange(
        ref _refreshAfterUnixMilliseconds,
        (DateTimeOffset.UtcNow + delay).ToUnixTimeMilliseconds());

    internal static IReadOnlyDictionary<string, string> ParseStationNames(string source)
    {
        var firstQuote = source.IndexOf('\'');
        var lastQuote = source.LastIndexOf('\'');
        if (firstQuote < 0 || lastQuote <= firstQuote)
            throw new InvalidDataException("12306 station_name.js format is invalid");

        var entries = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var record in source[(firstQuote + 1)..lastQuote].Split('@'))
        {
            if (record.Length == 0) continue;
            var fields = record.Split('|');
            if (fields.Length < 4) continue;
            var station = NormalizeStation(fields[1]);
            var pinyin = NormalizePinyin(fields[3]);
            if (station.Length > 0 && pinyin.Length > 0)
                entries.TryAdd(station, pinyin);
        }
        return entries.ToFrozenDictionary(StringComparer.Ordinal);
    }

    private static string NormalizePinyin(string value) => string.Concat(
        value.Where(character =>
            character is >= 'a' and <= 'z' or >= 'A' and <= 'Z' or >= '0' and <= '9'))
        .ToLowerInvariant();

    private static string NormalizeStation(string value)
    {
        var normalized = value.Trim();
        return normalized.EndsWith('站') ? normalized[..^1] : normalized;
    }

    private static string TicketCase(string value)
    {
        var normalized = NormalizePinyin(value);
        return normalized.Length == 0
            ? normalized
            : char.ToUpperInvariant(normalized[0]) + normalized[1..];
    }
}
