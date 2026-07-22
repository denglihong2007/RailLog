using Microsoft.Data.Sqlite;
using System.Text.Json.Serialization;

namespace RailLog.API.Services;

public sealed class TrainTimetableService(IHostEnvironment environment, ILogger<TrainTimetableService> logger)
{
    public async Task<IReadOnlyList<TrainTimetableSearchItem>> SearchAsync(
        string trainNumberPrefix,
        int year,
        CancellationToken cancellationToken = default)
    {
        var prefix = trainNumberPrefix.Trim().ToUpperInvariant();
        if (prefix.Length == 0 || year is < 2009 or > 2024) return [];

        await using var connection = await OpenConnectionAsync(year, cancellationToken);
        if (connection is null) return [];

        await using var command = connection.CreateCommand();
        var table = Quote(TableName(year));
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

    public async Task<IReadOnlyList<TrainTimetableStop>> GetAsync(
        string trainNumber,
        int year,
        CancellationToken cancellationToken = default)
    {
        var normalizedTrainNumber = trainNumber.Trim().ToUpperInvariant();
        if (normalizedTrainNumber.Length == 0 || year is < 2009 or > 2024)
            return [];

        var databasePath = Path.Combine(environment.ContentRootPath, "Assets", "train_timetables.db");
        if (!File.Exists(databasePath))
        {
            logger.LogWarning("Historical timetable database was not found at {Path}", databasePath);
            return [];
        }

        var tableName = $"timetable_{year}";
        await using var connection = await OpenConnectionAsync(year, cancellationToken);
        if (connection is null) return [];

        await using var command = connection.CreateCommand();
        command.CommandText = $"""
            SELECT
                TrainStation AS station_name,
                OrderID AS station_no,
                ArriveTime AS arrive_time,
                StartTime AS start_time,
                '' AS running_time,
                '' AS arrive_day_str,
                0 AS arrive_day_diff,
                Mileage AS mileage
            FROM {Quote(tableName)}
            WHERE upper(trim(COALESCE(TrainCode1, ''))) = @trainNumber
               OR upper(trim(COALESCE(TrainCode2, ''))) = @trainNumber
            ORDER BY OrderID, rowid
            """;
        command.Parameters.AddWithValue("@trainNumber", normalizedTrainNumber);

        var result = new List<TrainTimetableStop>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var stationName = ReadString(reader, "station_name");
            if (stationName.Length == 0) continue;
            result.Add(new TrainTimetableStop(
                stationName,
                ReadString(reader, "station_no"),
                ReadString(reader, "arrive_time"),
                ReadString(reader, "start_time"),
                ReadString(reader, "running_time"),
                ReadString(reader, "arrive_day_str"),
                ReadInt(reader, "arrive_day_diff"),
                ReadDouble(reader, "mileage")));
        }

        return result;
    }

    private async Task<SqliteConnection?> OpenConnectionAsync(
        int year,
        CancellationToken cancellationToken)
    {
        var databasePath = Path.Combine(environment.ContentRootPath, "Assets", "train_timetables.db");
        if (!File.Exists(databasePath))
        {
            logger.LogWarning("Historical timetable database was not found at {Path}", databasePath);
            return null;
        }

        var connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = databasePath,
            Mode = SqliteOpenMode.ReadOnly,
            Cache = SqliteCacheMode.Shared,
        }.ToString();
        var connection = new SqliteConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        var tableName = TableName(year);
        if (await TableExistsAsync(connection, tableName, cancellationToken)) return connection;
        await connection.DisposeAsync();
        logger.LogWarning("Historical timetable table {Table} was not found in {Path}", tableName, databasePath);
        return null;
    }

    private static string TableName(int year) => $"timetable_{year}";

    private static async Task<bool> TableExistsAsync(
        SqliteConnection connection,
        string tableName,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = @tableName LIMIT 1";
        command.Parameters.AddWithValue("@tableName", tableName);
        return await command.ExecuteScalarAsync(cancellationToken) is not null;
    }

    private static string Quote(string identifier) =>
        $"[{identifier.Replace("]", "]]", StringComparison.Ordinal)}]";

    private static string ReadString(SqliteDataReader reader, string name) =>
        reader[name] is DBNull ? string.Empty : Convert.ToString(reader[name])?.Trim() ?? string.Empty;

    private static int ReadInt(SqliteDataReader reader, string name) =>
        int.TryParse(ReadString(reader, name), out var value) ? value : 0;

    private static double ReadDouble(SqliteDataReader reader, string name) =>
        double.TryParse(ReadString(reader, name), out var value) ? value : 0;
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
