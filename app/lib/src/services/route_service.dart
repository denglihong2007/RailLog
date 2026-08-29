import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path_util;
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

  static Future<Map<String, List<String>>> resolveTripStations(
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

  static RouteResolution _resolveJourney(
    _RouteGraph graph,
    List<StationPairDistance> sections,
  ) {
    final allEdges = <_RouteEdge>[];
    final unresolved = <String>[];
    final inferenceLog = <String>[];
    var usedShortestPath = false;

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
      );
      if (result == null) {
        unresolved.add('${section.fromStation}-${section.toStation}');
        inferenceLog.add('结果：站点不存在或线路图中不可达');
        continue;
      }
      inferenceLog.addAll(result.inferenceLog);
      allEdges.addAll(result.edges);
      usedShortestPath = usedShortestPath || result.usedShortestPath;
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
      final rows = await database.rawQuery('''
        SELECT
          r.route_name,
          s.route_version_id,
          s.station_index,
          s.station_name,
          s.mileage
        FROM stations s
        JOIN routes r ON r.route_version_id = s.route_version_id
        ORDER BY s.route_version_id, s.station_index
      ''');
      return _RouteGraph.fromRows(rows);
    } finally {
      await database.close();
    }
  }

  static List<ViaRouteSegment> _mergeEdges(List<_RouteEdge> edges) {
    if (edges.isEmpty) return const [];
    final segments = <ViaRouteSegment>[];
    var routeName = edges.first.routeName;
    var fromStation = edges.first.fromStation;
    var toStation = edges.first.toStation;
    var mileage = edges.first.distanceKm;

    for (final edge in edges.skip(1)) {
      if (edge.routeName == routeName && edge.fromStation == toStation) {
        toStation = edge.toStation;
        mileage += edge.distanceKm;
        continue;
      }
      segments.add(
        ViaRouteSegment(
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
    }
    segments.add(
      ViaRouteSegment(
        routeName: routeName,
        fromStation: fromStation,
        toStation: toStation,
        mileageKm: mileage,
      ),
    );
    return segments;
  }
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
    final stations = routeStationIndexes[routeName];
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

  List<String> stationsForJourney(
    String fromStation,
    String toStation,
    List<ViaRouteSegment> segments,
  ) {
    if (segments.isEmpty) return [fromStation, toStation];

    final stations = <String>[];
    void append(String station) {
      if (station.isNotEmpty &&
          (stations.isEmpty || stations.last != station)) {
        stations.add(station);
      }
    }

    append(fromStation.trim());
    for (final segment in segments) {
      final routeName = _resolveRouteName(segment.routeName);
      final section = routeName == null
          ? null
          : _stationsBetweenOnRoute(
              routeName,
              segment.fromStation,
              segment.toStation,
            );
      if (section == null || section.isEmpty) {
        append(segment.fromStation.trim());
        append(segment.toStation.trim());
        continue;
      }
      for (final station in section) {
        append(station);
      }
    }
    append(toStation.trim());
    return stations;
  }

  factory _RouteGraph.fromRows(List<Map<String, Object?>> rows) {
    final adjacency = <String, List<_RouteEdge>>{};
    final routeStationIndexes = <String, Map<String, _RouteStationEntry>>{};
    String? currentRouteId;
    String? previousStation;
    double? previousMileage;

    for (final row in rows) {
      final routeId = row['route_version_id']?.toString();
      final routeName = row['route_name']?.toString().trim() ?? '';
      final station = row['station_name']?.toString().trim() ?? '';
      final mileage = (row['mileage'] as num?)?.toDouble();
      final stationIndex = (row['station_index'] as num?)?.toInt();
      if (routeId == null ||
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

      if (routeId != currentRouteId) {
        currentRouteId = routeId;
        previousStation = null;
        previousMileage = null;
      }
      if (previousStation != null && previousStation != station) {
        final distance = (mileage - previousMileage!).abs();
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

    final shortest = _shortestPath(start, end);
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
    );
    return _PathResult(
      edges: search.edges,
      usedShortestPath: identical(search.edges, shortest),
      inferenceLog: [
        '最短路径里程：${_formatDistance(_edgeDistance(shortest))} km',
        ...search.steps,
        '搜索状态数：${search.exploredStates}',
        search.matchedTolerance ? '结果：找到容差内匹配路径' : '结果：未找到容差内路径，采用里程最接近路径',
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
    final start = _resolveStationName(fromStation);
    final end = _resolveStationName(toStation);
    if (start == null || end == null) return null;
    if (start == end) return 0;
    final edges = _shortestPath(start, end, routeName: routeName);
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
    return matches.length == 1 ? matches.single : null;
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

  List<_RouteEdge>? _shortestPath(
    String start,
    String end, {
    String? routeName,
  }) {
    final queue = _MinHeap<_SearchNode>();
    final distances = <String, double>{start: 0};
    final previous = <String, _PreviousStep>{};
    queue.add(_SearchNode(station: start, distance: 0), 0);

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (current.distance > (distances[current.station] ?? double.infinity)) {
        continue;
      }
      if (current.station == end) return _reconstruct(previous, start, end);

      for (final edge in adjacency[current.station] ?? const []) {
        if (routeName != null && edge.routeName != routeName) continue;
        final nextDistance = current.distance + edge.distanceKm;
        if (nextDistance >= (distances[edge.toStation] ?? double.infinity)) {
          continue;
        }
        distances[edge.toStation] = nextDistance;
        previous[edge.toStation] = _PreviousStep(current.station, edge);
        queue.add(
          _SearchNode(station: edge.toStation, distance: nextDistance),
          nextDistance,
        );
      }
    }
    return null;
  }

  _DistanceSearchResult _distanceMatchingOrClosestPath(
    String start,
    String end,
    double targetDistance,
    List<_RouteEdge> shortest,
  ) {
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
      usedRouteNames: const {},
    );
    final routePriorityBand = targetDistance + _distanceTolerance + 1;
    queue.add(startNode, startLowerBound);
    final visited = <String>{startNode.stateKey};
    var exploredStates = 0;

    while (queue.isNotEmpty && exploredStates < _maxExactSearchStates) {
      final current = queue.removeFirst();
      exploredStates++;
      if (current.station == end) {
        final error = (current.distance - targetDistance).abs();
        if (error <= _distanceTolerance) {
          _addSearchStep(
            steps,
            '容差内候选：${_formatDistance(current.distance)} km，误差 ${_formatDistance(error)} km',
          );
          return _DistanceSearchResult(
            edges: current.edges,
            distance: current.distance,
            error: error,
            matchedTolerance: true,
            exploredStates: exploredStates,
            steps: steps,
          );
        }
        if (error < closestError) {
          closest = current.edges;
          closestError = error;
          _addSearchStep(
            steps,
            '更近候选：${_formatDistance(current.distance)} km，误差 ${_formatDistance(error)} km',
          );
        }
        continue;
      }

      for (final edge in adjacency[current.station] ?? const []) {
        if (current.containsStation(edge.toStation)) continue;
        final nextDistance = current.distance + edge.distanceKm;
        final lowerBound = lowerBounds[edge.toStation];
        if (lowerBound == null ||
            nextDistance > targetDistance + closestError ||
            nextDistance + lowerBound > targetDistance + closestError) {
          continue;
        }
        final next = _ExactSearchNode(
          station: edge.toStation,
          distance: nextDistance,
          previous: current,
          incomingEdge: edge,
          usedRouteNames: {...current.usedRouteNames, edge.routeName},
        );
        if (!visited.add(next.stateKey)) continue;
        queue.add(
          next,
          next.usedRouteNames.length * routePriorityBand +
              nextDistance +
              lowerBound,
        );
      }
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
    queue.add(_SearchNode(station: start, distance: 0), 0);
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
          nextDistance,
        );
      }
    }
    return distances;
  }

  List<_RouteEdge> _reconstruct(
    Map<String, _PreviousStep> previous,
    String start,
    String end,
  ) {
    final edges = <_RouteEdge>[];
    var current = end;
    while (current != start) {
      final step = previous[current];
      if (step == null) return const [];
      edges.add(step.edge);
      current = step.station;
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

class _PreviousStep {
  const _PreviousStep(this.station, this.edge);

  final String station;
  final _RouteEdge edge;
}

class _ExactSearchNode {
  const _ExactSearchNode({
    required this.station,
    required this.distance,
    required this.previous,
    required this.incomingEdge,
    required this.usedRouteNames,
  });

  final String station;
  final double distance;
  final _ExactSearchNode? previous;
  final _RouteEdge? incomingEdge;
  final Set<String> usedRouteNames;

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
  final double priority;
}

class _MinHeap<T> {
  final List<_HeapEntry<T>> _items = [];

  bool get isNotEmpty => _items.isNotEmpty;

  void add(T value, double priority) {
    _items.add(_HeapEntry(value, priority));
    var index = _items.length - 1;
    while (index > 0) {
      final parent = (index - 1) ~/ 2;
      if (_items[parent].priority <= priority) break;
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
          _items[right].priority < _items[left].priority) {
        child = right;
      }
      if (_items[child].priority >= last.priority) break;
      _items[index] = _items[child];
      index = child;
    }
    _items[index] = last;
    return first;
  }
}

const _distanceTolerance = 0.55;
const _maxExactSearchStates = 150000;
const _maxInferenceLogSteps = 200;

double _edgeDistance(List<_RouteEdge> edges) =>
    edges.fold(0, (sum, edge) => sum + edge.distanceKm);

String _describeEdges(List<_RouteEdge> edges) {
  if (edges.isEmpty) return '无';
  final sections = <String>[];
  var routeName = edges.first.routeName;
  var fromStation = edges.first.fromStation;
  var toStation = edges.first.toStation;
  for (final edge in edges.skip(1)) {
    if (edge.routeName == routeName && edge.fromStation == toStation) {
      toStation = edge.toStation;
      continue;
    }
    sections.add('$routeName（$fromStation → $toStation）');
    routeName = edge.routeName;
    fromStation = edge.fromStation;
    toStation = edge.toStation;
  }
  sections.add('$routeName（$fromStation → $toStation）');
  return sections.join('；');
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
