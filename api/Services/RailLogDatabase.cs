using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Caching.Memory;
using RailLog.API.Models;

namespace RailLog.API.Services;

public sealed class RailLogDatabase
{
    private const int LeaderboardSize = 20;
    private readonly string _connectionString;
    private readonly IMemoryCache _cache;
    private readonly SemaphoreSlim _statisticsLock = new(1, 1);
    private readonly TimeSpan _statisticsCacheLifetime;

    public RailLogDatabase(
        IConfiguration configuration,
        IWebHostEnvironment environment,
        IMemoryCache cache)
    {
        _cache = cache;
        var cacheMinutes = Math.Max(1, configuration.GetValue<int?>("Statistics:CacheMinutes") ?? 5);
        _statisticsCacheLifetime = TimeSpan.FromMinutes(cacheMinutes);
        var configured = configuration.GetConnectionString("RailLog") ?? "Data Source=raillog.db";
        var builder = new SqliteConnectionStringBuilder(configured);
        if (!Path.IsPathRooted(builder.DataSource))
            builder.DataSource = Path.Combine(environment.ContentRootPath, builder.DataSource);
        _connectionString = builder.ToString();
    }

    public async Task InitializeAsync()
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await ExecuteAsync(connection, "PRAGMA foreign_keys = ON;");
        await ExecuteAsync(connection, "PRAGMA journal_mode = WAL;");
        await ExecuteAsync(connection, """
            CREATE TABLE IF NOT EXISTS AspNetUsers (
                Id TEXT NOT NULL PRIMARY KEY,
                DisplayName TEXT NOT NULL,
                AvatarUrl TEXT NULL,
                Email TEXT NOT NULL,
                PasswordHash TEXT NOT NULL,
                Bio TEXT NULL,
                ShowEmailOnProfile INTEGER NOT NULL DEFAULT 0,
                CreatedAt TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS AuthTokens (
                TokenHash TEXT NOT NULL PRIMARY KEY,
                UserId TEXT NOT NULL,
                ExpiresAt TEXT NOT NULL,
                FOREIGN KEY (UserId) REFERENCES AspNetUsers (Id) ON DELETE CASCADE
            );
            CREATE TABLE IF NOT EXISTS EmailVerificationCodes (
                Id TEXT NOT NULL PRIMARY KEY,
                Email TEXT NOT NULL,
                Purpose TEXT NOT NULL,
                CodeHash TEXT NOT NULL,
                CreatedAt TEXT NOT NULL,
                ExpiresAt TEXT NOT NULL,
                AttemptCount INTEGER NOT NULL DEFAULT 0,
                ConsumedAt TEXT NULL
            );
            CREATE TABLE IF NOT EXISTS TripRecords (
                Id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                UserId TEXT NOT NULL,
                ClientId TEXT NOT NULL,
                CreatedAt TEXT NOT NULL,
                TrainNumber TEXT NOT NULL,
                TravelDate TEXT NOT NULL,
                RollingStock TEXT NULL,
                CompanyName TEXT NULL,
                FromStation TEXT NOT NULL,
                ToStation TEXT NOT NULL,
                DepartureTime TEXT NULL,
                ArrivalTime TEXT NULL,
                MileageKm REAL NOT NULL,
                ViaRoutes TEXT NOT NULL,
                SeatType TEXT NULL,
                SeatNumber TEXT NULL,
                Price REAL NOT NULL,
                Notes TEXT NULL,
                IsRailTrip INTEGER NOT NULL DEFAULT 1,
                UpdatedAt TEXT NOT NULL,
                DeletedAt TEXT NULL,
                FOREIGN KEY (UserId) REFERENCES AspNetUsers (Id) ON DELETE CASCADE,
                UNIQUE (UserId, ClientId)
            );
            CREATE TABLE IF NOT EXISTS TicketPdfDownloads (
                KeyHash TEXT NOT NULL PRIMARY KEY,
                RequestJson TEXT NOT NULL,
                CreatedAt TEXT NOT NULL,
                ExpiresAt TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS UserAchievements (
                UserId TEXT NOT NULL,
                AchievementId TEXT NOT NULL,
                TriggerTripId INTEGER NOT NULL,
                EvaluatedAt TEXT NOT NULL,
                PRIMARY KEY (UserId, AchievementId),
                FOREIGN KEY (UserId) REFERENCES AspNetUsers (Id) ON DELETE CASCADE,
                FOREIGN KEY (TriggerTripId) REFERENCES TripRecords (Id) ON DELETE CASCADE
            );
            """);
        // Remove indexes left by older Identity-compatible schemas before
        // dropping the no-longer-used normalized email column.
        await ExecuteAsync(connection, """
            DROP INDEX IF EXISTS EmailIndex;
            DROP INDEX IF EXISTS IX_AspNetUsers_NormalizedEmail;
            """);
        await DropColumnIfExistsAsync(connection, "AspNetUsers", "NormalizedEmail");
        await EnsureColumnAsync(connection, "AspNetUsers", "CreatedAt", "TEXT NULL");
        await EnsureColumnAsync(connection, "TripRecords", "ClientId", "TEXT NULL");
        await EnsureColumnAsync(connection, "TripRecords", "CompanyName", "TEXT NULL");
        await EnsureColumnAsync(connection, "TripRecords", "UpdatedAt", "TEXT NULL");
        await EnsureColumnAsync(connection, "TripRecords", "DeletedAt", "TEXT NULL");
        await ExecuteAsync(connection, $"""
            UPDATE AspNetUsers
            SET CreatedAt = '{ToDb(DateTime.Now)}'
            WHERE CreatedAt IS NULL OR CreatedAt = '';
            UPDATE TripRecords
            SET ClientId = lower(hex(randomblob(16)))
            WHERE ClientId IS NULL OR ClientId = '';
            UPDATE TripRecords
            SET UpdatedAt = CreatedAt
            WHERE UpdatedAt IS NULL OR UpdatedAt = '';
            CREATE UNIQUE INDEX IF NOT EXISTS IX_AspNetUsers_Email
                ON AspNetUsers (Email COLLATE NOCASE);
            CREATE UNIQUE INDEX IF NOT EXISTS IX_AspNetUsers_DisplayName
                ON AspNetUsers (DisplayName COLLATE NOCASE);
            CREATE INDEX IF NOT EXISTS IX_AuthTokens_UserId ON AuthTokens (UserId);
            CREATE INDEX IF NOT EXISTS IX_EmailVerificationCodes_Lookup
                ON EmailVerificationCodes (Email, Purpose, CreatedAt DESC);
            CREATE INDEX IF NOT EXISTS IX_TripRecords_UserId ON TripRecords (UserId);
            CREATE UNIQUE INDEX IF NOT EXISTS IX_TripRecords_UserClient
                ON TripRecords (UserId, ClientId);
            CREATE INDEX IF NOT EXISTS IX_TicketPdfDownloads_ExpiresAt
                ON TicketPdfDownloads (ExpiresAt);
            CREATE INDEX IF NOT EXISTS IX_UserAchievements_AchievementId
                ON UserAchievements (AchievementId);
            """);
        await RecalculateAllAchievementsAsync(connection);
    }

    public async Task CreateTicketPdfDownloadAsync(
        string keyHash,
        string requestJson,
        DateTime expiresAt)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            DELETE FROM TicketPdfDownloads WHERE ExpiresAt <= $now;
            INSERT INTO TicketPdfDownloads (KeyHash, RequestJson, CreatedAt, ExpiresAt)
            VALUES ($keyHash, $requestJson, $createdAt, $expiresAt);
            """;
        command.Parameters.AddWithValue("$now", ToDb(DateTime.Now));
        command.Parameters.AddWithValue("$keyHash", keyHash);
        command.Parameters.AddWithValue("$requestJson", requestJson);
        command.Parameters.AddWithValue("$createdAt", ToDb(DateTime.Now));
        command.Parameters.AddWithValue("$expiresAt", ToDb(expiresAt));
        await command.ExecuteNonQueryAsync();
    }

    public async Task<string?> GetTicketPdfDownloadAsync(string keyHash)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT RequestJson
            FROM TicketPdfDownloads
            WHERE KeyHash = $keyHash AND ExpiresAt > $now
            LIMIT 1;
            """;
        command.Parameters.AddWithValue("$keyHash", keyHash);
        command.Parameters.AddWithValue("$now", ToDb(DateTime.Now));
        return await command.ExecuteScalarAsync() as string;
    }

    public async Task<(AuthResponse? Response, string? Error)> RegisterAsync(RegisterRequest request)
    {
        var email = request.Email.Trim();
        var displayName = request.DisplayName.Trim();
        if (!IsValidEmail(email)) return (null, "请输入有效邮箱");
        if (displayName.Length is < 2 or > 40) return (null, "昵称长度应为 2 至 40 个字符");
        if (request.Password.Length < 8) return (null, "密码至少需要 8 个字符");

        await using var connection = OpenConnection();
        await connection.OpenAsync();
        var userId = Guid.NewGuid().ToString("N");
        await using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO AspNetUsers
                (Id, DisplayName, Email, PasswordHash, ShowEmailOnProfile, CreatedAt)
            VALUES ($id, $name, $email, $hash, 0, $createdAt);
            """;
        command.Parameters.AddWithValue("$id", userId);
        command.Parameters.AddWithValue("$name", displayName);
        command.Parameters.AddWithValue("$email", email);
        command.Parameters.AddWithValue("$hash", IdentityPasswordHasher.HashPassword(request.Password));
        command.Parameters.AddWithValue("$createdAt", ToDb(DateTime.Now));
        try
        {
            await command.ExecuteNonQueryAsync();
        }
        catch (SqliteException exception) when (exception.SqliteErrorCode == 19)
        {
            return (null, "邮箱或昵称已被使用");
        }
        return (await CreateSessionAsync(connection, new UserProfile(
            userId, email, displayName, null, null, false)), null);
    }

    public async Task<AuthResponse?> LoginAsync(LoginRequest request)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT Id, Email, DisplayName, AvatarUrl, Bio, ShowEmailOnProfile, PasswordHash
            FROM AspNetUsers WHERE Email = $email COLLATE NOCASE LIMIT 1;
            """;
        command.Parameters.AddWithValue("$email", request.Email.Trim());
        await using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync()) return null;
        var passwordHash = reader.IsDBNull(6) ? null : reader.GetString(6);
        if (!IdentityPasswordHasher.VerifyHashedPassword(passwordHash, request.Password)) return null;
        var profile = ReadProfile(reader);
        await reader.CloseAsync();
        return await CreateSessionAsync(connection, profile);
    }

    public async Task<bool> EmailExistsAsync(string email)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT 1 FROM AspNetUsers WHERE Email = $email COLLATE NOCASE LIMIT 1;";
        command.Parameters.AddWithValue("$email", email);
        return await command.ExecuteScalarAsync() is not null;
    }

    public async Task<DateTime?> GetLatestVerificationCreatedAtAsync(string email, string purpose)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT CreatedAt FROM EmailVerificationCodes
            WHERE Email = $email COLLATE NOCASE AND Purpose = $purpose
            ORDER BY CreatedAt DESC LIMIT 1;
            """;
        command.Parameters.AddWithValue("$email", email);
        command.Parameters.AddWithValue("$purpose", purpose);
        var value = await command.ExecuteScalarAsync() as string;
        return value is null ? null : FromDb(value);
    }

    public async Task InsertVerificationCodeAsync(
        string id,
        string email,
        string purpose,
        string codeHash,
        DateTime expiresAt)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO EmailVerificationCodes
                (Id, Email, Purpose, CodeHash, CreatedAt, ExpiresAt, AttemptCount)
            VALUES ($id, $email, $purpose, $hash, $createdAt, $expiresAt, 0);
            DELETE FROM EmailVerificationCodes
            WHERE CreatedAt < $cleanupBefore;
            """;
        command.Parameters.AddWithValue("$id", id);
        command.Parameters.AddWithValue("$email", email);
        command.Parameters.AddWithValue("$purpose", purpose);
        command.Parameters.AddWithValue("$hash", codeHash);
        command.Parameters.AddWithValue("$createdAt", ToDb(DateTime.Now));
        command.Parameters.AddWithValue("$expiresAt", ToDb(expiresAt));
        command.Parameters.AddWithValue("$cleanupBefore", ToDb(DateTime.Now.AddDays(-1)));
        await command.ExecuteNonQueryAsync();
    }

    public async Task DeleteVerificationCodeAsync(string id)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = "DELETE FROM EmailVerificationCodes WHERE Id = $id;";
        command.Parameters.AddWithValue("$id", id);
        await command.ExecuteNonQueryAsync();
    }

    public async Task<StoredVerificationCode?> GetLatestVerificationCodeAsync(
        string email,
        string purpose)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT Id, CodeHash, ExpiresAt, AttemptCount
            FROM EmailVerificationCodes
            WHERE Email = $email COLLATE NOCASE AND Purpose = $purpose AND ConsumedAt IS NULL
            ORDER BY CreatedAt DESC LIMIT 1;
            """;
        command.Parameters.AddWithValue("$email", email);
        command.Parameters.AddWithValue("$purpose", purpose);
        await using var reader = await command.ExecuteReaderAsync();
        return await reader.ReadAsync()
            ? new StoredVerificationCode(
                reader.GetString(0),
                reader.GetString(1),
                FromDb(reader.GetString(2)),
                reader.GetInt32(3))
            : null;
    }

    public async Task IncrementVerificationAttemptsAsync(string id)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            UPDATE EmailVerificationCodes
            SET AttemptCount = AttemptCount + 1
            WHERE Id = $id AND ConsumedAt IS NULL;
            """;
        command.Parameters.AddWithValue("$id", id);
        await command.ExecuteNonQueryAsync();
    }

    public async Task<bool> ConsumeVerificationCodeAsync(string id)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            UPDATE EmailVerificationCodes
            SET ConsumedAt = $consumedAt
            WHERE Id = $id AND ConsumedAt IS NULL;
            """;
        command.Parameters.AddWithValue("$id", id);
        command.Parameters.AddWithValue("$consumedAt", ToDb(DateTime.Now));
        return await command.ExecuteNonQueryAsync() == 1;
    }

    public async Task<bool> ResetPasswordAsync(string email, string newPassword)
    {
        if (newPassword.Length < 8) return false;
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var transaction = connection.BeginTransaction();
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            UPDATE AspNetUsers SET PasswordHash = $hash
            WHERE Email = $email COLLATE NOCASE;
            """;
        command.Parameters.AddWithValue("$hash", IdentityPasswordHasher.HashPassword(newPassword));
        command.Parameters.AddWithValue("$email", email.Trim());
        var changed = await command.ExecuteNonQueryAsync() == 1;
        if (changed)
        {
            await using var revoke = connection.CreateCommand();
            revoke.Transaction = transaction;
            revoke.CommandText = """
                DELETE FROM AuthTokens
                WHERE UserId = (SELECT Id FROM AspNetUsers WHERE Email = $email COLLATE NOCASE);
                """;
            revoke.Parameters.AddWithValue("$email", email.Trim());
            await revoke.ExecuteNonQueryAsync();
        }
        await transaction.CommitAsync();
        return changed;
    }

    public async Task<string?> ValidateTokenAsync(string token)
    {
        if (token.Length < 32) return null;
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT UserId FROM AuthTokens WHERE TokenHash = $hash AND ExpiresAt > $now LIMIT 1;";
        command.Parameters.AddWithValue("$hash", HashToken(token));
        command.Parameters.AddWithValue("$now", ToDb(DateTime.Now));
        return await command.ExecuteScalarAsync() as string;
    }

    public async Task<UserProfile?> GetProfileAsync(string userId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT Id, Email, DisplayName, AvatarUrl, Bio, ShowEmailOnProfile
            FROM AspNetUsers WHERE Id = $id LIMIT 1;
            """;
        command.Parameters.AddWithValue("$id", userId);
        await using var reader = await command.ExecuteReaderAsync();
        return await reader.ReadAsync() ? ReadProfile(reader) : null;
    }

    public async Task<(UserProfile? Profile, string? Error)> UpdateProfileAsync(
        string userId, UpdateProfileRequest request)
    {
        var name = request.DisplayName.Trim();
        if (name.Length is < 2 or > 40) return (null, "昵称长度应为 2 至 40 个字符");
        if (request.AvatarUrl?.Length > 1000 || request.Bio?.Length > 300)
            return (null, "头像地址或简介过长");
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            UPDATE AspNetUsers SET DisplayName = $name, AvatarUrl = $avatar,
                Bio = $bio, ShowEmailOnProfile = $showEmail WHERE Id = $id;
            """;
        command.Parameters.AddWithValue("$name", name);
        command.Parameters.AddWithValue("$avatar", DbValue(request.AvatarUrl));
        command.Parameters.AddWithValue("$bio", DbValue(request.Bio));
        command.Parameters.AddWithValue("$showEmail", request.ShowEmailOnProfile ? 1 : 0);
        command.Parameters.AddWithValue("$id", userId);
        try
        {
            await command.ExecuteNonQueryAsync();
        }
        catch (SqliteException exception) when (exception.SqliteErrorCode == 19)
        {
            return (null, "该昵称已被使用");
        }
        return (await GetProfileAsync(userId), null);
    }

    public async Task RevokeTokenAsync(string token)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = "DELETE FROM AuthTokens WHERE TokenHash = $hash;";
        command.Parameters.AddWithValue("$hash", HashToken(token));
        await command.ExecuteNonQueryAsync();
    }

    public async Task DeleteAccountAsync(string userId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await ExecuteAsync(connection, "PRAGMA foreign_keys = ON;");
        await using var command = connection.CreateCommand();
        command.CommandText = "DELETE FROM AspNetUsers WHERE Id = $id;";
        command.Parameters.AddWithValue("$id", userId);
        await command.ExecuteNonQueryAsync();
    }

    public async Task<IReadOnlyList<SyncTrip>> SyncTripsAsync(
        string userId, IReadOnlyList<SyncTrip> incoming)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var transaction = await connection.BeginTransactionAsync();
        foreach (var trip in incoming)
        {
            if (string.IsNullOrWhiteSpace(trip.ClientId) || trip.ClientId.Length > 100) continue;
            await using var command = connection.CreateCommand();
            command.Transaction = (SqliteTransaction)transaction;
            command.CommandText = """
                UPDATE TripRecords SET
                    CreatedAt=$createdAt, TrainNumber=$trainNumber,
                    TravelDate=$travelDate, RollingStock=$rollingStock,
                    CompanyName=$companyName, FromStation=$fromStation,
                    ToStation=$toStation, DepartureTime=$departureTime,
                    ArrivalTime=$arrivalTime, MileageKm=$mileage,
                    ViaRoutes=$routes, SeatType=$seatType,
                    SeatNumber=$seatNumber, Price=$price, Notes=$notes,
                    IsRailTrip=$isRail, UpdatedAt=$updatedAt, DeletedAt=$deletedAt
                WHERE UserId=$userId AND ClientId=$clientId
                  AND $updatedAt > UpdatedAt;

                INSERT INTO TripRecords
                    (UserId, ClientId, CreatedAt, TrainNumber, TravelDate, RollingStock, CompanyName,
                     FromStation, ToStation, DepartureTime, ArrivalTime, MileageKm, ViaRoutes,
                     SeatType, SeatNumber, Price, Notes, IsRailTrip, UpdatedAt, DeletedAt)
                SELECT
                     $userId, $clientId, $createdAt, $trainNumber, $travelDate, $rollingStock, $companyName,
                     $fromStation, $toStation, $departureTime, $arrivalTime, $mileage, $routes,
                     $seatType, $seatNumber, $price, $notes, $isRail, $updatedAt, $deletedAt
                WHERE NOT EXISTS (
                    SELECT 1 FROM TripRecords
                    WHERE UserId=$userId AND ClientId=$clientId
                );
                """;
            AddTripParameters(command, userId, trip);
            await command.ExecuteNonQueryAsync();
        }
        await RecalculateAchievementsAsync(
            connection, userId, (SqliteTransaction)transaction);
        await transaction.CommitAsync();
        return await GetTripsAsync(connection, userId);
    }

    public async Task<AchievementsResponse> GetAchievementsAsync(string userId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        return await GetAchievementsAsync(connection, userId);
    }

    public async Task<AchievementUnlockTripsResponse> GetAchievementUnlockTripsAsync(
        string achievementId,
        string currentUserId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT trip.Id, user.Id, user.DisplayName, user.AvatarUrl,
                   COALESCE(trip.DepartureTime, trip.CreatedAt), trip.TrainNumber,
                   trip.FromStation, trip.ToStation,
                   CASE WHEN user.Id = $currentUserId THEN 1 ELSE 0 END
            FROM UserAchievements achievement
            JOIN TripRecords trip ON trip.Id = achievement.TriggerTripId
            JOIN AspNetUsers user ON user.Id = achievement.UserId
            WHERE achievement.AchievementId = $achievementId
              AND trip.DeletedAt IS NULL
            ORDER BY CASE WHEN user.Id = $currentUserId THEN 0 ELSE 1 END,
                     COALESCE(trip.DepartureTime, trip.CreatedAt) DESC,
                     trip.Id DESC;
            """;
        command.Parameters.AddWithValue("$achievementId", achievementId);
        command.Parameters.AddWithValue("$currentUserId", currentUserId);
        await using var reader = await command.ExecuteReaderAsync();
        var trips = new List<AchievementUnlockTrip>();
        while (await reader.ReadAsync())
            trips.Add(new AchievementUnlockTrip(
                reader.GetInt64(0), reader.GetString(1), reader.GetString(2),
                NullableString(reader, 3), FromDb(reader.GetString(4)), reader.GetString(5),
                reader.GetString(6), reader.GetString(7), reader.GetInt32(8) == 1));
        return new AchievementUnlockTripsResponse(achievementId, trips);
    }

    public async Task<IReadOnlyList<IntersectionGroup>> GetIntersectionsAsync(string userId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            WITH ActiveTrips AS (
                SELECT * FROM TripRecords
                WHERE IsRailTrip = 1 AND DeletedAt IS NULL
            ),
            VisitEvents AS (
                SELECT Id AS TripId, UserId, trim(FromStation) AS Location,
                       DepartureTime AS OccurredAt,
                       date(DepartureTime) AS EventDay
                FROM ActiveTrips
                WHERE DepartureTime IS NOT NULL AND trim(FromStation) <> ''
                UNION ALL
                SELECT Id, UserId, trim(ToStation), ArrivalTime,
                       date(ArrivalTime)
                FROM ActiveTrips
                WHERE ArrivalTime IS NOT NULL AND trim(ToStation) <> ''
            ),
            MineVisits AS (
                SELECT DISTINCT Location, EventDay
                FROM VisitEvents WHERE UserId = $userId
            ),
            MineLocations AS (
                SELECT DISTINCT Location FROM MineVisits
            ),
            MineTrains AS (
                SELECT DISTINCT upper(trim(TrainNumber)) AS TrainKey,
                       date(DepartureTime) AS EventDay
                FROM ActiveTrips
                WHERE UserId = $userId AND DepartureTime IS NOT NULL
                  AND trim(TrainNumber) <> ''
            ),
            MineTrainKeys AS (
                SELECT DISTINCT TrainKey FROM MineTrains
            )
            SELECT 'station' AS Kind, other.Location, trip.Id, trip.UserId,
                   user.DisplayName, user.AvatarUrl,
                   min(other.OccurredAt) AS OccurredAt,
                   max(CASE WHEN EXISTS (
                       SELECT 1 FROM MineVisits exact
                       WHERE exact.Location = other.Location
                         AND exact.EventDay = other.EventDay
                   ) THEN 1 ELSE 0 END) AS IsStrict,
                   trip.TrainNumber
            FROM MineLocations mine
            JOIN VisitEvents other
              ON other.Location = mine.Location AND other.UserId <> $userId
            JOIN ActiveTrips trip ON trip.Id = other.TripId
            JOIN AspNetUsers user ON user.Id = trip.UserId
            GROUP BY other.Location, trip.Id

            UNION ALL

            SELECT DISTINCT 'train', upper(trim(trip.TrainNumber)), trip.Id,
                   trip.UserId, user.DisplayName, user.AvatarUrl,
                   trip.DepartureTime,
                   CASE WHEN EXISTS (
                       SELECT 1 FROM MineTrains exact
                       WHERE exact.TrainKey = upper(trim(trip.TrainNumber))
                         AND exact.EventDay = date(trip.DepartureTime)
                   ) THEN 1 ELSE 0 END,
                   trip.TrainNumber
            FROM MineTrainKeys mine
            JOIN ActiveTrips trip
              ON upper(trim(trip.TrainNumber)) = mine.TrainKey
             AND trip.UserId <> $userId
            JOIN AspNetUsers user ON user.Id = trip.UserId
            WHERE trip.DepartureTime IS NOT NULL
            ORDER BY OccurredAt DESC;
            """;
        command.Parameters.AddWithValue("$userId", userId);

        await using var reader = await command.ExecuteReaderAsync();
        var grouped = new Dictionary<(string Kind, string Location), List<IntersectionTrip>>();
        while (await reader.ReadAsync())
        {
            var kind = reader.GetString(0);
            var location = reader.GetString(1);
            var trip = new IntersectionTrip(
                reader.GetInt64(2), reader.GetString(3), reader.GetString(4),
                NullableString(reader, 5), FromDb(reader.GetString(6)),
                reader.GetInt32(7) == 1, reader.GetString(8));
            var key = (kind, location);
            if (!grouped.TryGetValue(key, out var trips))
            {
                trips = [];
                grouped[key] = trips;
            }
            trips.Add(trip);
        }

        return grouped
            .Select(entry => new IntersectionGroup(
                entry.Key.Kind,
                entry.Key.Location,
                entry.Value.Count,
                entry.Value.OrderByDescending(trip => trip.OccurredAt).ToList()))
            .OrderByDescending(group => group.IntersectionCount)
            .ThenByDescending(group => group.Trips.Max(trip => trip.OccurredAt))
            .ToList();
    }

    public async Task<PublicTripDetailsResponse?> GetPublicTripDetailsAsync(long ticketId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT user.Id, user.DisplayName, user.AvatarUrl, user.Bio,
                   CASE WHEN user.ShowEmailOnProfile = 1 THEN user.Email END,
                   trip.Id, trip.CreatedAt, trip.TrainNumber, trip.RollingStock,
                   trip.CompanyName, trip.FromStation, trip.ToStation,
                   trip.DepartureTime, trip.ArrivalTime, trip.MileageKm,
                   trip.ViaRoutes, trip.SeatType, trip.SeatNumber, trip.Price,
                   trip.Notes, trip.IsRailTrip
            FROM TripRecords trip
            JOIN AspNetUsers user ON user.Id = trip.UserId
            WHERE trip.Id = $ticketId AND trip.DeletedAt IS NULL
            LIMIT 1;
            """;
        command.Parameters.AddWithValue("$ticketId", ticketId);
        await using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync()) return null;

        var user = new PublicUser(
            reader.GetString(0), reader.GetString(1), NullableString(reader, 2),
            NullableString(reader, 3), NullableString(reader, 4));
        var trip = new PublicTrip(
            reader.GetInt64(5), FromDb(reader.GetString(6)), reader.GetString(7),
            NullableString(reader, 8), NullableString(reader, 9), reader.GetString(10),
            reader.GetString(11), NullableDate(reader, 12), NullableDate(reader, 13),
            reader.GetDouble(14), reader.GetString(15), NullableString(reader, 16),
            NullableString(reader, 17), reader.GetDouble(18), NullableString(reader, 19),
            reader.GetInt32(20) == 1);
        return new PublicTripDetailsResponse(user, trip);
    }

    public async Task<PublicUserDashboardResponse?> GetPublicUserDashboardAsync(string userId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();

        await using var profileCommand = connection.CreateCommand();
        profileCommand.CommandText = """
            SELECT Id, DisplayName, AvatarUrl, Bio,
                   CASE WHEN ShowEmailOnProfile = 1 THEN Email END
            FROM AspNetUsers WHERE Id = $userId LIMIT 1;
            """;
        profileCommand.Parameters.AddWithValue("$userId", userId);
        await using var profileReader = await profileCommand.ExecuteReaderAsync();
        if (!await profileReader.ReadAsync()) return null;
        var user = new PublicUser(
            profileReader.GetString(0), profileReader.GetString(1),
            NullableString(profileReader, 2), NullableString(profileReader, 3),
            NullableString(profileReader, 4));
        await profileReader.CloseAsync();

        await using var tripsCommand = connection.CreateCommand();
        tripsCommand.CommandText = """
            SELECT Id, CreatedAt, TrainNumber, RollingStock, CompanyName,
                   FromStation, ToStation, DepartureTime, ArrivalTime, MileageKm,
                   ViaRoutes, SeatType, SeatNumber, Price, Notes, IsRailTrip
            FROM TripRecords
            WHERE UserId = $userId AND DeletedAt IS NULL
            ORDER BY DepartureTime DESC, Id DESC;
            """;
        tripsCommand.Parameters.AddWithValue("$userId", userId);
        await using var tripsReader = await tripsCommand.ExecuteReaderAsync();
        var trips = new List<PublicTrip>();
        while (await tripsReader.ReadAsync())
        {
            trips.Add(new PublicTrip(
                tripsReader.GetInt64(0), FromDb(tripsReader.GetString(1)),
                tripsReader.GetString(2), NullableString(tripsReader, 3),
                NullableString(tripsReader, 4), tripsReader.GetString(5),
                tripsReader.GetString(6), NullableDate(tripsReader, 7),
                NullableDate(tripsReader, 8), tripsReader.GetDouble(9),
                tripsReader.GetString(10), NullableString(tripsReader, 11),
                NullableString(tripsReader, 12), tripsReader.GetDouble(13),
                NullableString(tripsReader, 14), tripsReader.GetInt32(15) == 1));
        }
        await tripsReader.CloseAsync();
        var achievements = await GetAchievementsAsync(connection, userId);
        return new PublicUserDashboardResponse(user, trips, achievements);
    }

    public async Task<StatisticsResponse> GetStatisticsAsync(string currentUserId)
    {
        var cacheKey = StatisticsCacheKey(currentUserId);
        if (_cache.TryGetValue(cacheKey, out StatisticsResponse? cached) && cached is not null)
            return cached;

        await _statisticsLock.WaitAsync();
        try
        {
            if (_cache.TryGetValue(cacheKey, out cached) && cached is not null)
                return cached;
            var result = await CalculateStatisticsAsync(currentUserId);
            _cache.Set(cacheKey, result, _statisticsCacheLifetime);
            return result;
        }
        finally
        {
            _statisticsLock.Release();
        }
    }

    private async Task<StatisticsResponse> CalculateStatisticsAsync(string currentUserId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT trip.Id, trip.CreatedAt, trip.TrainNumber, trip.TravelDate,
                   trip.RollingStock, trip.CompanyName, trip.FromStation,
                   trip.ToStation, trip.DepartureTime, trip.ArrivalTime,
                   trip.MileageKm, trip.ViaRoutes, trip.SeatType,
                   trip.SeatNumber, trip.Price, trip.Notes, trip.IsRailTrip,
                   user.Id, user.DisplayName, user.AvatarUrl, user.Bio,
                   CASE WHEN user.ShowEmailOnProfile = 1 THEN user.Email END
            FROM TripRecords trip
            JOIN AspNetUsers user ON user.Id = trip.UserId
            WHERE trip.IsRailTrip = 1 AND trip.DeletedAt IS NULL;
            """;

        await using var reader = await command.ExecuteReaderAsync();
        var trips = new List<StatisticsTrip>();
        while (await reader.ReadAsync())
        {
            var publicTrip = new PublicTrip(
                reader.GetInt64(0), FromDb(reader.GetString(1)), reader.GetString(2),
                NullableString(reader, 4), NullableString(reader, 5), reader.GetString(6),
                reader.GetString(7), NullableDate(reader, 8), NullableDate(reader, 9),
                reader.GetDouble(10), reader.GetString(11), NullableString(reader, 12),
                NullableString(reader, 13), reader.GetDouble(14), NullableString(reader, 15),
                reader.GetInt32(16) == 1);
            var user = new PublicUser(
                reader.GetString(17), reader.GetString(18), NullableString(reader, 19),
                NullableString(reader, 20), NullableString(reader, 21));
            trips.Add(new StatisticsTrip(
                publicTrip, user, FromDb(reader.GetString(3)), ParseRouteNames(reader.GetString(11))));
        }

        var chinaNow = DateTime.Now.AddHours(8);
        var today = chinaNow.Date;
        var weekStart = today.AddDays(-((7 + (int)today.DayOfWeek - (int)DayOfWeek.Monday) % 7));
        var yearTrips = trips
            .Where(trip => ChinaTravelDay(trip).Year == today.Year)
            .ToList();
        var monthTrips = trips
            .Where(trip =>
            {
                var day = ChinaTravelDay(trip);
                return day.Year == today.Year && day.Month == today.Month;
            })
            .ToList();
        var weekTrips = trips
            .Where(trip =>
            {
                var day = ChinaTravelDay(trip);
                return day >= weekStart && day < weekStart.AddDays(7);
            })
            .ToList();
        var site = new SiteStatistics(
            trips.Count,
            yearTrips.Count,
            monthTrips.Count,
            weekTrips.Count,
            Summarize(trips),
            Summarize(yearTrips),
            Summarize(monthTrips),
            Summarize(weekTrips));

        var users = trips.GroupBy(trip => trip.User.Id).Select(group => new
        {
            User = group.First().User,
            Spending = group.Sum(trip => trip.Trip.Price),
            Count = (double)group.Count(),
            Duration = group.Sum(trip => ValidDurationSeconds(trip.Trip) ?? 0),
            Mileage = group.Sum(trip => trip.Trip.MileageKm),
        }).ToList();
        var userBoards = new UserLeaderboards(
            RankUsers(users.Select(item => (item.User, item.Spending)), currentUserId),
            RankUsers(users.Select(item => (item.User, item.Count)), currentUserId),
            RankUsers(users.Select(item => (item.User, item.Duration)), currentUserId),
            RankUsers(users.Select(item => (item.User, item.Mileage)), currentUserId),
            await GetAchievementCountRankingAsync(connection, currentUserId));

        var durationTrips = trips
            .Select(trip => (Trip: trip, Duration: ValidDurationSeconds(trip.Trip)))
            .Where(item => item.Duration is not null).ToList();
        var ratioTrips = trips.Where(trip => trip.Trip.MileageKm > 0).ToList();
        var pricedRatioTrips = ratioTrips.Where(trip => trip.Trip.Price > 0).ToList();
        var speedTrips = durationTrips
            .Where(item => item.Trip.Trip.MileageKm > 0)
            .Select(item => (
                item.Trip,
                Speed: item.Trip.Trip.MileageKm * 3600 / item.Duration!.Value))
            .ToList();
        var tripBoards = new TripLeaderboards(
            RankTrips(trips.Select(item => (item, item.Trip.Price)), descending: true, currentUserId),
            RankTrips(trips.Select(item => (item, item.Trip.MileageKm)), descending: true, currentUserId),
            RankTrips(durationTrips.Select(item => (item.Trip, item.Duration!.Value)), descending: true, currentUserId),
            RankTrips(pricedRatioTrips.Select(item => (item, item.Trip.Price / item.Trip.MileageKm)), descending: false, currentUserId),
            RankTrips(ratioTrips.Select(item => (item, item.Trip.Price / item.Trip.MileageKm)), descending: true, currentUserId),
            RankTrips(speedTrips.Select(item => (item.Trip, item.Speed)), descending: false, currentUserId),
            RankTrips(speedTrips.Select(item => (item.Trip, item.Speed)), descending: true, currentUserId));

        var stationCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var routeCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var trainCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var rollingStockCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var companyCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        foreach (var trip in trips)
        {
            if (trip.Trip.DepartureTime is not null)
                Increment(stationCounts, trip.Trip.FromStation.Trim());
            if (trip.Trip.ArrivalTime is not null)
                Increment(stationCounts, trip.Trip.ToStation.Trim());
            foreach (var route in trip.RouteNames.Distinct(StringComparer.OrdinalIgnoreCase))
                Increment(routeCounts, route);
            Increment(trainCounts, trip.Trip.TrainNumber.Trim().ToUpperInvariant());
            foreach (var model in RollingStockModelCodes(trip.Trip.RollingStock))
                Increment(rollingStockCounts, model);
            Increment(companyCounts, trip.Trip.CompanyName?.Trim() ?? string.Empty);
        }
        var elementBoards = new ElementLeaderboards(
            RankElements(stationCounts), RankElements(routeCounts), RankElements(trainCounts),
            RankElements(rollingStockCounts), RankElements(companyCounts));
        return new StatisticsResponse(site, userBoards, tripBoards, elementBoards);
    }

    private static string StatisticsCacheKey(string userId) => $"statistics:{userId}";

    private async Task<IReadOnlyList<SyncTrip>> GetTripsAsync(SqliteConnection connection, string userId)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT Id, ClientId, CreatedAt, TrainNumber, TravelDate, RollingStock, CompanyName,
                   FromStation, ToStation, DepartureTime, ArrivalTime, MileageKm, ViaRoutes,
                   SeatType, SeatNumber, Price, Notes, IsRailTrip, UpdatedAt, DeletedAt
            FROM TripRecords WHERE UserId = $userId ORDER BY UpdatedAt;
            """;
        command.Parameters.AddWithValue("$userId", userId);
        await using var reader = await command.ExecuteReaderAsync();
        var trips = new List<SyncTrip>();
        while (await reader.ReadAsync())
        {
            trips.Add(new SyncTrip(
                reader.GetInt64(0), reader.GetString(1), FromDb(reader.GetString(2)), reader.GetString(3),
                FromDb(reader.GetString(4)), NullableString(reader, 5), NullableString(reader, 6),
                reader.GetString(7), reader.GetString(8), NullableDate(reader, 9), NullableDate(reader, 10),
                reader.GetDouble(11), reader.GetString(12), NullableString(reader, 13),
                NullableString(reader, 14), reader.GetDouble(15), NullableString(reader, 16),
                reader.GetInt32(17) == 1, FromDb(reader.GetString(18)), NullableDate(reader, 19)));
        }
        return trips;
    }

    private static void AddTripParameters(SqliteCommand command, string userId, SyncTrip trip)
    {
        command.Parameters.AddWithValue("$userId", userId);
        command.Parameters.AddWithValue("$clientId", trip.ClientId);
        command.Parameters.AddWithValue("$createdAt", ToDb(trip.CreatedAt));
        command.Parameters.AddWithValue("$trainNumber", trip.TrainNumber);
        command.Parameters.AddWithValue("$travelDate", ToDb(trip.TravelDate));
        command.Parameters.AddWithValue("$rollingStock", DbValue(trip.RollingStock));
        command.Parameters.AddWithValue("$companyName", DbValue(trip.CompanyName));
        command.Parameters.AddWithValue("$fromStation", trip.FromStation);
        command.Parameters.AddWithValue("$toStation", trip.ToStation);
        command.Parameters.AddWithValue("$departureTime", DbValue(trip.DepartureTime));
        command.Parameters.AddWithValue("$arrivalTime", DbValue(trip.ArrivalTime));
        command.Parameters.AddWithValue("$mileage", trip.MileageKm);
        command.Parameters.AddWithValue("$routes", trip.ViaRoutes);
        command.Parameters.AddWithValue("$seatType", DbValue(trip.SeatType));
        command.Parameters.AddWithValue("$seatNumber", DbValue(trip.SeatNumber));
        command.Parameters.AddWithValue("$price", trip.Price);
        command.Parameters.AddWithValue("$notes", DbValue(trip.Notes));
        command.Parameters.AddWithValue("$isRail", trip.IsRailTrip ? 1 : 0);
        command.Parameters.AddWithValue("$updatedAt", ToDb(trip.UpdatedAt));
        command.Parameters.AddWithValue("$deletedAt", DbValue(trip.DeletedAt));
    }

    private async Task<AuthResponse> CreateSessionAsync(SqliteConnection connection, UserProfile profile)
    {
        var token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48))
            .TrimEnd('=').Replace('+', '-').Replace('/', '_');
        var expiresAt = DateTime.Now.AddDays(30);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO AuthTokens (TokenHash, UserId, ExpiresAt) VALUES ($hash, $userId, $expiresAt);
            """;
        command.Parameters.AddWithValue("$hash", HashToken(token));
        command.Parameters.AddWithValue("$userId", profile.Id);
        command.Parameters.AddWithValue("$expiresAt", ToDb(expiresAt));
        await command.ExecuteNonQueryAsync();
        return new AuthResponse(token, expiresAt, profile);
    }

    private SqliteConnection OpenConnection() => new(_connectionString);
    private static bool IsValidEmail(string value) =>
        value.Length <= 254 && value.Contains('@') && !value.StartsWith('@') && !value.EndsWith('@');
    private static string HashToken(string token) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));
    private static string ToDb(DateTime value) => value.ToString("O");
    private static DateTime FromDb(string value) => DateTime.Parse(value);
    private static object DbValue(string? value) => string.IsNullOrWhiteSpace(value) ? DBNull.Value : value.Trim();
    private static object DbValue(DateTime? value) => value is null ? DBNull.Value : ToDb(value.Value);
    private static string? NullableString(SqliteDataReader reader, int ordinal) =>
        reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);
    private static DateTime? NullableDate(SqliteDataReader reader, int ordinal) =>
        reader.IsDBNull(ordinal) ? null : FromDb(reader.GetString(ordinal));

    private static DateTime ChinaTravelDay(StatisticsTrip trip) =>
        (trip.Trip.DepartureTime ?? trip.TravelDate).AddHours(8).Date;

    private static double? ValidDurationSeconds(PublicTrip trip)
    {
        if (trip.DepartureTime is null || trip.ArrivalTime is null ||
            trip.ArrivalTime <= trip.DepartureTime) return null;
        return (trip.ArrivalTime.Value - trip.DepartureTime.Value).TotalSeconds;
    }

    private static SitePeriodStatistics Summarize(IEnumerable<StatisticsTrip> trips)
    {
        var values = trips.ToList();
        return new SitePeriodStatistics(
            values.Count,
            values.Sum(item => item.Trip.MileageKm),
            values.Sum(item => ValidDurationSeconds(item.Trip) ?? 0),
            values.Sum(item => item.Trip.Price));
    }

    private static IReadOnlyList<UserRankingEntry> RankUsers(
        IEnumerable<(PublicUser User, double Value)> values, string currentUserId)
    {
        var ordered = values
            .OrderByDescending(item => item.Value)
            .ThenBy(item => item.User.DisplayName, StringComparer.Ordinal)
            .ThenBy(item => item.User.Id, StringComparer.Ordinal);
        var leaderboard = new List<UserRankingEntry>(LeaderboardSize + 1);
        UserRankingEntry? currentUser = null;
        var rank = 0;
        foreach (var item in ordered)
        {
            rank++;
            var entry = new UserRankingEntry(rank, item.User, item.Value);
            if (rank <= LeaderboardSize) leaderboard.Add(entry);
            if (item.User.Id == currentUserId) currentUser = entry;
            if (rank >= LeaderboardSize && currentUser is not null) break;
        }
        if (currentUser?.Rank > LeaderboardSize) leaderboard.Add(currentUser);
        return leaderboard;
    }

    private static async Task<IReadOnlyList<UserRankingEntry>> GetAchievementCountRankingAsync(
        SqliteConnection connection,
        string currentUserId)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT user.Id, user.DisplayName, user.AvatarUrl, user.Bio,
                   CASE WHEN user.ShowEmailOnProfile = 1 THEN user.Email END,
                   COUNT(achievement.AchievementId)
            FROM AspNetUsers user
            LEFT JOIN UserAchievements achievement ON achievement.UserId = user.Id
            GROUP BY user.Id;
            """;
        await using var reader = await command.ExecuteReaderAsync();
        var values = new List<(PublicUser User, double Value)>();
        while (await reader.ReadAsync())
        {
            var user = new PublicUser(
                reader.GetString(0), reader.GetString(1), NullableString(reader, 2),
                NullableString(reader, 3), NullableString(reader, 4));
            values.Add((user, reader.GetInt32(5)));
        }
        return RankUsers(values, currentUserId);
    }

    private static IReadOnlyList<TripRankingEntry> RankTrips(
        IEnumerable<(StatisticsTrip Trip, double Value)> values, bool descending,
        string currentUserId)
    {
        var ordered = descending
            ? values.OrderByDescending(item => item.Value)
            : values.OrderBy(item => item.Value);
        var leaderboard = new List<TripRankingEntry>(LeaderboardSize + 1);
        TripRankingEntry? currentTrip = null;
        var rank = 0;
        foreach (var item in ordered.ThenBy(item => item.Trip.Trip.TicketId))
        {
            rank++;
            if (rank <= LeaderboardSize ||
                (currentTrip is null && item.Trip.User.Id == currentUserId))
            {
                var entry = new TripRankingEntry(
                    rank, item.Trip.User, ToSummary(item.Trip.Trip), item.Value);
                if (rank <= LeaderboardSize) leaderboard.Add(entry);
                if (item.Trip.User.Id == currentUserId) currentTrip = entry;
            }
            if (rank >= LeaderboardSize && currentTrip is not null) break;
        }
        if (currentTrip?.Rank > LeaderboardSize) leaderboard.Add(currentTrip);
        return leaderboard;
    }

    private static PublicTripSummary ToSummary(PublicTrip trip) => new(
        trip.TicketId,
        trip.CreatedAt,
        trip.TrainNumber,
        trip.FromStation,
        trip.ToStation,
        trip.DepartureTime,
        trip.ArrivalTime,
        trip.MileageKm,
        trip.SeatType,
        trip.SeatNumber,
        trip.Price,
        trip.IsRailTrip);

    private static async Task<IReadOnlyList<PublicTrip>> GetAchievementTripsAsync(
        SqliteConnection connection,
        string userId,
        SqliteTransaction? transaction = null)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT Id, CreatedAt, TrainNumber, RollingStock, CompanyName,
                   FromStation, ToStation, DepartureTime, ArrivalTime, MileageKm,
                   ViaRoutes, SeatType, SeatNumber, Price, Notes, IsRailTrip
            FROM TripRecords
            WHERE UserId = $userId AND DeletedAt IS NULL AND IsRailTrip = 1
            ORDER BY DepartureTime, Id;
            """;
        command.Parameters.AddWithValue("$userId", userId);
        await using var reader = await command.ExecuteReaderAsync();
        var trips = new List<PublicTrip>();
        while (await reader.ReadAsync())
        {
            trips.Add(new PublicTrip(
                reader.GetInt64(0), FromDb(reader.GetString(1)), reader.GetString(2),
                NullableString(reader, 3), NullableString(reader, 4), reader.GetString(5),
                reader.GetString(6), NullableDate(reader, 7), NullableDate(reader, 8),
                reader.GetDouble(9), reader.GetString(10), NullableString(reader, 11),
                NullableString(reader, 12), reader.GetDouble(13), NullableString(reader, 14),
                reader.GetInt32(15) == 1));
        }
        return trips;
    }

    private static async Task RecalculateAchievementsAsync(
        SqliteConnection connection,
        string userId)
    {
        await using var transaction = (SqliteTransaction)await connection.BeginTransactionAsync();
        await RecalculateAchievementsAsync(connection, userId, transaction);
        await transaction.CommitAsync();
    }

    private static async Task RecalculateAchievementsAsync(
        SqliteConnection connection,
        string userId,
        SqliteTransaction transaction)
    {
        var trips = await GetAchievementTripsAsync(connection, userId, transaction);
        var unlocked = AchievementEngine.Evaluate(trips)
            .Where(item => item.TriggerTripId.HasValue)
            .ToList();

        await using (var delete = connection.CreateCommand())
        {
            delete.Transaction = transaction;
            delete.CommandText = "DELETE FROM UserAchievements WHERE UserId = $userId;";
            delete.Parameters.AddWithValue("$userId", userId);
            await delete.ExecuteNonQueryAsync();
        }

        foreach (var achievement in unlocked)
        {
            await using var insert = connection.CreateCommand();
            insert.Transaction = transaction;
            insert.CommandText = """
                INSERT INTO UserAchievements
                    (UserId, AchievementId, TriggerTripId, EvaluatedAt)
                VALUES ($userId, $achievementId, $triggerTripId, $evaluatedAt);
                """;
            insert.Parameters.AddWithValue("$userId", userId);
            insert.Parameters.AddWithValue("$achievementId", achievement.Id);
            insert.Parameters.AddWithValue("$triggerTripId", achievement.TriggerTripId!.Value);
            insert.Parameters.AddWithValue("$evaluatedAt", ToDb(DateTime.Now));
            await insert.ExecuteNonQueryAsync();
        }
    }

    private static async Task RecalculateAllAchievementsAsync(SqliteConnection connection)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT Id FROM AspNetUsers ORDER BY Id;";
        await using var reader = await command.ExecuteReaderAsync();
        var userIds = new List<string>();
        while (await reader.ReadAsync()) userIds.Add(reader.GetString(0));
        await reader.CloseAsync();
        foreach (var userId in userIds) await RecalculateAchievementsAsync(connection, userId);
    }

    private static async Task<AchievementsResponse> GetAchievementsAsync(
        SqliteConnection connection,
        string userId)
    {
        var triggers = new Dictionary<string, long>(StringComparer.Ordinal);
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = """
                SELECT AchievementId, TriggerTripId
                FROM UserAchievements WHERE UserId = $userId;
                """;
            command.Parameters.AddWithValue("$userId", userId);
            await using var reader = await command.ExecuteReaderAsync();
            while (await reader.ReadAsync()) triggers[reader.GetString(0)] = reader.GetInt64(1);
        }

        var counts = new Dictionary<string, int>(StringComparer.Ordinal);
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = """
                SELECT AchievementId, COUNT(*)
                FROM UserAchievements GROUP BY AchievementId;
                """;
            await using var reader = await command.ExecuteReaderAsync();
            while (await reader.ReadAsync()) counts[reader.GetString(0)] = reader.GetInt32(1);
        }

        int totalUsers;
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = "SELECT COUNT(*) FROM AspNetUsers;";
            totalUsers = Convert.ToInt32(await command.ExecuteScalarAsync());
        }

        var definitions = AchievementEngine.Evaluate(
            await GetAchievementTripsAsync(connection, userId));
        var items = definitions
            .Select((definition, index) => new
            {
                Definition = definition,
                Index = index,
                Trigger = triggers.GetValueOrDefault(definition.Id)
            })
            .OrderByDescending(item => item.Trigger != 0)
            .ThenBy(item => item.Index)
            .Select(item => new AchievementResponse(
                item.Definition.Id,
                item.Definition.Category,
                item.Definition.Icon,
                item.Definition.Title,
                item.Definition.Description,
                item.Trigger == 0 ? "locked" : "unlocked",
                item.Trigger == 0 ? null : item.Trigger,
                counts.GetValueOrDefault(item.Definition.Id),
                item.Definition.Progress?.Current,
                item.Definition.Progress?.Target))
            .ToList();
        return new AchievementsResponse(totalUsers, items);
    }

    private static IReadOnlyList<ElementRankingEntry> RankElements(
        IReadOnlyDictionary<string, int> counts) => counts
        .OrderByDescending(item => item.Value)
        .ThenBy(item => item.Key, StringComparer.Ordinal)
        .Take(LeaderboardSize)
        .Select((item, index) => new ElementRankingEntry(index + 1, item.Key, item.Value))
        .ToList();

    private static void Increment(IDictionary<string, int> counts, string name)
    {
        if (name.Length == 0) return;
        counts[name] = counts.TryGetValue(name, out var count) ? count + 1 : 1;
    }

    private static IReadOnlyList<string> RollingStockModelCodes(string? rawValue)
    {
        if (string.IsNullOrWhiteSpace(rawValue)) return [];
        return rawValue.Split('+', StringSplitOptions.RemoveEmptyEntries)
            .Select(component =>
            {
                var value = component.Trim();
                if (value.Length == 0) return string.Empty;
                var emu = Regex.Match(value, @"^(.+?)-\d{4}(?:&\d{4})*$",
                    RegexOptions.IgnoreCase);
                return (emu.Success ? emu.Groups[1].Value :
                    Regex.Split(value, @"\s+")[0]).Trim();
            })
            .Where(model => model.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private static IReadOnlyList<string> ParseRouteNames(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind != JsonValueKind.Array) return [];
            return document.RootElement.EnumerateArray()
                .Where(item => item.ValueKind == JsonValueKind.Object &&
                    item.TryGetProperty("routeName", out var name) &&
                    name.ValueKind == JsonValueKind.String)
                .Select(item => item.GetProperty("routeName").GetString()?.Trim() ?? string.Empty)
                .Where(name => name.Length > 0)
                .ToList();
        }
        catch (JsonException)
        {
            return [];
        }
    }

    private sealed record StatisticsTrip(
        PublicTrip Trip,
        PublicUser User,
        DateTime TravelDate,
        IReadOnlyList<string> RouteNames);
    private static UserProfile ReadProfile(SqliteDataReader reader) => new(
        reader.GetString(0),
        reader.IsDBNull(1) ? string.Empty : reader.GetString(1),
        reader.IsDBNull(2) ? "RailLog 用户" : reader.GetString(2),
        NullableString(reader, 3), NullableString(reader, 4), reader.GetInt32(5) == 1);

    private static async Task EnsureColumnAsync(
        SqliteConnection connection, string table, string column, string definition)
    {
        await using var check = connection.CreateCommand();
        check.CommandText = $"PRAGMA table_info(\"{table}\");";
        await using var reader = await check.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            if (string.Equals(reader.GetString(1), column, StringComparison.OrdinalIgnoreCase)) return;
        }
        await reader.CloseAsync();
        await ExecuteAsync(connection, $"ALTER TABLE \"{table}\" ADD COLUMN \"{column}\" {definition};");
    }

    private static async Task DropColumnIfExistsAsync(
        SqliteConnection connection, string table, string column)
    {
        await using var check = connection.CreateCommand();
        check.CommandText = $"PRAGMA table_info(\"{table}\");";
        await using var reader = await check.ExecuteReaderAsync();
        var exists = false;
        while (await reader.ReadAsync())
        {
            if (string.Equals(reader.GetString(1), column, StringComparison.OrdinalIgnoreCase))
            {
                exists = true;
                break;
            }
        }
        await reader.CloseAsync();
        if (exists)
            await ExecuteAsync(connection, $"ALTER TABLE \"{table}\" DROP COLUMN \"{column}\";");
    }

    private static async Task ExecuteAsync(SqliteConnection connection, string sql)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = sql;
        await command.ExecuteNonQueryAsync();
    }
}

public sealed record StoredVerificationCode(
    string Id,
    string CodeHash,
    DateTime ExpiresAt,
    int AttemptCount);
