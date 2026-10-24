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

    /// <summary>前缀搜索里 <c>limit</c> 的上限，超出按这个算。</summary>
    private const int MaxSearchLimit = 500;

    /// <summary>单站车次查询的上限。最大的站实测约 1300 趟，留出余量。</summary>
    private const int MaxTrainsAtStation = 2000;

    /// <summary>
    /// 站站查询的上限。实测最大的两站组合也就几十趟，留到 500 是为了不静默漏车 ——
    /// 客户端要显示"共 N 趟"，截断了还报满数就是错的。
    /// </summary>
    public const int BetweenLimit = 500;

    /// <summary>
    /// 车次号前缀搜索。<paramref name="limit"/> 为 <c>null</c> 时不截断，与加入该参数
    /// 之前的行为一致 —— 老客户端不传它，静默改成只给 50 条会让它们的建议列表变样。
    /// </summary>
    public async Task<IReadOnlyList<TrainTimetableSearchItem>> SearchAsync(
        string trainNumberPrefix,
        string version,
        int? limit = null,
        CancellationToken cancellationToken = default)
    {
        var prefix = trainNumberPrefix.Trim().ToUpperInvariant();
        if (prefix.Length == 0) return [];

        await using var connection = await OpenVersionAsync(version, cancellationToken);
        if (connection is null) return [];

        await using var command = connection.CreateCommand();
        var table = Quote(TableName(version));
        var limitClause = limit.HasValue ? "\n    LIMIT @limit" : string.Empty;
        // 匹配按**单个号**（输入 D114 也要能搜到 D111/D114 这趟车），但结果按**号对**
        // 去重：同一趟车只出一行，匹配到的号排在展示号前面。同一个单号若挂在两个
        // 号对下（如 D8269 与 D8269/D8272 是两趟不同的车），两行都在，绝不合并。
        command.CommandText = $"""
    WITH matching_trains(code1, code2) AS (
        SELECT TrainCode1, TrainCode2 FROM {table}
        WHERE TrainCode1 LIKE @prefix || '%'
        UNION
        SELECT TrainCode1, TrainCode2 FROM {table}
        WHERE TrainCode2 LIKE @prefix || '%'
    )
    SELECT
        m.code1,
        m.code2,
        CASE WHEN m.code1 LIKE @prefix || '%' THEN m.code1 ELSE m.code2 END AS train_number,
        (
            SELECT t.TrainStation FROM {table} t
            WHERE t.TrainCode1 = m.code1 AND t.TrainCode2 = m.code2
            ORDER BY t.OrderID ASC, t.rowid ASC
            LIMIT 1
        ) AS departure_station,
        (
            SELECT t.TrainStation FROM {table} t
            WHERE t.TrainCode1 = m.code1 AND t.TrainCode2 = m.code2
            ORDER BY t.OrderID DESC, t.rowid DESC
            LIMIT 1
        ) AS arrival_station
    FROM matching_trains m
    WHERE (m.code1 IS NOT NULL AND m.code1 <> '')
       OR (m.code2 IS NOT NULL AND m.code2 <> '')
    ORDER BY train_number, m.code1, m.code2{limitClause}
    """;
        command.Parameters.AddWithValue("@prefix", prefix);
        if (limit.HasValue)
            command.Parameters.AddWithValue("@limit", Math.Clamp(limit.Value, 1, MaxSearchLimit));

        var result = new List<TrainTimetableSearchItem>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var matchedNumber = ReadString(reader, "train_number").ToUpperInvariant();
            if (matchedNumber.Length == 0) continue;
            var code1 = ReadString(reader, "code1");
            var code2 = ReadString(reader, "code2");
            // 每个号对一条结果；单号只属于一个号对时就是原来的展示号，
            // 同一个单号挂在多个号对下时靠 "/" 区分开。
            var displayCode = FormatMatchedTrainCodes(code1, code2, matchedNumber);
            result.Add(new TrainTimetableSearchItem(
                displayCode,
                ReadString(reader, "departure_station"),
                ReadString(reader, "arrival_station"),
                displayCode,
                FormatTrainCodes(code1, code2)));
        }
        return result;
    }

    /// <summary>
    /// 合并运行的车次展示号：<c>code2 == "" ? code1 : $"{code1}/{code2}"</c>。
    /// 两个号一样时也只写一个（脏数据里偶有 TrainCode2 复制了 TrainCode1）。
    /// </summary>
    private static string FormatTrainCodes(string code1, string code2)
    {
        var first = code1.Trim();
        var second = code2.Trim();
        if (first.Length == 0) return second;
        if (second.Length == 0 || string.Equals(second, first, StringComparison.OrdinalIgnoreCase))
            return first;
        return $"{first}/{second}";
    }

    /// <summary>
    /// 搜索结果里的展示号：把**匹配到的号排在前面**，另一个号跟在 "/" 后面。
    /// <para>
    /// 这样 <c>D8269</c> 与 <c>D8269/D8272</c> 在同一个搜索前缀下是两行不同的展示号，
    /// 客户端按展示号去重也不会把两趟车塌成一趟。单号（<c>code2</c> 为空）原样返回。
    /// </para>
    /// </summary>
    private static string FormatMatchedTrainCodes(string code1, string code2, string matched)
    {
        var first = code1.Trim();
        var second = code2.Trim();
        if (first.Length == 0) return second;
        if (second.Length == 0 || string.Equals(second, first, StringComparison.OrdinalIgnoreCase))
            return first;
        return string.Equals(matched.Trim(), first, StringComparison.OrdinalIgnoreCase)
            ? $"{first}/{second}"
            : $"{second}/{first}";
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

    /// <summary>
    /// 某一站停靠的全部车次，附上在该站的到发时刻。
    /// </summary>
    /// <remarks>
    /// 首末站一律按**完整号对** <c>(TrainCode1, TrainCode2)</c> 取：同一个单号若挂在
    /// 两个号对下就是两趟不同的车，按单号 <c>OR</c> 取首末站会把两趟的站序拼在一起
    /// （2017.04.20 的 <c>D8269</c> 与 <c>D8269/D8272</c>）。号对相等比较仍走
    /// <c>(TrainCode1, OrderID)</c> 索引，不会退化成全表扫描。
    /// <para>
    /// <b>合并运行的车只出一行</b>：D111+D114 是一趟车，两个号都在这站停，早先 UNION
    /// 两个号等于把同一趟车报成两趟；现在按「一行停站 = 一行结果」出，身份号用完整
    /// 号对 <c>D111/D114</c>。
    /// </para>
    /// <para>
    /// 但折返车在该站会名正言顺地出两行（三亚、武昌、合肥南这些站都有，2026.09.25
    /// 快照里查到十几组）：同一趟车去程和回程各停一次，到发时刻不同，<c>DISTINCT</c>
    /// 挡不掉也不该挡。同号多行是预期行为，客户端别拿车次号当行的唯一键。
    /// </para>
    /// </remarks>
    public async Task<IReadOnlyList<TrainTimetableAtStationItem>> GetTrainsAtStationAsync(
        string station,
        string version,
        CancellationToken cancellationToken = default)
    {
        var name = station.Trim();
        if (name.Length == 0) return [];

        await using var connection = await OpenVersionAsync(version, cancellationToken);
        if (connection is null) return [];

        var table = Quote(TableName(version));
        await using var command = connection.CreateCommand();
        command.CommandText = $"""
            WITH station_rows AS (
                SELECT TrainCode1 AS code1, TrainCode2 AS code2,
                       ArriveTime, StartTime
                FROM {table}
                WHERE trim(TrainStation) = @station
            ), hits AS (
                -- DISTINCT 只用来挡脏数据里完全重复的停站行（原来的 UNION 顺带
                -- 起了这个作用）；同一趟车在这站本来就只有一行。
                SELECT DISTINCT code1, code2, ArriveTime, StartTime
                FROM station_rows
                WHERE code1 <> '' OR code2 <> ''
            )
            SELECT
                h.code1,
                h.code2,
                -- 首末站按**完整号对**取：同一个单号若挂在两个号对下是两趟车，
                -- 按单号 OR 会把两趟的站序并在一起。
                (
                    SELECT trim(TrainStation) FROM {table}
                    WHERE TrainCode1 = h.code1 AND TrainCode2 = h.code2
                    ORDER BY OrderID, rowid LIMIT 1
                ) AS from_station,
                (
                    SELECT trim(TrainStation) FROM {table}
                    WHERE TrainCode1 = h.code1 AND TrainCode2 = h.code2
                    ORDER BY OrderID DESC, rowid DESC LIMIT 1
                ) AS to_station,
                h.ArriveTime,
                h.StartTime
            FROM hits h
            WHERE h.code1 <> '' OR h.code2 <> ''
            ORDER BY h.code1, h.code2
            LIMIT @limit
            """;
        command.Parameters.AddWithValue("@station", name);
        command.Parameters.AddWithValue("@limit", MaxTrainsAtStation);

        var result = new List<TrainTimetableAtStationItem>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var code1 = ReadString(reader, "code1");
            var code2 = ReadString(reader, "code2");
            var displayCode = FormatTrainCodes(code1, code2);
            if (displayCode.Length == 0) continue;
            result.Add(new TrainTimetableAtStationItem(
                displayCode,
                ReadString(reader, "from_station"),
                ReadString(reader, "to_station"),
                displayCode,
                ReadString(reader, "ArriveTime"),
                ReadString(reader, "StartTime"),
                displayCode));
        }
        return result;
    }

    /// <summary>
    /// 两站之间开行的车次，附在两站的开点/到点、区间里程，以及该车次自身的始发终到。
    /// <para>
    /// 这些字段都不能只查这两站：跨零点的天数、以及"里程要从上一站算起"都必须在
    /// <b>整条站序</b>上推。所以 SQL 只负责挑出该走的车次，把它们全部停站行取回来，
    /// 再在 C# 里按 <see cref="GetAsync"/> 同一套日序规则走一遍。
    /// </para>
    /// </summary>
    public async Task<IReadOnlyList<TrainTimetableBetweenItem>> SearchBetweenAsync(
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
        // 分组键是**号对** (code1, code2)，不是单个号：合并运行的 D111+D114 是一趟车，
        // 早先按单号展开会把同一趟车的每一站各出两行，站序被走成"两趟"，跨天推演跟着错。
        // 号对还有一个好处：万一同一个号出现在两个不同的对里，也不会把两趟车搅在一起。
        command.CommandText = $"""
            WITH train_stops AS (
                SELECT trim(TrainCode1) AS code1, trim(TrainCode2) AS code2,
                       OrderID, trim(TrainStation) AS station,
                       ArriveTime, StartTime, Mileage
                FROM {table}
                WHERE trim(TrainCode1) <> '' OR trim(TrainCode2) <> ''
            ), matching AS (
                SELECT code1, code2,
                       MIN(CASE WHEN station = @fromStation THEN OrderID END) AS from_order,
                       MIN(CASE WHEN station = @toStation THEN OrderID END) AS to_order
                FROM train_stops
                GROUP BY code1, code2
            ), selected AS (
                SELECT code1, code2, from_order, to_order
                FROM matching
                WHERE from_order IS NOT NULL AND to_order IS NOT NULL AND from_order < to_order
                ORDER BY code1, code2
                LIMIT @limit
            )
            SELECT s.code1, s.code2, s.OrderID, s.station, s.ArriveTime, s.StartTime, s.Mileage,
                   sel.from_order, sel.to_order
            FROM train_stops s
            JOIN selected sel ON sel.code1 = s.code1 AND sel.code2 = s.code2
            ORDER BY s.code1, s.code2, s.OrderID;
            """;
        command.Parameters.AddWithValue("@fromStation", from);
        command.Parameters.AddWithValue("@toStation", to);
        command.Parameters.AddWithValue("@limit", BetweenLimit);

        var result = new List<TrainTimetableBetweenItem>();
        var stops = new List<BetweenStopRow>();
        // 换组看的是号对。SQL 已按 (code1, code2) 排序，所以同一对的行走在一起。
        (string Code1, string Code2)? currentTrain = null;
        long fromOrder = 0;
        long toOrder = 0;
        var lastOrderId = long.MinValue;

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var code1 = ReadString(reader, "code1");
            var code2 = ReadString(reader, "code2");
            if (code1.Length == 0 && code2.Length == 0) continue;

            if (currentTrain is null ||
                !string.Equals(code1, currentTrain.Value.Code1, StringComparison.Ordinal) ||
                !string.Equals(code2, currentTrain.Value.Code2, StringComparison.Ordinal))
            {
                AddBetweenItem(result, currentTrain, from, to, fromOrder, toOrder, stops);
                currentTrain = (code1, code2);
                stops = [];
                lastOrderId = long.MinValue;
                fromOrder = reader.GetInt64(reader.GetOrdinal("from_order"));
                toOrder = reader.GetInt64(reader.GetOrdinal("to_order"));
            }

            var orderId = reader.GetInt64(reader.GetOrdinal("OrderID"));
            // 同一趟车的 OrderID 必须严格递增。脏数据里若残留重复行，丢掉后面的，
            // 否则同一个站会被走两次，跨天推演就跟着错。
            if (orderId <= lastOrderId) continue;
            lastOrderId = orderId;

            stops.Add(new BetweenStopRow(
                orderId,
                ReadString(reader, "station"),
                ReadString(reader, "ArriveTime"),
                ReadString(reader, "StartTime"),
                ReadDouble(reader, "Mileage")));
        }

        AddBetweenItem(result, currentTrain, from, to, fromOrder, toOrder, stops);
        return result;
    }

    private static void AddBetweenItem(
        List<TrainTimetableBetweenItem> result,
        (string Code1, string Code2)? train,
        string from,
        string to,
        long fromOrder,
        long toOrder,
        List<BetweenStopRow> stops)
    {
        if (train is null || stops.Count == 0) return;
        var (code1, code2) = train.Value;
        // 身份号用完整号对（D8269 vs D8269/D8272 是两趟车），客户端拿去查站序时
        // 也原样回来，服务端按号对精确定位。
        var displayCode = FormatTrainCodes(code1, code2);
        var item = BuildBetweenItem(
            displayCode,
            displayCode,
            from,
            to,
            fromOrder,
            toOrder,
            stops);
        if (item is not null) result.Add(item);
    }

    /// <summary>
    /// 把一趟车的整条站序走一遍，取出查询区间的开点、到点、区间里程，以及该车次的始发终到。
    /// 走法与 <see cref="GetAsync"/> 完全一致：按 到达 → 出发 的顺序推进时间，
    /// 时间比上一个事件早就算跨了一整天（Z21 北京西 19:48 开、拉萨 11:46 第3日到，全靠它）。
    /// </summary>
    private static TrainTimetableBetweenItem? BuildBetweenItem(
        string trainNumber,
        string trainCodes,
        string from,
        string to,
        long fromOrder,
        long toOrder,
        List<BetweenStopRow> stops)
    {
        TimeSpan? previousEventTime = null;
        int? departureDay = null;
        int? arrivalDay = null;
        var departTime = string.Empty;
        var arriveTime = string.Empty;
        var fromMileage = 0d;
        var toMileage = 0d;

        foreach (var stop in stops)
        {
            var isFrom = stop.OrderId == fromOrder;
            var isTo = stop.OrderId == toOrder;

            if (TryParseTime(stop.ArriveTime, out var arrivalEventTime))
            {
                arrivalEventTime = MoveToNextEventDay(arrivalEventTime, previousEventTime);
                previousEventTime = arrivalEventTime;
                if (isTo)
                {
                    arrivalDay = GetDayDifference(arrivalEventTime);
                    arriveTime = stop.ArriveTime;
                }
            }

            // 车可能停着跨零点：出发必须排在到达之后处理，下一站才继承得上这一天。
            if (TryParseTime(stop.StartTime, out var departureEventTime))
            {
                departureEventTime = MoveToNextEventDay(departureEventTime, previousEventTime);
                previousEventTime = departureEventTime;
                if (isFrom)
                {
                    departureDay = GetDayDifference(departureEventTime);
                    departTime = stop.StartTime;
                }
            }

            if (isFrom) fromMileage = stop.Mileage;
            if (isTo) toMileage = stop.Mileage;
        }

        return new TrainTimetableBetweenItem(
            trainNumber,
            from,
            to,
            stops[0].Station,
            stops[^1].Station,
            departTime,
            arriveTime,
            Math.Max(0, (arrivalDay ?? 0) - (departureDay ?? 0)),
            Math.Max(0d, toMileage - fromMileage),
            trainNumber,
            trainCodes);
    }

    /// <summary>站站查询里用到的停站行；只留推日序和取区间要用的列。</summary>
    private readonly record struct BetweenStopRow(
        long OrderId,
        string Station,
        string ArriveTime,
        string StartTime,
        double Mileage);

    /// <summary>
    /// 一趟车的完整站序。输入可以是单个号（<c>D8269</c>），也可以是带 "/" 的号对
    /// （<c>D8269/D8272</c>）—— 检索接口返回什么，这里就原样接什么。
    /// </summary>
    /// <remarks>
    /// <para>
    /// 查询一律落到**唯一一个号对**上，绝不把同一单号挂着的几份时刻表合并：
    /// 同一个号出现在多个号对下时它们本来就是不同的车（2017.04.20 的 <c>D8269</c>
    /// 与 <c>D8269/D8272</c> 是桂林北—北海和南宁东—贺州两趟车）。
    /// </para>
    /// <para>
    /// 单号对应多个号对时按固定规则挑一个：优先无第二号的号对，其次命中 TrainCode1 的，
    /// 最后命中 TrainCode2 的，同级按号对字典序。要精确指定另一趟车就传带 "/" 的号对。
    /// </para>
    /// </remarks>
    public async Task<TrainTimetableSchedule> GetAsync(
        string trainNumber,
        string version,
        CancellationToken cancellationToken = default)
    {
        var normalizedTrainNumber = trainNumber.Trim().ToUpperInvariant();
        if (normalizedTrainNumber.Length == 0) return new TrainTimetableSchedule([], string.Empty);

        // 只取前两段：库里最多就是号对，三段号在构建时也只保留前两段。
        var parts = normalizedTrainNumber.Split(
            '/',
            StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0) return new TrainTimetableSchedule([], normalizedTrainNumber);

        await using var connection = await OpenVersionAsync(version, cancellationToken);
        if (connection is null) return new TrainTimetableSchedule([], normalizedTrainNumber);

        var pair = await ResolvePairAsync(connection, version, parts, cancellationToken);
        if (pair is null) return new TrainTimetableSchedule([], normalizedTrainNumber);

        var (code1, code2) = pair.Value;
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
            WHERE TrainCode1 = @code1 AND TrainCode2 = @code2
            ORDER BY OrderID, rowid
            """;
        command.Parameters.AddWithValue("@code1", code1);
        command.Parameters.AddWithValue("@code2", code2);

        var result = new List<TrainTimetableStop>();
        TimeSpan? previousEventTime = null;
        // 查不到任何停站时退回用户输入的那个号，客户端就不用再兜一次底。
        var trainCodes = normalizedTrainNumber;
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var stationName = ReadString(reader, "station_name");
            if (stationName.Length == 0) continue;

            trainCodes = FormatTrainCodes(code1, code2);

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

        return new TrainTimetableSchedule(result, trainCodes);
    }

    /// <summary>
    /// 把请求里的号对/单号解析成库里唯一一个 <c>(TrainCode1, TrainCode2)</c>。
    /// 号对顺序不敏感（<c>D8272/D8269</c> 与 <c>D8269/D8272</c> 等价）；
    /// 单号按固定优先级挑一个号对，不跨号对合并。
    /// </summary>
    private static async Task<(string Code1, string Code2)?> ResolvePairAsync(
        SqliteConnection connection,
        string version,
        string[] parts,
        CancellationToken cancellationToken)
    {
        var table = Quote(TableName(version));
        await using var command = connection.CreateCommand();
        if (parts.Length >= 2)
        {
            command.CommandText = $"""
                SELECT TrainCode1 AS code1, TrainCode2 AS code2
                FROM {table}
                WHERE (TrainCode1 = @first AND TrainCode2 = @second)
                   OR (TrainCode1 = @second AND TrainCode2 = @first)
                ORDER BY code1, code2
                LIMIT 1
                """;
            command.Parameters.AddWithValue("@first", parts[0]);
            command.Parameters.AddWithValue("@second", parts[1]);
        }
        else
        {
            // 走两个索引再 GROUP BY，避免 TrainCode1 OR TrainCode2 的全表扫描。
            // priority: 0 = 无第二号的号对（D8269），1 = TrainCode1 命中，2 = TrainCode2 命中。
            command.CommandText = $"""
                SELECT code1, code2
                FROM (
                    SELECT TrainCode1 AS code1, TrainCode2 AS code2,
                           CASE WHEN TrainCode2 = '' THEN 0 ELSE 1 END AS priority
                    FROM {table}
                    WHERE TrainCode1 = @code
                    UNION ALL
                    SELECT TrainCode1 AS code1, TrainCode2 AS code2, 2 AS priority
                    FROM {table}
                    WHERE TrainCode2 = @code
                )
                GROUP BY code1, code2
                ORDER BY MIN(priority), code1, code2
                LIMIT 1
                """;
            command.Parameters.AddWithValue("@code", parts[0]);
        }

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)) return null;
        var code1 = ReadString(reader, "code1");
        var code2 = ReadString(reader, "code2");
        if (code1.Length == 0 && code2.Length == 0) return null;
        return (code1, code2);
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

/// <summary>
/// 站序查询的结果：停站表，加上这趟车的展示号对（<c>D111/D114</c>）。
/// </summary>
public sealed record TrainTimetableSchedule(
    IReadOnlyList<TrainTimetableStop> Stops,
    string TrainCodes);

public sealed record TrainTimetableStop(
    [property: JsonPropertyName("station_name")] string StationName,
    [property: JsonPropertyName("station_no")] string StationNo,
    [property: JsonPropertyName("arrive_time")] string ArriveTime,
    [property: JsonPropertyName("start_time")] string StartTime,
    [property: JsonPropertyName("running_time")] string RunningTime,
    [property: JsonPropertyName("arrive_day_str")] string ArriveDayStr,
    [property: JsonPropertyName("arrive_day_diff")] int ArriveDayDiff,
    [property: JsonPropertyName("mileage")] double Mileage);

/// <summary>
/// 车次号前缀搜索的结果项。**每个号对一条**。
/// <para>
/// <c>station_train_code</c>/<c>train_no</c> 是展示号：单号车次就是它本身；号对车次把
/// 匹配到的号排在前面、另一个号跟在 "/" 后面（<c>D111/D114</c> 或 <c>D114/D111</c>）。
/// 同一单号若挂在两个号对下（<c>D8269</c> 与 <c>D8269/D8272</c>），两行展示号不同，
/// 客户端不会把它们塌成一条，查站序时也原样回传。
/// </para>
/// <para><c>train_codes</c> 是库里的规范号对顺序（<c>D111/D114</c>）。</para>
/// </summary>
public sealed record TrainTimetableSearchItem(
    [property: JsonPropertyName("station_train_code")] string TrainNumber,
    [property: JsonPropertyName("from_station")] string DepartureStation,
    [property: JsonPropertyName("to_station")] string ArrivalStation,
    [property: JsonPropertyName("train_no")] string TrainNo,
    [property: JsonPropertyName("train_codes")] string TrainCodes);

/// <summary>
/// 按车站查询的结果项，比 <see cref="TrainTimetableSearchItem"/> 多出在该站的到发时刻。
/// 首站的到点与末站的发点为 <c>""</c>，与站序接口的约定一致。
/// <para>
/// 一趟车只出一行：<c>station_train_code</c>/<c>train_no</c>/<c>train_codes</c> 都是
/// 完整号对（<c>D111/D114</c>，单号车次则是 <c>D111</c>），同一个单号挂在两个号对下时
/// 也能分开。
/// </para>
/// </summary>
public sealed record TrainTimetableAtStationItem(
    [property: JsonPropertyName("station_train_code")] string TrainNumber,
    [property: JsonPropertyName("from_station")] string DepartureStation,
    [property: JsonPropertyName("to_station")] string ArrivalStation,
    [property: JsonPropertyName("train_no")] string TrainNo,
    [property: JsonPropertyName("arrive_time")] string ArriveTime,
    [property: JsonPropertyName("start_time")] string StartTime,
    [property: JsonPropertyName("train_codes")] string TrainCodes);

/// <summary>
/// 站站查询的结果项。比 <see cref="TrainTimetableSearchItem"/> 多出查询区间上的
/// 开点、到点、区间里程，以及该车次自身的始发终到。
/// <para>
/// <c>from_station</c>/<c>to_station</c> 复述的是**查询的两个站**（与旧行为一致），
/// 车次自己的始发终到是 <c>origin_station</c>/<c>terminal_station</c> —— 两者在
/// 过路车里并不相同，客户端靠这个判断"这趟车是不是从我这站始发"。
/// </para>
/// <para>
/// 历时没有单独字段：<c>arrive_day_diff</c> 加上两个时刻就够算了。
/// </para>
/// <para>
/// 一趟车只出一行：<c>station_train_code</c>/<c>train_no</c>/<c>train_codes</c> 都是
/// 完整号对（<c>D111/D114</c>，单号车次则是 <c>D111</c>），同一个单号挂在两个号对下时
/// 也能分开。
/// </para>
/// <para>
/// <c>train_no</c> 是给调用方拿去查站序用的车次标识，与 <c>station_train_code</c>
/// 同值。主 App 靠它接站序接口（拿到结果点一下就拉这趟车的站序），不能省。
/// </para>
/// </summary>
public sealed record TrainTimetableBetweenItem(
    [property: JsonPropertyName("station_train_code")] string TrainNumber,
    [property: JsonPropertyName("from_station")] string DepartureStation,
    [property: JsonPropertyName("to_station")] string ArrivalStation,
    [property: JsonPropertyName("origin_station")] string OriginStation,
    [property: JsonPropertyName("terminal_station")] string TerminalStation,
    [property: JsonPropertyName("depart_time")] string DepartTime,
    [property: JsonPropertyName("arrive_time")] string ArriveTime,
    [property: JsonPropertyName("arrive_day_diff")] int ArriveDayDiff,
    [property: JsonPropertyName("mileage")] double Mileage,
    [property: JsonPropertyName("train_no")] string TrainNo,
    [property: JsonPropertyName("train_codes")] string TrainCodes);
