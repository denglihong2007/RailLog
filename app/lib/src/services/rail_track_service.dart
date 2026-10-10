import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path_util;
import 'package:raillog/src/services/database_path_service.dart';
import 'package:sqflite/sqflite.dart';

/// 站间轨道折线的内存索引。
///
/// 键为 `线路名|起点站|终点站`（三段都按 [trackKeyOf] 归一化），值是 WGS84 的
/// 折线点。折线由 tools/osm_update/build_rail_tracks.py 离线生成、打包进
/// assets/db/rail_tracks.db。
class RailTrackIndex {
  const RailTrackIndex._(this._tracks);

  /// 空索引：查任何段都返回 null，绘制退回站间直线。
  const RailTrackIndex.empty() : _tracks = const {};

  final Map<String, List<List<double>>> _tracks;

  int get length => _tracks.length;

  /// 查一段折线，**并把它摆成 `from→to` 走向**；没有对应数据时返回 null，
  /// 调用方回退为直线。
  ///
  /// 管线只按一个走向存一行，一趟车走过的方向不一定有那一行——这时用反向键再查
  /// 一次，并把点序倒过来。**不能直接把反向命中的原样交出去**：调用方会把它当成
  /// `from→to` 的点列（首尾各补一个站坐标），于是画成「站间直线 + 倒着走的真轨 +
  /// 站间直线」的往返折返，地图上就是真轨旁边多出一条直线。
  List<List<double>>? findOriented(String routeName, String from, String to) {
    final forward = _tracks[trackKeyOf(routeName, from, to)];
    if (forward != null) return forward;
    final backward = _tracks[trackKeyOf(routeName, to, from)];
    return backward?.reversed.toList();
  }

  static RailTrackIndex fromBatches(List<Map<String, Object?>> rows) {
    final tracks = <String, List<List<double>>>{};
    for (final row in rows) {
      final routeName = row['route_name']?.toString() ?? '';
      final from = row['from_station']?.toString() ?? '';
      final to = row['to_station']?.toString() ?? '';
      final blob = row['polyline'];
      if (routeName.isEmpty || from.isEmpty || to.isEmpty || blob is! List<int>) {
        continue;
      }
      try {
        final points = _decodePolyline(blob);
        if (points.length < 2) continue;
        tracks[trackKeyOf(routeName, from, to)] = points;
      } on FormatException {
        continue; // 单条数据损坏不影响其余折线
      } on TypeError {
        continue; // 结构不是 [[lat, lon], ...] 时同样跳过
      }
    }
    return RailTrackIndex._(tracks);
  }

  /// 解 `gzip(JSON([[lat, lon], ...]))`，与管线端 encode_polyline 对应。
  static List<List<double>> _decodePolyline(List<int> blob) {
    final decoded = jsonDecode(utf8.decode(gzip.decode(blob)));
    return [
      for (final point in decoded as List<dynamic>)
        [for (final value in point as List<dynamic>) (value as num).toDouble()],
    ];
  }
}

/// 管线解析出的车站坐标（rail_tracks.db 的 `stations` 表）。
///
/// 坐标取自 OSM 的 `railway=station/halt` 节点——那些点就落在轨道上，比
/// coordinates.csv 可靠：同名异地错配的站、CSV 里缺坐标的站，都能在这里修正。
/// 站名保持原样不归一化，查询交给 [StationCoordinateIndex.fromSources]，避免
/// 归一化规则出现第二份实现。
///
/// 值为**空列表**表示「管线知道这个站，但判定它没有可信坐标」（与前后站的直线
/// 距离都对不上里程）——写成 NULL 行。它与「表里没有这一个站」是两回事：后者可以
/// 退回 coordinates.csv，前者必须把 CSV 的同名值一并丢掉，否则被舍掉的错坐标会从
/// 兜底路径原样回来。见 [StationCoordinateIndex.fromSources]。
class RailStationIndex {
  const RailStationIndex._(this._stations);

  /// 空索引：调用方退回 coordinates.csv。
  const RailStationIndex.empty() : _stations = const {};

  /// 原始站名 → [纬度, 经度]。
  final Map<String, List<double>> _stations;

  /// 原始站名 → [纬度, 经度]；供 StationCoordinateIndex 归一化后建索引。
  Map<String, List<double>> get all => _stations;

  int get length => _stations.length;

  bool get isEmpty => _stations.isEmpty;

  static RailStationIndex fromBatches(List<Map<String, Object?>> rows) {
    final stations = <String, List<double>>{};
    for (final row in rows) {
      final name = row['station_name']?.toString() ?? '';
      if (name.isEmpty) continue;
      final latitude = (row['latitude'] as num?)?.toDouble();
      final longitude = (row['longitude'] as num?)?.toDouble();
      if (latitude == null || longitude == null) {
        // 坐标为 NULL：管线知道这个站，但判定它没有可信坐标（前后站里程对不上），
        // 于是显式记为「未知」。空列表与「表里没有这个站」含义不同——前者不许
        // 回退 coordinates.csv（见 StationCoordinateIndex.fromSources）。
        stations[name] = const [];
        continue;
      }
      if (latitude < -90 || latitude > 90) continue;
      if (longitude < -180 || longitude > 180) continue;
      stations[name] = [latitude, longitude];
    }
    return RailStationIndex._(stations);
  }
}

/// rail_tracks.db 的全部内容：折线 + 车站坐标。一次打开连接读完，避免开两次库。
class RailTrackData {
  const RailTrackData({required this.tracks, required this.stations});

  const RailTrackData.empty()
      : tracks = const RailTrackIndex.empty(),
        stations = const RailStationIndex.empty();

  final RailTrackIndex tracks;
  final RailStationIndex stations;
}

/// 查折线用的键。必须与 tools/osm_update/rail_track_geometry.py 的 `track_key` 一致，
/// 否则管线生成的折线一条都查不到。
String trackKeyOf(String routeName, String from, String to) =>
    '${_routeKey(routeName)}|${_stationKey(from)}|${_stationKey(to)}';

/// 去掉「铁路/线」后缀并转小写，与 RouteService 解析线路名的做法一致。
String _routeKey(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.replaceFirst(RegExp(r'(铁路|线)$'), '').toLowerCase();
}

/// 站名归一化：去掉尾部括号注释与「站/火车站」后缀、去掉空白、转小写。
String _stationKey(String value) {
  final trimmed = value.trim().replaceAll('（', '(').replaceAll('）', ')');
  if (trimmed.isEmpty) return '';
  var normalized = trimmed.replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '');
  normalized = normalized.replaceFirst(RegExp(r'(火车站|站)$'), '');
  normalized = normalized.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  return normalized.isEmpty ? trimmed.toLowerCase() : normalized;
}

class RailTrackService {
  RailTrackService._();

  static Future<RailTrackData>? _dataRequest;

  /// 幂等加载；与 RouteService.loadGraph 一样，把打包的数据库拷到可写目录后
  /// 以只读方式打开，读出内存索引即可关闭连接。
  static Future<RailTrackData> loadData() => _dataRequest ??= _open();

  /// 只要折线时的便捷入口（只读 `tracks` 表的老路径）。
  static Future<RailTrackIndex> loadTracks() async =>
      (await loadData()).tracks;

  /// 供测试重置静态缓存。
  static void resetForTesting() {
    _dataRequest = null;
  }

  static Future<RailTrackData> _open() async {
    final data = await rootBundle.load('assets/db/rail_tracks.db');
    final databasesPath = await DatabasePathService.directory();
    final databasePath = path_util.join(databasesPath, 'rail_tracks_reference.db');
    await Directory(databasesPath).create(recursive: true);
    await File(databasePath).writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );

    final database = await openDatabase(databasePath, readOnly: true);
    try {
      final rows = await database.rawQuery(
        'SELECT route_name, from_station, to_station, polyline FROM tracks',
      );
      return RailTrackData(
        tracks: RailTrackIndex.fromBatches(rows),
        stations: RailStationIndex.fromBatches(await _stationRows(database)),
      );
    } finally {
      await database.close();
    }
  }

  /// 读 `stations` 表；老库（或 --stub 生成的库）可能没有这张表，当作没有坐标。
  static Future<List<Map<String, Object?>>> _stationRows(
    Database database,
  ) async {
    try {
      return await database.rawQuery(
        'SELECT station_name, latitude, longitude FROM stations',
      );
    } on DatabaseException {
      return const [];
    }
  }
}
