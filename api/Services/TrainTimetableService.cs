using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Options;
using System.Globalization;
using System.Text.Json.Serialization;

namespace RailLog.API.Services;

/// <summary>
/// 历史时刻表库按快照日期版本化，一个版本一张 <c>timetable_&lt;yyyy.MM.dd&gt;</c> 表。
/// 库本体不进仓库（约 800MB），路径由 user-secrets 里的
/// <c>TrainTimetables:DatabasePath</c> 指定；没配置时接口一律返回空结果。
/// </summary>
public sealed class TrainTimetableService(
    IOptions<TrainTimetablesOptions> options,
    ILogger<TrainTimetableService> logger)
{
    private readonly TrainTimetablesOptions _options = options.Value;
    private readonly SemaphoreSlim _versionsGate = new(1, 1);
    private IReadOnlyList<string>? _versions;
    private bool _missingPathReported;

    /// <summary>可用的版本号，升序。表名的字典序恰好等于时间序。</summary>
    public async Task<IReadOnlyList<string>> GetVersionsAsync(
        CancellationToken cancellationToken = default)
    {
        var cached = _versions;
        if (cached is not null) return cached;

        await _versionsGate.WaitAsync(cancellationToken);
        try
        {
            if (_versions is not null) return _versions;

            var databasePath = ResolveDatabasePath();
            if (databasePath is null)
            {
                _versions = [];
                return _versions;
            }

            var versions = new List<string>();
            try
            {
                await using var connection = await OpenConnectionAsync(databasePath, cancellationToken);
                await using var command = connection.CreateCommand();
                command.CommandText =
                    "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'timetable\\_%' ESCAPE '\\'";
                await using var reader = await command.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    var name = reader.GetString(0);
                    var version = name["timetable_".Length..];
                    if (IsValidVersion(version)) versions.Add(version);
                }
            }
            catch (SqliteException exception)
            {
                logger.LogError(exception, "Failed to read timetable versions from {Path}", databasePath);
                return [];
            }

            versions.Sort(StringComparer.Ordinal);
            _versions = versions;
            logger.LogInformation(
                "Historical timetable database offers {Count} versions ({First} .. {Last})",
                versions.Count,
                versions.Count > 0 ? versions[0] : "-",
                versions.Count > 0 ? versions[^1] : "-");
            return _versions;
        }
        finally
        {
            _versionsGate.Release();
        }
    }

    public async Task<bool> SupportsVersionAsync(
        string version,
        CancellationToken cancellationToken = default)
    {
        if (!IsValidVersion(version)) return false;
        var versions = await GetVersionsAsync(cancellationToken);
        return versions.Contains(version, StringComparer.Ordinal);
    }

    public async Task<IReadOnlyList<TrainTimetableSearchItem>> SearchAsync(
        string trainNumberPrefix,
        string version,
        CancellationToken cancellationToken = default)
    {
        var prefix = trainNumberPrefix.Trim().ToUpperInvariant();
        if (prefix.Length == 0) return [];

        await using var connection = await OpenVersionAsync(version, cancellationToken);
        if (connection is null) return [];

        await using var command = connection.CreateCommand();
        var table = Quote(TableName(version));
        command.CommandText = $"""
    WITH matching_trains(train_number) AS (
        SELECT TrainCode1 FROM {table}
        WHERE TrainCode1 LIKE @prefix || '%'
        UNION
        SELECT TrainCode2 FROM {table}
        WHERE TrainCode2 LIKE @prefix || '%'
    )
    SELECT
        m.train_number,
        (
            SELECT t.TrainStation FROM {table} t
            WHERE t.TrainCode1 = m.train_number
               OR t.TrainCode2 = m.train_number
            ORDER BY t.OrderID ASC, t.rowid ASC
            LIMIT 1
        ) AS departure_station,
        (
            SELECT t.TrainStation FROM {table} t
            WHERE t.TrainCode1 = m.train_number
               OR t.TrainCode2 = m.train_number
            ORDER BY t.OrderID DESC, t.rowid DESC
            LIMIT 1
        ) AS arrival_station
    FROM matching_trains m
    WHERE m.train_number IS NOT NULL AND m.train_number <> ''
    ORDER BY m.train_number
    """;
        command.Parameters.AddWithValue("@prefix", prefix);

        var result = new List<TrainTimetableSearchItem>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var trainNumber = ReadString(reader, "train_number").ToUpperInvariant();
            if (trainNumber.Length == 0) continue;
            result.Add(new TrainTimetableSearchItem(
                trainNumber,
                ReadString(reader, "departure_station"),
                ReadString(reader, "arrival_station"),
                trainNumber));
        }
        return result;
    }

    public async Task<IReadOnlyList<string>> GetStationsAsync(
        string version,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenVersionAsync(version, cancellationToken);
        if (connection is null) return [];
        await using var command = connection.CreateCommand();
        command.CommandText = $"""
            SELECT DISTINCT trim(TrainStation) AS station_name
            FROM {Quote(TableName(version))}
            WHERE trim(TrainStation) <> ''
            ORDER BY station_name;
            """;
        var result = new List<string>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
            result.Add(reader.GetString(0));
        return result;
    }

    public async Task<IReadOnlyList<TrainTimetableSearchItem>> SearchBetweenAsync(
        string fromStation,
        string toStation,
        string version,
        CancellationToken cancellationToken = default)
    {
        var from = fromStation.Trim();
        var to = toStation.Trim();
        if (from.Length == 0 || to.Length == 0 || from == to) return [];
        await using var connection = await OpenVersionAsync(version, cancellationToken);
        if (connection is null) return [];
        await using var command = connection.CreateCommand();
        var table = Quote(TableName(version));
        command.CommandText = $"""
            WITH train_stops AS (
                SELECT trim(TrainCode1) AS train_number, OrderID, trim(TrainStation) AS station
                FROM {table} WHERE trim(TrainCode1) <> ''
                UNION ALL
                SELECT trim(TrainCode2), OrderID, trim(TrainStation)
                FROM {table} WHERE trim(TrainCode2) <> ''
            ), matching AS (
                SELECT train_number,
                       MIN(CASE WHEN station = @fromStation THEN OrderID END) AS from_order,
                       MIN(CASE WHEN station = @toStation THEN OrderID END) AS to_order
                FROM train_stops
                GROUP BY train_number
            )
            SELECT train_number, @fromStation, @toStation, train_number
            FROM matching
            WHERE from_order IS NOT NULL AND to_order IS NOT NULL AND from_order < to_order
            ORDER BY train_number
            LIMIT 100;
            """;
        command.Parameters.AddWithValue("@fromStation", from);
        command.Parameters.AddWithValue("@toStation", to);
        var result = new List<TrainTimetableSearchItem>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(new TrainTimetableSearchItem(
                ReadString(reader, "train_number"), from, to, ReadString(reader, "train_number")));
        }
        return result;
    }

    public async Task<IReadOnlyList<TrainTimetableStop>> GetAsync(
        string trainNumber,
        string version,
        CancellationToken cancellationToken = default)
    {
        var normalizedTrainNumber = trainNumber.Trim().ToUpperInvariant();
        if (normalizedTrainNumber.Length == 0) return [];

        await using var connection = await OpenVersionAsync(version, cancellationToken);
        if (connection is null) return [];

        await using var command = connection.CreateCommand();
        command.CommandText = $"""
            SELECT
                TrainStation AS station_name,
                OrderID AS station_no,
                ArriveTime AS arrive_time,
                StartTime AS start_time,
                '' AS running_time,
                Mileage AS mileage
            FROM {Quote(TableName(version))}
            WHERE upper(trim(COALESCE(TrainCode1, ''))) = @trainNumber
               OR upper(trim(COALESCE(TrainCode2, ''))) = @trainNumber
            ORDER BY OrderID, rowid
            """;
        command.Parameters.AddWithValue("@trainNumber", normalizedTrainNumber);

        var result = new List<TrainTimetableStop>();
        TimeSpan? previousEventTime = null;
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var stationName = ReadString(reader, "station_name");
            if (stationName.Length == 0) continue;

            var arriveTime = ReadString(reader, "arrive_time");
            var startTime = ReadString(reader, "start_time");
            var arriveDayDiff = 0;
            if (TryParseTime(arriveTime, out var arrivalEventTime))
            {
                arrivalEventTime = MoveToNextEventDay(arrivalEventTime, previousEventTime);
                previousEventTime = arrivalEventTime;
                arriveDayDiff = GetDayDifference(arrivalEventTime);
            }

            // A train can cross midnight while dwelling at a station. Process the
            // departure after the arrival so the next station inherits that day.
            if (TryParseTime(startTime, out var departureEventTime))
                previousEventTime = MoveToNextEventDay(departureEventTime, previousEventTime);

            result.Add(new TrainTimetableStop(
                stationName,
                ReadString(reader, "station_no"),
                arriveTime,
                startTime,
                string.Empty,
                string.Empty,
                arriveDayDiff,
                ReadDouble(reader, "mileage")));
        }

        return result;
    }

    /// <summary>配好且存在的库路径；没配或不存在返回 null（只报一次 warning）。</summary>
    private string? ResolveDatabasePath()
    {
        var configured = _options.DatabasePath?.Trim();
        if (string.IsNullOrEmpty(configured))
        {
            if (!_missingPathReported)
            {
                _missingPathReported = true;
                logger.LogWarning(
                    "历史时刻表数据库未配置，相关接口会返回空结果。请设置 user-secrets："
                    + "dotnet user-secrets set \"TrainTimetables:DatabasePath\" \"<路径>\\train_timetables.db\"");
            }
            return null;
        }

        if (!File.Exists(configured))
        {
            if (!_missingPathReported)
            {
                _missingPathReported = true;
                logger.LogWarning(
                    "历史时刻表数据库不存在：{Path}（TrainTimetables:DatabasePath 指向的文件找不到）",
                    configured);
            }
            return null;
        }

        return configured;
    }

    private async Task<SqliteConnection?> OpenVersionAsync(
        string version,
        CancellationToken cancellationToken)
    {
        if (!IsValidVersion(version)) return null;
        if (!await SupportsVersionAsync(version, cancellationToken)) return null;

        var databasePath = ResolveDatabasePath();
        if (databasePath is null) return null;
        return await OpenConnectionAsync(databasePath, cancellationToken);
    }

    private static async Task<SqliteConnection> OpenConnectionAsync(
        string databasePath,
        CancellationToken cancellationToken)
    {
        var connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = databasePath,
            Mode = SqliteOpenMode.ReadOnly,
            Cache = SqliteCacheMode.Shared,
        }.ToString();
        var connection = new SqliteConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        return connection;
    }

    /// <summary>版本号形如 2003.11.25。</summary>
    public static bool IsValidVersion(string? version) =>
        version is { Length: 10 } &&
        version[4] == '.' && version[7] == '.' &&
        DateOnly.TryParseExact(version, "yyyy.MM.dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out _);

    private static string TableName(string version) => $"timetable_{version}";

    private static string Quote(string identifier) =>
        $"[{identifier.Replace("]", "]]", StringComparison.Ordinal)}]";

    private static string ReadString(SqliteDataReader reader, string name) =>
        reader[name] is DBNull ? string.Empty : Convert.ToString(reader[name])?.Trim() ?? string.Empty;

    private static double ReadDouble(SqliteDataReader reader, string name) =>
        double.TryParse(ReadString(reader, name), out var value) ? value : 0;

    private static bool TryParseTime(string value, out TimeSpan time)
    {
        time = default;
        var normalized = value.Trim();
        if (normalized.Length == 0 || normalized.All(static character => character == '-'))
            return false;

        return TimeSpan.TryParse(normalized, CultureInfo.InvariantCulture, out time) &&
               time >= TimeSpan.Zero;
    }

    private static TimeSpan MoveToNextEventDay(TimeSpan eventTime, TimeSpan? previousEventTime)
    {
        while (previousEventTime is not null && eventTime < previousEventTime.Value)
            eventTime += TimeSpan.FromDays(1);
        return eventTime;
    }

    private static int GetDayDifference(TimeSpan eventTime) =>
        Math.Max(0, (int)eventTime.TotalDays);
}

public sealed record TrainTimetableStop(
    [property: JsonPropertyName("station_name")] string StationName,
    [property: JsonPropertyName("station_no")] string StationNo,
    [property: JsonPropertyName("arrive_time")] string ArriveTime,
    [property: JsonPropertyName("start_time")] string StartTime,
    [property: JsonPropertyName("running_time")] string RunningTime,
    [property: JsonPropertyName("arrive_day_str")] string ArriveDayStr,
    [property: JsonPropertyName("arrive_day_diff")] int ArriveDayDiff,
    [property: JsonPropertyName("mileage")] double Mileage);

public sealed record TrainTimetableSearchItem(
    [property: JsonPropertyName("station_train_code")] string TrainNumber,
    [property: JsonPropertyName("from_station")] string DepartureStation,
    [property: JsonPropertyName("to_station")] string ArrivalStation,
    [property: JsonPropertyName("train_no")] string TrainNo);
