using Microsoft.Data.Sqlite;
using RailLog.API.Models;

namespace RailLog.API.Services;

public sealed partial class RailLogDatabase
{
    private static async Task AddNotificationAsync(
        SqliteConnection connection,
        SqliteTransaction? transaction,
        string userId,
        string type,
        string actorName,
        string message,
        long? tripId = null,
        long? reviewId = null,
        string? entityType = null,
        string? entityKey = null,
        string? actorUserId = null)
    {
        if (string.IsNullOrWhiteSpace(userId)) return;
        // 自己回应/提及自己时不打扰。
        if (actorUserId is not null && actorUserId == userId) return;

        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            INSERT INTO Notifications
                (UserId, Type, ActorUserId, ActorName, Message, TripId, ReviewId,
                 EntityType, EntityKey, CreatedAt)
            VALUES
                ($userId, $type, $actorUserId, $actorName, $message, $tripId,
                 $reviewId, $entityType, $entityKey, $createdAt);
            """;
        command.Parameters.AddWithValue("$userId", userId);
        command.Parameters.AddWithValue("$type", type);
        command.Parameters.AddWithValue("$actorUserId", DbValue(actorUserId));
        command.Parameters.AddWithValue("$actorName", actorName);
        command.Parameters.AddWithValue("$message", message);
        command.Parameters.AddWithValue("$tripId", (object?)tripId ?? DBNull.Value);
        command.Parameters.AddWithValue("$reviewId", (object?)reviewId ?? DBNull.Value);
        command.Parameters.AddWithValue("$entityType", DbValue(entityType));
        command.Parameters.AddWithValue("$entityKey", DbValue(entityKey));
        command.Parameters.AddWithValue("$createdAt", ToDbUtc(DateTime.UtcNow));
        await command.ExecuteNonQueryAsync();
    }

    private static async Task<string?> GetUserDisplayNameAsync(
        SqliteConnection connection,
        SqliteTransaction? transaction,
        string userId)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "SELECT DisplayName FROM AspNetUsers WHERE Id=$userId;";
        command.Parameters.AddWithValue("$userId", userId);
        return await command.ExecuteScalarAsync() as string;
    }

    /// <summary>评价正文里被 @ 的人，每人一条通知；作者自己 @ 自己不通知。</summary>
    private static async Task NotifyReviewMentionsAsync(
        SqliteConnection connection,
        SqliteTransaction? transaction,
        long reviewId,
        string authorUserId,
        string entityType,
        string entityKey,
        IReadOnlyList<string> mentionedUserIds)
    {
        if (mentionedUserIds.Count == 0) return;
        var authorName =
            await GetUserDisplayNameAsync(connection, transaction, authorUserId)
            ?? "某位用户";
        foreach (var mentionedUserId in mentionedUserIds)
        {
            await AddNotificationAsync(
                connection,
                transaction,
                mentionedUserId,
                "review_mention",
                authorName,
                $"{authorName} 在「{entityKey}」的评价中提到了你。",
                reviewId: reviewId,
                entityType: entityType,
                entityKey: entityKey,
                actorUserId: authorUserId);
        }
    }

    public async Task<NotificationPageResponse> GetNotificationsAsync(
        string userId,
        int offset,
        int limit)
    {
        offset = Math.Max(0, offset);
        limit = Math.Clamp(limit, 1, 50);
        await using var connection = OpenConnection();
        await connection.OpenAsync();

        long total;
        int unreadCount;
        await using (var count = connection.CreateCommand())
        {
            count.CommandText = """
                SELECT COUNT(*),
                       COALESCE(SUM(CASE WHEN ReadAt IS NULL THEN 1 ELSE 0 END), 0)
                FROM Notifications
                WHERE UserId=$userId;
                """;
            count.Parameters.AddWithValue("$userId", userId);
            await using var reader = await count.ExecuteReaderAsync();
            await reader.ReadAsync();
            total = reader.GetInt64(0);
            unreadCount = reader.GetInt32(1);
        }

        var items = new List<NotificationResponse>();
        await using (var command = connection.CreateCommand())
        {
            command.CommandText = """
                SELECT Id, Type, ActorName, Message, TripId, ReviewId, EntityType,
                       EntityKey, CreatedAt, ReadAt
                FROM Notifications
                WHERE UserId=$userId
                ORDER BY CreatedAt DESC, Id DESC
                LIMIT $limit OFFSET $offset;
                """;
            command.Parameters.AddWithValue("$userId", userId);
            command.Parameters.AddWithValue("$limit", limit);
            command.Parameters.AddWithValue("$offset", offset);
            await using var reader = await command.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                items.Add(new NotificationResponse(
                    reader.GetInt64(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetInt64(4),
                    reader.IsDBNull(5) ? null : reader.GetInt64(5),
                    NullableString(reader, 6),
                    NullableString(reader, 7),
                    ParseDbTimestamp(reader.GetString(8)),
                    reader.IsDBNull(9)
                        ? null
                        : ParseDbTimestamp(reader.GetString(9))));
            }
        }
        return new NotificationPageResponse(items, unreadCount, total);
    }

    public async Task<int> GetNotificationUnreadCountAsync(string userId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT COUNT(*) FROM Notifications
            WHERE UserId=$userId AND ReadAt IS NULL;
            """;
        command.Parameters.AddWithValue("$userId", userId);
        return Convert.ToInt32(await command.ExecuteScalarAsync());
    }

    /// <summary>传 null 或空数组表示全部标记已读。</summary>
    public async Task MarkNotificationsReadAsync(
        string userId,
        IReadOnlyList<long>? ids)
    {
        var now = ToDbUtc(DateTime.UtcNow);
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        var targets = (ids ?? [])
            .Where(id => id > 0)
            .Distinct()
            .Take(200)
            .ToList();
        if (targets.Count == 0)
        {
            command.CommandText = """
                UPDATE Notifications SET ReadAt=$now
                WHERE UserId=$userId AND ReadAt IS NULL;
                """;
        }
        else
        {
            var parameters = targets
                .Select((_, index) => $"$id{index}")
                .ToList();
            command.CommandText = $"""
                UPDATE Notifications SET ReadAt=$now
                WHERE UserId=$userId AND ReadAt IS NULL
                  AND Id IN ({string.Join(",", parameters)});
                """;
            for (var index = 0; index < targets.Count; index++)
                command.Parameters.AddWithValue(parameters[index], targets[index]);
        }
        command.Parameters.AddWithValue("$now", now);
        command.Parameters.AddWithValue("$userId", userId);
        await command.ExecuteNonQueryAsync();
    }
}
