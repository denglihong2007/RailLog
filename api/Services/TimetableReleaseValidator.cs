using System.Globalization;
using Microsoft.Data.Sqlite;

namespace RailLog.API.Services;

/// <summary>
/// 校验刚从 GitHub Release 下载的 <c>train_timetables.db</c>：文件完整
/// （<c>quick_check</c>）、表齐全、<c>meta.version</c> 与 Release 版本对得上。
/// <para>
/// 文件通过校验后原样放到 <c>timetables/{yyyy.MM.dd}.db</c>，查询侧直接读
/// <c>stops</c> 表，不再转换格式。
/// </para>
/// </summary>
public static class TimetableReleaseValidator
{
    public static async Task ValidateAsync(
        string sourcePath,
        string version,
        CancellationToken cancellationToken)
    {
        await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = sourcePath,
            Mode = SqliteOpenMode.ReadOnly,
            // 连接池会一直握着下载文件的句柄，校验完就删不掉；源库只读一次，不要池化。
            Pooling = false,
        }.ToString());
        await connection.OpenAsync(cancellationToken);

        await using (var check = connection.CreateCommand())
        {
            check.CommandText = "PRAGMA quick_check;";
            var result = Convert.ToString(
                await check.ExecuteScalarAsync(cancellationToken), CultureInfo.InvariantCulture);
            if (!string.Equals(result, "ok", StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException($"SQLite quick_check failed for {version}: {result}");
        }

        var tables = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = "SELECT name FROM sqlite_master WHERE type = 'table'";
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
                tables.Add(reader.GetString(0));
        }

        if (!tables.Contains("stops") || !tables.Contains("trains"))
            throw new InvalidDataException($"Release database for {version} has no stops/trains.");

        if (tables.Contains("meta"))
        {
            await using var command = connection.CreateCommand();
            command.CommandText = "SELECT value FROM meta WHERE key = 'version' LIMIT 1";
            var actual = Convert.ToString(
                await command.ExecuteScalarAsync(cancellationToken), CultureInfo.InvariantCulture);
            if (!string.IsNullOrEmpty(actual) &&
                !string.Equals(actual, version, StringComparison.Ordinal))
            {
                throw new InvalidDataException(
                    $"Release database for {version} reports version {actual}.");
            }
        }
    }
}
