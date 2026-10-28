import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path_util;
import 'package:raillog/src/models/journey_stations.dart';
import 'package:raillog/src/models/route_resolution.dart';
import 'package:raillog/src/models/route_station.dart';
import 'package:raillog/src/models/station_pair_distance.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';
import 'package:raillog/src/services/database_path_service.dart';
import 'package:sqflite/sqflite.dart';

class RouteService {
  RouteService._();

  static Future<_RouteGraph>? _graphFuture;

  static Future<List<String>> getRouteNames() async {
    final graph = await (_graphFuture ??= _loadGraph());
    return graph.routeNames;
  }

  static Future<List<String>> getStationNames() async {
    final graph = await (_graphFuture ??= _loadGraph());
    return graph.stationNames;
  }

  static Future<List<String>> getStationsForRoute(String routeName) async {
    final graph = await (_graphFuture ??= _loadGraph());
    return graph.stationsForRoute(routeName);
  }

  static Future<List<RouteStation>> getStationsBetweenRoute(
    String routeName,
    String fromStation,
    String toStation,
  ) async {
    final graph = await (_graphFuture ??= _loadGraph());
    return Isolate.run(
      () => graph.stationsBetweenOnRoute(routeName, fromStation, toStation),
    );
  }

  static Future<Map<String, JourneyStations>> resolveTripStations(
    Iterable<TripRecord> source,
  ) async {
    final trips = source.where((trip) => trip.isRailTrip).toList();
    final graph = await (_graphFuture ??= _loadGraph());
    return Isolate.run(
      () => {
        for (final trip in trips)
          trip.clientId: graph.stationsForJourney(
            trip.fromStation,
            trip.toStation,
            trip.viaRouteSegments,
          ),
      },
    );
  }

  static Future<RouteResolution> resolveShortestJourney(
    String fromStation,
    String toStation,
  ) async {
    final graph = await (_graphFuture ??= _loadGraph());
    return Isolate.run(() {
      final result = graph.findPath(
        fromStation,
        toStation,
        targetDistance: null,
      );
      if (result == null) {
        return RouteResolution(
          segments: const [],
          usedShortestPath: true,
          unresolvedSections: ['$fromStation-$toStation'],
          inferenceLog: [
            '最短路径识别：$fromStation → $toStation',
            '结果：站点不存在或线路图中不可达',
          ],
        );
      }
      return RouteResolution(
        segments: _mergeEdges(result.edges),
        usedShortestPath: true,
        unresolvedSections: const [],
        inferenceLog: [
          '最短路径识别：$fromStation → $toStation',
          ...result.inferenceLog,
        ],
      );
    });
  }

  static Future<double?> getDistanceOnRoute(
    String routeName,
    String fromStation,
    String toStation,
  ) async {
    final graph = await (_graphFuture ??= _loadGraph());
    return Isolate.run(
      () => graph.distanceOnRoute(routeName, fromStation, toStation),
    );
  }

  static Future<RouteResolution> resolveJourney(
    List<StationPairDistance> sections,
  ) async {
    final graph = await (_graphFuture ??= _loadGraph());
    return Isolate.run(() => _resolveJourney(graph, sections));
  }

  /// 已存经由在当前线路库里画不出来的行程。
  ///
  /// 「画不出来」指线路名解析不到、或该线路上找不到这一段的起止站：地图只能把这一段
  /// 退化成直线，用户看到的就是「经由损坏 / 线路数据库不通」。空经由不算损坏——那是
  /// 还没填，不是填错了。
  static Future<Set<int>> findUndrawableTripIds(
    Iterable<TripRecord> source,
  ) async {
    final trips = source
        .where((trip) => trip.isRailTrip && trip.viaRouteSegments.isNotEmpty)
        .toList(growable: false);
    if (trips.isEmpty) return const {};
    final graph = await (_graphFuture ??= _loadGraph());
    return Isolate.run(() {
      final ids = <int>{};
      for (final trip in trips) {
        if (trip.viaRouteSegments.any(
          (segment) => !graph.isSegmentDrawable(segment),
        )) {
          ids.add(trip.id);
        }
      }
      return ids;
    });
  }

  static RouteResolution _resolveJourney(
    _RouteGraph graph,
    List<StationPairDistance> sections,
  ) {
    final allEdges = <_RouteEdge>[];
    final unresolved = <String>[];
    final inferenceLog = <String>[];
    var usedShortestPath = false;
    // 上一段落在哪条线上。区段是逐个独立搜的，而两条并行线路的里程桩可能一模一样
    // （胶济客专线与胶济线就是这样），此时只看里程分不出该走哪条，很容易一段挑一条、
    // 拼起来就成了在两条线之间反复横跳。把上一段的线路名交给下一段，等于让它接着走，
    // 交界处就不会无故换名。
    String? continuationRouteName;

    for (var index = 0; index < sections.length; index++) {
      final section = sections[index];
      inferenceLog.add(
        '区间 ${index + 1}：${section.fromStation} → ${section.toStation}',
      );
      inferenceLog.add(
        section.distanceKm == null
            ? '目标里程：未获取，将使用最短路径'
            : '目标里程：${_formatDistance(section.distanceKm!)} km',
      );
      final result = graph.findPath(
        section.fromStation,
        section.toStation,
        targetDistance: section.distanceKm,
        initialRouteName: continuationRouteName,
      );
      if (result == null) {
        unresolved.add('${section.fromStation}-${section.toStation}');
        inferenceLog.add('结果：站点不存在或线路图中不可达');
        continue;
      }
      inferenceLog.addAll(result.inferenceLog);
      allEdges.addAll(result.edges);
      usedShortestPath = usedShortestPath || result.usedShortestPath;
      if (result.edges.isNotEmpty) {
        continuationRouteName = result.edges.last.routeName;
      }
    }

    return RouteResolution(
      segments: _mergeEdges(allEdges),
      usedShortestPath: usedShortestPath,
      unresolvedSections: unresolved,
      inferenceLog: inferenceLog,
    );
  }

  static Future<_RouteGraph> _loadGraph() async {
    final data = await rootBundle.load('assets/db/routes.db');
    final databasesPath = await DatabasePathService.directory();
    final databasePath = path_util.join(databasesPath, 'routes_reference.db');
    await Directory(databasesPath).create(recursive: true);
    await File(databasePath).writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );

    final database = await openDatabase(databasePath, readOnly: true);
    try {
      // 先按线路名排序（同名再按 line_id）：并行线路的里程桩完全相同时（京沪线 与
      // 沪宁高速、陇海线 与 宁西西合段），走哪条由邻接表的加入次序决定。line_id 是
      // 线路库每次重新生成时重新分配的，按它排会让同一趟行程的经由随库版本漂移；
      // 线路名稳定，并列时的取舍也就稳定。
      final rows = await database.rawQuery('''
        SELECT
          l.line_name,
          ls.line_id,
          ls.seq,
          ls.station,
          ls.km
        FROM line_stations ls
        JOIN lines l ON l.line_id = ls.line_id
        ORDER BY l.line_name, ls.line_id, ls.seq
      ''');
      return _RouteGraph.fromRows(rows);
    } finally {
      await database.close();
    }
  }

  static List<ViaRouteSegment> _mergeEdges(List<_RouteEdge> edges) => [
    for (final section in _mergeSections(edges))
      ViaRouteSegment(
        routeName: section.routeName,
        fromStation: section.fromStation,
        toStation: section.toStation,
        mileageKm: section.mileageKm,
      ),
  ];
}

class _RouteGraph {
  _RouteGraph(this.adjacency, this.routeStationIndexes);

  final Map<String, List<_RouteEdge>> adjacency;
  final Map<String, Map<String, _RouteStationEntry>> routeStationIndexes;

  List<String> get routeNames {
    final names = adjacency.values
        .expand((edges) => edges)
        .map((edge) => edge.routeName)
        .toSet()
        .toList();
    names.sort();
    return names;
  }

  List<String> get stationNames {
    final names = adjacency.keys.toList()..sort();
    return names;
  }

  List<String> stationsForRoute(String routeName) {
    final resolvedRouteName = _resolveRouteName(routeName);
    if (resolvedRouteName == null) return const [];
    final stations = routeStationIndexes[resolvedRouteName];
    if (stations == null) return const [];
    final entries = stations.values.toList()
      ..sort((first, second) {
        final indexComparison = first.index.compareTo(second.index);
        return indexComparison != 0
            ? indexComparison
            : first.name.compareTo(second.name);
      });
    return entries.map((entry) => entry.name).toList(growable: false);
  }

  List<RouteStation> stationsBetweenOnRoute(
    String routeName,
    String fromStation,
    String toStation,
  ) {
    final resolvedRouteName = _resolveRouteName(routeName);
    if (resolvedRouteName == null) return const [];
    final stationIndexes = routeStationIndexes[resolvedRouteName];
    if (stationIndexes == null) return const [];
    final ordered = stationIndexes.values.toList()
      ..sort((first, second) => first.index.compareTo(second.index));
    final start = _routeStationPosition(ordered, fromStation);
    final end = _routeStationPosition(ordered, toStation);
    if (start == null || end == null) return const [];
    final selected = start <= end
        ? ordered.sublist(start, end + 1)
        : ordered.sublist(end, start + 1).reversed;
    return [
      for (final entry in selected)
        RouteStation(name: entry.name, mileage: entry.mileage),
    ];
  }

  /// 这一段能否在当前线路库里画出来：线路名解析得到，且起止站都在这条线上。
  bool isSegmentDrawable(ViaRouteSegment segment) {
    final resolvedRouteName = _resolveRouteName(segment.routeName);
    if (resolvedRouteName == null) return false;
    final section = _stationsBetweenOnRoute(
      resolvedRouteName,
      segment.fromStation,
      segment.toStation,
    );
    return section != null && section.isNotEmpty;
  }

  JourneyStations stationsForJourney(
    String fromStation,
    String toStation,
    List<ViaRouteSegment> segments,
  ) {
    if (segments.isEmpty) {
      return JourneyStations.of([fromStation.trim(), toStation.trim()]);
    }

    final stations = <String>[];
    final legRouteNames = <String>[];
    // 新站加入时，它到上一站那一段归属于「正在展开的线路」。
    void append(String station, String routeName) {
      final name = station.trim();
      if (name.isEmpty) return;
      if (stations.isEmpty) {
        stations.add(name);
        return;
      }
      if (stations.last == name) return;
      stations.add(name);
      legRouteNames.add(routeName);
    }

    var currentRouteName = segments.first.routeName.trim();
    append(fromStation, currentRouteName);
    for (final segment in segments) {
      final routeName = _resolveRouteName(segment.routeName);
      // 查不到线路时保留原始名字，至少能作为诊断信息带下去。
      currentRouteName = routeName ?? segment.routeName.trim();
      final section = routeName == null
          ? null
          : _stationsBetweenOnRoute(
              routeName,
              segment.fromStation,
              segment.toStation,
            );
      if (section == null || section.isEmpty) {
        append(segment.fromStation, currentRouteName);
        append(segment.toStation, currentRouteName);
        continue;
      }
      for (final station in section) {
        append(station, currentRouteName);
      }
    }
    append(toStation, currentRouteName);
    return JourneyStations(stations: stations, legRouteNames: legRouteNames);
  }

  factory _RouteGraph.fromRows(List<Map<String, Object?>> rows) {
    final adjacency = <String, List<_RouteEdge>>{};
    final routeStationIndexes = <String, Map<String, _RouteStationEntry>>{};
    String? currentLineId;
    String? previousStation;
    double? previousMileage;

    for (final row in rows) {
      final lineId = row['line_id']?.toString();
      final routeName = row['line_name']?.toString().trim() ?? '';
      final station = row['station']?.toString().trim() ?? '';
      final mileage = (row['km'] as num?)?.toDouble();
      final stationIndex = (row['seq'] as num?)?.toInt();
      if (lineId == null ||
          routeName.isEmpty ||
          station.isEmpty ||
          mileage == null ||
          stationIndex == null) {
        continue;
      }

      final stationIndexes = routeStationIndexes.putIfAbsent(
        routeName,
        () => {},
      );
      final existingStation = stationIndexes[station];
      if (existingStation == null || stationIndex < existingStation.index) {
        stationIndexes[station] = _RouteStationEntry(
          name: station,
          index: stationIndex,
          mileage: mileage,
        );
      }

      if (lineId != currentLineId) {
        currentLineId = lineId;
        previousStation = null;
        previousMileage = null;
      }
      if (previousStation != null && previousStation != station) {
        final distance = (mileage - previousMileage!).abs();
        // 相邻两站的里程桩可能相同（杭深线的 绅坊 与 乐清东 都写作 377 km，
        // 合福高速线的 延平 与 南平北 都是 729 km），这时差值为 0。仍然要连上这条
        // 零长边：线路库是按 seq 连成的链，缺一条边就把整条线断成两截，按线路名过滤
        // 的搜索（经由选择里的站间距离就是它）跨不过断点，会报「线路不连接起终点」。
        // 代价只是这一段不占里程，而沿线走法的总里程等于两端里程桩之差，不受影响。
        final forward = _RouteEdge(
          fromStation: previousStation,
          toStation: station,
          routeName: routeName,
          distanceKm: distance,
        );
        final backward = forward.reversed();
        adjacency.putIfAbsent(previousStation, () => []).add(forward);
        adjacency.putIfAbsent(station, () => []).add(backward);
      }
      previousStation = station;
      previousMileage = mileage;
      adjacency.putIfAbsent(station, () => []);
    }
    return _RouteGraph(adjacency, routeStationIndexes);
  }

  _PathResult? findPath(
    String fromStation,
    String toStation, {
    required double? targetDistance,
    String? initialRouteName,
  }) {
    final start = _resolveStationName(fromStation);
    final end = _resolveStationName(toStation);
    if (start == null || end == null) return null;
    if (start == end) {
      return const _PathResult(
        edges: [],
        usedShortestPath: false,
        inferenceLog: ['结果：起点与终点相同，无需搜索'],
      );
    }

    final shortest = _shortestPath(
      start,
      end,
      initialRouteName: initialRouteName,
    );
    if (shortest == null) return null;
    if (targetDistance == null) {
      return _PathResult(
        edges: shortest,
        usedShortestPath: true,
        inferenceLog: [
          '结果：采用最短路径，里程 ${_formatDistance(_edgeDistance(shortest))} km',
          '线路：${_describeEdges(shortest)}',
        ],
      );
    }
    final search = _distanceMatchingOrClosestPath(
      start,
      end,
      targetDistance,
      shortest,
      initialRouteName: initialRouteName,
    );
    final resultLine = search.matchedTolerance
        ? '结果：找到容差内匹配路径'
        : search.error <= _matchTolerance(search.edges.length)
        ? '结果：里程与目标并列，取用到线路名更少的走法'
        : '结果：未找到容差内路径，采用里程最接近路径';
    return _PathResult(
      edges: search.edges,
      usedShortestPath: identical(search.edges, shortest),
      inferenceLog: [
        '最短路径里程：${_formatDistance(_edgeDistance(shortest))} km',
        ...search.steps,
        '搜索状态数：${search.exploredStates}',
        resultLine,
        '选定里程：${_formatDistance(search.distance)} km，误差 ${_formatDistance(search.error)} km',
        '线路：${_describeEdges(search.edges)}',
      ],
    );
  }

  double? distanceOnRoute(
    String routeName,
    String fromStation,
    String toStation,
  ) {
    final resolvedRouteName = _resolveRouteName(routeName);
    if (resolvedRouteName == null) return null;
    final start = _resolveStationName(fromStation);
    final end = _resolveStationName(toStation);
    if (start == null || end == null) return null;
    if (start == end) return 0;
    final edges = _shortestPath(start, end, routeName: resolvedRouteName);
    if (edges == null) return null;
    return edges.fold<double>(0, (sum, edge) => sum + edge.distanceKm);
  }

  String? _resolveStationName(String value) {
    final normalized = value.trim();
    if (adjacency.containsKey(normalized)) return normalized;
    if (normalized.endsWith('站')) {
      final withoutSuffix = normalized.substring(0, normalized.length - 1);
      if (adjacency.containsKey(withoutSuffix)) return withoutSuffix;
    } else if (adjacency.containsKey('$normalized站')) {
      return '$normalized站';
    }
    return null;
  }

  String? _resolveRouteName(String value) {
    final routeName = value.trim();
    if (routeStationIndexes.containsKey(routeName)) return routeName;
    final normalized = routeName.replaceFirst(RegExp(r'(铁路|线)$'), '');
    final matches = routeStationIndexes.keys.where(
      (candidate) =>
          candidate.replaceFirst(RegExp(r'(铁路|线)$'), '') == normalized,
    );
    if (matches.length == 1) return matches.single;

    // 2.6.1 的线路库删过速度等级与「线」字（京港高铁合安段 → 京港合安段、
    // 宁西线西合段 → 宁西西合段）；当前线路库恢复成全名，旧行程里两种写法都有。
    // 字面规则救不了的少数改名先查别名表，再按宽松键找一次；只有唯一命中才采用，
    // 避免把「京广线」和「京广高铁」这类只差速度等级的并行线路混成一条。
    final alias = _routeNameAliases[routeName];
    if (alias != null && routeStationIndexes.containsKey(alias)) return alias;
    final loose = _looseRouteKey(routeName);
    final looseMatches = routeStationIndexes.keys
        .where((candidate) => _looseRouteKey(candidate) == loose)
        .toList(growable: false);
    return looseMatches.length == 1 ? looseMatches.single : null;
  }

  List<String>? _stationsBetweenOnRoute(
    String routeName,
    String fromStation,
    String toStation,
  ) {
    final stationIndexes = routeStationIndexes[routeName];
    if (stationIndexes == null) return null;
    final ordered = stationIndexes.values.toList()
      ..sort((first, second) => first.index.compareTo(second.index));
    final start = _routeStationPosition(ordered, fromStation);
    final end = _routeStationPosition(ordered, toStation);
    if (start == null || end == null) return null;
    if (start <= end) {
      return ordered
          .sublist(start, end + 1)
          .map((entry) => entry.name)
          .toList(growable: false);
    }
    return ordered
        .sublist(end, start + 1)
        .reversed
        .map((entry) => entry.name)
        .toList(growable: false);
  }

  int? _routeStationPosition(List<_RouteStationEntry> ordered, String value) {
    final station = value.trim();
    var position = ordered.indexWhere((entry) => entry.name == station);
    if (position >= 0) return position;
    final alternate = station.endsWith('站')
        ? station.substring(0, station.length - 1)
        : '$station站';
    position = ordered.indexWhere((entry) => entry.name == alternate);
    return position < 0 ? null : position;
  }

  /// 里程最短的走法；里程并列时取**换线最少**的一条。
  ///
  /// 状态是「站 + 到达它时走的线路名」，代价按 `[里程, 换线次数]` 字典序比较。两条
  /// 并行线路的里程桩可能完全相同（胶济客专线与胶济线就是这样），只按站做 Dijkstra
  /// 时并列由松弛顺序决定，于是一段路会在两条线之间换名——UI 上就是「经由线路」凭空
  /// 多出几段、地图在两条并行走廊之间来回跳。把换线次数当次级代价，里程并列时就只会
  /// 留在同一条线上。
  ///
  /// [initialRouteName] 是上一段的线路名：从它接着走不算换线，相邻区间于是不会在
  /// 交界处换名。
  List<_RouteEdge>? _shortestPath(
    String start,
    String end, {
    String? routeName,
    String? initialRouteName,
  }) {
    final startState = _RouteState(
      station: start,
      routeName: initialRouteName,
      cost: const [0, 0],
    );
    final costs = <String, List<double>>{startState.key: startState.cost};
    final previous = <String, _RouteStateStep>{};
    final queue = _MinHeap<_RouteState>();
    queue.add(startState, startState.cost);

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (_comparePriority(current.cost, costs[current.key]!) > 0) {
        continue; // 堆里剩下的旧标签，已经被更优的取代
      }
      if (current.station == end) {
        return _reconstructStates(previous, startState.key, current.key);
      }

      for (final edge in adjacency[current.station] ?? const []) {
        if (routeName != null && edge.routeName != routeName) continue;
        final switched =
            current.routeName != null && edge.routeName != current.routeName;
        final nextStateKey = _routeStateKey(edge.toStation, edge.routeName);
        final nextCost = <double>[
          current.cost[0] + edge.distanceKm,
          current.cost[1] + (switched ? 1 : 0),
        ];
        final known = costs[nextStateKey];
        if (known != null && _comparePriority(nextCost, known) >= 0) {
          continue;
        }
        costs[nextStateKey] = nextCost;
        previous[nextStateKey] = _RouteStateStep(current.key, edge);
        queue.add(
          _RouteState(
            station: edge.toStation,
            routeName: edge.routeName,
            cost: nextCost,
          ),
          nextCost,
        );
      }
    }
    return null;
  }

  /// 搜一条里程贴着 [targetDistance] 的走法，误差落在它自己的刻度差允许量内
  /// （[_matchTolerance]，见 [_mileageDriftPerHop]）就算命中；命中里取用到的线路名
  /// 最少的那条，都不命中时退回里程最接近的一条。[initialRouteName] 是上一段落在的
  /// 那条线，算作已经用上，这样两条线里程一模一样时（沪宁段的 京沪线 与 沪宁高速线
  /// 就是）能接着上一段走。
  _DistanceSearchResult _distanceMatchingOrClosestPath(
    String start,
    String end,
    double targetDistance,
    List<_RouteEdge> shortest, {
    String? initialRouteName,
  }) {
    final lowerBounds = _shortestDistancesFrom(end);
    final startLowerBound = lowerBounds[start];
    if (startLowerBound == null) {
      return _DistanceSearchResult(
        edges: shortest,
        distance: _edgeDistance(shortest),
        error: (_edgeDistance(shortest) - targetDistance).abs(),
        matchedTolerance: false,
        exploredStates: 0,
        steps: const ['无法计算目标站最短距离，保留最短路径候选'],
      );
    }

    var closest = shortest;
    var closestError = (startLowerBound - targetDistance).abs();
    final steps = <String>[
      '初始候选：${_formatDistance(startLowerBound)} km，误差 ${_formatDistance(closestError)} km',
    ];
    if (closestError <= _distanceTolerance ||
        startLowerBound > targetDistance) {
      return _DistanceSearchResult(
        edges: closest,
        distance: startLowerBound,
        error: closestError,
        matchedTolerance: closestError <= _distanceTolerance,
        exploredStates: 0,
        steps: steps,
      );
    }

    final queue = _MinHeap<_ExactSearchNode>();
    final startNode = _ExactSearchNode(
      station: start,
      distance: 0,
      previous: null,
      incomingEdge: null,
      usedRouteNames: initialRouteName == null ? const {} : {initialRouteName},
      hopCount: 0,
    );
    // 优先级按 [用到的线路名数, 离目标里程的误差下界, 潜力里程] 字典序比较：先要线路名少，
    // 其次要贴目标，最后才看走得短不短。先出队的就是「线路名最少的贴目标走法」，所以
    // 一旦它落在自己的刻度差允许量内就可以直接返回。「里程并列取线路名少」正是靠这个
    // 次序——线路名少一个的走法哪怕误差大一点，也排在前面。
    queue.add(startNode, [
      startNode.usedRouteNames.length.toDouble(),
      _errorLowerBound(0, startLowerBound, targetDistance),
      startLowerBound,
    ]);
    final visited = <String>{startNode.stateKey};
    var exploredStates = 0;
    // 已经收下的候选。终点节点先出队，不代表它就是这一「线路名数」里最贴目标的那个：
    // 优先级里只有终点节点用真误差，中转节点用的都是误差下界，两条走法可以在同一个中转站
    // 上打平——新丰镇→西安 有 陇海线 与 宁西西合段 两条等长的走法（都是 35 km），谁先
    // 弹出全看堆的内部次序。所以收下之后还要接着把「线路名数不比它多、误差下界还比它小」
    // 的节点走完，从中挑最贴目标的那个。
    List<_RouteEdge>? accepted;
    var acceptedNames = 0;
    var acceptedError = 0.0;

    while (queue.isNotEmpty && exploredStates < _maxExactSearchStates) {
      if (accepted != null) {
        final front = queue.peekPriority;
        if (front == null || front[0] > acceptedNames) break;
        if (front[0] == acceptedNames && front[1] >= acceptedError) break;
      }
      final current = queue.removeFirst();
      exploredStates++;
      if (current.station == end) {
        final error = (current.distance - targetDistance).abs();
        final tieBand = _mileageTieBand(current.hopCount);
        if (error <= _distanceTolerance + tieBand) {
          final exact = error <= _distanceTolerance;
          _addSearchStep(
            steps,
            exact
                ? '容差内候选：${_formatDistance(current.distance)} km，误差 ${_formatDistance(error)} km'
                : '里程并列候选：${_formatDistance(current.distance)} km，误差 ${_formatDistance(error)} km'
                      '（经过 ${current.hopCount} 站，刻度差允许 ${_formatDistance(tieBand)} km，'
                      '取用到线路名更少的走法）',
          );
          if (accepted == null || error < acceptedError) {
            accepted = current.edges;
            acceptedNames = current.usedRouteNames.length;
            acceptedError = error;
          }
        } else if (error < closestError) {
          closest = current.edges;
          closestError = error;
          _addSearchStep(
            steps,
            '更近候选：${_formatDistance(current.distance)} km，误差 ${_formatDistance(error)} km',
          );
        }
        continue;
      }

      // 剪枝窗口：误差超过刻度差允许量的走法不会被选中，所以窗口至少留这么宽（按再走一站
      // 算，子节点只会更宽），再随已经弹出的更近候选收紧——收下的候选更贴目标，比它更贴的
      // 走法更不该被剪掉。
      var minWindow =
          _distanceTolerance + _mileageTieBand(current.hopCount + 1);
      if (accepted != null && acceptedError > minWindow) {
        minWindow = acceptedError;
      }
      final pruneWindow = closestError > minWindow ? closestError : minWindow;
      for (final edge in adjacency[current.station] ?? const []) {
        if (current.containsStation(edge.toStation)) continue;
        final nextDistance = current.distance + edge.distanceKm;
        final lowerBound = lowerBounds[edge.toStation];
        if (lowerBound == null ||
            nextDistance > targetDistance + pruneWindow ||
            nextDistance + lowerBound > targetDistance + pruneWindow) {
          continue;
        }
        final next = _ExactSearchNode(
          station: edge.toStation,
          distance: nextDistance,
          previous: current,
          incomingEdge: edge,
          usedRouteNames: {...current.usedRouteNames, edge.routeName},
          hopCount: current.hopCount + 1,
        );
        if (!visited.add(next.stateKey)) continue;
        // 出队次序的第二个判据是「离目标里程至少还差多少」，而不是潜力里程（走到这儿的累计
        // 里程 + 到终点的最短距离）。潜力里程小只说明走得短，不代表贴目标：D966 的
        // 西安北→石家庄 目标 807，绕 徐兰高速线+临潼东联络、或在太原枢纽反复换线的走法
        // 潜力里程可以更短，误差反而更大；按误差排就不会——误差 0 先于误差 1，并列带只用
        // 来放宽「先用线路名少的」。
        final errorLowerBound = edge.toStation == end
            ? (nextDistance - targetDistance).abs()
            : _errorLowerBound(nextDistance, lowerBound, targetDistance);
        queue.add(next, [
          next.usedRouteNames.length.toDouble(),
          errorLowerBound,
          nextDistance + lowerBound,
        ]);
      }
    }
    final acceptedEdges = accepted;
    if (acceptedEdges != null) {
      return _DistanceSearchResult(
        edges: acceptedEdges,
        distance: _edgeDistance(acceptedEdges),
        error: acceptedError,
        matchedTolerance: acceptedError <= _distanceTolerance,
        exploredStates: exploredStates,
        steps: steps,
      );
    }
    final closestDistance = _edgeDistance(closest);
    return _DistanceSearchResult(
      edges: closest,
      distance: closestDistance,
      error: (closestDistance - targetDistance).abs(),
      matchedTolerance: false,
      exploredStates: exploredStates,
      steps: steps,
    );
  }

  Map<String, double> _shortestDistancesFrom(String start) {
    final queue = _MinHeap<_SearchNode>();
    final distances = <String, double>{start: 0};
    queue.add(_SearchNode(station: start, distance: 0), const [0]);
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (current.distance > (distances[current.station] ?? double.infinity)) {
        continue;
      }
      for (final edge in adjacency[current.station] ?? const []) {
        final nextDistance = current.distance + edge.distanceKm;
        if (nextDistance >= (distances[edge.toStation] ?? double.infinity)) {
          continue;
        }
        distances[edge.toStation] = nextDistance;
        queue.add(
          _SearchNode(station: edge.toStation, distance: nextDistance),
          [nextDistance],
        );
      }
    }
    return distances;
  }

  List<_RouteEdge> _reconstructStates(
    Map<String, _RouteStateStep> previous,
    String startKey,
    String endKey,
  ) {
    final edges = <_RouteEdge>[];
    var key = endKey;
    while (key != startKey) {
      final step = previous[key];
      if (step == null) return const [];
      edges.add(step.edge);
      key = step.previousKey;
    }
    return edges.reversed.toList();
  }
}

class _RouteStationEntry {
  const _RouteStationEntry({
    required this.name,
    required this.index,
    required this.mileage,
  });

  final String name;
  final int index;
  final double mileage;
}

class _RouteEdge {
  const _RouteEdge({
    required this.fromStation,
    required this.toStation,
    required this.routeName,
    required this.distanceKm,
  });

  final String fromStation;
  final String toStation;
  final String routeName;
  final double distanceKm;

  _RouteEdge reversed() => _RouteEdge(
    fromStation: toStation,
    toStation: fromStation,
    routeName: routeName,
    distanceKm: distanceKm,
  );
}

/// 把逐条边并成段的结果：一段同线路名、首尾相接、中途没有折返的走法。
class _MergedSection {
  const _MergedSection({
    required this.routeName,
    required this.fromStation,
    required this.toStation,
    required this.mileageKm,
  });

  final String routeName;
  final String fromStation;
  final String toStation;
  final double mileageKm;
}

class _PathResult {
  const _PathResult({
    required this.edges,
    required this.usedShortestPath,
    required this.inferenceLog,
  });

  final List<_RouteEdge> edges;
  final bool usedShortestPath;
  final List<String> inferenceLog;
}

class _DistanceSearchResult {
  const _DistanceSearchResult({
    required this.edges,
    required this.distance,
    required this.error,
    required this.matchedTolerance,
    required this.exploredStates,
    required this.steps,
  });

  final List<_RouteEdge> edges;
  final double distance;
  final double error;
  final bool matchedTolerance;
  final int exploredStates;
  final List<String> steps;
}

class _SearchNode {
  const _SearchNode({required this.station, required this.distance});

  final String station;
  final double distance;
}

/// 搜索状态：走到 [station] 时最后一次用的是哪条线（起点为 null），以及到达它的
/// `[里程, 换线次数]` 代价。
class _RouteState {
  const _RouteState({
    required this.station,
    required this.routeName,
    required this.cost,
  });

  final String station;
  final String? routeName;
  final List<double> cost;

  String get key => _routeStateKey(station, routeName);
}

/// 状态的前驱：上一个状态 + 走过来的那条边。
class _RouteStateStep {
  const _RouteStateStep(this.previousKey, this.edge);

  final String previousKey;
  final _RouteEdge edge;
}

String _routeStateKey(String station, String? routeName) =>
    '$station\u0000${routeName ?? ''}';

/// 各版线路库之间改了名的线路：旧经由名 → 当前库里的线路名。
///
/// 武西高速线、西渝高速线是 2.6.0 以前的写法，当前库按区段拆成了
/// 武西高铁云十段 / 西渝高铁西康段；广深港的三段是 2.6.1 的临时拆法。
/// 只放能唯一落到一条线的改名：宁蓉线、焦柳线这类在库里拆成多条的不在此列，
/// 旧库的经由本来就存区段名。
const Map<String, String> _routeNameAliases = {
  '武西高速线': '武西高铁云十段',
  '武西高铁': '武西高铁云十段',
  '西渝高速线': '西渝高铁西康段',
  '广深港广深': '广深港高速线',
  '广深港福田': '广深港高速线',
  '广深港香港': '广深港高速线',
  '昆万昆磨段': '中老昆万铁路昆磨段',
  '昆万磨万段': '中老昆万铁路磨万段',
};

/// 线路名的宽松键：去掉速度等级词和「铁路/线」。
///
/// 2.6.1 的命名省掉了等级词（「京港高铁合安段」写作「京港合安段」），
/// 「宁西线西合段」也写作「宁西西合段」；当前库恢复成全名。只在精确匹配和
/// 别名表失败时用它兜底，调用方还会要求唯一命中，不能拿它当主键。
String _looseRouteKey(String value) {
  var key = value.trim();
  key = key.replaceAll(RegExp(r'(客运专线|高铁|客专|城际|高速)'), '');
  key = key.replaceAll(RegExp(r'(铁路|线)'), '');
  return key.toLowerCase();
}

class _ExactSearchNode {
  const _ExactSearchNode({
    required this.station,
    required this.distance,
    required this.previous,
    required this.incomingEdge,
    required this.usedRouteNames,
    required this.hopCount,
  });

  final String station;
  final double distance;
  final _ExactSearchNode? previous;
  final _RouteEdge? incomingEdge;
  final Set<String> usedRouteNames;

  /// 走到这儿经过了多少站（几条边）。里程容差按它放宽，见 [_mileageDriftPerHop]。
  final int hopCount;

  bool containsStation(String value) {
    _ExactSearchNode? node = this;
    while (node != null) {
      if (node.station == value) return true;
      node = node.previous;
    }
    return false;
  }

  List<_RouteEdge> get edges {
    final result = <_RouteEdge>[];
    _ExactSearchNode? node = this;
    while (node?.incomingEdge != null) {
      result.add(node!.incomingEdge!);
      node = node.previous;
    }
    return result.reversed.toList();
  }

  String get stateKey {
    final visitedStations = <String>[];
    _ExactSearchNode? node = this;
    while (node != null) {
      visitedStations.add(node.station);
      node = node.previous;
    }
    visitedStations.sort();
    final routes = usedRouteNames.toList()..sort();
    return '$station:${(distance * 10).round()}:${visitedStations.join('|')}:${routes.join('|')}';
  }
}

class _HeapEntry<T> {
  const _HeapEntry(this.value, this.priority);

  final T value;

  /// 按字典序比较：先比第一位，相同再比第二位……位数不同时短的算小。
  final List<double> priority;
}

class _MinHeap<T> {
  final List<_HeapEntry<T>> _items = [];

  bool get isNotEmpty => _items.isNotEmpty;

  /// 队首的优先级，不看值本身。用来判断「剩下的节点里还有没有可能更优的走法」。
  List<double>? get peekPriority =>
      _items.isEmpty ? null : _items.first.priority;

  void add(T value, List<double> priority) {
    _items.add(_HeapEntry(value, priority));
    var index = _items.length - 1;
    while (index > 0) {
      final parent = (index - 1) ~/ 2;
      if (_comparePriority(_items[parent].priority, priority) <= 0) break;
      _items[index] = _items[parent];
      index = parent;
    }
    _items[index] = _HeapEntry(value, priority);
  }

  T removeFirst() {
    final first = _items.first.value;
    final last = _items.removeLast();
    if (_items.isEmpty) return first;

    var index = 0;
    while (true) {
      final left = index * 2 + 1;
      if (left >= _items.length) break;
      final right = left + 1;
      var child = left;
      if (right < _items.length &&
          _comparePriority(_items[right].priority, _items[left].priority) < 0) {
        child = right;
      }
      if (_comparePriority(_items[child].priority, last.priority) >= 0) break;
      _items[index] = _items[child];
      index = child;
    }
    _items[index] = last;
    return first;
  }
}

int _comparePriority(List<double> first, List<double> second) {
  final length = first.length < second.length ? first.length : second.length;
  for (var index = 0; index < length; index++) {
    final comparison = first[index].compareTo(second[index]);
    if (comparison != 0) return comparison;
  }
  return first.length.compareTo(second.length);
}

/// 精确命中：目标里程与选定走法的里程差在这个范围内，就认定是这条走法。
const _distanceTolerance = 0.55;

/// 里程并列带的下限。目标里程和 routes.db 的里程桩不是同一套刻度（1461/1462 的时刻表在
/// 沪宁段每过一个站就比里程桩多 1 km），这类差不足以说明走法不同：宁可要「误差再大一点
/// 但始终待在同一条线上」的走法，也不要「误差小一点却要借道一条平行线」的走法。误差落在
/// 这个带内算里程并列，并列时取用到的线路名最少的走法（与 `_shortestPath` 的次级判据一致）。
const _distanceTieBand = 1.0;

/// 每多经过一站允许的额外误差。时刻表的累计里程和 routes.db 的里程桩是两套刻度，偏差
/// **逐站累积**（沪宁段每过一站就差 1 km），走法越长差得越多，所以并列带不能是个固定值。
/// 带子太窄，「终点前一站换到平行的另一条线上」那种里程更贴目标、但多用一个线路名的借道
/// 走法就会冒头；按每站 0.5 km 放宽后，线路名少的那条才保得住。
const _mileageDriftPerHop = 0.5;

const _maxExactSearchStates = 150000;
const _maxInferenceLogSteps = 200;

/// 把逐条边并成段：线路名相同、上一条的终点就是下一条的起点，就并进同一段。
///
/// 折返（换向）处断开——车会在同一条线上原路退回去，必然重复经过本段已经走过的某一站。
/// 例如 T7 在 西安 换向，陇海线 新丰镇→…→灞桥→西安 之后接着 西安→灞桥→田王：合起来会得到
/// 一段自相重叠的走法（首尾同名只是其中最极端的一种）。展开站表和贴轨都只能按
/// 「线路名 + 首尾站」查，重叠的那一段会被抹掉，换向站本身也会整站丢掉。断开后记成
/// 新丰镇→西安、西安→灞桥 两段，折返那一段在两边各出现一次，里程也一样对得上。
List<_MergedSection> _mergeSections(List<_RouteEdge> edges) {
  if (edges.isEmpty) return const [];
  final sections = <_MergedSection>[];
  var routeName = edges.first.routeName;
  var fromStation = edges.first.fromStation;
  var toStation = edges.first.toStation;
  var mileage = edges.first.distanceKm;
  // 本段已经走过的站。新的一段从当前边的起点算起，不带上一段的历史。
  var runStations = <String>{fromStation, toStation};

  for (final edge in edges.skip(1)) {
    final isReversal = runStations.contains(edge.toStation);
    if (edge.routeName == routeName &&
        edge.fromStation == toStation &&
        !isReversal) {
      toStation = edge.toStation;
      mileage += edge.distanceKm;
      runStations.add(edge.toStation);
      continue;
    }
    sections.add(
      _MergedSection(
        routeName: routeName,
        fromStation: fromStation,
        toStation: toStation,
        mileageKm: mileage,
      ),
    );
    routeName = edge.routeName;
    fromStation = edge.fromStation;
    toStation = edge.toStation;
    mileage = edge.distanceKm;
    runStations = {fromStation, toStation};
  }
  sections.add(
    _MergedSection(
      routeName: routeName,
      fromStation: fromStation,
      toStation: toStation,
      mileageKm: mileage,
    ),
  );
  return sections;
}

double _edgeDistance(List<_RouteEdge> edges) =>
    edges.fold(0, (sum, edge) => sum + edge.distanceKm);

/// 一条经过 [hops] 站的走法允许差多少里程：刻度差逐站累积（见 [_mileageDriftPerHop]），
/// 短走法至少留 [_distanceTieBand]。
double _mileageTieBand(int hops) {
  final drifted = _mileageDriftPerHop * hops;
  return drifted > _distanceTieBand ? drifted : _distanceTieBand;
}

/// 一条经过 [hops] 站的走法的接受门槛：精确容差 + 它自己的刻度差允许量。
double _matchTolerance(int hops) => _distanceTolerance + _mileageTieBand(hops);

/// 走到 [distance] 时，最终里程与 [target] 至少还差多少（[lowerBound] 是当前位置到终点的
/// 最短距离）。已经越过目标时误差不可能再缩小，就是超出的部分；还没到的时候可能正好命中，
/// 下界是 0。
double _errorLowerBound(double distance, double lowerBound, double target) {
  final potential = distance + lowerBound;
  return potential > target ? potential - target : 0;
}

String _describeEdges(List<_RouteEdge> edges) {
  if (edges.isEmpty) return '无';
  return _mergeSections(edges)
      .map(
        (section) =>
            '${section.routeName}（${section.fromStation} → ${section.toStation}）',
      )
      .join('；');
}

String _formatDistance(double value) {
  final rounded = value.roundToDouble();
  return value == rounded
      ? rounded.toInt().toString()
      : value.toStringAsFixed(1);
}

void _addSearchStep(List<String> steps, String entry) {
  if (steps.length < _maxInferenceLogSteps) {
    steps.add(entry);
  } else if (steps.length == _maxInferenceLogSteps) {
    steps.add('候选记录过多，后续改进过程已省略');
  }
}
