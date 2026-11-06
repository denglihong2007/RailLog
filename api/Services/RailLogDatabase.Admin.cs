using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Data.Sqlite;
using RailLog.API.Models;

namespace RailLog.API.Services;

// 管理员后台用的数据访问。和主文件拆开只是为了让 3000 多行的类保持可读；
// 它们共享 _writeLock、版本分配和成就重算等内部机制，因此必须是同一个 partial 类。
public sealed partial class RailLogDatabase
{
    private const string AdminTripColumns = """
        Id, UserId, ClientId, CreatedAt, TrainNumber, TravelDate, RollingStock,
        CompanyName, FromStation, ToStation, DepartureTime, ArrivalTime, MileageKm,
        ViaRoutes, SeatType, SeatNumber, Price, Notes, GroupName, IsRailTrip,
        UpdatedAt, DeletedAt, SyncVersion
        """;

    private const string TicketPasswordHashKey = "TicketPdf:DownloadPasswordHash";

    // ---- 公告 ----

    public async Task<IReadOnlyList<AdminAnnouncement>> GetAnnouncementsAsync()
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT Id, Text, Weight, IsActive, SortOrder, CreatedAt, UpdatedAt
            FROM Announcements
            ORDER BY IsActive DESC, SortOrder ASC, CreatedAt ASC;
            """;
        var items = new List<AdminAnnouncement>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            items.Add(new AdminAnnouncement(
                reader.GetString(0),
                reader.GetString(1),
                reader.GetInt32(2),
                reader.GetInt32(3) == 1,
                reader.GetInt32(4),
                FromDb(reader.GetString(5)),
                FromDb(reader.GetString(6))));
        }
        return items;
    }

    /// <summary>
    /// 供 App 主页横幅使用的公告。返回空列表时由调用方决定是否回退到
    /// appsettings 里的旧配置。
    /// </summary>
    public async Task<IReadOnlyList<SystemAnnouncementResponse>> GetActiveAnnouncementsAsync()
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT Text, Weight
            FROM Announcements
            WHERE IsActive = 1 AND Weight > 0
            ORDER BY SortOrder ASC, CreatedAt ASC;
            """;
        var items = new List<SystemAnnouncementResponse>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
            items.Add(new SystemAnnouncementResponse(reader.GetString(0), reader.GetInt32(1)));
        return items;
    }

    /// <summary>
    /// 表里是否至少有一条公告（无论是否上线）。用于区分「后台从未配置过」
    /// 和「管理员把所有公告都下线了」。
    /// </summary>
    public async Task<bool> HasAnnouncementsAsync()
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT 1 FROM Announcements LIMIT 1;";
        return await command.ExecuteScalarAsync() is not null;
    }

    public async Task<(AdminAnnouncement? Item, string? Error)> SaveAnnouncementAsync(
        AdminAnnouncementRequest request)
    {
        var text = request.Text?.Trim() ?? string.Empty;
        if (text.Length is < 1 or > 256)
            return (null, "公告内容应为 1 至 256 个字符");
        var weight = Math.Clamp(request.Weight, 0, 1000);
        var sortOrder = Math.Clamp(request.SortOrder, 0, 9999);
        var now = DateTime.Now;
        var id = string.IsNullOrWhiteSpace(request.Id) ? Guid.NewGuid().ToString("N") : request.Id.Trim();

        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO Announcements (Id, Text, Weight, IsActive, SortOrder, CreatedAt, UpdatedAt)
            VALUES ($id, $text, $weight, $active, $sortOrder, $now, $now)
            ON CONFLICT(Id) DO UPDATE SET
                Text = excluded.Text,
                Weight = excluded.Weight,
                IsActive = excluded.IsActive,
                SortOrder = excluded.SortOrder,
                UpdatedAt = excluded.UpdatedAt;
            """;
        command.Parameters.AddWithValue("$id", id);
        command.Parameters.AddWithValue("$text", text);
        command.Parameters.AddWithValue("$weight", weight);
        command.Parameters.AddWithValue("$active", request.IsActive ? 1 : 0);
        command.Parameters.AddWithValue("$sortOrder", sortOrder);
        command.Parameters.AddWithValue("$now", ToDb(now));
        await command.ExecuteNonQueryAsync();

        await using var read = connection.CreateCommand();
        read.CommandText = """
            SELECT Id, Text, Weight, IsActive, SortOrder, CreatedAt, UpdatedAt
            FROM Announcements WHERE Id = $id LIMIT 1;
            """;
        read.Parameters.AddWithValue("$id", id);
        await using var reader = await read.ExecuteReaderAsync();
        if (!await reader.ReadAsync()) return (null, "公告保存失败");
        return (new AdminAnnouncement(
            reader.GetString(0),
            reader.GetString(1),
            reader.GetInt32(2),
            reader.GetInt32(3) == 1,
            reader.GetInt32(4),
            FromDb(reader.GetString(5)),
            FromDb(reader.GetString(6))), null);
    }

    public async Task<bool> DeleteAnnouncementAsync(string id)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = "DELETE FROM Announcements WHERE Id = $id;";
        command.Parameters.AddWithValue("$id", id);
        return await command.ExecuteNonQueryAsync() > 0;
    }

    // ---- PDF 下载密码 ----

    /// <summary>
    /// 后台设置的下载密码只保存 SHA-256 摘要。返回 null 表示管理员
    /// 没有覆盖过，调用方应回退到 appsettings 里的配置。
    /// </summary>
    public async Task<(string Hash, DateTime UpdatedAt)?> GetTicketPasswordHashAsync()
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT Value, UpdatedAt FROM AppSettings
            WHERE Key = $key LIMIT 1;
            """;
        command.Parameters.AddWithValue("$key", TicketPasswordHashKey);
        await using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync()) return null;
        return (reader.GetString(0), FromDb(reader.GetString(1)));
    }

    public async Task SetTicketPasswordAsync(string password)
    {
        var hash = Convert.ToHexString(
            SHA256.HashData(Encoding.UTF8.GetBytes(password)));
        await _writeLock.WaitAsync();
        try
        {
            await using var connection = OpenConnection();
            await connection.OpenAsync();
            await using var command = connection.CreateCommand();
            command.CommandText = """
                INSERT INTO AppSettings (Key, Value, UpdatedAt)
                VALUES ($key, $value, $now)
                ON CONFLICT(Key) DO UPDATE SET
                    Value = excluded.Value,
                    UpdatedAt = excluded.UpdatedAt;
                """;
            command.Parameters.AddWithValue("$key", TicketPasswordHashKey);
            command.Parameters.AddWithValue("$value", hash);
            command.Parameters.AddWithValue("$now", ToDb(DateTime.Now));
            await command.ExecuteNonQueryAsync();
        }
        finally
        {
            _writeLock.Release();
        }
    }

    public async Task<bool> ClearTicketPasswordAsync()
    {
        await _writeLock.WaitAsync();
        try
        {
            await using var connection = OpenConnection();
            await connection.OpenAsync();
            await using var command = connection.CreateCommand();
            command.CommandText = "DELETE FROM AppSettings WHERE Key = $key;";
            command.Parameters.AddWithValue("$key", TicketPasswordHashKey);
            return await command.ExecuteNonQueryAsync() > 0;
        }
        finally
        {
            _writeLock.Release();
        }
    }

    // ---- PDF 下载请求 Key ----

    /// <summary>
    /// 列出网页端生成的 PDF 下载请求。Key 本身只保存摘要，所以后台展示的
    /// 是摘要 ID、乘车人信息、关联行程和有效期；撤销即删除对应行。
    /// 搜索直接在 RequestJson 上做匹配，可按乘车人、证件号（掩码）或票样检索。
    /// </summary>
    public async Task<AdminPdfRequestPage> GetAdminPdfRequestsAsync(
        string? query, string? sort, string? order, int offset, int limit)
    {
        var search = query?.Trim() ?? string.Empty;
        offset = Math.Max(0, offset);
        limit = Math.Clamp(limit, 1, 100);
        var now = DateTime.Now;
        var nowDb = ToDb(now);
        var pattern = $"%{EscapeLike(search)}%";
        const string filter = """
            WHERE ($query = '' OR RequestJson LIKE $pattern ESCAPE '\')
            """;

        await using var connection = OpenConnection();
        await connection.OpenAsync();

        long total;
        long active;
        await using (var count = connection.CreateCommand())
        {
            count.CommandText = $"""
                SELECT COUNT(*),
                       COALESCE(SUM(CASE WHEN julianday(ExpiresAt) > julianday($now)
                                         THEN 1 ELSE 0 END), 0)
                FROM TicketPdfDownloads
                {filter};
                """;
            count.Parameters.AddWithValue("$now", nowDb);
            count.Parameters.AddWithValue("$query", search);
            count.Parameters.AddWithValue("$pattern", pattern);
            await using var reader = await count.ExecuteReaderAsync();
            await reader.ReadAsync();
            total = reader.GetInt64(0);
            active = reader.GetInt64(1);
        }

        var items = new List<AdminPdfRequest>();
        await using var command = connection.CreateCommand();
        command.CommandText = $"""
            SELECT KeyHash, RequestJson, CreatedAt, ExpiresAt
            FROM TicketPdfDownloads
            {filter}
            ORDER BY {AdminOrderBy(sort, order, AdminPdfSortColumns, "created", "KeyHash")}
            LIMIT $limit OFFSET $offset;
            """;
        command.Parameters.AddWithValue("$query", search);
        command.Parameters.AddWithValue("$pattern", pattern);
        // status 排序列会用到 $now；其余排序键下这个参数不被引用也无妨。
        command.Parameters.AddWithValue("$now", nowDb);
        command.Parameters.AddWithValue("$limit", limit);
        command.Parameters.AddWithValue("$offset", offset);
        await using var rows = await command.ExecuteReaderAsync();
        while (await rows.ReadAsync())
        {
            var expiresAt = FromDb(rows.GetString(3));
            var request = ParsePdfRequestJson(rows.GetString(1));
            items.Add(new AdminPdfRequest(
                rows.GetString(0),
                FromDb(rows.GetString(2)),
                expiresAt,
                expiresAt <= now,
                request.Style,
                request.Passenger,
                request.MaskedId,
                request.TripIds));
        }

        return new AdminPdfRequestPage(total, active, items);
    }

    private static (string Style, string Passenger, string MaskedId, IReadOnlyList<long> TripIds)
        ParsePdfRequestJson(string json)
    {
        try
        {
            var request = JsonSerializer.Deserialize<CreateTicketPdfKeyRequest>(json);
            return (
                request?.Style ?? string.Empty,
                request?.Passenger ?? string.Empty,
                request?.MaskedId ?? string.Empty,
                request?.TripIds ?? []);
        }
        catch (JsonException)
        {
            return (string.Empty, string.Empty, string.Empty, []);
        }
    }

    public async Task<bool> DeleteAdminPdfRequestAsync(string id)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = "DELETE FROM TicketPdfDownloads WHERE KeyHash = $id;";
        command.Parameters.AddWithValue("$id", id);
        return await command.ExecuteNonQueryAsync() > 0;
    }

    public async Task<int> DeleteExpiredPdfRequestsAsync()
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            DELETE FROM TicketPdfDownloads
            WHERE julianday(ExpiresAt) <= julianday($now);
            """;
        command.Parameters.AddWithValue("$now", ToDb(DateTime.Now));
        return await command.ExecuteNonQueryAsync();
    }

    // ---- 用户等级分界线 ----

    private const string UserLevelThresholdsKey = "UserLevels:Thresholds";

    /// <summary>在已有连接上读取等级门槛，供成就重算复用同一快照。</summary>
    private static async Task<IReadOnlyList<int>> ReadUserLevelThresholdsAsync(
        SqliteConnection connection)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT Value FROM AppSettings WHERE Key = $key LIMIT 1;";
        command.Parameters.AddWithValue("$key", UserLevelThresholdsKey);
        var value = await command.ExecuteScalarAsync() as string;
        return UserLevels.ParseOrDefault(value);
    }

    public async Task<(IReadOnlyList<int> Thresholds, DateTime? UpdatedAt)>
        GetUserLevelThresholdsAsync()
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT Value, UpdatedAt FROM AppSettings
            WHERE Key = $key LIMIT 1;
            """;
        command.Parameters.AddWithValue("$key", UserLevelThresholdsKey);
        await using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
            return (UserLevels.DefaultThresholds, null);
        return (UserLevels.ParseOrDefault(reader.GetString(0)), FromDb(reader.GetString(1)));
    }

    /// <summary>
    /// 按已保存的等级门槛统计各等级用户数。经验取 UserAchievements.Experience 之和，
    /// 与 App / 成就引擎的 TotalExperience 同一口径；没有成就的用户计入 LV0。
    /// </summary>
    public async Task<(long TotalUsers, IReadOnlyList<AdminUserLevelStat> Levels)>
        GetUserLevelStatsAsync()
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        var thresholds = await ReadUserLevelThresholdsAsync(connection);

        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT COALESCE(SUM(achievement.Experience), 0)
            FROM AspNetUsers user
            LEFT JOIN UserAchievements achievement ON achievement.UserId = user.Id
            GROUP BY user.Id;
            """;

        var counts = new long[thresholds.Count];
        long totalUsers = 0;
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            totalUsers++;
            counts[LevelIndexForExperience(thresholds, reader.GetInt64(0))]++;
        }

        var levels = new List<AdminUserLevelStat>(thresholds.Count);
        for (var level = 0; level < thresholds.Count; level++)
        {
            levels.Add(new AdminUserLevelStat(
                level,
                thresholds[level],
                counts[level],
                totalUsers > 0 ? Math.Round(counts[level] * 100.0 / totalUsers, 1) : 0));
        }
        return (totalUsers, levels);
    }

    private static int LevelIndexForExperience(
        IReadOnlyList<int> thresholds, long experience)
    {
        for (var level = thresholds.Count - 1; level > 0; level--)
        {
            if (experience >= thresholds[level]) return level;
        }
        return 0;
    }

    public async Task<(IReadOnlyList<int>? Thresholds, string? Error)>
        SaveUserLevelThresholdsAsync(IReadOnlyList<int> thresholds)
    {
        var error = UserLevels.Validate(thresholds);
        if (error is not null) return (null, error);

        var json = JsonSerializer.Serialize(thresholds);
        await _writeLock.WaitAsync();
        try
        {
            await using var connection = OpenConnection();
            await connection.OpenAsync();
            await using var command = connection.CreateCommand();
            command.CommandText = """
                INSERT INTO AppSettings (Key, Value, UpdatedAt)
                VALUES ($key, $value, $now)
                ON CONFLICT(Key) DO UPDATE SET
                    Value = excluded.Value,
                    UpdatedAt = excluded.UpdatedAt;
                """;
            command.Parameters.AddWithValue("$key", UserLevelThresholdsKey);
            command.Parameters.AddWithValue("$value", json);
            command.Parameters.AddWithValue("$now", ToDb(DateTime.Now));
            await command.ExecuteNonQueryAsync();
        }
        finally
        {
            _writeLock.Release();
        }
        return (thresholds, null);
    }

    // ---- 用户 ----

    public async Task<AdminUserPage> GetAdminUsersAsync(
        string? query, int? level, string? sort, string? order, int offset, int limit)
    {
        var search = query?.Trim() ?? string.Empty;
        offset = Math.Max(0, offset);
        limit = Math.Clamp(limit, 1, 100);
        var pattern = $"%{EscapeLike(search)}%";

        await using var connection = OpenConnection();
        await connection.OpenAsync();
        var thresholds = await ReadUserLevelThresholdsAsync(connection);

        // 越界的 level 视为「没有筛选」，避免后台书签失效后整页空白。
        var selectedLevel = level is >= 0 && level < thresholds.Count ? level.Value : -1;
        int? minExperience = selectedLevel >= 0 ? thresholds[selectedLevel] : null;
        int? maxExperience = selectedLevel >= 0 && selectedLevel + 1 < thresholds.Count
            ? thresholds[selectedLevel + 1]
            : null;

        const string filter = """
            ($query = '' OR Email COLLATE NOCASE LIKE $pattern ESCAPE '\'
                OR DisplayName COLLATE NOCASE LIKE $pattern ESCAPE '\'
                OR Id = $query)
            AND ($level < 0
                 OR (Experience >= $minExperience
                     AND ($maxExperience IS NULL OR Experience < $maxExperience)))
            """;
        const string userRows = """
            WITH user_rows AS (
                SELECT user.Id, user.Email, user.DisplayName, user.AvatarUrl, user.CreatedAt,
                       (SELECT COUNT(*) FROM TripRecords trip
                        WHERE trip.UserId = user.Id AND trip.DeletedAt IS NULL) AS TripCount,
                       (SELECT COUNT(*) FROM TripRecords trip
                        WHERE trip.UserId = user.Id AND trip.DeletedAt IS NOT NULL) AS DeletedTripCount,
                       COALESCE((SELECT SUM(achievement.Experience) FROM UserAchievements achievement
                                 WHERE achievement.UserId = user.Id), 0) AS Experience
                FROM AspNetUsers user
            )
            """;

        long total;
        await using (var count = connection.CreateCommand())
        {
            count.CommandText = $"{userRows} SELECT COUNT(*) FROM user_rows WHERE {filter};";
            AddUserFilterParameters(count, search, pattern, selectedLevel, minExperience, maxExperience);
            total = Convert.ToInt64(await count.ExecuteScalarAsync());
        }

        await using var command = connection.CreateCommand();
        command.CommandText = $"""
            {userRows}
            SELECT Id, Email, DisplayName, AvatarUrl, CreatedAt,
                   TripCount, DeletedTripCount, Experience
            FROM user_rows
            WHERE {filter}
            ORDER BY {AdminOrderBy(sort, order, AdminUserSortColumns, "created", "Id")}
            LIMIT $limit OFFSET $offset;
            """;
        AddUserFilterParameters(command, search, pattern, selectedLevel, minExperience, maxExperience);
        command.Parameters.AddWithValue("$limit", limit);
        command.Parameters.AddWithValue("$offset", offset);
        var items = new List<AdminUserSummary>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            var experience = Convert.ToInt32(reader.GetInt64(7));
            items.Add(new AdminUserSummary(
                reader.GetString(0),
                reader.IsDBNull(1) ? string.Empty : reader.GetString(1),
                reader.IsDBNull(2) ? "RailLog 用户" : reader.GetString(2),
                NullableString(reader, 3),
                reader.IsDBNull(4) ? DateTime.MinValue : FromDb(reader.GetString(4)),
                reader.GetInt64(5),
                reader.GetInt64(6),
                experience,
                LevelIndexForExperience(thresholds, experience)));
        }
        return new AdminUserPage(items, total);
    }

    private static void AddUserFilterParameters(
        SqliteCommand command,
        string query,
        string pattern,
        int level,
        int? minExperience,
        int? maxExperience)
    {
        command.Parameters.AddWithValue("$query", query);
        command.Parameters.AddWithValue("$pattern", pattern);
        command.Parameters.AddWithValue("$level", level);
        command.Parameters.AddWithValue("$minExperience", (object?)minExperience ?? DBNull.Value);
        command.Parameters.AddWithValue("$maxExperience", (object?)maxExperience ?? DBNull.Value);
    }

    public async Task<AdminUserSummary?> GetAdminUserAsync(string userId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        var thresholds = await ReadUserLevelThresholdsAsync(connection);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT user.Id, user.Email, user.DisplayName, user.AvatarUrl, user.CreatedAt,
                   (SELECT COUNT(*) FROM TripRecords trip
                    WHERE trip.UserId = user.Id AND trip.DeletedAt IS NULL),
                   (SELECT COUNT(*) FROM TripRecords trip
                    WHERE trip.UserId = user.Id AND trip.DeletedAt IS NOT NULL),
                   COALESCE((SELECT SUM(achievement.Experience) FROM UserAchievements achievement
                             WHERE achievement.UserId = user.Id), 0),
                   user.Bio, user.ShowEmailOnProfile
            FROM AspNetUsers user
            WHERE user.Id = $userId
            LIMIT 1;
            """;
        command.Parameters.AddWithValue("$userId", userId);
        await using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync()) return null;
        var experience = Convert.ToInt32(reader.GetInt64(7));
        return new AdminUserSummary(
            reader.GetString(0),
            reader.IsDBNull(1) ? string.Empty : reader.GetString(1),
            reader.IsDBNull(2) ? "RailLog 用户" : reader.GetString(2),
            NullableString(reader, 3),
            reader.IsDBNull(4) ? DateTime.MinValue : FromDb(reader.GetString(4)),
            reader.GetInt64(5),
            reader.GetInt64(6),
            experience,
            LevelIndexForExperience(thresholds, experience),
            NullableString(reader, 8),
            !reader.IsDBNull(9) && reader.GetInt32(9) == 1);
    }

    public async Task<(AdminUserSummary? User, string? Error)> UpdateAdminUserAsync(
        string userId,
        AdminUserUpdateRequest request)
    {
        var name = request.DisplayName?.Trim() ?? string.Empty;
        var email = request.Email?.Trim() ?? string.Empty;
        if (name.Length is < 2 or > 40) return (null, "昵称长度应为 2 至 40 个字符");
        if (email.Length is < 3 or > 200 || !email.Contains('@'))
            return (null, "请填写有效的邮箱地址");
        if (request.AvatarUrl?.Trim().Length > 1000) return (null, "头像地址过长");
        if (request.Bio?.Trim().Length > 300) return (null, "个人简介不能超过 300 个字符");

        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            UPDATE AspNetUsers
            SET DisplayName = $name, Email = $email, AvatarUrl = $avatar,
                Bio = $bio, ShowEmailOnProfile = $showEmail
            WHERE Id = $id;
            """;
        command.Parameters.AddWithValue("$name", name);
        command.Parameters.AddWithValue("$email", email);
        command.Parameters.AddWithValue("$avatar", DbValue(request.AvatarUrl));
        command.Parameters.AddWithValue("$bio", DbValue(request.Bio));
        command.Parameters.AddWithValue("$showEmail", request.ShowEmailOnProfile ? 1 : 0);
        command.Parameters.AddWithValue("$id", userId);
        try
        {
            if (await command.ExecuteNonQueryAsync() == 0)
                return (null, "没有找到该用户");
        }
        catch (SqliteException exception) when (exception.SqliteErrorCode == 19)
        {
            return (null, "昵称或邮箱已被其他用户使用");
        }
        return (await GetAdminUserAsync(userId), null);
    }

    /// <summary>
    /// 硬删除账户。外键级联会一并清掉行程、评价、成就与令牌；
    /// 管理员账户由控制器层拦截，这里不再重复判断。
    /// </summary>
    public async Task<bool> DeleteAdminUserAsync(string userId)
    {
        var deleted = false;
        await _writeLock.WaitAsync();
        try
        {
            await using var connection = OpenConnection();
            await connection.OpenAsync();
            await using var transaction = await BeginTransactionWithRetryAsync(connection);
            await using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = "DELETE FROM AspNetUsers WHERE Id = $id;";
            command.Parameters.AddWithValue("$id", userId);
            deleted = await command.ExecuteNonQueryAsync() > 0;
            await transaction.CommitAsync();
        }
        finally
        {
            _writeLock.Release();
        }

        if (deleted) InvalidateStatisticsCache(userId);
        return deleted;
    }

    // ---- 行程 ----

    public async Task<IReadOnlyList<AdminTrip>> GetAdminTripsAsync(
        string userId, bool includeDeleted = true)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = $"""
            SELECT {AdminTripColumns}
            FROM TripRecords
            WHERE UserId = $userId
              AND ($includeDeleted = 1 OR DeletedAt IS NULL)
            ORDER BY DeletedAt IS NOT NULL, DepartureTime DESC, Id DESC;
            """;
        command.Parameters.AddWithValue("$userId", userId);
        command.Parameters.AddWithValue("$includeDeleted", includeDeleted ? 1 : 0);
        var items = new List<AdminTrip>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
            items.Add(ReadAdminTrip(reader));
        return items;
    }

    public async Task<(AdminTrip? Trip, string? Error)> CreateAdminTripAsync(
        string userId, AdminTripRequest request)
    {
        var error = ValidateAdminTrip(request);
        if (error is not null) return (null, error);

        AdminTrip? trip = null;
        await _writeLock.WaitAsync();
        try
        {
            await using var connection = OpenConnection();
            await connection.OpenAsync();
            await using var transaction = await BeginTransactionWithRetryAsync(connection);

            await using (var exists = connection.CreateCommand())
            {
                exists.Transaction = transaction;
                exists.CommandText = "SELECT 1 FROM AspNetUsers WHERE Id = $userId LIMIT 1;";
                exists.Parameters.AddWithValue("$userId", userId);
                if (await exists.ExecuteScalarAsync() is null)
                {
                    await transaction.RollbackAsync();
                    return (null, "用户不存在");
                }
            }

            var version = await AllocateSyncVersionAsync(
                connection, userId, (SqliteTransaction)transaction);
            var now = DateTime.Now;
            await using var insert = connection.CreateCommand();
            insert.Transaction = transaction;
            insert.CommandText = """
                INSERT INTO TripRecords
                    (UserId, ClientId, CreatedAt, TrainNumber, TravelDate, RollingStock,
                     CompanyName, FromStation, ToStation, DepartureTime, ArrivalTime,
                     MileageKm, ViaRoutes, SeatType, SeatNumber, Price, Notes,
                     GroupName, IsRailTrip, UpdatedAt, DeletedAt, ServerUpdatedAt,
                     SyncVersion)
                VALUES
                    ($userId, $clientId, $createdAt, $trainNumber, $travelDate, $rollingStock,
                     $companyName, $fromStation, $toStation, $departureTime, $arrivalTime,
                     $mileage, $routes, $seatType, $seatNumber, $price, $notes,
                     $groupName, $isRail, $updatedAt, NULL, $serverUpdatedAt,
                     $syncVersion)
                RETURNING Id;
                """;
            AddAdminTripParameters(insert, request, now);
            insert.Parameters.AddWithValue("$userId", userId);
            insert.Parameters.AddWithValue("$clientId", Guid.NewGuid().ToString("N"));
            insert.Parameters.AddWithValue("$createdAt", ToDb(now));
            insert.Parameters.AddWithValue("$syncVersion", version);
            var id = Convert.ToInt64(await insert.ExecuteScalarAsync());
            trip = await ReadAdminTripAsync(connection, id, transaction);
            await transaction.CommitAsync();
        }
        finally
        {
            _writeLock.Release();
        }

        if (trip is not null)
        {
            EnqueueAchievementRecompute(userId);
            InvalidateStatisticsCache(userId);
        }
        return (trip, null);
    }

    public async Task<(AdminTrip? Trip, string? Error)> UpdateAdminTripAsync(
        long ticketId, AdminTripRequest request)
    {
        var error = ValidateAdminTrip(request);
        if (error is not null) return (null, error);

        string? userId = null;
        AdminTrip? trip = null;
        await _writeLock.WaitAsync();
        try
        {
            await using var connection = OpenConnection();
            await connection.OpenAsync();
            await using var transaction = await BeginTransactionWithRetryAsync(connection);

            DateTime? existingDeletedAt = null;
            await using (var owner = connection.CreateCommand())
            {
                owner.Transaction = transaction;
                owner.CommandText = "SELECT UserId, DeletedAt FROM TripRecords WHERE Id = $id LIMIT 1;";
                owner.Parameters.AddWithValue("$id", ticketId);
                await using var reader = await owner.ExecuteReaderAsync();
                if (!await reader.ReadAsync())
                {
                    await transaction.RollbackAsync();
                    return (null, "行程不存在");
                }
                userId = reader.GetString(0);
                existingDeletedAt = reader.IsDBNull(1) ? null : FromDb(reader.GetString(1));
            }

            var version = await AllocateSyncVersionAsync(
                connection, userId!, (SqliteTransaction)transaction);
            var now = DateTime.Now;
            var deletedAt = request.IsDeleted ? existingDeletedAt ?? now : (DateTime?)null;
            await using var update = connection.CreateCommand();
            update.Transaction = transaction;
            update.CommandText = """
                UPDATE TripRecords SET
                    TrainNumber=$trainNumber, TravelDate=$travelDate,
                    RollingStock=$rollingStock, CompanyName=$companyName,
                    FromStation=$fromStation, ToStation=$toStation,
                    DepartureTime=$departureTime, ArrivalTime=$arrivalTime,
                    MileageKm=$mileage, ViaRoutes=$routes, SeatType=$seatType,
                    SeatNumber=$seatNumber, Price=$price, Notes=$notes,
                    GroupName=$groupName, IsRailTrip=$isRail,
                    UpdatedAt=$updatedAt, DeletedAt=$deletedAt,
                    ServerUpdatedAt=$serverUpdatedAt, SyncVersion=$syncVersion
                WHERE Id=$id;
                """;
            AddAdminTripParameters(update, request, now);
            update.Parameters.AddWithValue("$id", ticketId);
            update.Parameters.AddWithValue("$deletedAt", DbValue(deletedAt));
            update.Parameters.AddWithValue("$syncVersion", version);
            await update.ExecuteNonQueryAsync();
            trip = await ReadAdminTripAsync(connection, ticketId, transaction);
            await transaction.CommitAsync();
        }
        finally
        {
            _writeLock.Release();
        }

        if (trip is not null && userId is not null)
        {
            EnqueueAchievementRecompute(userId);
            InvalidateStatisticsCache(userId);
        }
        return (trip, null);
    }

    public async Task<bool> DeleteAdminTripAsync(long ticketId)
    {
        string? userId = null;
        var deleted = false;
        await _writeLock.WaitAsync();
        try
        {
            await using var connection = OpenConnection();
            await connection.OpenAsync();
            await using var transaction = await BeginTransactionWithRetryAsync(connection);
            await using (var owner = connection.CreateCommand())
            {
                owner.Transaction = transaction;
                owner.CommandText = """
                    SELECT UserId FROM TripRecords
                    WHERE Id = $id AND DeletedAt IS NULL LIMIT 1;
                    """;
                owner.Parameters.AddWithValue("$id", ticketId);
                userId = await owner.ExecuteScalarAsync() as string;
            }
            if (userId is null)
            {
                await transaction.RollbackAsync();
                return false;
            }

            var version = await AllocateSyncVersionAsync(
                connection, userId, (SqliteTransaction)transaction);
            var now = DateTime.Now;
            await using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = """
                UPDATE TripRecords
                SET DeletedAt = $deletedAt, UpdatedAt = $deletedAt,
                    ServerUpdatedAt = $serverUpdatedAt, SyncVersion = $syncVersion
                WHERE Id = $id;
                """;
            command.Parameters.AddWithValue("$deletedAt", ToDb(now));
            command.Parameters.AddWithValue("$serverUpdatedAt", ToDbUtc(DateTime.UtcNow));
            command.Parameters.AddWithValue("$syncVersion", version);
            command.Parameters.AddWithValue("$id", ticketId);
            deleted = await command.ExecuteNonQueryAsync() > 0;
            await transaction.CommitAsync();
        }
        finally
        {
            _writeLock.Release();
        }
        if (deleted && userId is not null)
        {
            EnqueueAchievementRecompute(userId);
            InvalidateStatisticsCache(userId);
        }
        return deleted;
    }

    // ---- 评价管理 ----

    private const string AdminReviewFilter = """
        WHERE ($type = '' OR r.EntityType = $type COLLATE NOCASE)
          AND ($review = '' OR r.ReviewType = $review COLLATE NOCASE)
          AND ($keyword = ''
               OR r.Comment LIKE $like ESCAPE '\'
               OR r.EntityKey LIKE $like ESCAPE '\'
               OR u.DisplayName LIKE $like ESCAPE '\'
               OR u.Email LIKE $like ESCAPE '\'
               OR trip.TrainNumber LIKE $like ESCAPE '\')
        """;

    public async Task<AdminReviewPage> GetAdminReviewsAsync(
        string? query,
        string? entityType,
        string? reviewType,
        string? sort,
        string? order,
        int offset,
        int limit)
    {
        offset = Math.Max(0, offset);
        limit = Math.Clamp(limit, 1, 100);
        var keyword = query?.Trim() ?? string.Empty;
        var type = entityType?.Trim() ?? string.Empty;
        var review = reviewType?.Trim() ?? string.Empty;

        await using var connection = OpenConnection();
        await connection.OpenAsync();

        await using var countCommand = connection.CreateCommand();
        countCommand.CommandText = $"""
            SELECT COUNT(*)
            FROM EntityReviews r
            JOIN AspNetUsers u ON u.Id = r.UserId
            LEFT JOIN TripRecords trip ON trip.Id = r.TripId AND trip.UserId = r.UserId
            {AdminReviewFilter};
            """;
        AddAdminReviewParameters(countCommand, keyword, type, review);
        var total = Convert.ToInt64(await countCommand.ExecuteScalarAsync());

        await using var command = connection.CreateCommand();
        command.CommandText = $"""
            SELECT r.Id,r.EntityType,r.EntityKey,r.ReviewType,r.UserId,
                   u.DisplayName,u.Email,u.AvatarUrl,r.Rating,r.Comment,
                   r.TripId,r.SecondTripId,r.RouteFromStation,r.RouteToStation,
                   r.Dish,r.Price,r.CreatedAt,
                   (SELECT COUNT(*) FROM EntityReviewReactions reaction
                    WHERE reaction.ReviewId = r.Id),
                   trip.Id,trip.TrainNumber,trip.TravelDate,
                   trip.FromStation,trip.ToStation,trip.DeletedAt
            FROM EntityReviews r
            JOIN AspNetUsers u ON u.Id = r.UserId
            LEFT JOIN TripRecords trip ON trip.Id = r.TripId AND trip.UserId = r.UserId
            {AdminReviewFilter}
            ORDER BY {AdminOrderBy(sort, order, AdminReviewSortColumns, "created", "r.Id DESC")}
            LIMIT $limit OFFSET $offset;
            """;
        AddAdminReviewParameters(command, keyword, type, review);
        command.Parameters.AddWithValue("$limit", limit);
        command.Parameters.AddWithValue("$offset", offset);

        var items = new List<AdminReview>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
            items.Add(ReadAdminReview(reader));
        return new AdminReviewPage(items, total);
    }

    private static void AddAdminReviewParameters(
        SqliteCommand command,
        string keyword,
        string entityType,
        string reviewType)
    {
        command.Parameters.AddWithValue("$keyword", keyword);
        command.Parameters.AddWithValue(
            "$like",
            $"%{keyword.Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_")}%");
        command.Parameters.AddWithValue("$type", entityType);
        command.Parameters.AddWithValue("$review", reviewType);
    }

    private static AdminReview ReadAdminReview(SqliteDataReader reader) => new(
        reader.GetInt64(0),
        reader.GetString(1),
        reader.GetString(2),
        reader.GetString(3),
        reader.GetString(4),
        reader.GetString(5),
        NullableString(reader, 6),
        NullableString(reader, 7),
        reader.GetInt32(8),
        reader.GetString(9),
        reader.IsDBNull(10) ? null : reader.GetInt64(10),
        reader.IsDBNull(11) ? null : reader.GetInt64(11),
        NullableString(reader, 12),
        NullableString(reader, 13),
        NullableString(reader, 14),
        reader.IsDBNull(15) ? null : Convert.ToDecimal(reader.GetValue(15)),
        FromDb(reader.GetString(16)),
        reader.GetInt64(17),
        reader.IsDBNull(18)
            ? null
            : new AdminReviewTrip(
                reader.GetInt64(18),
                reader.GetString(19),
                FromDb(reader.GetString(20)),
                reader.GetString(21),
                reader.GetString(22),
                NullableDate(reader, 23)));

    public async Task<bool> DeleteAdminReviewAsync(long id)
    {
        string? userId = null;
        var deleted = false;
        await _writeLock.WaitAsync();
        try
        {
            await using var connection = OpenConnection();
            await connection.OpenAsync();
            await using var transaction = await BeginTransactionWithRetryAsync(connection);
            await using (var owner = connection.CreateCommand())
            {
                owner.Transaction = transaction;
                owner.CommandText = "SELECT UserId FROM EntityReviews WHERE Id = $id LIMIT 1;";
                owner.Parameters.AddWithValue("$id", id);
                userId = await owner.ExecuteScalarAsync() as string;
            }
            if (userId is null)
            {
                await transaction.RollbackAsync();
                return false;
            }

            await using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = """
                DELETE FROM EntityReviewReactions WHERE ReviewId = $id;
                DELETE FROM EntityReviews WHERE Id = $id;
                """;
            command.Parameters.AddWithValue("$id", id);
            deleted = await command.ExecuteNonQueryAsync() > 0;
            await transaction.CommitAsync();
        }
        finally
        {
            _writeLock.Release();
        }

        // 删除评价会改变作者的「评价数」和「收到回应的次数」，两者都是成就输入。
        if (deleted && userId is not null)
        {
            EnqueueAchievementRecompute(userId);
            // 评分同时是要素排行榜的输入，后台删除也要让缓存失效。
            InvalidateStatisticsCache(userId);
        }
        return deleted;
    }

    // ---- 成就（只读） ----

    /// <summary>
    /// 全站成就达成情况。成就定义直接来自引擎，因此即使某个成就
    /// 无人达成，管理后台也能看到它；Hidden 成就向管理员显示真实标题。
    /// </summary>
    public async Task<AdminAchievementOverview> GetAdminAchievementsAsync()
    {
        var definitions = AchievementEngine.Evaluate([], [], new AchievementContext(0, 0));

        await using var connection = OpenConnection();
        await connection.OpenAsync();

        long totalUsers;
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = "SELECT COUNT(*) FROM AspNetUsers;";
            totalUsers = Convert.ToInt64(await command.ExecuteScalarAsync());
        }

        var stats = new Dictionary<string, (long Count, DateTime? Latest)>(
            StringComparer.Ordinal);
        await using (var command = connection.CreateCommand())
        {
            // EvaluatedAt 每轮重算都会刷新，不能当达成时间；用「触发行程」的
            // 乘车/录入时间近似「最近有人达成」。
            command.CommandText = """
                SELECT achievement.AchievementId, COUNT(*),
                       (SELECT COALESCE(trip2.DepartureTime, trip2.CreatedAt)
                        FROM UserAchievements achievement2
                        JOIN TripRecords trip2 ON trip2.Id = achievement2.TriggerTripId
                        WHERE achievement2.AchievementId = achievement.AchievementId
                        ORDER BY julianday(COALESCE(trip2.DepartureTime, trip2.CreatedAt)) DESC
                        LIMIT 1)
                FROM UserAchievements achievement
                GROUP BY achievement.AchievementId;
                """;
            await using var reader = await command.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                stats[reader.GetString(0)] = (
                    reader.GetInt64(1),
                    reader.IsDBNull(2) ? null : FromDb(reader.GetString(2)));
            }
        }

        var items = definitions
            .Select(definition =>
            {
                var (count, latest) = stats.GetValueOrDefault(definition.Id);
                return new AdminAchievement(
                    definition.Id,
                    definition.Category,
                    definition.Icon,
                    definition.Title,
                    definition.Description,
                    definition.Experience,
                    definition.Hidden,
                    count,
                    totalUsers > 0
                        ? Math.Round(count * 100.0 / totalUsers, 1)
                        : 0,
                    latest);
            })
            .ToList();
        return new AdminAchievementOverview(
            totalUsers,
            stats.Values.Sum(value => value.Count),
            items);
    }

    public async Task<AdminAchievementUnlockPage?> GetAdminAchievementUnlocksAsync(
        string achievementId,
        int offset,
        int limit)
    {
        var definition = AchievementEngine
            .Evaluate([], [], new AchievementContext(0, 0))
            .FirstOrDefault(item => item.Id == achievementId);
        if (definition is null) return null;

        offset = Math.Max(0, offset);
        limit = Math.Clamp(limit, 1, 100);

        await using var connection = OpenConnection();
        await connection.OpenAsync();

        long total;
        await using (var count = connection.CreateCommand())
        {
            count.CommandText = """
                SELECT COUNT(*) FROM UserAchievements
                WHERE AchievementId = $achievementId;
                """;
            count.Parameters.AddWithValue("$achievementId", achievementId);
            total = Convert.ToInt64(await count.ExecuteScalarAsync());
        }

        var items = new List<AdminAchievementUnlock>();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT user.Id, user.DisplayName, user.Email,
                   trip.Id, trip.TrainNumber, trip.FromStation, trip.ToStation,
                   COALESCE(trip.DepartureTime, trip.CreatedAt), trip.DeletedAt
            FROM UserAchievements achievement
            JOIN AspNetUsers user ON user.Id = achievement.UserId
            JOIN TripRecords trip ON trip.Id = achievement.TriggerTripId
            WHERE achievement.AchievementId = $achievementId
            ORDER BY julianday(COALESCE(trip.DepartureTime, trip.CreatedAt)) DESC,
                     trip.Id DESC
            LIMIT $limit OFFSET $offset;
            """;
        command.Parameters.AddWithValue("$achievementId", achievementId);
        command.Parameters.AddWithValue("$limit", limit);
        command.Parameters.AddWithValue("$offset", offset);
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            items.Add(new AdminAchievementUnlock(
                reader.GetString(0),
                reader.GetString(1),
                NullableString(reader, 2),
                reader.GetInt64(3),
                reader.GetString(4),
                reader.GetString(5),
                reader.GetString(6),
                FromDb(reader.GetString(7)),
                NullableDate(reader, 8)));
        }

        return new AdminAchievementUnlockPage(achievementId, total, items);
    }

    // ---- 后台首页 ----

    /// <summary>
    /// 平均速度超过 360 km/h，或起止时间缺失/倒置导致时长无效的行程都不参与排行榜，
    /// 因此这里只标出「能算速度、但算出来不可能」的记录。
    /// </summary>
    private const string OverspeedTripCondition = """
        trip.IsRailTrip = 1 AND trip.DeletedAt IS NULL
        AND trip.MileageKm > 0
        AND trip.DepartureTime IS NOT NULL AND trip.ArrivalTime IS NOT NULL
        AND julianday(trip.ArrivalTime) > julianday(trip.DepartureTime)
        AND trip.MileageKm
            / (julianday(trip.ArrivalTime) - julianday(trip.DepartureTime)) / 24.0 > 360
        """;

    /// <summary>
    /// 疑似重复的判据：同用户、同车次、同乘车日期，且始发终到站、票价、
    /// 里程都一致。区间或票价不同说明是两次不同的乘车，不能算重复。
    /// </summary>
    private const string DuplicateGroupKey = """
        SELECT UserId, TrainNumber, date(TravelDate) AS Day,
               FromStation, ToStation, MileageKm, Price
        FROM TripRecords
        WHERE IsRailTrip = 1 AND DeletedAt IS NULL
        GROUP BY UserId, TrainNumber, date(TravelDate),
                 FromStation, ToStation, MileageKm, Price
        HAVING COUNT(*) > 1
        """;

    public async Task<AdminOverview> GetAdminOverviewAsync(int sampleLimit = 5)
    {
        sampleLimit = Math.Clamp(sampleLimit, 1, 20);
        var since = ToDbUtc(DateTime.UtcNow.AddDays(-7));

        await using var connection = OpenConnection();
        await connection.OpenAsync();

        AdminOverviewCounts counts;
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = """
                SELECT
                    (SELECT COUNT(*) FROM AspNetUsers),
                    (SELECT COUNT(*) FROM AspNetUsers
                     WHERE julianday(CreatedAt) >= julianday($since)),
                    (SELECT COUNT(*) FROM TripRecords WHERE DeletedAt IS NULL),
                    (SELECT COUNT(*) FROM TripRecords
                     WHERE DeletedAt IS NULL AND julianday(CreatedAt) >= julianday($since)),
                    (SELECT COUNT(*) FROM TripRecords WHERE DeletedAt IS NOT NULL),
                    (SELECT COUNT(*) FROM EntityReviews),
                    (SELECT COUNT(*) FROM EntityReviews
                     WHERE julianday(CreatedAt) >= julianday($since)),
                    (SELECT COUNT(*) FROM Announcements WHERE IsActive = 1);
                """;
            command.Parameters.AddWithValue("$since", since);
            await using var reader = await command.ExecuteReaderAsync();
            await reader.ReadAsync();
            counts = new AdminOverviewCounts(
                reader.GetInt64(0),
                reader.GetInt64(1),
                reader.GetInt64(2),
                reader.GetInt64(3),
                reader.GetInt64(4),
                reader.GetInt64(5),
                reader.GetInt64(6),
                reader.GetInt64(7));
        }

        long overspeedCount;
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = $"""
                SELECT COUNT(*) FROM TripRecords trip WHERE {OverspeedTripCondition};
                """;
            overspeedCount = Convert.ToInt64(await command.ExecuteScalarAsync());
        }

        var overspeedTrips = new List<AdminFlaggedTrip>();
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = $"""
                SELECT trip.Id, trip.UserId, user.DisplayName, trip.TrainNumber,
                       trip.FromStation, trip.ToStation, trip.TravelDate,
                       trip.MileageKm,
                       trip.MileageKm
                         / (julianday(trip.ArrivalTime) - julianday(trip.DepartureTime))
                         / 24.0 AS SpeedKmh
                FROM TripRecords trip
                JOIN AspNetUsers user ON user.Id = trip.UserId
                WHERE {OverspeedTripCondition}
                ORDER BY SpeedKmh DESC
                LIMIT $limit;
                """;
            command.Parameters.AddWithValue("$limit", sampleLimit);
            await using var reader = await command.ExecuteReaderAsync();
            while (await reader.ReadAsync())
                overspeedTrips.Add(ReadFlaggedTrip(reader));
        }

        long duplicateGroupCount;
        long duplicateTripCount;
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = """
                SELECT COUNT(*), COALESCE(SUM(cnt), 0)
                FROM (
                    SELECT COUNT(*) AS cnt
                    FROM TripRecords
                    WHERE IsRailTrip = 1 AND DeletedAt IS NULL
                    GROUP BY UserId, TrainNumber, date(TravelDate),
                             FromStation, ToStation, MileageKm, Price
                    HAVING COUNT(*) > 1
                );
                """;
            await using var reader = await command.ExecuteReaderAsync();
            await reader.ReadAsync();
            duplicateGroupCount = reader.GetInt64(0);
            duplicateTripCount = reader.GetInt64(1);
        }

        var duplicateGroups = await ReadDuplicateGroupsAsync(
            connection, offset: 0, limit: sampleLimit);

        var recentReviews = new List<AdminRecentReview>();
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = """
                SELECT review.Id, review.UserId, user.DisplayName,
                       review.EntityType, review.EntityKey, review.ReviewType,
                       review.Rating, review.Comment, review.CreatedAt
                FROM EntityReviews review
                JOIN AspNetUsers user ON user.Id = review.UserId
                ORDER BY julianday(review.CreatedAt) DESC, review.Id DESC
                LIMIT $limit;
                """;
            command.Parameters.AddWithValue("$limit", sampleLimit);
            await using var reader = await command.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                recentReviews.Add(new AdminRecentReview(
                    reader.GetInt64(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    reader.GetString(5),
                    reader.GetInt32(6),
                    reader.GetString(7),
                    FromDb(reader.GetString(8))));
            }
        }

        var recentUsers = new List<AdminRecentUser>();
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = """
                SELECT user.Id, user.DisplayName, user.Email,
                       user.CreatedAt,
                       (SELECT COUNT(*) FROM TripRecords trip
                        WHERE trip.UserId = user.Id AND trip.DeletedAt IS NULL)
                FROM AspNetUsers user
                ORDER BY julianday(user.CreatedAt) DESC, user.Id
                LIMIT $limit;
                """;
            command.Parameters.AddWithValue("$limit", sampleLimit);
            await using var reader = await command.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                recentUsers.Add(new AdminRecentUser(
                    reader.GetString(0),
                    reader.IsDBNull(1) ? "RailLog 用户" : reader.GetString(1),
                    NullableString(reader, 2),
                    reader.IsDBNull(3) ? DateTime.MinValue : FromDb(reader.GetString(3)),
                    reader.GetInt64(4)));
            }
        }

        return new AdminOverview(
            counts,
            overspeedCount,
            overspeedTrips,
            duplicateTripCount,
            duplicateGroupCount,
            duplicateGroups,
            recentReviews,
            recentUsers);
    }

    /// <summary>分页列出全部疑似重复行程组，供概览页的「查看全部」使用。</summary>
    public async Task<AdminDuplicateGroupPage> GetAdminDuplicateGroupsAsync(
        int offset,
        int limit)
    {
        offset = Math.Max(0, offset);
        limit = Math.Clamp(limit, 1, 50);

        await using var connection = OpenConnection();
        await connection.OpenAsync();

        long totalGroups;
        long totalTrips;
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = """
                SELECT COUNT(*), COALESCE(SUM(cnt), 0)
                FROM (
                    SELECT COUNT(*) AS cnt
                    FROM TripRecords
                    WHERE IsRailTrip = 1 AND DeletedAt IS NULL
                    GROUP BY UserId, TrainNumber, date(TravelDate),
                             FromStation, ToStation, MileageKm, Price
                    HAVING COUNT(*) > 1
                );
                """;
            await using var reader = await command.ExecuteReaderAsync();
            await reader.ReadAsync();
            totalGroups = reader.GetInt64(0);
            totalTrips = reader.GetInt64(1);
        }

        var items = await ReadDuplicateGroupsAsync(connection, offset, limit);
        return new AdminDuplicateGroupPage(totalGroups, totalTrips, items);
    }

    private static async Task<List<AdminDuplicateGroup>> ReadDuplicateGroupsAsync(
        SqliteConnection connection,
        int offset,
        int limit)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = $"""
            WITH duplicate AS ({DuplicateGroupKey}),
                 page AS (
                     SELECT * FROM duplicate
                     ORDER BY Day DESC, TrainNumber, UserId, FromStation, ToStation
                     LIMIT $limit OFFSET $offset
                 )
            SELECT page.UserId, user.DisplayName, page.TrainNumber, page.Day,
                   page.FromStation, page.ToStation, page.MileageKm, page.Price,
                   trip.Id, trip.FromStation, trip.ToStation,
                   trip.DepartureTime, trip.ArrivalTime, trip.MileageKm, trip.Price,
                   trip.RollingStock, trip.SeatType, trip.SeatNumber, trip.CreatedAt
            FROM page
            JOIN AspNetUsers user ON user.Id = page.UserId
            JOIN TripRecords trip ON trip.UserId = page.UserId
             AND trip.TrainNumber = page.TrainNumber
             AND date(trip.TravelDate) = page.Day
             AND trip.FromStation = page.FromStation
             AND trip.ToStation = page.ToStation
             AND trip.MileageKm = page.MileageKm
             AND trip.Price = page.Price
            WHERE trip.IsRailTrip = 1 AND trip.DeletedAt IS NULL
            ORDER BY page.Day DESC, page.TrainNumber, page.UserId,
                     page.FromStation, page.ToStation, trip.CreatedAt, trip.Id;
            """;
        command.Parameters.AddWithValue("$limit", limit);
        command.Parameters.AddWithValue("$offset", offset);
        await using var reader = await command.ExecuteReaderAsync();

        var groups = new List<AdminDuplicateGroup>();
        var byKey = new Dictionary<string, List<AdminDuplicateTrip>>(StringComparer.Ordinal);
        while (await reader.ReadAsync())
        {
            var userId = reader.GetString(0);
            var displayName = reader.IsDBNull(1) ? "RailLog 用户" : reader.GetString(1);
            var trainNumber = reader.GetString(2);
            var day = reader.GetString(3);
            var fromStation = reader.GetString(4);
            var toStation = reader.GetString(5);
            var groupMileage = reader.GetDouble(6);
            var groupPrice = reader.GetDouble(7);
            var key = string.Join('\u001f',
                userId, trainNumber, day, fromStation, toStation,
                groupMileage.ToString("R", CultureInfo.InvariantCulture),
                groupPrice.ToString("R", CultureInfo.InvariantCulture));
            if (!byKey.TryGetValue(key, out var trips))
            {
                trips = [];
                byKey[key] = trips;
                groups.Add(new AdminDuplicateGroup(
                    userId,
                    displayName,
                    trainNumber,
                    FromDb(day),
                    fromStation,
                    toStation,
                    groupMileage,
                    groupPrice,
                    trips));
            }
            trips.Add(new AdminDuplicateTrip(
                reader.GetInt64(8),
                reader.GetString(9),
                reader.GetString(10),
                NullableDate(reader, 11),
                NullableDate(reader, 12),
                reader.GetDouble(13),
                reader.GetDouble(14),
                NullableString(reader, 15),
                NullableString(reader, 16),
                NullableString(reader, 17),
                FromDb(reader.GetString(18))));
        }
        return groups;
    }

    private static AdminFlaggedTrip ReadFlaggedTrip(SqliteDataReader reader) => new(
        reader.GetInt64(0),
        reader.GetString(1),
        reader.GetString(2),
        reader.GetString(3),
        reader.GetString(4),
        reader.GetString(5),
        FromDb(reader.GetString(6)),
        reader.GetDouble(7),
        reader.IsDBNull(8) ? null : reader.GetDouble(8));

    private static AdminTrip ReadAdminTrip(SqliteDataReader reader) => new(
        reader.GetInt64(0),
        reader.GetString(1),
        reader.GetString(2),
        FromDb(reader.GetString(3)),
        reader.GetString(4),
        FromDb(reader.GetString(5)),
        NullableString(reader, 6),
        NullableString(reader, 7),
        reader.GetString(8),
        reader.GetString(9),
        NullableDate(reader, 10),
        NullableDate(reader, 11),
        reader.GetDouble(12),
        reader.GetString(13),
        NullableString(reader, 14),
        NullableString(reader, 15),
        reader.GetDouble(16),
        NullableString(reader, 17),
        NullableString(reader, 18),
        reader.GetInt32(19) == 1,
        FromDb(reader.GetString(20)),
        NullableDate(reader, 21),
        reader.GetInt64(22));

    public async Task<AdminTrip?> GetAdminTripAsync(long ticketId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        return await ReadAdminTripAsync(connection, ticketId, null);
    }

    private static async Task<AdminTrip?> ReadAdminTripAsync(
        SqliteConnection connection, long ticketId, SqliteTransaction? transaction)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = $"SELECT {AdminTripColumns} FROM TripRecords WHERE Id = $id LIMIT 1;";
        command.Parameters.AddWithValue("$id", ticketId);
        await using var reader = await command.ExecuteReaderAsync();
        return await reader.ReadAsync() ? ReadAdminTrip(reader) : null;
    }

    private static void AddAdminTripParameters(
        SqliteCommand command, AdminTripRequest request, DateTime now)
    {
        command.Parameters.AddWithValue("$trainNumber", request.TrainNumber.Trim());
        command.Parameters.AddWithValue("$travelDate", ToDb(request.TravelDate));
        command.Parameters.AddWithValue("$rollingStock", DbValue(request.RollingStock));
        command.Parameters.AddWithValue("$companyName", DbValue(request.CompanyName));
        command.Parameters.AddWithValue("$fromStation", request.FromStation.Trim());
        command.Parameters.AddWithValue("$toStation", request.ToStation.Trim());
        command.Parameters.AddWithValue("$departureTime", DbValue(request.DepartureTime));
        command.Parameters.AddWithValue("$arrivalTime", DbValue(request.ArrivalTime));
        command.Parameters.AddWithValue("$mileage", request.MileageKm);
        command.Parameters.AddWithValue("$routes", NormalizeAdminRoutes(request.ViaRoutes));
        command.Parameters.AddWithValue("$seatType", DbValue(request.SeatType));
        command.Parameters.AddWithValue("$seatNumber", DbValue(request.SeatNumber));
        command.Parameters.AddWithValue("$price", request.Price);
        command.Parameters.AddWithValue("$notes", DbValue(request.Notes));
        command.Parameters.AddWithValue("$groupName", DbValue(request.GroupName));
        command.Parameters.AddWithValue("$isRail", request.IsRailTrip ? 1 : 0);
        command.Parameters.AddWithValue("$updatedAt", ToDb(now));
        command.Parameters.AddWithValue("$serverUpdatedAt", ToDbUtc(DateTime.UtcNow));
    }

    private static string NormalizeAdminRoutes(string? routes) =>
        string.IsNullOrWhiteSpace(routes) ? "[]" : routes.Trim();

    private static string? ValidateAdminTrip(AdminTripRequest request)
    {
        if (request.TravelDate == default)
            return "乘车日期不能为空";
        if (string.IsNullOrWhiteSpace(request.TrainNumber) || request.TrainNumber.Trim().Length > 40)
            return "车次应为 1 至 40 个字符";
        if (string.IsNullOrWhiteSpace(request.FromStation) || request.FromStation.Trim().Length > 100)
            return "出发站应为 1 至 100 个字符";
        if (string.IsNullOrWhiteSpace(request.ToStation) || request.ToStation.Trim().Length > 100)
            return "到达站应为 1 至 100 个字符";
        if (!double.IsFinite(request.MileageKm) || request.MileageKm is < 0 or > 100_000)
            return "里程应为 0 至 100000 公里";
        if (!double.IsFinite(request.Price) || request.Price is < 0 or > 1_000_000)
            return "票价应为 0 至 1000000 元";
        if (request.RollingStock?.Trim().Length > 100)
            return "车型/编组过长";
        if (request.CompanyName?.Trim().Length > 100)
            return "值乘公司过长";
        if (request.SeatType?.Trim().Length > 50 || request.SeatNumber?.Trim().Length > 50)
            return "席位信息过长";
        if (request.Notes?.Trim().Length > 2000)
            return "备注过长";
        if (request.GroupName?.Trim().Length > 100)
            return "分组名称过长";
        if (!IsValidViaRoutes(request.ViaRoutes))
            return "经由线路必须是 JSON 数组";
        return null;
    }

    private static bool IsValidViaRoutes(string? routes)
    {
        if (string.IsNullOrWhiteSpace(routes)) return true;
        try
        {
            using var document = JsonDocument.Parse(routes);
            return document.RootElement.ValueKind == JsonValueKind.Array;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    // ---- 操作日志 ----

    /// <summary>
    /// 追加一条管理员操作日志。AdminName 在这里快照，账号之后改名也不影响历史。
    /// </summary>
    public async Task WriteAdminAuditAsync(
        string adminUserId,
        string action,
        string? target = null,
        string? detail = null)
    {
        await _writeLock.WaitAsync();
        try
        {
            await using var connection = OpenConnection();
            await connection.OpenAsync();
            await using var command = connection.CreateCommand();
            command.CommandText = """
                INSERT INTO AdminAuditLogs
                    (AdminUserId, AdminName, Action, Target, Detail, CreatedAt)
                VALUES (
                    $adminUserId,
                    COALESCE((SELECT DisplayName FROM AspNetUsers WHERE Id = $adminUserId),
                             $adminUserId),
                    $action, $target, $detail, $now);
                """;
            command.Parameters.AddWithValue("$adminUserId", adminUserId);
            command.Parameters.AddWithValue("$action", Truncate(action, 80) ?? string.Empty);
            command.Parameters.AddWithValue("$target", (object?)Truncate(target, 200) ?? DBNull.Value);
            command.Parameters.AddWithValue("$detail", (object?)Truncate(detail, 500) ?? DBNull.Value);
            command.Parameters.AddWithValue("$now", ToDb(DateTime.Now));
            await command.ExecuteNonQueryAsync();
        }
        finally
        {
            _writeLock.Release();
        }
    }

    public async Task<AdminAuditPage> GetAdminAuditLogsAsync(
        string? query, string? sort, string? order, int offset, int limit)
    {
        var search = query?.Trim() ?? string.Empty;
        offset = Math.Max(0, offset);
        limit = Math.Clamp(limit, 1, 200);
        var pattern = $"%{EscapeLike(search)}%";
        const string filter = """
            WHERE ($query = ''
                   OR Action LIKE $pattern ESCAPE '\'
                   OR Target LIKE $pattern ESCAPE '\'
                   OR Detail LIKE $pattern ESCAPE '\'
                   OR AdminName LIKE $pattern ESCAPE '\')
            """;

        await using var connection = OpenConnection();
        await connection.OpenAsync();

        long total;
        await using (var count = connection.CreateCommand())
        {
            count.CommandText = $"SELECT COUNT(*) FROM AdminAuditLogs {filter};";
            count.Parameters.AddWithValue("$query", search);
            count.Parameters.AddWithValue("$pattern", pattern);
            total = Convert.ToInt64(await count.ExecuteScalarAsync());
        }

        var items = new List<AdminAuditEntry>();
        await using var command = connection.CreateCommand();
        command.CommandText = $"""
            SELECT Id, AdminUserId, AdminName, Action, Target, Detail, CreatedAt
            FROM AdminAuditLogs
            {filter}
            ORDER BY {AdminOrderBy(sort, order, AdminAuditSortColumns, "created", "Id DESC")}
            LIMIT $limit OFFSET $offset;
            """;
        command.Parameters.AddWithValue("$query", search);
        command.Parameters.AddWithValue("$pattern", pattern);
        command.Parameters.AddWithValue("$limit", limit);
        command.Parameters.AddWithValue("$offset", offset);
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            items.Add(new AdminAuditEntry(
                reader.GetInt64(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.GetString(3),
                NullableString(reader, 4),
                NullableString(reader, 5),
                FromDb(reader.GetString(6))));
        }
        return new AdminAuditPage(total, items);
    }

    private static string? Truncate(string? value, int max)
    {
        if (string.IsNullOrEmpty(value)) return null;
        return value.Length <= max ? value : value[..max];
    }

    // ---- 排序 ----
    // 后台表格的排序列都走白名单映射：前端只传键名，SQL 片段永远来自这里的常量，
    // 未知键回退到该表的默认排序，因此不存在把用户输入拼进 ORDER BY 的路径。

    private static readonly IReadOnlyDictionary<string, string> AdminUserSortColumns =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["name"] = "DisplayName COLLATE NOCASE",
            ["email"] = "Email COLLATE NOCASE",
            // 等级由经验按单调门槛推导，按经验排序等价于按等级排序。
            ["level"] = "Experience",
            ["trips"] = "TripCount",
            ["deleted"] = "DeletedTripCount",
            ["experience"] = "Experience",
            ["created"] = "CreatedAt",
        };

    private static readonly IReadOnlyDictionary<string, string> AdminPdfSortColumns =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["passenger"] = "json_extract(RequestJson, '$.Passenger') COLLATE NOCASE",
            ["created"] = "julianday(CreatedAt)",
            ["expires"] = "julianday(ExpiresAt)",
            ["status"] = "CASE WHEN julianday(ExpiresAt) > julianday($now) THEN 0 ELSE 1 END",
        };

    private static readonly IReadOnlyDictionary<string, string> AdminReviewSortColumns =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["created"] = "r.CreatedAt",
            ["rating"] = "r.Rating",
            ["reactions"] =
                "(SELECT COUNT(*) FROM EntityReviewReactions reaction WHERE reaction.ReviewId = r.Id)",
            ["user"] = "u.DisplayName COLLATE NOCASE",
            ["entity"] = "r.EntityKey COLLATE NOCASE",
        };

    private static readonly IReadOnlyDictionary<string, string> AdminAuditSortColumns =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["created"] = "CreatedAt",
            ["admin"] = "AdminName COLLATE NOCASE",
            ["action"] = "Action COLLATE NOCASE",
        };

    private static string AdminOrderBy(
        string? sort,
        string? order,
        IReadOnlyDictionary<string, string> columns,
        string defaultSort,
        string tieBreaker)
    {
        var key = sort?.Trim();
        var descending = string.Equals(order?.Trim(), "desc", StringComparison.OrdinalIgnoreCase);
        if (key is null || !columns.TryGetValue(key, out var column))
        {
            column = columns[defaultSort];
            descending = true;
        }
        return $"{column} {(descending ? "DESC" : "ASC")}, {tieBreaker}";
    }
}
