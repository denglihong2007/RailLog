using System.Globalization;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Caching.Memory;
using RailLog.API.Models;

namespace RailLog.API.Services;

public sealed partial class RailLogDatabase
{
    // 「与我相关」的排序权重。类型权重只作温和的先验：车站、车次、担当
    // 单位略高于车型和线路。真正的区分度交给「实体覆盖率」——同一个 25G
    // 可能覆盖用户 10%～30% 的行程，而某个具体车站只覆盖 0.1%，覆盖率
    // 会把前者自然压低。本地数据中类型层面的中位覆盖率其实很接近
    // （车站 3.5%、单位 3.4%、车型 3.6%），因此不再按类型做 5 倍级压制。
    // 线路是覆盖率最高的类型（中位 6.3%），权重最低。
    private const double RelatedStationWeight = 1.00;
    private const double RelatedTrainWeight = 1.00;
    private const double RelatedCompanyWeight = 0.90;
    private const double RelatedRouteWeight = 0.55;
    private const double RelatedRollingStockWeight = 0.80;
    private const double RelatedUnknownWeight = 0.10;
    private const double RelatedSpecificityFactor = 5.0;
    private const int RelatedEntityHalfLifeDays = 365;
    private const int RelatedReviewHalfLifeDays = 90;

    // 多样性惩罚：同一实体、同一作者、同一类型每多出现一次，后续条目的
    // 分数就按这个比例下调。实体惩罚最重，作者次之，类型最轻。
    private const double RelatedEntityPenalty = 2.0;
    private const double RelatedAuthorPenalty = 0.6;
    private const double RelatedTypePenalty = 0.4;
    private const int RelatedCacheSeconds = 60;

    private sealed class RelatedReviewProfile
    {
        public int TripCount { get; set; }
        public Dictionary<(string Type, string Key), RelatedEntityUsage> Entities { get; } = new();
        public Dictionary<string, List<RelatedRouteSegment>> Routes { get; } =
            new(StringComparer.Ordinal);
    }

    private sealed record RelatedEntityUsage(int Uses, DateTime LastTripAt);

    private sealed record RelatedRouteSegment(TripRouteSegment Segment, DateTime LastTripAt);

    private sealed record RelatedReviewCandidate(EntityReviewResponse Review, double Score);

    /// <summary>
    /// 取「与我相关」的候选评价。画像实体一次查完，候选评价用临时表 join，
    /// 不再按行程逐条查询；结果按用户和库版本缓存几十秒。
    /// </summary>
    private async Task<IReadOnlyList<RelatedReviewCandidate>> GetRelatedReviewCandidatesAsync(
        SqliteConnection connection,
        string currentUserId)
    {
        var version = await GetRelatedCacheVersionAsync(connection, currentUserId);
        var cacheKey = $"travel-guide-related:{currentUserId}:{version}";
        if (_cache.TryGetValue(
            cacheKey,
            out List<RelatedReviewCandidate>? cached) && cached is not null)
        {
            return cached;
        }

        var profile = await BuildRelatedReviewProfileAsync(connection, currentUserId);
        if (profile.Entities.Count == 0) return [];

        await PopulateRelatedEntityTableAsync(connection, profile);
        var candidates = await QueryRelatedReviewCandidatesAsync(
            connection,
            currentUserId,
            profile);
        _cache.Set(cacheKey, candidates, TimeSpan.FromSeconds(RelatedCacheSeconds));
        return candidates;
    }

    /// <summary>
    /// 建立当前用户的实体画像：每个实体被多少条行程用过、最近一次是哪天。
    /// 线路另外保留所有区间段，用于复用现有的区间重叠判断。
    /// </summary>
    private async Task<RelatedReviewProfile> BuildRelatedReviewProfileAsync(
        SqliteConnection connection,
        string currentUserId)
    {
        var profile = new RelatedReviewProfile();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT TrainNumber, RollingStock, CompanyName, FromStation, ToStation,
                   ViaRoutes, COALESCE(DepartureTime, TravelDate)
            FROM TripRecords
            WHERE UserId=$userId AND DeletedAt IS NULL AND IsRailTrip=1;
            """;
        command.Parameters.AddWithValue("$userId", currentUserId);

        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            profile.TripCount++;
            var trainNumber = reader.GetString(0).Trim();
            var rollingStock = NullableString(reader, 1)?.Trim() ?? string.Empty;
            var companyName = NullableString(reader, 2)?.Trim() ?? string.Empty;
            var fromStation = reader.GetString(3).Trim();
            var toStation = reader.GetString(4).Trim();
            var viaRoutes = reader.GetString(5);
            var when = ParseDbTimestamp(reader.GetString(6));

            // 同一行程内同一实体只计一次，避免往返或同站始发终到把 uses 翻倍。
            var keys = new HashSet<(string Type, string Key)>();
            AddProfileEntity(keys, "station", fromStation);
            AddProfileEntity(keys, "station", toStation);
            AddProfileEntity(keys, "train", trainNumber);
            AddProfileEntity(keys, "company", companyName);
            foreach (var model in TrainModelParser.ParseTrainString(rollingStock))
                AddProfileEntity(keys, "rollingstock", model.StatisticsCode);
            foreach (var segment in ParseRouteSegments(viaRoutes))
            {
                AddProfileEntity(keys, "route", segment.RouteName);
                var routeName = NormalizeRouteName(segment.RouteName);
                if (routeName.Length == 0) continue;
                if (!profile.Routes.TryGetValue(routeName, out var segments))
                    profile.Routes[routeName] = segments = [];
                segments.Add(new RelatedRouteSegment(segment, when));
            }

            foreach (var key in keys)
            {
                if (profile.Entities.TryGetValue(key, out var usage))
                {
                    profile.Entities[key] = usage with
                    {
                        Uses = usage.Uses + 1,
                        LastTripAt = when > usage.LastTripAt ? when : usage.LastTripAt,
                    };
                }
                else
                {
                    profile.Entities[key] = new RelatedEntityUsage(1, when);
                }
            }
        }
        return profile;
    }

    private static void AddProfileEntity(
        HashSet<(string Type, string Key)> keys,
        string type,
        string key)
    {
        var normalized = key.Trim().ToLowerInvariant();
        if (normalized.Length > 0) keys.Add((type, normalized));
    }

    /// <summary>
    /// 把画像灌进临时表，供候选评价一次 join。参数按批次拆开，避免超过
    /// SQLite 的变量上限。
    /// </summary>
    private static async Task PopulateRelatedEntityTableAsync(
        SqliteConnection connection,
        RelatedReviewProfile profile)
    {
        await using (var create = connection.CreateCommand())
        {
            create.CommandText = """
                CREATE TEMP TABLE IF NOT EXISTS RelatedEntityProfile (
                    EntityType TEXT NOT NULL,
                    EntityKey TEXT NOT NULL COLLATE NOCASE,
                    Uses INTEGER NOT NULL,
                    LastTripAt TEXT NOT NULL,
                    PRIMARY KEY (EntityType, EntityKey)
                );
                DELETE FROM RelatedEntityProfile;
                """;
            await create.ExecuteNonQueryAsync();
        }

        var entries = profile.Entities.ToList();
        const int batchSize = 200;
        for (var start = 0; start < entries.Count; start += batchSize)
        {
            var count = Math.Min(batchSize, entries.Count - start);
            await using var insert = connection.CreateCommand();
            var values = new List<string>(count);
            for (var offset = 0; offset < count; offset++)
            {
                var index = start + offset;
                var ((type, key), usage) = entries[index];
                values.Add($"($type{index},$key{index},$uses{index},$last{index})");
                insert.Parameters.AddWithValue($"$type{index}", type);
                insert.Parameters.AddWithValue($"$key{index}", key);
                insert.Parameters.AddWithValue($"$uses{index}", usage.Uses);
                insert.Parameters.AddWithValue($"$last{index}", ToDbUtc(usage.LastTripAt));
            }
            insert.CommandText = $"""
                INSERT INTO RelatedEntityProfile (EntityType, EntityKey, Uses, LastTripAt)
                VALUES {string.Join(",", values)};
                """;
            await insert.ExecuteNonQueryAsync();
        }
    }

    private async Task<List<RelatedReviewCandidate>> QueryRelatedReviewCandidatesAsync(
        SqliteConnection connection,
        string currentUserId,
        RelatedReviewProfile profile)
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
                   ), 0),
                   e.Uses,e.LastTripAt
            FROM EntityReviews r
            JOIN AspNetUsers u ON u.Id=r.UserId
            JOIN RelatedEntityProfile e
                ON e.EntityType=lower(r.EntityType)
               AND e.EntityKey=r.EntityKey COLLATE NOCASE
            LEFT JOIN TripRecords trip ON trip.Id=r.TripId
                AND trip.UserId=r.UserId AND trip.DeletedAt IS NULL
            LEFT JOIN TripRecords secondTrip ON secondTrip.Id=r.SecondTripId
                AND secondTrip.UserId=r.UserId AND secondTrip.DeletedAt IS NULL
            WHERE r.UserId <> $currentUserId
            ORDER BY r.CreatedAt DESC, r.Id DESC;
            """;
        command.Parameters.AddWithValue("$currentUserId", currentUserId);

        var routeStations = GetRouteStationIndexes();
        var now = DateTime.UtcNow;
        var result = new List<RelatedReviewCandidate>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            var review = ReadEntityReview(reader);
            var uses = reader.GetInt32(50);
            var lastTripAt = ParseDbTimestamp(reader.GetString(51));
            if (review.EntityType.Equals("route", StringComparison.OrdinalIgnoreCase))
            {
                if (!TryGetRouteLastTrip(review, profile, routeStations, out var routeLastTripAt))
                    continue;
                lastTripAt = routeLastTripAt;
            }
            result.Add(new RelatedReviewCandidate(
                review,
                RelatedReviewScore(
                    review,
                    uses,
                    profile.TripCount,
                    lastTripAt,
                    now)));
        }
        return result;
    }

    /// <summary>
    /// 线路评价不能只看线路名：同一条线上只有区间重叠才算相关。返回我这些
    /// 重叠区间里最近一次乘坐的时间，供新鲜度打分。
    /// </summary>
    private static bool TryGetRouteLastTrip(
        EntityReviewResponse review,
        RelatedReviewProfile profile,
        IReadOnlyDictionary<string, IReadOnlyDictionary<string, int>> routeStations,
        out DateTime lastTripAt)
    {
        lastTripAt = default;
        if (!profile.Routes.TryGetValue(
                NormalizeRouteName(review.EntityKey),
                out var routeSegments))
        {
            return false;
        }

        var matched = false;
        foreach (var reviewSegment in ReviewRouteSegments(review))
        {
            foreach (var target in routeSegments)
            {
                if (!RouteSegmentsOverlap(target.Segment, reviewSegment, routeStations))
                    continue;
                if (!matched || target.LastTripAt > lastTripAt)
                    lastTripAt = target.LastTripAt;
                matched = true;
            }
        }
        return matched;
    }

    private static double RelatedReviewScore(
        EntityReviewResponse review,
        int uses,
        int tripCount,
        DateTime lastTripAt,
        DateTime now)
    {
        var typeWeight = review.EntityType.ToLowerInvariant() switch
        {
            "station" => RelatedStationWeight,
            "train" => RelatedTrainWeight,
            "company" => RelatedCompanyWeight,
            "route" => RelatedRouteWeight,
            "rollingstock" => RelatedRollingStockWeight,
            _ => RelatedUnknownWeight,
        };
        // 用「该实体覆盖了我多大比例的行程」衡量特异性，而不是原始使用
        // 次数：行程多的用户不会因为次数绝对值大而被整体压低。本地数据
        // 里 25G 的中位覆盖率约 12%，特异性约 0.62；25T/CR400BF 约 3%～
        // 4%，特异性约 0.84～0.86；只坐过一两次的车站/车次接近 1。
        var coverage = tripCount > 0 ? (double)uses / tripCount : 0.0;
        var specificity = 1.0 / (1.0 + RelatedSpecificityFactor * coverage);
        var entityAgeDays = Math.Max(0.0, (now - lastTripAt).TotalDays);
        var reviewAgeDays = Math.Max(
            0.0,
            (now - NormalizeUtc(review.CreatedAt)).TotalDays);
        var entityRecency = Math.Pow(
            0.5,
            entityAgeDays / RelatedEntityHalfLifeDays);
        var reviewFreshness = Math.Pow(
            0.5,
            reviewAgeDays / RelatedReviewHalfLifeDays);
        var relevance = specificity * entityRecency * reviewFreshness;
        // 类型权重给出基础量级，覆盖率与新鲜度在 50%～100% 内调整。
        return typeWeight * (0.5 + 0.5 * relevance);
    }

    /// <summary>
    /// 按分数从高到低贪心选取，每次对同实体、同作者、同类型的重复出现做
    /// 惩罚。只要前 <paramref name="take"/> 条，分页时前缀与整体排序一致。
    /// </summary>
    private static List<EntityReviewResponse> RankRelatedReviewCandidates(
        IReadOnlyList<RelatedReviewCandidate> candidates,
        int take)
    {
        var result = new List<EntityReviewResponse>(Math.Max(0, take));
        if (take <= 0 || candidates.Count == 0) return result;

        var remaining = candidates.ToList();
        var entityCounts = new Dictionary<(string Type, string Key), int>();
        var authorCounts = new Dictionary<string, int>(StringComparer.Ordinal);
        var typeCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

        while (remaining.Count > 0 && result.Count < take)
        {
            var bestIndex = 0;
            var bestValue = double.NegativeInfinity;
            for (var index = 0; index < remaining.Count; index++)
            {
                var candidate = remaining[index];
                var review = candidate.Review;
                var type = review.EntityType.ToLowerInvariant();
                var entityKey = (type, review.EntityKey.Trim().ToLowerInvariant());
                var penalty = 1.0
                    + RelatedEntityPenalty * GetCount(entityCounts, entityKey)
                    + RelatedAuthorPenalty * GetCount(authorCounts, review.UserId)
                    + RelatedTypePenalty * GetCount(typeCounts, type);
                var value = candidate.Score / penalty;
                if (value > bestValue)
                {
                    bestValue = value;
                    bestIndex = index;
                }
            }

            var chosen = remaining[bestIndex];
            remaining.RemoveAt(bestIndex);
            var chosenReview = chosen.Review;
            var chosenType = chosenReview.EntityType.ToLowerInvariant();
            var chosenKey = (chosenType, chosenReview.EntityKey.Trim().ToLowerInvariant());
            entityCounts[chosenKey] = GetCount(entityCounts, chosenKey) + 1;
            authorCounts[chosenReview.UserId] =
                GetCount(authorCounts, chosenReview.UserId) + 1;
            typeCounts[chosenType] = GetCount(typeCounts, chosenType) + 1;
            result.Add(chosenReview);
        }
        return result;
    }

    private static int GetCount<TKey>(
        IReadOnlyDictionary<TKey, int> counts,
        TKey key) where TKey : notnull =>
        counts.TryGetValue(key, out var count) ? count : 0;

    /// <summary>
    /// 缓存版本：全站评价数量/最大 Id 变化说明有新评价或删评；当前用户行程
    /// 数量/最后更新时间变化说明画像需要重建。
    /// </summary>
    private static async Task<string> GetRelatedCacheVersionAsync(
        SqliteConnection connection,
        string currentUserId)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT
                (SELECT COUNT(*) FROM EntityReviews),
                (SELECT COALESCE(MAX(Id), 0) FROM EntityReviews),
                (SELECT COUNT(*) FROM TripRecords
                 WHERE UserId=$userId AND DeletedAt IS NULL AND IsRailTrip=1),
                (SELECT COALESCE(MAX(UpdatedAt), '') FROM TripRecords
                 WHERE UserId=$userId AND DeletedAt IS NULL AND IsRailTrip=1);
            """;
        command.Parameters.AddWithValue("$userId", currentUserId);
        await using var reader = await command.ExecuteReaderAsync();
        await reader.ReadAsync();
        return string.Join(
            ":",
            reader.GetInt64(0),
            reader.GetInt64(1),
            reader.GetInt64(2),
            reader.GetString(3));
    }

    private static DateTime ParseDbTimestamp(string value) =>
        NormalizeUtc(DateTime.Parse(
            value,
            CultureInfo.InvariantCulture,
            DateTimeStyles.RoundtripKind));

    private static DateTime NormalizeUtc(DateTime value) => value.Kind switch
    {
        DateTimeKind.Utc => value,
        DateTimeKind.Local => value.ToUniversalTime(),
        _ => DateTime.SpecifyKind(value, DateTimeKind.Utc),
    };
}
