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
    private const int HomeTravelGuideLimit = 12;
    private const int HomeTravelGuideHotLimit = 3;
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
            CREATE TABLE IF NOT EXISTS UserSyncState (
                UserId TEXT NOT NULL PRIMARY KEY,
                Version INTEGER NOT NULL DEFAULT 0,
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
                ServerUpdatedAt TEXT NULL,
                SyncVersion INTEGER NOT NULL DEFAULT 0,
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
                Experience INTEGER NOT NULL DEFAULT 0,
                EvaluatedAt TEXT NOT NULL,
                PRIMARY KEY (UserId, AchievementId),
                FOREIGN KEY (UserId) REFERENCES AspNetUsers (Id) ON DELETE CASCADE,
                FOREIGN KEY (TriggerTripId) REFERENCES TripRecords (Id) ON DELETE CASCADE
            );
            CREATE TABLE IF NOT EXISTS EntityReviews (
                Id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                EntityType TEXT NOT NULL,
                EntityKey TEXT NOT NULL,
                ReviewType TEXT NOT NULL,
                UserId TEXT NOT NULL,
                Rating INTEGER NOT NULL,
                Comment TEXT NOT NULL,
                TripId INTEGER NULL,
                SecondTripId INTEGER NULL,
                TransferMinutes INTEGER NULL,
                RouteFromStation TEXT NULL,
                RouteToStation TEXT NULL,
                Dish TEXT NULL,
                Price REAL NULL,
                CreatedAt TEXT NOT NULL,
                FOREIGN KEY (UserId) REFERENCES AspNetUsers (Id) ON DELETE CASCADE
            );
            CREATE TABLE IF NOT EXISTS EntityReviewReactions (
                ReviewId INTEGER NOT NULL,
                UserId TEXT NOT NULL,
                Emoji TEXT NOT NULL,
                CreatedAt TEXT NOT NULL,
                PRIMARY KEY (ReviewId, UserId),
                FOREIGN KEY (ReviewId) REFERENCES EntityReviews (Id) ON DELETE CASCADE,
                FOREIGN KEY (UserId) REFERENCES AspNetUsers (Id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS IX_EntityReviews_Entity ON EntityReviews(EntityType, EntityKey);
            CREATE INDEX IF NOT EXISTS IX_EntityReviews_UserId ON EntityReviews(UserId);
            CREATE INDEX IF NOT EXISTS IX_EntityReviews_TripId ON EntityReviews(TripId);
            CREATE INDEX IF NOT EXISTS IX_EntityReviews_SecondTripId ON EntityReviews(SecondTripId);
            CREATE INDEX IF NOT EXISTS IX_EntityReviewReactions_ReviewId ON EntityReviewReactions(ReviewId);
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
        await EnsureColumnAsync(connection, "TripRecords", "ServerUpdatedAt", "TEXT NULL");
        await EnsureColumnAsync(connection, "TripRecords", "SyncVersion", "INTEGER NOT NULL DEFAULT 0");
        await EnsureColumnAsync(connection, "EntityReviews", "SecondTripId", "INTEGER NULL");
        await EnsureColumnAsync(connection, "EntityReviews", "RouteFromStation", "TEXT NULL");
        await EnsureColumnAsync(connection, "EntityReviews", "RouteToStation", "TEXT NULL");
        await EnsureColumnAsync(connection, "UserAchievements", "Experience", "INTEGER NOT NULL DEFAULT 0");
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
            UPDATE TripRecords
            SET ServerUpdatedAt = '{ToDbUtc(DateTime.UtcNow)}'
            WHERE ServerUpdatedAt IS NULL OR ServerUpdatedAt = '';
            INSERT OR IGNORE INTO UserSyncState (UserId, Version)
            SELECT Id, 0 FROM AspNetUsers;
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
            CREATE INDEX IF NOT EXISTS IX_TripRecords_UserServerUpdatedAt
                ON TripRecords (UserId, ServerUpdatedAt);
            CREATE INDEX IF NOT EXISTS IX_TripRecords_UserSyncVersion
                ON TripRecords (UserId, SyncVersion);
            CREATE INDEX IF NOT EXISTS IX_TripRecords_UserPublicDashboard
                ON TripRecords (UserId, DeletedAt, DepartureTime DESC, Id DESC);
            CREATE INDEX IF NOT EXISTS IX_TicketPdfDownloads_ExpiresAt
                ON TicketPdfDownloads (ExpiresAt);
            CREATE INDEX IF NOT EXISTS IX_UserAchievements_AchievementId
                ON UserAchievements (AchievementId);
            """);
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

    public async Task<(IReadOnlyList<SyncTrip> Trips, long ServerVersion)> SyncTripsAsync(
        string userId,
        IReadOnlyList<SyncTrip> incoming,
        DateTime? since,
        long? sinceVersion,
        DateTime serverTime)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var transaction = await connection.BeginTransactionAsync();
        await using var upsert = connection.CreateCommand();
        upsert.Transaction = (SqliteTransaction)transaction;
        upsert.CommandText = """
            INSERT INTO TripRecords
                (UserId, ClientId, CreatedAt, TrainNumber, TravelDate, RollingStock,
                 CompanyName, FromStation, ToStation, DepartureTime, ArrivalTime,
                 MileageKm, ViaRoutes, SeatType, SeatNumber, Price, Notes,
                 IsRailTrip, UpdatedAt, DeletedAt, ServerUpdatedAt, SyncVersion)
            VALUES
                ($userId, $clientId, $createdAt, $trainNumber, $travelDate,
                 $rollingStock, $companyName, $fromStation, $toStation,
                 $departureTime, $arrivalTime, $mileage, $routes, $seatType,
                 $seatNumber, $price, $notes, $isRail, $updatedAt, $deletedAt,
                 $serverUpdatedAt, $syncVersion)
            ON CONFLICT(UserId, ClientId) DO UPDATE SET
                CreatedAt=excluded.CreatedAt,
                TrainNumber=excluded.TrainNumber,
                TravelDate=excluded.TravelDate,
                RollingStock=excluded.RollingStock,
                CompanyName=excluded.CompanyName,
                FromStation=excluded.FromStation,
                ToStation=excluded.ToStation,
                DepartureTime=excluded.DepartureTime,
                ArrivalTime=excluded.ArrivalTime,
                MileageKm=excluded.MileageKm,
                ViaRoutes=excluded.ViaRoutes,
                SeatType=excluded.SeatType,
                SeatNumber=excluded.SeatNumber,
                Price=excluded.Price,
                Notes=excluded.Notes,
                IsRailTrip=excluded.IsRailTrip,
                UpdatedAt=excluded.UpdatedAt,
                DeletedAt=excluded.DeletedAt,
                ServerUpdatedAt=excluded.ServerUpdatedAt,
                SyncVersion=excluded.SyncVersion
            WHERE julianday(excluded.UpdatedAt) > julianday(TripRecords.UpdatedAt);
            """;
        AddTripParameters(upsert);
        upsert.Parameters.Add("$serverUpdatedAt", SqliteType.Text);
        upsert.Parameters.Add("$syncVersion", SqliteType.Integer);

        await using var touch = connection.CreateCommand();
        touch.Transaction = (SqliteTransaction)transaction;
        touch.CommandText = """
            UPDATE TripRecords
            SET ServerUpdatedAt = $serverUpdatedAt, SyncVersion = $syncVersion
            WHERE UserId = $userId AND ClientId = $clientId
              AND julianday(UpdatedAt) > julianday($updatedAt);
            """;
        touch.Parameters.Add("$userId", SqliteType.Text);
        touch.Parameters.Add("$clientId", SqliteType.Text);
        touch.Parameters.Add("$serverUpdatedAt", SqliteType.Text);
        touch.Parameters.Add("$syncVersion", SqliteType.Integer);
        touch.Parameters.Add("$updatedAt", SqliteType.Text);

        var validIncoming = incoming
            .Where(trip =>
                !string.IsNullOrWhiteSpace(trip.ClientId) &&
                trip.ClientId.Length <= 100)
            .ToList();
        var serverVersion = validIncoming.Count == 0
            ? await GetSyncVersionAsync(connection, userId, (SqliteTransaction)transaction)
            : await AllocateSyncVersionAsync(connection, userId, (SqliteTransaction)transaction);
        var hasChanges = false;
        foreach (var trip in validIncoming)
        {
            SetTripParameters(upsert, userId, trip, serverTime, serverVersion);
            var changed = await upsert.ExecuteNonQueryAsync() > 0;
            hasChanges |= changed;
            if (changed) continue;

            touch.Parameters["$userId"].Value = userId;
            touch.Parameters["$clientId"].Value = trip.ClientId;
            touch.Parameters["$serverUpdatedAt"].Value = ToDbUtc(serverTime);
            touch.Parameters["$syncVersion"].Value = serverVersion;
            touch.Parameters["$updatedAt"].Value = ToDb(trip.UpdatedAt);
            await touch.ExecuteNonQueryAsync();
        }
        if (hasChanges)
        {
            await RecalculateAchievementsAsync(
                connection, userId, (SqliteTransaction)transaction);
        }
        await transaction.CommitAsync();
        var trips = await GetTripsAsync(
            connection,
            userId,
            since,
            sinceVersion,
            serverTime,
            serverVersion);
        return (trips, serverVersion);
    }

    public async Task<IReadOnlyList<EntityReviewResponse>> GetEntityReviewsAsync(
        string type,
        string key,
        string? currentUserId = null)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT r.Id,r.EntityType,r.EntityKey,r.ReviewType,r.UserId,
                   u.DisplayName,u.AvatarUrl,r.Rating,r.Comment,r.TripId,
                   r.SecondTripId,r.TransferMinutes,r.RouteFromStation,
                   r.RouteToStation,r.Dish,r.Price,r.CreatedAt,
                   trip.Id,trip.CreatedAt,trip.TrainNumber,trip.RollingStock,
                   trip.CompanyName,trip.FromStation,trip.ToStation,
                   trip.DepartureTime,trip.ArrivalTime,trip.MileageKm,
                   trip.ViaRoutes,trip.SeatType,trip.SeatNumber,trip.Price,
                   trip.Notes,trip.IsRailTrip,
                   secondTrip.Id,secondTrip.CreatedAt,secondTrip.TrainNumber,
                   secondTrip.RollingStock,secondTrip.CompanyName,
                   secondTrip.FromStation,secondTrip.ToStation,
                   secondTrip.DepartureTime,secondTrip.ArrivalTime,
                   secondTrip.MileageKm,secondTrip.ViaRoutes,
                   secondTrip.SeatType,secondTrip.SeatNumber,secondTrip.Price,
                   secondTrip.Notes,secondTrip.IsRailTrip,
                   COALESCE((
                       SELECT SUM(achievement.Experience)
                       FROM UserAchievements achievement
                       WHERE achievement.UserId=r.UserId
                   ), 0)
            FROM EntityReviews r
            JOIN AspNetUsers u ON u.Id=r.UserId
            LEFT JOIN TripRecords trip ON trip.Id=r.TripId
                AND trip.UserId=r.UserId AND trip.DeletedAt IS NULL
            LEFT JOIN TripRecords secondTrip ON secondTrip.Id=r.SecondTripId
                AND secondTrip.UserId=r.UserId AND secondTrip.DeletedAt IS NULL
            WHERE r.EntityType=$type AND r.EntityKey=$key
            ORDER BY r.CreatedAt DESC;
            """;
        command.Parameters.AddWithValue("$type", type);
        command.Parameters.AddWithValue("$key", key);
        var result = new List<EntityReviewResponse>();
        await using (var reader = await command.ExecuteReaderAsync())
        {
            while (await reader.ReadAsync())
                result.Add(new EntityReviewResponse(
                    reader.GetInt64(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    reader.GetString(5),
                    NullableString(reader, 6),
                    reader.GetInt32(7),
                    reader.GetString(8),
                    reader.IsDBNull(9) ? null : reader.GetInt64(9),
                    reader.IsDBNull(10) ? null : reader.GetInt64(10),
                    reader.IsDBNull(11) ? null : reader.GetInt32(11),
                    NullableString(reader, 12),
                    NullableString(reader, 13),
                    NullableString(reader, 14),
                    reader.IsDBNull(15) ? null : Convert.ToDecimal(reader.GetValue(15)),
                    DateTime.Parse(reader.GetString(16)),
                    ReadPublicTrip(reader, 17),
                    ReadPublicTrip(reader, 33),
                    [],
                    Convert.ToInt32(reader.GetInt64(49))));
        }
        var reactions = await GetEntityReviewReactionSummariesAsync(
            connection,
            type,
            key,
            currentUserId);
        return result
            .Select(review => review with
            {
                Reactions = reactions.GetValueOrDefault(review.Id, []),
            })
            .ToList();
    }

    public async Task<IReadOnlyList<EntityReviewResponse>> GetTripReviewsAsync(
        long ticketId,
        string? currentUserId = null)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT r.Id,r.EntityType,r.EntityKey,r.ReviewType,r.UserId,
                   u.DisplayName,u.AvatarUrl,r.Rating,r.Comment,r.TripId,
                   r.SecondTripId,r.TransferMinutes,r.RouteFromStation,
                   r.RouteToStation,r.Dish,r.Price,r.CreatedAt,
                   trip.Id,trip.CreatedAt,trip.TrainNumber,trip.RollingStock,
                   trip.CompanyName,trip.FromStation,trip.ToStation,
                   trip.DepartureTime,trip.ArrivalTime,trip.MileageKm,
                   trip.ViaRoutes,trip.SeatType,trip.SeatNumber,trip.Price,
                   trip.Notes,trip.IsRailTrip,
                   secondTrip.Id,secondTrip.CreatedAt,secondTrip.TrainNumber,
                   secondTrip.RollingStock,secondTrip.CompanyName,
                   secondTrip.FromStation,secondTrip.ToStation,
                   secondTrip.DepartureTime,secondTrip.ArrivalTime,
                   secondTrip.MileageKm,secondTrip.ViaRoutes,
                   secondTrip.SeatType,secondTrip.SeatNumber,secondTrip.Price,
                   secondTrip.Notes,secondTrip.IsRailTrip,
                   COALESCE((
                       SELECT SUM(achievement.Experience)
                       FROM UserAchievements achievement
                       WHERE achievement.UserId=r.UserId
                   ), 0)
            FROM TripRecords reviewedTrip
            JOIN EntityReviews r
                ON r.UserId=reviewedTrip.UserId
               AND (r.TripId=reviewedTrip.Id OR r.SecondTripId=reviewedTrip.Id)
            JOIN AspNetUsers u ON u.Id=r.UserId
            LEFT JOIN TripRecords trip ON trip.Id=r.TripId
                AND trip.UserId=r.UserId AND trip.DeletedAt IS NULL
            LEFT JOIN TripRecords secondTrip ON secondTrip.Id=r.SecondTripId
                AND secondTrip.UserId=r.UserId AND secondTrip.DeletedAt IS NULL
            WHERE reviewedTrip.Id=$ticketId
              AND reviewedTrip.DeletedAt IS NULL
              AND reviewedTrip.IsRailTrip=1
            ORDER BY r.CreatedAt DESC;
            """;
        command.Parameters.AddWithValue("$ticketId", ticketId);
        var result = new List<EntityReviewResponse>();
        await using (var reader = await command.ExecuteReaderAsync())
        {
            while (await reader.ReadAsync())
                result.Add(new EntityReviewResponse(
                    reader.GetInt64(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    reader.GetString(5),
                    NullableString(reader, 6),
                    reader.GetInt32(7),
                    reader.GetString(8),
                    reader.IsDBNull(9) ? null : reader.GetInt64(9),
                    reader.IsDBNull(10) ? null : reader.GetInt64(10),
                    reader.IsDBNull(11) ? null : reader.GetInt32(11),
                    NullableString(reader, 12),
                    NullableString(reader, 13),
                    NullableString(reader, 14),
                    reader.IsDBNull(15) ? null : Convert.ToDecimal(reader.GetValue(15)),
                    DateTime.Parse(reader.GetString(16)),
                    ReadPublicTrip(reader, 17),
                    ReadPublicTrip(reader, 33),
                    [],
                    Convert.ToInt32(reader.GetInt64(49))));
        }
        var reactions = await GetTripReviewReactionSummariesAsync(
            connection,
            ticketId,
            currentUserId);
        return result
            .Select(review => review with
            {
                Reactions = reactions.GetValueOrDefault(review.Id, []),
            })
            .ToList();
    }

    public async Task<IReadOnlyList<EntityReviewResponse>?> GetTravelGuideReviewsAsync(
        long ticketId,
        string currentUserId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();

        await using var tripCommand = connection.CreateCommand();
        tripCommand.CommandText = """
            SELECT TrainNumber, RollingStock, CompanyName, FromStation,
                   ToStation, ViaRoutes
            FROM TripRecords
            WHERE Id=$ticketId AND UserId=$userId
              AND DeletedAt IS NULL AND IsRailTrip=1;
            """;
        tripCommand.Parameters.AddWithValue("$ticketId", ticketId);
        tripCommand.Parameters.AddWithValue("$userId", currentUserId);
        string trainNumber;
        string rollingStock;
        string companyName;
        string fromStation;
        string toStation;
        IReadOnlyList<TripRouteSegment> targetRouteSegments;
        await using (var reader = await tripCommand.ExecuteReaderAsync())
        {
            if (!await reader.ReadAsync()) return null;
            trainNumber = reader.GetString(0).Trim();
            rollingStock = NullableString(reader, 1)?.Trim() ?? string.Empty;
            companyName = NullableString(reader, 2)?.Trim() ?? string.Empty;
            fromStation = reader.GetString(3).Trim();
            toStation = reader.GetString(4).Trim();
            targetRouteSegments = ParseRouteSegments(reader.GetString(5));
        }

        var criteria = new List<(string Type, IReadOnlyList<string> Keys)>();
        AddReviewCriteria(criteria, "station", [fromStation, toStation]);
        AddReviewCriteria(criteria, "company", [companyName]);
        AddReviewCriteria(criteria, "train", [trainNumber]);
        AddReviewCriteria(
            criteria,
            "rollingStock",
            TrainModelParser.ParseTrainString(rollingStock)
                .Select(model => model.StatisticsCode));
        AddReviewCriteria(
            criteria,
            "route",
            targetRouteSegments.Select(segment => segment.RouteName));
        if (criteria.Count == 0) return [];

        await using var command = connection.CreateCommand();
        var clauses = new List<string>();
        var parameters = new List<(string Name, string Value)>();
        for (var criteriaIndex = 0; criteriaIndex < criteria.Count; criteriaIndex++)
        {
            var (type, keys) = criteria[criteriaIndex];
            var typeParameter = $"$type{criteriaIndex}";
            var valueParameters = new List<string>();
            for (var keyIndex = 0; keyIndex < keys.Count; keyIndex++)
            {
                var parameter = $"$key{criteriaIndex}_{keyIndex}";
                valueParameters.Add(parameter);
                parameters.Add((parameter, keys[keyIndex]));
            }
            clauses.Add(
                $"(lower(r.EntityType)={typeParameter} AND " +
                $"r.EntityKey COLLATE NOCASE IN ({string.Join(",", valueParameters)}))");
            command.Parameters.AddWithValue(typeParameter, type.ToLowerInvariant());
        }
        foreach (var (name, value) in parameters)
            command.Parameters.AddWithValue(name, value);
        command.Parameters.AddWithValue("$currentUserId", currentUserId);
        command.CommandText = $"""
            SELECT r.Id,r.EntityType,r.EntityKey,r.ReviewType,r.UserId,
                   u.DisplayName,u.AvatarUrl,r.Rating,r.Comment,r.TripId,
                   r.SecondTripId,r.TransferMinutes,r.RouteFromStation,
                   r.RouteToStation,r.Dish,r.Price,r.CreatedAt,
                   trip.Id,trip.CreatedAt,trip.TrainNumber,trip.RollingStock,
                   trip.CompanyName,trip.FromStation,trip.ToStation,
                   trip.DepartureTime,trip.ArrivalTime,trip.MileageKm,
                   trip.ViaRoutes,trip.SeatType,trip.SeatNumber,trip.Price,
                   trip.Notes,trip.IsRailTrip,
                   secondTrip.Id,secondTrip.CreatedAt,secondTrip.TrainNumber,
                   secondTrip.RollingStock,secondTrip.CompanyName,
                   secondTrip.FromStation,secondTrip.ToStation,
                   secondTrip.DepartureTime,secondTrip.ArrivalTime,
                   secondTrip.MileageKm,secondTrip.ViaRoutes,
                   secondTrip.SeatType,secondTrip.SeatNumber,secondTrip.Price,
                   secondTrip.Notes,secondTrip.IsRailTrip,
                   COALESCE((
                       SELECT SUM(achievement.Experience)
                       FROM UserAchievements achievement
                       WHERE achievement.UserId=r.UserId
                   ), 0)
            FROM EntityReviews r
            JOIN AspNetUsers u ON u.Id=r.UserId
            LEFT JOIN TripRecords trip ON trip.Id=r.TripId
                AND trip.UserId=r.UserId AND trip.DeletedAt IS NULL
            LEFT JOIN TripRecords secondTrip ON secondTrip.Id=r.SecondTripId
                AND secondTrip.UserId=r.UserId AND secondTrip.DeletedAt IS NULL
            WHERE r.UserId <> $currentUserId
              AND ({string.Join(" OR ", clauses)})
            ORDER BY r.CreatedAt DESC, r.Id DESC;
            """;

        var candidates = new List<EntityReviewResponse>();
        await using (var reader = await command.ExecuteReaderAsync())
        {
            while (await reader.ReadAsync())
                candidates.Add(ReadEntityReview(reader));
        }

        var routeStations = GetRouteStationIndexes();
        var result = candidates
            .Where(review =>
                !review.EntityType.Equals("route", StringComparison.OrdinalIgnoreCase) ||
                IsRelevantRouteReview(review, targetRouteSegments, routeStations))
            .ToList();
        if (result.Count == 0) return result;

        var reactions = await GetReviewReactionSummariesAsync(
            connection,
            result.Select(review => review.Id).ToList(),
            currentUserId);
        return result
            .Select(review => review with
            {
                Reactions = reactions.GetValueOrDefault(review.Id, []),
            })
            .ToList();
    }

    public async Task<IReadOnlyList<EntityReviewResponse>> GetHomeTravelGuideReviewsAsync(
        string currentUserId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();

        var popular = await GetPopularEntityReviewsAsync(
            connection,
            currentUserId,
            HomeTravelGuideHotLimit);
        var result = popular.ToList();
        var includedIds = result.Select(review => review.Id).ToHashSet();
        if (result.Count >= HomeTravelGuideLimit) return result;

        await using var tripsCommand = connection.CreateCommand();
        tripsCommand.CommandText = """
            SELECT Id
            FROM TripRecords
            WHERE UserId=$userId AND DeletedAt IS NULL AND IsRailTrip=1
            ORDER BY COALESCE(DepartureTime, TravelDate) DESC, Id DESC;
            """;
        tripsCommand.Parameters.AddWithValue("$userId", currentUserId);
        var tripIds = new List<long>();
        await using (var reader = await tripsCommand.ExecuteReaderAsync())
        {
            while (await reader.ReadAsync())
                tripIds.Add(reader.GetInt64(0));
        }

        foreach (var ticketId in tripIds)
        {
            var related = await GetTravelGuideReviewsAsync(ticketId, currentUserId);
            if (related is null) continue;
            foreach (var review in related)
            {
                if (!includedIds.Add(review.Id)) continue;
                result.Add(review);
                if (result.Count >= HomeTravelGuideLimit) return result;
            }
        }
        return result;
    }

    private static async Task<IReadOnlyList<EntityReviewResponse>> GetPopularEntityReviewsAsync(
        SqliteConnection connection,
        string currentUserId,
        int limit)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT r.Id,r.EntityType,r.EntityKey,r.ReviewType,r.UserId,
                   u.DisplayName,u.AvatarUrl,r.Rating,r.Comment,r.TripId,
                   r.SecondTripId,r.TransferMinutes,r.RouteFromStation,
                   r.RouteToStation,r.Dish,r.Price,r.CreatedAt,
                   trip.Id,trip.CreatedAt,trip.TrainNumber,trip.RollingStock,
                   trip.CompanyName,trip.FromStation,trip.ToStation,
                   trip.DepartureTime,trip.ArrivalTime,trip.MileageKm,
                   trip.ViaRoutes,trip.SeatType,trip.SeatNumber,trip.Price,
                   trip.Notes,trip.IsRailTrip,
                   secondTrip.Id,secondTrip.CreatedAt,secondTrip.TrainNumber,
                   secondTrip.RollingStock,secondTrip.CompanyName,
                   secondTrip.FromStation,secondTrip.ToStation,
                   secondTrip.DepartureTime,secondTrip.ArrivalTime,
                   secondTrip.MileageKm,secondTrip.ViaRoutes,
                   secondTrip.SeatType,secondTrip.SeatNumber,secondTrip.Price,
                   secondTrip.Notes,secondTrip.IsRailTrip,
                   COALESCE((
                       SELECT SUM(achievement.Experience)
                       FROM UserAchievements achievement
                       WHERE achievement.UserId=r.UserId
                   ), 0)
            FROM EntityReviews r
            JOIN AspNetUsers u ON u.Id=r.UserId
            LEFT JOIN TripRecords trip ON trip.Id=r.TripId
                AND trip.UserId=r.UserId AND trip.DeletedAt IS NULL
            LEFT JOIN TripRecords secondTrip ON secondTrip.Id=r.SecondTripId
                AND secondTrip.UserId=r.UserId AND secondTrip.DeletedAt IS NULL
            WHERE r.UserId <> $currentUserId
            ORDER BY (
                SELECT COUNT(*)
                FROM EntityReviewReactions reaction
                WHERE reaction.ReviewId=r.Id
            ) DESC, r.CreatedAt DESC, r.Id DESC
            LIMIT $limit;
            """;
        command.Parameters.AddWithValue("$currentUserId", currentUserId);
        command.Parameters.AddWithValue("$limit", limit);
        var result = new List<EntityReviewResponse>();
        await using (var reader = await command.ExecuteReaderAsync())
        {
            while (await reader.ReadAsync())
                result.Add(ReadEntityReview(reader));
        }
        var reactions = await GetReviewReactionSummariesAsync(
            connection,
            result.Select(review => review.Id).ToList(),
            currentUserId);
        return result
            .Select(review => review with
            {
                Reactions = reactions.GetValueOrDefault(review.Id, []),
            })
            .ToList();
    }

    private static EntityReviewResponse ReadEntityReview(SqliteDataReader reader) => new(
        reader.GetInt64(0),
        reader.GetString(1),
        reader.GetString(2),
        reader.GetString(3),
        reader.GetString(4),
        reader.GetString(5),
        NullableString(reader, 6),
        reader.GetInt32(7),
        reader.GetString(8),
        reader.IsDBNull(9) ? null : reader.GetInt64(9),
        reader.IsDBNull(10) ? null : reader.GetInt64(10),
        reader.IsDBNull(11) ? null : reader.GetInt32(11),
        NullableString(reader, 12),
        NullableString(reader, 13),
        NullableString(reader, 14),
        reader.IsDBNull(15) ? null : Convert.ToDecimal(reader.GetValue(15)),
        DateTime.Parse(reader.GetString(16)),
        ReadPublicTrip(reader, 17),
        ReadPublicTrip(reader, 33),
        [],
        Convert.ToInt32(reader.GetInt64(49)));

    private static void AddReviewCriteria(
        ICollection<(string Type, IReadOnlyList<string> Keys)> criteria,
        string type,
        IEnumerable<string> source)
    {
        var keys = source
            .Select(value => value.Trim())
            .Where(value => value.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (keys.Count > 0) criteria.Add((type, keys));
    }

    private static async Task<Dictionary<long, IReadOnlyList<EntityReviewReactionSummary>>> GetReviewReactionSummariesAsync(
        SqliteConnection connection,
        IReadOnlyList<long> reviewIds,
        string currentUserId)
    {
        if (reviewIds.Count == 0)
            return new Dictionary<long, IReadOnlyList<EntityReviewReactionSummary>>();
        await using var command = connection.CreateCommand();
        var parameters = reviewIds
            .Select((_, index) => $"$review{index}")
            .ToList();
        command.CommandText = $"""
            SELECT reaction.ReviewId, reaction.Emoji, COUNT(*),
                   MAX(CASE WHEN reaction.UserId=$userId THEN 1 ELSE 0 END)
            FROM EntityReviewReactions reaction
            WHERE reaction.ReviewId IN ({string.Join(",", parameters)})
            GROUP BY reaction.ReviewId, reaction.Emoji
            ORDER BY reaction.ReviewId,
                     COUNT(*) DESC,
                     reaction.Emoji;
            """;
        for (var index = 0; index < reviewIds.Count; index++)
            command.Parameters.AddWithValue(parameters[index], reviewIds[index]);
        command.Parameters.AddWithValue("$userId", currentUserId);
        var grouped = new Dictionary<long, List<EntityReviewReactionSummary>>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            var reviewId = reader.GetInt64(0);
            if (!grouped.TryGetValue(reviewId, out var summaries))
            {
                summaries = [];
                grouped[reviewId] = summaries;
            }
            summaries.Add(new EntityReviewReactionSummary(
                reader.GetString(1),
                Convert.ToInt32(reader.GetInt64(2)),
                reader.GetInt64(3) == 1));
        }
        return grouped.ToDictionary(
            pair => pair.Key,
            pair => (IReadOnlyList<EntityReviewReactionSummary>)pair.Value);
    }

    private IReadOnlyDictionary<string, IReadOnlyDictionary<string, int>> GetRouteStationIndexes()
    {
        const string cacheKey = "route-station-indexes";
        if (_cache.TryGetValue(
            cacheKey,
            out IReadOnlyDictionary<string, IReadOnlyDictionary<string, int>>? cached))
            return cached!;

        var result = new Dictionary<string, Dictionary<string, int>>(StringComparer.Ordinal);
        var path = Path.Combine(AppContext.BaseDirectory, "Assets", "db", "routes.db");
        if (File.Exists(path))
        {
            using var connection = new SqliteConnection($"Data Source={path};Mode=ReadOnly");
            connection.Open();
            using var command = connection.CreateCommand();
            command.CommandText = """
                SELECT r.route_name, s.station_name, s.station_index
                FROM routes r
                JOIN stations s ON s.route_version_id=r.route_version_id;
                """;
            using var reader = command.ExecuteReader();
            while (reader.Read())
            {
                var routeName = NormalizeRouteName(reader.GetString(0));
                var stationName = NormalizeStation(reader.GetString(1));
                if (routeName.Length == 0 || stationName.Length == 0) continue;
                if (!result.TryGetValue(routeName, out var stations))
                    result[routeName] = stations = new Dictionary<string, int>(StringComparer.Ordinal);
                stations.TryAdd(stationName, reader.GetInt32(2));
            }
        }

        IReadOnlyDictionary<string, IReadOnlyDictionary<string, int>> value =
            result.ToDictionary(
                pair => pair.Key,
                pair => (IReadOnlyDictionary<string, int>)pair.Value,
                StringComparer.Ordinal);
        _cache.Set(cacheKey, value, TimeSpan.FromHours(12));
        return value;
    }

    private static bool IsRelevantRouteReview(
        EntityReviewResponse review,
        IReadOnlyList<TripRouteSegment> targetSegments,
        IReadOnlyDictionary<string, IReadOnlyDictionary<string, int>> routeStations)
    {
        foreach (var reviewSegment in ReviewRouteSegments(review))
        {
            foreach (var targetSegment in targetSegments)
            {
                if (RouteSegmentsOverlap(
                    targetSegment,
                    reviewSegment,
                    routeStations))
                    return true;
            }
        }
        return false;
    }

    private static IEnumerable<TripRouteSegment> ReviewRouteSegments(
        EntityReviewResponse review)
    {
        var routeName = review.EntityKey.Trim();
        if (review.RouteFromStation?.Trim() is { Length: > 0 } fromStation &&
            review.RouteToStation?.Trim() is { Length: > 0 } toStation)
        {
            yield return new TripRouteSegment(routeName, fromStation, toStation);
            yield break;
        }

        foreach (var trip in new[] { review.Trip, review.SecondTrip })
        {
            if (trip is null) continue;
            foreach (var segment in ParseRouteSegments(trip.ViaRoutes))
            {
                if (NormalizeRouteName(segment.RouteName) == NormalizeRouteName(routeName))
                    yield return segment;
            }
        }
    }

    private static bool RouteSegmentsOverlap(
        TripRouteSegment first,
        TripRouteSegment second,
        IReadOnlyDictionary<string, IReadOnlyDictionary<string, int>> routeStations)
    {
        var routeName = NormalizeRouteName(first.RouteName);
        if (routeName.Length == 0 ||
            routeName != NormalizeRouteName(second.RouteName))
            return false;

        if (routeStations.TryGetValue(routeName, out var stations) &&
            stations.TryGetValue(NormalizeStation(first.FromStation), out var firstFrom) &&
            stations.TryGetValue(NormalizeStation(first.ToStation), out var firstTo) &&
            stations.TryGetValue(NormalizeStation(second.FromStation), out var secondFrom) &&
            stations.TryGetValue(NormalizeStation(second.ToStation), out var secondTo))
        {
            var firstLow = Math.Min(firstFrom, firstTo);
            var firstHigh = Math.Max(firstFrom, firstTo);
            var secondLow = Math.Min(secondFrom, secondTo);
            var secondHigh = Math.Max(secondFrom, secondTo);
            return Math.Max(firstLow, secondLow) <= Math.Min(firstHigh, secondHigh);
        }

        var firstStations = new HashSet<string>(
            [NormalizeStation(first.FromStation), NormalizeStation(first.ToStation)],
            StringComparer.Ordinal);
        return firstStations.Contains(NormalizeStation(second.FromStation)) ||
            firstStations.Contains(NormalizeStation(second.ToStation));
    }

    private static async Task<Dictionary<long, IReadOnlyList<EntityReviewReactionSummary>>> GetEntityReviewReactionSummariesAsync(
        SqliteConnection connection,
        string type,
        string key,
        string? currentUserId)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT reaction.ReviewId, reaction.Emoji, COUNT(*),
                   MAX(CASE WHEN reaction.UserId=$userId THEN 1 ELSE 0 END)
            FROM EntityReviewReactions reaction
            JOIN EntityReviews review ON review.Id=reaction.ReviewId
            WHERE review.EntityType=$type AND review.EntityKey=$key
            GROUP BY reaction.ReviewId, reaction.Emoji
            ORDER BY reaction.ReviewId,
                     COUNT(*) DESC,
                     reaction.Emoji;
            """;
        command.Parameters.AddWithValue("$type", type);
        command.Parameters.AddWithValue("$key", key);
        command.Parameters.AddWithValue(
            "$userId",
            (object?)currentUserId ?? DBNull.Value);
        var grouped = new Dictionary<long, List<EntityReviewReactionSummary>>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            var reviewId = reader.GetInt64(0);
            if (!grouped.TryGetValue(reviewId, out var summaries))
            {
                summaries = [];
                grouped[reviewId] = summaries;
            }
            summaries.Add(new EntityReviewReactionSummary(
                reader.GetString(1),
                Convert.ToInt32(reader.GetInt64(2)),
                reader.GetInt64(3) == 1));
        }
        return grouped.ToDictionary(
            pair => pair.Key,
            pair => (IReadOnlyList<EntityReviewReactionSummary>)pair.Value);
    }

    private static async Task<Dictionary<long, IReadOnlyList<EntityReviewReactionSummary>>> GetTripReviewReactionSummariesAsync(
        SqliteConnection connection,
        long ticketId,
        string? currentUserId)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT reaction.ReviewId, reaction.Emoji, COUNT(*),
                   MAX(CASE WHEN reaction.UserId=$userId THEN 1 ELSE 0 END)
            FROM TripRecords reviewedTrip
            JOIN EntityReviews review
                ON review.UserId=reviewedTrip.UserId
               AND (review.TripId=reviewedTrip.Id OR review.SecondTripId=reviewedTrip.Id)
            JOIN EntityReviewReactions reaction ON reaction.ReviewId=review.Id
            WHERE reviewedTrip.Id=$ticketId
              AND reviewedTrip.DeletedAt IS NULL
              AND reviewedTrip.IsRailTrip=1
            GROUP BY reaction.ReviewId, reaction.Emoji
            ORDER BY reaction.ReviewId,
                     COUNT(*) DESC,
                     reaction.Emoji;
            """;
        command.Parameters.AddWithValue("$ticketId", ticketId);
        command.Parameters.AddWithValue(
            "$userId",
            (object?)currentUserId ?? DBNull.Value);
        var grouped = new Dictionary<long, List<EntityReviewReactionSummary>>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            var reviewId = reader.GetInt64(0);
            if (!grouped.TryGetValue(reviewId, out var summaries))
            {
                summaries = [];
                grouped[reviewId] = summaries;
            }
            summaries.Add(new EntityReviewReactionSummary(
                reader.GetString(1),
                Convert.ToInt32(reader.GetInt64(2)),
                reader.GetInt64(3) == 1));
        }
        return grouped.ToDictionary(
            pair => pair.Key,
            pair => (IReadOnlyList<EntityReviewReactionSummary>)pair.Value);
    }

    public async Task<bool> AreReviewTripsValidAsync(
        string userId,
        long? tripId,
        long? secondTripId)
    {
        if (tripId is null) return secondTripId is null;
        if (tripId == secondTripId) return false;

        await using var connection = OpenConnection();
        await connection.OpenAsync();
        if (!await OwnedTripExistsAsync(connection, userId, tripId.Value))
            return false;
        return secondTripId is null ||
            await OwnedTripExistsAsync(connection, userId, secondTripId.Value);
    }

    private static async Task<bool> OwnedTripExistsAsync(
        SqliteConnection connection,
        string userId,
        long tripId)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT COUNT(*)
            FROM TripRecords
            WHERE Id=$tripId AND UserId=$userId AND DeletedAt IS NULL;
            """;
        command.Parameters.AddWithValue("$tripId", tripId);
        command.Parameters.AddWithValue("$userId", userId);
        return Convert.ToInt64(await command.ExecuteScalarAsync()) > 0;
    }

    public async Task<long> GetEntityCountAsync(string type, string key)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT TrainNumber,RollingStock,CompanyName,FromStation,ToStation,ViaRoutes FROM TripRecords WHERE DeletedAt IS NULL AND IsRailTrip = 1";
        await using var reader = await command.ExecuteReaderAsync();
        var normalized = NormalizeEntity(key);
        long count = 0;
        while (await reader.ReadAsync())
        {
            var matches = type.ToLowerInvariant() switch
            {
                "train" => NormalizeEntity(reader.GetString(0)) == normalized,
                "rollingstock" => TrainModelParser
                    .ParseTrainString(reader.IsDBNull(1) ? "" : reader.GetString(1))
                    .Any(model => NormalizeEntity(model.StatisticsCode) == normalized),
                "company" => NormalizeEntity(reader.IsDBNull(2) ? "" : reader.GetString(2)) == normalized,
                "station" => NormalizeEntity(reader.GetString(3)) == normalized || NormalizeEntity(reader.GetString(4)) == normalized,
                "route" => reader.IsDBNull(5) ? false : reader.GetString(5).Contains(key, StringComparison.OrdinalIgnoreCase),
                _ => false,
            };
            if (matches) count++;
        }
        return count;
    }

    public async Task<IReadOnlyList<EntitySearchResult>> SearchEntitiesAsync(
        string type,
        string query,
        int limit)
    {
        var normalizedQuery = NormalizeEntity(query);
        if (normalizedQuery.Length == 0) return [];

        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT TrainNumber, RollingStock, CompanyName, FromStation, ToStation,
                   ViaRoutes
            FROM TripRecords
            WHERE DeletedAt IS NULL AND IsRailTrip = 1;
            """;

        var counts = new Dictionary<string, (string Name, long Count)>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            IEnumerable<string> matches = type switch
            {
                "train" => [reader.GetString(0)],
                "rollingstock" => TrainModelParser.ParseTrainString(NullableString(reader, 1))
                    .Select(model => model.StatisticsCode),
                "company" => reader.IsDBNull(2) ? [] : [reader.GetString(2)],
                "station" => [reader.GetString(3), reader.GetString(4)],
                "route" => reader.IsDBNull(5) ? [] : ParseRouteNames(reader.GetString(5)),
                _ => [],
            };

            foreach (var match in matches.Distinct(StringComparer.OrdinalIgnoreCase))
            {
                var normalized = NormalizeEntity(match);
                if (!normalized.Contains(normalizedQuery, StringComparison.Ordinal))
                    continue;
                if (counts.TryGetValue(normalized, out var current))
                    counts[normalized] = (current.Name, current.Count + 1);
                else
                    counts[normalized] = (match, 1);
            }
        }

        return counts.Values
            .OrderByDescending(item => NormalizeEntity(item.Name) == normalizedQuery)
            .ThenByDescending(item =>
                NormalizeEntity(item.Name).StartsWith(normalizedQuery, StringComparison.Ordinal))
            .ThenByDescending(item => item.Count)
            .ThenBy(item => item.Name, StringComparer.OrdinalIgnoreCase)
            .Take(limit)
            .Select(item => new EntitySearchResult(type, item.Name, item.Count))
            .ToList();
    }

    public async Task<IReadOnlyList<UserSearchResult>> SearchUsersAsync(
        string query,
        int limit)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT user.Id, user.DisplayName, user.AvatarUrl, user.Bio,
                   COUNT(trip.Id)
            FROM AspNetUsers user
            LEFT JOIN TripRecords trip
              ON trip.UserId = user.Id AND trip.DeletedAt IS NULL
            WHERE user.DisplayName COLLATE NOCASE LIKE $pattern ESCAPE '\'
               OR user.Id = $exactQuery
            GROUP BY user.Id, user.DisplayName, user.AvatarUrl, user.Bio
            ORDER BY CASE
                         WHEN user.Id = $exactQuery THEN 0
                         WHEN user.DisplayName = $exactQuery COLLATE NOCASE THEN 1
                         WHEN user.DisplayName COLLATE NOCASE LIKE $prefix ESCAPE '\' THEN 2
                         ELSE 3
                     END,
                     COUNT(trip.Id) DESC,
                     user.DisplayName COLLATE NOCASE
            LIMIT $limit;
            """;
        command.Parameters.AddWithValue("$pattern", LikePattern(query));
        command.Parameters.AddWithValue("$prefix", LikePrefix(query));
        command.Parameters.AddWithValue("$exactQuery", query);
        command.Parameters.AddWithValue("$limit", limit);

        var results = new List<UserSearchResult>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
            results.Add(new UserSearchResult(
                reader.GetString(0),
                reader.GetString(1),
                NullableString(reader, 2),
                NullableString(reader, 3),
                reader.GetInt64(4)));
        return results;
    }

    private static string NormalizeEntity(string value) => Regex.Replace(value.Trim().ToLowerInvariant(), "\\s+", "");

    private static string LikePattern(string value) => $"%{EscapeLike(value)}%";

    private static string LikePrefix(string value) => $"{EscapeLike(value)}%";

    private static string EscapeLike(string value) => value
        .Replace("\\", "\\\\", StringComparison.Ordinal)
        .Replace("%", "\\%", StringComparison.Ordinal)
        .Replace("_", "\\_", StringComparison.Ordinal);

    public async Task<EntityReviewResponse> AddEntityReviewAsync(string userId, CreateEntityReviewRequest request)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = "INSERT INTO EntityReviews(EntityType,EntityKey,ReviewType,UserId,Rating,Comment,TripId,SecondTripId,TransferMinutes,RouteFromStation,RouteToStation,Dish,Price,CreatedAt) VALUES($type,$key,$review,$user,$rating,$comment,$trip,$second,$minutes,$routeFrom,$routeTo,$dish,$price,$created); SELECT last_insert_rowid();";
        command.Parameters.AddWithValue("$type", request.EntityType); command.Parameters.AddWithValue("$key", request.EntityKey); command.Parameters.AddWithValue("$review", request.ReviewType); command.Parameters.AddWithValue("$user", userId); command.Parameters.AddWithValue("$rating", request.Rating); command.Parameters.AddWithValue("$comment", request.Comment); command.Parameters.AddWithValue("$trip", (object?)request.TripId ?? DBNull.Value); command.Parameters.AddWithValue("$second", (object?)request.SecondTripId ?? DBNull.Value); command.Parameters.AddWithValue("$minutes", (object?)request.TransferMinutes ?? DBNull.Value); command.Parameters.AddWithValue("$routeFrom", DbValue(request.RouteFromStation)); command.Parameters.AddWithValue("$routeTo", DbValue(request.RouteToStation)); command.Parameters.AddWithValue("$dish", (object?)request.Dish ?? DBNull.Value); command.Parameters.AddWithValue("$price", (object?)request.Price ?? DBNull.Value); command.Parameters.AddWithValue("$created", DateTime.UtcNow.ToString("O"));
        var id = Convert.ToInt64(await command.ExecuteScalarAsync());
        return (await GetEntityReviewsAsync(request.EntityType, request.EntityKey)).First(r => r.Id == id);
    }

    public async Task<bool> DeleteEntityReviewAsync(long id, string userId)
    {
        await using var connection = OpenConnection(); await connection.OpenAsync();
        await using var transaction = await connection.BeginTransactionAsync();
        await using var command = connection.CreateCommand();
        command.Transaction = (SqliteTransaction)transaction;
        command.CommandText = """
            DELETE FROM EntityReviewReactions
            WHERE ReviewId=$id
              AND EXISTS (
                  SELECT 1 FROM EntityReviews
                  WHERE Id=$id AND UserId=$user
              );
            DELETE FROM EntityReviews WHERE Id=$id AND UserId=$user;
            """;
        command.Parameters.AddWithValue("$id", id);
        command.Parameters.AddWithValue("$user", userId);
        var affected = await command.ExecuteNonQueryAsync();
        await transaction.CommitAsync();
        return affected > 0;
    }

    public async Task<bool> SetEntityReviewReactionAsync(
        long reviewId,
        string userId,
        string emoji)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var ownerCommand = connection.CreateCommand();
        ownerCommand.CommandText = "SELECT UserId FROM EntityReviews WHERE Id=$id;";
        ownerCommand.Parameters.AddWithValue("$id", reviewId);
        var ownerId = await ownerCommand.ExecuteScalarAsync() as string;
        if (ownerId is null || ownerId == userId) return false;

        await using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO EntityReviewReactions (ReviewId, UserId, Emoji, CreatedAt)
            VALUES ($reviewId, $userId, $emoji, $createdAt)
            ON CONFLICT (ReviewId, UserId) DO UPDATE SET
                Emoji=excluded.Emoji,
                CreatedAt=excluded.CreatedAt;
            """;
        command.Parameters.AddWithValue("$reviewId", reviewId);
        command.Parameters.AddWithValue("$userId", userId);
        command.Parameters.AddWithValue("$emoji", emoji);
        command.Parameters.AddWithValue("$createdAt", DateTime.UtcNow.ToString("O"));
        return await command.ExecuteNonQueryAsync() > 0;
    }

    public async Task<bool> RemoveEntityReviewReactionAsync(
        long reviewId,
        string userId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            DELETE FROM EntityReviewReactions
            WHERE ReviewId=$reviewId AND UserId=$userId;
            """;
        command.Parameters.AddWithValue("$reviewId", reviewId);
        command.Parameters.AddWithValue("$userId", userId);
        return await command.ExecuteNonQueryAsync() > 0;
    }

    public async Task<bool> UpdateEntityReviewAsync(long id, string userId, UpdateEntityReviewRequest request)
    {
        await using var connection = OpenConnection(); await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = "UPDATE EntityReviews SET Rating=$rating,Comment=$comment,TripId=$trip,SecondTripId=$second,TransferMinutes=$minutes,RouteFromStation=$routeFrom,RouteToStation=$routeTo,Dish=$dish,Price=$price WHERE Id=$id AND UserId=$user";
        command.Parameters.AddWithValue("$rating", request.Rating); command.Parameters.AddWithValue("$comment", request.Comment); command.Parameters.AddWithValue("$trip", (object?)request.TripId ?? DBNull.Value); command.Parameters.AddWithValue("$second", (object?)request.SecondTripId ?? DBNull.Value); command.Parameters.AddWithValue("$minutes", (object?)request.TransferMinutes ?? DBNull.Value); command.Parameters.AddWithValue("$routeFrom", DbValue(request.RouteFromStation)); command.Parameters.AddWithValue("$routeTo", DbValue(request.RouteToStation)); command.Parameters.AddWithValue("$dish", (object?)request.Dish ?? DBNull.Value); command.Parameters.AddWithValue("$price", (object?)request.Price ?? DBNull.Value); command.Parameters.AddWithValue("$id", id); command.Parameters.AddWithValue("$user", userId);
        return await command.ExecuteNonQueryAsync() > 0;
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
        if (AchievementEngine.IsHiddenAchievement(achievementId))
        {
            await using var unlockCommand = connection.CreateCommand();
            unlockCommand.CommandText = """
                SELECT 1
                FROM UserAchievements
                WHERE UserId = $userId AND AchievementId = $achievementId
                LIMIT 1;
                """;
            unlockCommand.Parameters.AddWithValue("$userId", currentUserId);
            unlockCommand.Parameters.AddWithValue("$achievementId", achievementId);
            if (await unlockCommand.ExecuteScalarAsync() is null)
                return new AchievementUnlockTripsResponse(achievementId, []);
        }
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

    private async Task<IReadOnlyList<IntersectionGroup>> GetIntersectionsAsync(string userId)
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
                   COALESCE((
                       SELECT SUM(achievement.Experience)
                       FROM UserAchievements achievement
                       WHERE achievement.UserId=user.Id
                   ), 0),
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
            NullableString(reader, 3), NullableString(reader, 4),
            Convert.ToInt32(reader.GetInt64(5)));
        var trip = new PublicTrip(
            reader.GetInt64(6), FromDb(reader.GetString(7)), reader.GetString(8),
            NullableString(reader, 9), NullableString(reader, 10), reader.GetString(11),
            reader.GetString(12), NullableDate(reader, 13), NullableDate(reader, 14),
            reader.GetDouble(15), reader.GetString(16), NullableString(reader, 17),
            NullableString(reader, 18), reader.GetDouble(19), NullableString(reader, 20),
            reader.GetInt32(21) == 1);
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
        var achievements = await GetAchievementsAsync(connection, userId, trips);
        user = user with
        {
            AchievementExperience = achievements.Achievements
                .Where(item => item.Status == "unlocked")
                .Sum(item => item.Experience),
        };
        var publicAchievements = new AchievementsResponse(
            achievements.TotalUserCount,
            achievements.Achievements
                .Where(item => !item.Hidden || item.Status != "unlocked")
                .ToList());
        return new PublicUserDashboardResponse(user, trips, publicAchievements);
    }

    public async Task<IReadOnlyList<IntersectionGroup>> GetEntityIntersectionsAsync(string userId, string type, string key)
    {
        var all = await GetIntersectionsAsync(userId);
        var normalized = NormalizeEntity(key);
        return all.Where(group =>
            (type.Equals("station", StringComparison.OrdinalIgnoreCase) && NormalizeEntity(group.Location) == normalized) ||
            (type.Equals("train", StringComparison.OrdinalIgnoreCase) && NormalizeEntity(group.Location) == normalized)
        ).ToList();
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
            await GetAchievementExperienceRankingAsync(connection, currentUserId));

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
            foreach (var model in TrainModelParser.ParseTrainString(trip.Trip.RollingStock)
                         .Select(model => model.StatisticsCode)
                         .Where(model => model.Length > 0)
                         .Distinct(StringComparer.OrdinalIgnoreCase))
                Increment(rollingStockCounts, model);
            Increment(companyCounts, trip.Trip.CompanyName?.Trim() ?? string.Empty);
        }
        var elementBoards = new ElementLeaderboards(
            RankElements(stationCounts), RankElements(routeCounts), RankElements(trainCounts),
            RankElements(rollingStockCounts), RankElements(companyCounts));
        return new StatisticsResponse(site, userBoards, tripBoards, elementBoards);
    }

    private static string StatisticsCacheKey(string userId) => $"statistics:{userId}";

    private async Task<IReadOnlyList<SyncTrip>> GetTripsAsync(
        SqliteConnection connection,
        string userId,
        DateTime? since,
        long? sinceVersion,
        DateTime serverTime,
        long serverVersion)
    {
        await using var command = connection.CreateCommand();
        var filter = sinceVersion is not null
            ? "AND SyncVersion > $sinceVersion AND SyncVersion <= $serverVersion"
            : since is not null
                ? "AND ServerUpdatedAt > $since AND ServerUpdatedAt <= $serverTime"
                : string.Empty;
        var orderBy = sinceVersion is not null
            ? "SyncVersion, Id"
            : since is not null
                ? "ServerUpdatedAt, Id"
                : "Id";
        command.CommandText = $"""
            SELECT Id, ClientId, CreatedAt, TrainNumber, TravelDate, RollingStock, CompanyName,
                   FromStation, ToStation, DepartureTime, ArrivalTime, MileageKm, ViaRoutes,
                   SeatType, SeatNumber, Price, Notes, IsRailTrip, UpdatedAt, DeletedAt
            FROM TripRecords
            WHERE UserId = $userId
              {filter}
            ORDER BY {orderBy};
            """;
        command.Parameters.AddWithValue("$userId", userId);
        command.Parameters.AddWithValue("$serverVersion", serverVersion);
        if (sinceVersion is not null)
        {
            command.Parameters.AddWithValue("$sinceVersion", sinceVersion.Value);
        }
        else if (since is not null)
        {
            command.Parameters.AddWithValue("$serverTime", ToDbUtc(serverTime));
            command.Parameters.AddWithValue("$since", ToDbUtc(since.Value));
        }
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

    private static void AddTripParameters(SqliteCommand command)
    {
        foreach (var name in new[]
                 {
                     "$userId", "$clientId", "$createdAt", "$trainNumber",
                     "$travelDate", "$rollingStock", "$companyName",
                     "$fromStation", "$toStation", "$departureTime",
                     "$arrivalTime", "$mileage", "$routes", "$seatType",
                     "$seatNumber", "$price", "$notes", "$isRail",
                     "$updatedAt", "$deletedAt",
                 })
        {
            command.Parameters.Add(name, SqliteType.Text);
        }
    }

    private static void SetTripParameters(
        SqliteCommand command,
        string userId,
        SyncTrip trip,
        DateTime serverTime,
        long serverVersion)
    {
        command.Parameters["$userId"].Value = userId;
        command.Parameters["$clientId"].Value = trip.ClientId;
        command.Parameters["$createdAt"].Value = ToDb(trip.CreatedAt);
        command.Parameters["$trainNumber"].Value = trip.TrainNumber;
        command.Parameters["$travelDate"].Value = ToDb(trip.TravelDate);
        command.Parameters["$rollingStock"].Value = DbValue(trip.RollingStock);
        command.Parameters["$companyName"].Value = DbValue(trip.CompanyName);
        command.Parameters["$fromStation"].Value = trip.FromStation;
        command.Parameters["$toStation"].Value = trip.ToStation;
        command.Parameters["$departureTime"].Value = DbValue(trip.DepartureTime);
        command.Parameters["$arrivalTime"].Value = DbValue(trip.ArrivalTime);
        command.Parameters["$mileage"].Value = trip.MileageKm;
        command.Parameters["$routes"].Value = trip.ViaRoutes;
        command.Parameters["$seatType"].Value = DbValue(trip.SeatType);
        command.Parameters["$seatNumber"].Value = DbValue(trip.SeatNumber);
        command.Parameters["$price"].Value = trip.Price;
        command.Parameters["$notes"].Value = DbValue(trip.Notes);
        command.Parameters["$isRail"].Value = trip.IsRailTrip ? 1 : 0;
        command.Parameters["$updatedAt"].Value = ToDb(trip.UpdatedAt);
        command.Parameters["$deletedAt"].Value = DbValue(trip.DeletedAt);
        command.Parameters["$serverUpdatedAt"].Value = ToDbUtc(serverTime);
        command.Parameters["$syncVersion"].Value = serverVersion;
    }

    private static async Task<long> GetSyncVersionAsync(
        SqliteConnection connection,
        string userId,
        SqliteTransaction transaction)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT COALESCE((
                SELECT Version FROM UserSyncState WHERE UserId = $userId
            ), 0);
            """;
        command.Parameters.AddWithValue("$userId", userId);
        return Convert.ToInt64(await command.ExecuteScalarAsync());
    }

    private static async Task<long> AllocateSyncVersionAsync(
        SqliteConnection connection,
        string userId,
        SqliteTransaction transaction)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            INSERT INTO UserSyncState (UserId, Version)
            VALUES ($userId, 1)
            ON CONFLICT(UserId) DO UPDATE SET Version = Version + 1
            RETURNING Version;
            """;
        command.Parameters.AddWithValue("$userId", userId);
        return Convert.ToInt64(await command.ExecuteScalarAsync());
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
    private static string ToDbUtc(DateTime value) =>
        value.ToUniversalTime().ToString(
            "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",
            System.Globalization.CultureInfo.InvariantCulture);
    private static DateTime FromDb(string value) => DateTime.Parse(value);
    private static object DbValue(string? value) => string.IsNullOrWhiteSpace(value) ? DBNull.Value : value.Trim();
    private static object DbValue(DateTime? value) => value is null ? DBNull.Value : ToDb(value.Value);
    private static string? NullableString(SqliteDataReader reader, int ordinal) =>
        reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);
    private static DateTime? NullableDate(SqliteDataReader reader, int ordinal) =>
        reader.IsDBNull(ordinal) ? null : FromDb(reader.GetString(ordinal));

    private static PublicTrip? ReadPublicTrip(SqliteDataReader reader, int offset)
    {
        if (reader.IsDBNull(offset)) return null;
        return new PublicTrip(
            reader.GetInt64(offset),
            FromDb(reader.GetString(offset + 1)),
            reader.GetString(offset + 2),
            NullableString(reader, offset + 3),
            NullableString(reader, offset + 4),
            reader.GetString(offset + 5),
            reader.GetString(offset + 6),
            NullableDate(reader, offset + 7),
            NullableDate(reader, offset + 8),
            reader.GetDouble(offset + 9),
            reader.GetString(offset + 10),
            NullableString(reader, offset + 11),
            NullableString(reader, offset + 12),
            reader.GetDouble(offset + 13),
            NullableString(reader, offset + 14),
            reader.GetInt32(offset + 15) == 1);
    }

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

    private static async Task<IReadOnlyList<UserRankingEntry>> GetAchievementExperienceRankingAsync(
        SqliteConnection connection,
        string currentUserId)
    {
        var regularIds = AchievementEngine.RegularAchievementIds.ToList();
        await using var command = connection.CreateCommand();
        var placeholders = string.Join(", ", regularIds.Select((_, index) => $"$achievement{index}"));
        command.CommandText = $"""
            SELECT user.Id, user.DisplayName, user.AvatarUrl, user.Bio,
                   CASE WHEN user.ShowEmailOnProfile = 1 THEN user.Email END,
                   COALESCE(SUM(achievement.Experience), 0)
            FROM AspNetUsers user
            LEFT JOIN UserAchievements achievement
              ON achievement.UserId = user.Id
             AND achievement.AchievementId IN ({placeholders})
            GROUP BY user.Id;
            """;
        for (var index = 0; index < regularIds.Count; index++)
            command.Parameters.AddWithValue($"$achievement{index}", regularIds[index]);
        await using var reader = await command.ExecuteReaderAsync();
        var values = new List<(PublicUser User, double Value)>();
        while (await reader.ReadAsync())
        {
            var user = new PublicUser(
                reader.GetString(0), reader.GetString(1), NullableString(reader, 2),
                NullableString(reader, 3), NullableString(reader, 4));
            values.Add((user, reader.GetInt64(5)));
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
        var reviews = await GetAchievementReviewsAsync(connection, userId, transaction);
        var totalReviewReactions = await GetAchievementReviewReactionCountAsync(
            connection,
            userId,
            transaction);
        var unlocked = new List<AchievementEvaluation>();
        var totalExperience = 0;
        for (var pass = 0; pass < 8; pass++)
        {
            var context = new AchievementContext(totalExperience, totalReviewReactions);
            unlocked = AchievementEngine.Evaluate(trips, reviews, context)
                .Where(item => item.TriggerTripId.HasValue)
                .ToList();
            totalExperience = unlocked.Sum(item => item.Experience);
        }

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
                    (UserId, AchievementId, TriggerTripId, Experience, EvaluatedAt)
                VALUES ($userId, $achievementId, $triggerTripId, $experience, $evaluatedAt);
                """;
            insert.Parameters.AddWithValue("$userId", userId);
            insert.Parameters.AddWithValue("$achievementId", achievement.Id);
            insert.Parameters.AddWithValue("$triggerTripId", achievement.TriggerTripId!.Value);
            insert.Parameters.AddWithValue("$experience", achievement.Experience);
            insert.Parameters.AddWithValue("$evaluatedAt", ToDb(DateTime.Now));
            await insert.ExecuteNonQueryAsync();
        }
    }

    public async Task RecalculateAllAchievementsAsync(
        CancellationToken cancellationToken = default)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync(cancellationToken);
        await ExecuteAsync(connection, "PRAGMA busy_timeout = 30000;");
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT Id FROM AspNetUsers ORDER BY Id;";
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var userIds = new List<string>();
        while (await reader.ReadAsync(cancellationToken)) userIds.Add(reader.GetString(0));
        await reader.CloseAsync();
        foreach (var userId in userIds)
        {
            cancellationToken.ThrowIfCancellationRequested();
            await RecalculateAchievementsAsync(connection, userId);
        }
    }

    private static async Task<AchievementsResponse> GetAchievementsAsync(
        SqliteConnection connection,
        string userId,
        IReadOnlyList<PublicTrip>? loadedTrips = null)
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

        var trips = loadedTrips is null
            ? await GetAchievementTripsAsync(connection, userId)
            : loadedTrips
                .Where(trip => trip.IsRailTrip)
                .OrderBy(trip => trip.DepartureTime)
                .ThenBy(trip => trip.TicketId)
                .ToList();
        var reviews = await GetAchievementReviewsAsync(connection, userId);
        var totalExperience = await GetAchievementExperienceAsync(connection, userId);
        var totalReviewReactions = await GetAchievementReviewReactionCountAsync(
            connection,
            userId);
        var definitions = AchievementEngine.Evaluate(
            trips,
            reviews,
            new AchievementContext(totalExperience, totalReviewReactions));
        var items = definitions
            .Select((definition, index) => new
            {
                Definition = definition,
                Index = index,
                Trigger = triggers.GetValueOrDefault(definition.Id)
            })
            .OrderByDescending(item => item.Trigger != 0)
            .ThenBy(item => item.Index)
            .Select(item =>
            {
                var unlocked = item.Trigger != 0;
                var hiddenLocked = item.Definition.Hidden && !unlocked;
                return new AchievementResponse(
                    item.Definition.Id,
                    item.Definition.Category,
                    hiddenLocked ? "help_outline" : item.Definition.Icon,
                    hiddenLocked ? "？？？" : item.Definition.Title,
                    hiddenLocked ? "隐藏成就，取得后显示" : item.Definition.Description,
                    unlocked ? "unlocked" : "locked",
                    unlocked ? item.Trigger : null,
                    item.Definition.Hidden ? 0 : counts.GetValueOrDefault(item.Definition.Id),
                    hiddenLocked ? null : item.Definition.Progress?.Current,
                    hiddenLocked ? null : item.Definition.Progress?.Target,
                    hiddenLocked ? 0 : item.Definition.Experience,
                    item.Definition.Hidden,
                    hiddenLocked ? null : item.Definition.Note,
                    hiddenLocked ? null : item.Definition.NarrativeNote);
            })
            .ToList();
        return new AchievementsResponse(totalUsers, items);
    }

    private static async Task<int> GetAchievementExperienceAsync(
        SqliteConnection connection,
        string userId,
        SqliteTransaction? transaction = null)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT COALESCE(SUM(Experience), 0)
            FROM UserAchievements
            WHERE UserId = $userId;
            """;
        command.Parameters.AddWithValue("$userId", userId);
        return Convert.ToInt32(await command.ExecuteScalarAsync());
    }

    private static async Task<int> GetAchievementReviewReactionCountAsync(
        SqliteConnection connection,
        string userId,
        SqliteTransaction? transaction = null)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT COUNT(*)
            FROM EntityReviewReactions reaction
            JOIN EntityReviews review ON review.Id = reaction.ReviewId
            WHERE review.UserId = $userId;
            """;
        command.Parameters.AddWithValue("$userId", userId);
        return Convert.ToInt32(await command.ExecuteScalarAsync());
    }

    private static async Task<IReadOnlyList<AchievementReview>> GetAchievementReviewsAsync(
        SqliteConnection connection,
        string userId,
        SqliteTransaction? transaction = null)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            SELECT EntityType, EntityKey
            FROM EntityReviews
            WHERE UserId = $userId;
            """;
        command.Parameters.AddWithValue("$userId", userId);
        var reviews = new List<AchievementReview>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
            reviews.Add(new AchievementReview(reader.GetString(0), reader.GetString(1)));
        return reviews;
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

    private static IReadOnlyList<string> ParseRouteNames(string json)
    {
        return ParseRouteSegments(json)
            .Select(segment => segment.RouteName)
            .ToList();
    }

    private static IReadOnlyList<TripRouteSegment> ParseRouteSegments(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind != JsonValueKind.Array) return [];
            return document.RootElement.EnumerateArray()
                .Where(item => item.ValueKind == JsonValueKind.Object &&
                    item.TryGetProperty("routeName", out var name) &&
                    name.ValueKind == JsonValueKind.String)
                .Select(item =>
                {
                    var routeName = item.GetProperty("routeName").GetString()?.Trim() ?? string.Empty;
                    var fromStation = item.TryGetProperty("fromStation", out var from) &&
                        from.ValueKind == JsonValueKind.String
                        ? from.GetString()?.Trim() ?? string.Empty
                        : string.Empty;
                    var toStation = item.TryGetProperty("toStation", out var to) &&
                        to.ValueKind == JsonValueKind.String
                        ? to.GetString()?.Trim() ?? string.Empty
                        : string.Empty;
                    return new TripRouteSegment(routeName, fromStation, toStation);
                })
                .Where(segment => segment.RouteName.Length > 0)
                .ToList();
        }
        catch (JsonException)
        {
            return [];
        }
    }

    private static string NormalizeRouteName(string value) =>
        Regex.Replace(
            value.Trim().ToLowerInvariant(),
            "(?:铁路|线)$",
            string.Empty);

    private static string NormalizeStation(string value) =>
        Regex.Replace(value.Trim().ToLowerInvariant(), "\\s+|站$", string.Empty);

    private sealed record TripRouteSegment(
        string RouteName,
        string FromStation,
        string ToStation);

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
