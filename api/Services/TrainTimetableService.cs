using Microsoft.Data.Sqlite;
using System.Globalization;
using System.Text.Json.Serialization;

namespace RailLog.API.Services;

/// <summary>
/// 历史时刻表查询。库本体不进仓库，由 <see cref="TimetableSyncService"/> 每天从
/// GitHub Release 同步到 <c>{ContentRoot}/timetables/</c>，一个快照一个文件
/// （<c>train_timetables.db</c> 原样保存成 <c>{yyyy.MM.dd}.db</c>）。
/// <para>
/// 这里直接读 Release 库的 <c>stops</c> 表，不再转成按版本分表的旧结构。库还没同步下来时
/// 接口返回空结果。
/// </para>
/// </summary>
public sealed class TrainTimetableService(
    IWebHostEnvironment environment,
    ILogger<TrainTimetableService> logger)
{
    private readonly string _timetablesDirectory =
        TimetableDatabasePath.ResolveDirectory(environment);
    private readonly SemaphoreSlim _versionsGate = new(1, 1);
    private IReadOnlyList<string>? _versions;
    private bool _missingDirectoryReported;

    /// <summary>
    /// Release 库的 <c>train_no</c> 还没有归一化，查询时按旧接口的规则还原成号对：
    /// <list type="bullet">
    /// <item>只取前两段，三段号（<c>1060/1061/1063</c>）丢掉第三段；</item>
    /// <item>去掉 <c>#N</c> 重号后缀与车号尾缀字母（<c>6062#2</c> → <c>6062</c>，
    /// <c>4654B</c> → <c>4654</c>）；</item>
    /// <item>两段相同只留第一段（第二段落成空串）；</item>
    /// <item>归一化后重号的原始车次只保留字典序最小的一趟，其余整趟丢弃。</item>
    /// </list>
    /// 这套规则与原来的构建脚本一致 —— 客户端看到的车次号不变。
    /// </summary>
    private const string PairsCte = """
        codes AS (
            SELECT DISTINCT train_no FROM stops
        ),
        parts AS (
            SELECT train_no,
                   trim(CASE WHEN instr(train_no, '/') > 0
                             THEN substr(train_no, 1, instr(train_no, '/') - 1)
                             ELSE train_no END) AS raw1,
                   CASE WHEN instr(train_no, '/') > 0
                        THEN substr(train_no, instr(train_no, '/') + 1)
                        ELSE '' END AS rest
            FROM codes
        ),
        split AS (
            SELECT train_no, raw1,
                   trim(CASE WHEN instr(rest, '/') > 0
                             THEN substr(rest, 1, instr(rest, '/') - 1)
                             ELSE rest END) AS raw2
            FROM parts
        ),
        norm AS (
            SELECT train_no,
                   rtrim(upper(CASE WHEN instr(raw1, '#') > 0
                                    THEN substr(raw1, 1, instr(raw1, '#') - 1)
                                    ELSE raw1 END),
                         'ABCDEFGHIJKLMNOPQRSTUVWXYZ') AS code1,
                   rtrim(upper(CASE WHEN instr(raw2, '#') > 0
                                    THEN substr(raw2, 1, instr(raw2, '#') - 1)
                                    ELSE raw2 END),
                         'ABCDEFGHIJKLMNOPQRSTUVWXYZ') AS code2_raw
            FROM split
        ),
        collapsed AS (
            SELECT train_no, code1,
                   CASE WHEN code2_raw = code1 THEN '' ELSE code2_raw END AS code2
            FROM norm
        ),
        pairs AS (
            SELECT code1, code2, MIN(train_no) AS winner
            FROM collapsed
            WHERE code1 <> '' AND code1 GLOB '*[0-9]*'
            GROUP BY code1, code2
        )
        """;

    /// <summary>Release 库里 <c>-</c> 表示没有到发时刻，对外统一成空串。</summary>
    private static string Time(string column) =>
        $"CASE WHEN trim({column}) = '-' THEN '' ELSE trim({column}) END";

    /// <summary>可用的版本号，升序。文件名就是版本号，字典序恰好等于时间序。</summary>
    public async Task<IReadOnlyList<string>> GetVersionsAsync(
        CancellationToken cancellationToken = default)
    {
        var cached = _versions;
        if (cached is not null) return cached;

        await _versionsGate.WaitAsync(cancellationToken);
        try
        {
            if (_versions is not null) return _versions;

            if (!Directory.Exists(_timetablesDirectory))
            {
                if (!_missingDirectoryReported)
                {
                    _missingDirectoryReported = true;
                    logger.LogWarning(
                        "历史时刻表目录不存在：{Path}，等待 TimetableSyncService 首次同步；"
                        + "在此之前相关接口会返回空结果",
                        _timetablesDirectory);
                }
                _versions = [];
                return _versions;
            }

            var versions = Directory
                .EnumerateFiles(_timetablesDirectory, "*.db")
                .Select(Path.GetFileNameWithoutExtension)
                .Where(static name => IsValidVersion(name))
                .Select(static name => name!)
                .OrderBy(static name => name, StringComparer.Ordinal)
                .ToList();

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
        var limitClause = limit.HasValue ? "\n    LIMIT @limit" : string.Empty;
        // 匹配按**单个号**（输入 D114 也要能搜到 D111/D114 这趟车），但结果按**号对**
        // 去重：同一趟车只出一行，匹配到的号排在展示号前面。同一个单号若挂在两个
        // 号对下（如 D8269 与 D8269/D8272 是两趟不同的车），两行都在，绝不合并。
        command.CommandText = WithPairs($"""
    SELECT
        p.code1,
        p.code2,
        CASE WHEN p.code1 LIKE @prefix || '%' THEN p.code1 ELSE p.code2 END AS train_number,
        (
            SELECT trim(station) FROM stops
            WHERE train_no = p.winner
            ORDER BY seq ASC
            LIMIT 1
        ) AS departure_station,
        (
            SELECT trim(station) FROM stops
            WHERE train_no = p.winner
            ORDER BY seq DESC
            LIMIT 1
        ) AS arrival_station
    FROM pairs p
    WHERE p.code1 LIKE @prefix || '%'
       OR p.code2 LIKE @prefix || '%'
    ORDER BY train_number, p.code1, p.code2{limitClause}
    """);
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
        // 只算归一化后留下的那趟车：重号被丢弃的原始车次不进车站表。
        command.CommandText = WithPairs("""
            SELECT DISTINCT trim(s.station) AS station_name
            FROM stops s
            JOIN pairs p ON p.winner = s.train_no
            WHERE trim(s.station) <> ''
            ORDER BY station_name;
            """);
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
    /// 首末站一律按**完整号对**取：同一个单号若挂在两个号对下就是两趟不同的车，按单号
    /// <c>OR</c> 取首末站会把两趟的站序拼在一起（2017.04.20 的 <c>D8269</c> 与
    /// <c>D8269/D8272</c>）。
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

        await using var command = connection.CreateCommand();
        command.CommandText = WithPairs($"""
            , station_rows AS (
                SELECT p.code1 AS code1, p.code2 AS code2, s.train_no AS winner,
                       {Time("s.arrival")} AS arrive_time,
                       {Time("s.departure")} AS start_time
                FROM stops s
                JOIN pairs p ON p.winner = s.train_no
                WHERE trim(s.station) = @station
            ), hits AS (
                -- DISTINCT 只用来挡脏数据里完全重复的停站行；同一趟车在这站本来就只有一行。
                SELECT DISTINCT code1, code2, winner, arrive_time, start_time
                FROM station_rows
                WHERE code1 <> ''
            )
            SELECT
                h.code1,
                h.code2,
                -- 首末站按**完整号对**取：同一个单号若挂在两个号对下是两趟车，
                -- 按单号 OR 会把两趟的站序并在一起。
                (
                    SELECT trim(station) FROM stops
                    WHERE train_no = h.winner
                    ORDER BY seq ASC LIMIT 1
                ) AS from_station,
                (
                    SELECT trim(station) FROM stops
                    WHERE train_no = h.winner
                    ORDER BY seq DESC LIMIT 1
                ) AS to_station,
                h.arrive_time,
                h.start_time
            FROM hits h
            ORDER BY h.code1, h.code2
            LIMIT @limit
            """);
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
                ReadString(reader, "arrive_time"),
                ReadString(reader, "start_time"),
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
        // 分组键是**号对** (code1, code2)，不是单个号：合并运行的 D111+D114 是一趟车，
        // 早先按单号展开会把同一趟车的每一站各出两行，站序被走成"两趟"，跨天推演跟着错。
        // 号对还有一个好处：万一同一个号出现在两个不同的对里，也不会把两趟车搅在一起。
        command.CommandText = WithPairs($"""
            , train_stops AS (
                SELECT p.code1 AS code1, p.code2 AS code2,
                       s.seq AS OrderID, trim(s.station) AS station,
                       {Time("s.arrival")} AS ArriveTime,
                       {Time("s.departure")} AS StartTime,
                       s.km AS Mileage
                FROM stops s
                JOIN pairs p ON p.winner = s.train_no
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
            """);
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

        // 只取前两段：库里最多就是号对，三段号在归一化时也只保留前两段。
        var parts = normalizedTrainNumber.Split(
            '/',
            StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0) return new TrainTimetableSchedule([], normalizedTrainNumber);

        await using var connection = await OpenVersionAsync(version, cancellationToken);
        if (connection is null) return new TrainTimetableSchedule([], normalizedTrainNumber);

        var pair = await ResolvePairAsync(connection, parts, cancellationToken);
        if (pair is null) return new TrainTimetableSchedule([], normalizedTrainNumber);

        var (code1, code2, winner) = pair.Value;
        await using var command = connection.CreateCommand();
        // 首站没有到点、末站没有发点：Release 库里本来就是 "-"，个别快照里即使填了
        // 也按旧约定抹掉。
        command.CommandText = $"""
            SELECT
                trim(station) AS station_name,
                seq AS station_no,
                CASE WHEN seq = 1 THEN '' ELSE {Time("arrival")} END AS arrive_time,
                CASE WHEN seq = (SELECT MAX(seq) FROM stops WHERE train_no = @winner)
                     THEN '' ELSE {Time("departure")} END AS start_time,
                km AS mileage
            FROM stops
            WHERE train_no = @winner
            ORDER BY seq
            """;
        command.Parameters.AddWithValue("@winner", winner);

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
    /// 把请求里的号对/单号解析成库里唯一一个号对（<c>code1</c>/<c>code2</c>），
    /// 连同它对应的原始 <c>train_no</c> —— 停站行是按原始车次号存的。
    /// 号对顺序不敏感（<c>D8272/D8269</c> 与 <c>D8269/D8272</c> 等价）；
    /// 单号按固定优先级挑一个号对，不跨号对合并。
    /// </summary>
    private static async Task<(string Code1, string Code2, string Winner)?> ResolvePairAsync(
        SqliteConnection connection,
        string[] parts,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        if (parts.Length >= 2)
        {
            command.CommandText = WithPairs("""
                SELECT code1, code2, winner
                FROM pairs
                WHERE (code1 = @first AND code2 = @second)
                   OR (code1 = @second AND code2 = @first)
                ORDER BY code1, code2
                LIMIT 1
                """);
            command.Parameters.AddWithValue("@first", parts[0]);
            command.Parameters.AddWithValue("@second", parts[1]);
        }
        else
        {
            // priority: 0 = 无第二号的号对（D8269），1 = 第一段命中，2 = 第二段命中。
            command.CommandText = WithPairs("""
                SELECT code1, code2, winner
                FROM pairs
                WHERE code1 = @code OR code2 = @code
                ORDER BY
                    CASE WHEN code2 = '' THEN 0 WHEN code1 = @code THEN 1 ELSE 2 END,
                    code1, code2
                LIMIT 1
                """);
            command.Parameters.AddWithValue("@code", parts[0]);
        }

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)) return null;
        var code1 = ReadString(reader, "code1");
        var code2 = ReadString(reader, "code2");
        var winner = ReadString(reader, "winner");
        if (code1.Length == 0 && code2.Length == 0) return null;
        return (code1, code2, winner);
    }

    /// <summary>
    /// 同步服务每写入一个新版本就调用一次，让下一次查询重新读版本列表。
    /// 与 <see cref="GetVersionsAsync"/> 共用同一把门，保证不会在读完旧列表之后
    /// 又把旧列表写回缓存。
    /// </summary>
    public async Task InvalidateVersionsAsync(CancellationToken cancellationToken = default)
    {
        await _versionsGate.WaitAsync(cancellationToken);
        try
        {
            _versions = null;
        }
        finally
        {
            _versionsGate.Release();
        }
    }

    private async Task<SqliteConnection?> OpenVersionAsync(
        string version,
        CancellationToken cancellationToken)
    {
        if (!IsValidVersion(version)) return null;
        if (!await SupportsVersionAsync(version, cancellationToken)) return null;

        var path = TimetableDatabasePath.Resolve(environment, version);
        if (!File.Exists(path)) return null;

        return await OpenConnectionAsync(path, cancellationToken);
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

    private static string WithPairs(string body) => $"WITH {PairsCte}{body}";

    /// <summary>版本号形如 2003.11.25。</summary>
    public static bool IsValidVersion(string? version) =>
        version is { Length: 10 } &&
        version[4] == '.' && version[7] == '.' &&
        DateOnly.TryParseExact(version, "yyyy.MM.dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out _);

    private static string ReadString(SqliteDataReader reader, string name) =>
        reader[name] is DBNull ? string.Empty : Convert.ToString(reader[name])?.Trim() ?? string.Empty;

    private static double ReadDouble(SqliteDataReader reader, string name) =>
        double.TryParse(ReadString(reader, name), NumberStyles.Any, CultureInfo.InvariantCulture, out var value)
            ? value
            : 0;

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
