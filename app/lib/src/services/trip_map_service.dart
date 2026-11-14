import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:raillog/src/models/journey_stations.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/map_settings.dart';
import 'package:raillog/src/services/rail_track_service.dart';

class StationCoordinate {
  const StationCoordinate({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  List<double> get amapPosition => _wgs84ToGcj02(latitude, longitude);
}

enum TripMapDirection { direction1, direction2, bidirectional }

class TripMapRouteEntry {
  const TripMapRouteEntry({
    required this.trainNumber,
    required this.departureDate,
    required this.direction,
    this.tripId,
    this.ticketId,
  });

  final String trainNumber;
  final DateTime departureDate;
  final TripMapDirection direction;

  /// 行程在本地库里的 id；他人主页的公开行程是负数（`-ticketId`）。
  final int? tripId;

  /// 已同步到服务端的票据 id，本机尚未同步的行程为 null。
  final int? ticketId;
}

/// 地图弹窗里点中的那一趟行程。
///
/// 两个 id 至少有一个非空：自己主页的行程用 [tripId] 打开本地详情，他人主页的
/// 公开行程用 [ticketId] 打开只读详情。
class TripMapTripRef {
  const TripMapTripRef({this.tripId, this.ticketId});

  final int? tripId;
  final int? ticketId;
}

class TripMapEndpoint {
  const TripMapEndpoint({required this.station, required this.coordinate});

  final String station;
  final StationCoordinate coordinate;
}

class TripMapRoute {
  const TripMapRoute({
    required this.name,
    this.lineName,
    this.color,
    this.entries = const [],
    this.direction = TripMapDirection.direction1,
    required this.fromStation,
    required this.toStation,
    required this.fromCoordinate,
    required this.toCoordinate,
    required this.points,
  });

  final String name;

  /// 这一段所走的线路名（可能来自线路库的规范名）；查不到时为 null。
  ///
  /// 上层用它给折线配简图里同一条线路的颜色。
  final String? lineName;

  /// 折线的 CSS 颜色。为空时按经过次数/上下行着色（多行程地图的默认样式）。
  final String? color;

  final List<TripMapRouteEntry> entries;
  final TripMapDirection direction;
  final String fromStation;
  final String toStation;
  final StationCoordinate? fromCoordinate;
  final StationCoordinate? toCoordinate;
  final List<StationCoordinate> points;

  TripMapRoute withColor(String? color) => TripMapRoute(
    name: name,
    lineName: lineName,
    color: color,
    entries: entries,
    direction: direction,
    fromStation: fromStation,
    toStation: toStation,
    fromCoordinate: fromCoordinate,
    toCoordinate: toCoordinate,
    points: points,
  );
}

class TripMapData {
  const TripMapData({
    required this.routes,
    required this.endpoints,
    required this.tripCount,
    required this.mappedTripCount,
    required this.missingViaRouteCount,
    required this.missingStations,
  });

  final List<TripMapRoute> routes;
  final List<TripMapEndpoint> endpoints;
  final int tripCount;
  final int mappedTripCount;
  final int missingViaRouteCount;
  final Set<String> missingStations;
}

class StationCoordinateIndex {
  StationCoordinateIndex._(this._coordinates);

  final Map<String, StationCoordinate> _coordinates;

  factory StationCoordinateIndex.fromCsv(String csv) =>
      StationCoordinateIndex._(_parseCsv(csv));

  /// 管线（rail_tracks.db 的 `stations` 表）为权威，coordinates.csv 只补它没有的站。
  ///
  /// 那张表是离线用**线路几何**消歧过的：同名车站节点在全国有几十个，管线按
  /// 「正确的新立屯必然紧邻名为新义线的轨道」这类约束挑出对的那个。所以它可以
  /// 无条件采信，包括与 CSV 相距上千公里的值——新立屯正是这种，CSV 命中了内蒙古
  /// 的同名村庄，只有这套消歧能把它挪回辽宁。
  ///
  /// 这里曾经有一条「OSM 值必须落在 CSV 的 30km 内才采信」的守卫，本意是防 OSM
  /// 的 first-wins 挑到外省同名节点。但那同时也把「CSV 错、OSM 对且相距很远」
  /// 一并挡掉了，正是最需要修的那一类。消歧搬到管线侧之后，这条守卫就成了纯粹的
  /// 阻碍：管线已经给出结论，App 不该再质疑一遍。管线侧仍保留同款守卫，用于那些
  /// **没有**线路上下文、无法消歧的站。
  ///
  /// [resolvedStations] 里值为**空列表**的键是第三种情况，也是唯一会删东西的一种：
  /// 「管线知道这个站，但判定它没有可信坐标」（与前后站的直线距离都对不上里程，
  /// 见管线侧的 discard_implausible_station_coordinates）。这类键必须把
  /// coordinates.csv 里的同名值一并删掉——那个值正是被舍掉的错坐标，留着就会从
  /// 兜底路径原样回来，地图照旧画到错误省份。被删的站在 [buildData] 里等同无坐标，
  /// 前后两站自动桥接成一段（管线也为这段写了折线，坐标对得上，能直接命中）。
  ///
  /// 删除统一放在所有写入之后：同一个站可能有两种写法（「永乐」与「永乐站」）分属
  /// 不同来源，先删后写会让 CSV 值顺着另一个键回来。
  factory StationCoordinateIndex.fromSources(
    Map<String, List<double>> resolvedStations,
    String csv,
  ) {
    final coordinates = _parseCsv(csv);
    final explicitlyUnknown = <String>[];
    for (final entry in resolvedStations.entries) {
      final values = entry.value;
      if (values.isEmpty) {
        // 归一化后为空的站名（全空白）没有键可删；它本来也查不到，跳过即可。
        final keys = _stationKeys(entry.key);
        if (keys.isNotEmpty) explicitlyUnknown.add(keys.last);
        continue;
      }
      if (values.length < 2) continue;
      final latitude = values[0];
      final longitude = values[1];
      if (!latitude.isFinite || !longitude.isFinite) continue;
      if (latitude < -90 || latitude > 90) continue;
      if (longitude < -180 || longitude > 180) continue;
      final coordinate = StationCoordinate(
        latitude: latitude,
        longitude: longitude,
      );
      for (final key in _stationKeys(entry.key)) {
        coordinates[key] = coordinate;
      }
    }
    // 删掉所有归一化后与它同属一个站的键，而不是只删同名的那个：同一个站可能以
    // 多种写法进了索引（CSV 一行「永乐」、OSM 节点叫「永乐站」），留着另一种写法
    // 就等于这个站没被舍去，错坐标照旧画到地图上。
    for (final unknown in explicitlyUnknown) {
      coordinates.removeWhere((key, _) => _stationKeys(key).contains(unknown));
    }
    return StationCoordinateIndex._(coordinates);
  }

  static Map<String, StationCoordinate> _parseCsv(String csv) {
    final coordinates = <String, StationCoordinate>{};
    for (final line in const LineSplitter().convert(csv).skip(1)) {
      final lastComma = line.lastIndexOf(',');
      if (lastComma <= 0) continue;
      final secondLastComma = line.lastIndexOf(',', lastComma - 1);
      if (secondLastComma <= 0) continue;

      final name = line.substring(0, secondLastComma).trim();
      final latitude = double.tryParse(
        line.substring(secondLastComma + 1, lastComma).trim(),
      );
      final longitude = double.tryParse(line.substring(lastComma + 1).trim());
      if (name.isEmpty || latitude == null || longitude == null) continue;

      final coordinate = StationCoordinate(
        latitude: latitude,
        longitude: longitude,
      );
      for (final key in _stationKeys(name)) {
        coordinates.putIfAbsent(key, () => coordinate);
      }
    }
    return coordinates;
  }

  StationCoordinate? find(String station) {
    for (final key in _stationKeys(station)) {
      final coordinate = _coordinates[key];
      if (coordinate != null) return coordinate;
    }
    return null;
  }
}

class TripMapService {
  TripMapService._();

  static Future<String>? _csvRequest;

  /// 打包的 coordinates.csv 原文，只读一次。
  ///
  /// 调用方拿它和 rail_tracks.db 的车站坐标一起交给
  /// [StationCoordinateIndex.fromSources]：OSM 主源、CSV 兜底。
  static Future<String> loadCoordinatesCsv() =>
      _csvRequest ??= rootBundle.loadString('assets/db/coordinates.csv');

  static TripMapData buildData(
    Iterable<TripRecord> trips,
    StationCoordinateIndex coordinates, {
    Map<String, JourneyStations> journeyStations = const {},
    RailTrackIndex? tracks,
    DateTime? start,
    DateTime? endExclusive,
    bool mergeAcrossLines = true,
  }) {
    final routeGroups = <String, _TripMapRouteGroup>{};
    final endpoints = <String, TripMapEndpoint>{};
    final missingStations = <String>{};
    var tripCount = 0;
    var mappedTripCount = 0;
    var missingViaRouteCount = 0;

    for (final trip in trips) {
      if (!trip.isRailTrip ||
          (start != null && trip.departureTime.isBefore(start)) ||
          (endExclusive != null &&
              !trip.departureTime.isBefore(endExclusive))) {
        continue;
      }
      tripCount++;
      if (trip.viaRouteSegments.isEmpty ||
          trip.viaRouteSegments.every(
            (segment) => segment.routeName.trim().isEmpty,
          )) {
        missingViaRouteCount++;
        continue;
      }

      final journey = journeyStations[trip.clientId];
      final stationNames = journey?.stations ?? _fallbackStationNames(trip);
      final stationRouteNames =
          journey?.legRouteNames ?? _fallbackLegRouteNames(trip);
      final locatedStations =
          <({String name, StationCoordinate coordinate, String routeName})>[];
      for (var index = 0; index < stationNames.length; index++) {
        final station = stationNames[index];
        final coordinate = coordinates.find(station);
        if (coordinate == null) {
          final normalized = station.trim();
          if (normalized.isNotEmpty) missingStations.add(normalized);
          continue;
        }
        if (locatedStations.isNotEmpty &&
            locatedStations.last.coordinate.latitude == coordinate.latitude &&
            locatedStations.last.coordinate.longitude == coordinate.longitude) {
          continue;
        }
        locatedStations.add((
          name: station,
          coordinate: coordinate,
          // 站点被坐标去重折叠后，离开这一站的线路名取自被保留的那个站。
          routeName: index < stationRouteNames.length
              ? stationRouteNames[index]
              : '',
        ));
      }
      if (locatedStations.length < 2) continue;
      mappedTripCount++;
      _addEndpoint(endpoints, trip.fromStation, coordinates);
      _addEndpoint(endpoints, trip.toStation, coordinates);

      for (var index = 0; index < locatedStations.length - 1; index++) {
        final from = locatedStations[index];
        final to = locatedStations[index + 1];
        final forwardKey = _routeKey([from.coordinate, to.coordinate]);
        final reverseKey = _routeKey([to.coordinate, from.coordinate]);
        final pairKey = forwardKey.compareTo(reverseKey) <= 0
            ? forwardKey
            : reverseKey;
        // 一对坐标可能被两条线路共用：客专线与普速线在同一个城市各有一个坐标接近的
        // 车站，客里表把它们并到一处；只按坐标建组就会把两条线的车并到同一条折线上
        // （宝成线的车画到西成客专上，反之亦然）。线路名一起进键，各查各自的折线。
        // 没有线路名的段自成一组画直线，最后被 [_absorbShadowedStraightRoutes] 并进
        // 盖住它的那条真实折线，不会多画。
        final key = '$pairKey\u0001${_lineKey(from.routeName)}';
        final group = routeGroups.putIfAbsent(
          key,
          () => _TripMapRouteGroup(
            tracks: tracks,
            fromStation: from.name,
            toStation: to.name,
            fromCoordinate: from.coordinate,
            toCoordinate: to.coordinate,
          ),
        );
        group.addTrip(
          trip.trainNumber.trim(),
          trip.departureTime,
          from.routeName,
          from.coordinate,
          tripId: trip.id,
          ticketId: trip.ticketId,
        );
      }
    }

    final routes = _absorbShadowedStraightRoutes(
      _mergeAdjacentRoutes(
        routeGroups.values.map((group) => group.toRoute()).toList(),
        mergeAcrossLines: mergeAcrossLines,
      ),
    );

    return TripMapData(
      routes: routes,
      endpoints: endpoints.values.toList(),
      tripCount: tripCount,
      mappedTripCount: mappedTripCount,
      missingViaRouteCount: missingViaRouteCount,
      missingStations: missingStations,
    );
  }

  /// 没有解析出经停站时的退化站序列：起始站 + 各段终到站 + 行程终到站。
  static List<String> _fallbackStationNames(TripRecord trip) => [
    trip.fromStation,
    ...trip.viaRouteSegments.map((segment) => segment.toStation),
    trip.toStation,
  ];

  /// 与 [_fallbackStationNames] 对齐的每段线路名。
  ///
  /// 段序列比站序列少一个，末段的终到站到行程终到站那一段同样归给最后一条线路，
  /// 这样它也有机会查到折线。
  static List<String> _fallbackLegRouteNames(TripRecord trip) {
    final segments = trip.viaRouteSegments;
    if (segments.isEmpty) return const [];
    return [
      for (final segment in segments) segment.routeName,
      segments.last.routeName,
    ];
  }
}

/// 把一条折线拼成「起点站坐标 + 折线中间点 + 终点站坐标」。
///
/// 首尾强制用坐标表里的精确站坐标——折线端点本来也是它，但只有保证完全一致，
/// 相邻区段的合并与往返方向判定才不会失配。
List<StationCoordinate> _trackPoints(
  List<List<double>>? track,
  StationCoordinate from,
  StationCoordinate to,
) {
  final points = <StationCoordinate>[from];
  for (final point in track ?? const <List<double>>[]) {
    final coordinate = StationCoordinate(
      latitude: point[0],
      longitude: point[1],
    );
    if (!_sameCoordinate(coordinate, points.last)) points.add(coordinate);
  }
  if (!_sameCoordinate(to, points.last)) points.add(to);
  return points;
}

String buildAmapHtml(
  List<TripMapRoute> routes, {
  required bool darkMode,
  required String backgroundColor,
  required bool showStationMarkers,
  List<TripMapEndpoint> endpoints = const [],
  MapDetailLevel detailLevel = MapDetailLevel.normal,
  bool colorByRoute = false,
  bool tripLinks = true,
}) {
  final apiBaseUrl = ApiClient.baseUrl.replaceFirst(RegExp(r'/+$'), '');
  // 要素名全是 ASCII，不必像 routeJson 那样做尖括号转义。
  final featuresJson = jsonEncode(detailLevel.features);
  final routeJson = jsonEncode(
    routes
        .map(
          (route) => {
            'name': route.name,
            'lineName': route.lineName,
            'color': route.color,
            'direction': route.direction.name,
            'entries': route.entries
                .map(
                  (entry) => {
                    'trainNumber': entry.trainNumber,
                    'departureDate': _dateOnly(entry.departureDate),
                    'direction': entry.direction.name,
                    'tripId': entry.tripId,
                    'ticketId': entry.ticketId,
                  },
                )
                .toList(),
            'fromStation': route.fromStation,
            'toStation': route.toStation,
            'fromPosition': route.fromCoordinate?.amapPosition,
            'toPosition': route.toCoordinate?.amapPosition,
            'coordinates': route.points
                .map((point) => point.amapPosition)
                .toList(),
          },
        )
        .toList(),
  ).replaceAll('<', r'\u003c');
  final endpointJson = jsonEncode(
    endpoints
        .map(
          (endpoint) => {
            'station': endpoint.station,
            'position': endpoint.coordinate.amapPosition,
          },
        )
        .toList(),
  ).replaceAll('<', r'\u003c');

  return '''<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
  <style>
    html, body, #map { width: 100%; height: 100%; margin: 0; overflow: hidden; background: $backgroundColor; }
    .amap-logo, .amap-copyright { opacity: .62; }
    .amap-marker-label { pointer-events: none; padding: 3px 6px; border: 1px solid rgba(255,255,255,.28); border-radius: 3px; background: rgba(10,16,22,.9); color: #FFF; font: 12px/1.25 sans-serif; box-shadow: 0 1px 4px rgba(0,0,0,.45); white-space: nowrap; }
    .route-popup { width: 268px; max-width: calc(100vw - 32px); max-height: 240px; overflow-y: auto; padding: 4px; border: 1px solid rgba(255,255,255,.24); border-radius: 4px; background: rgba(10,16,22,.94); color: #FFF; font: 12px/1.35 sans-serif; box-shadow: 0 3px 12px rgba(0,0,0,.32); }
    .route-popup-summary { padding: 3px 5px 5px; margin-bottom: 2px; border-bottom: 1px solid rgba(255,255,255,.14); color: rgba(255,255,255,.62); font-size: 11px; }
    .route-popup-list { display: flex; flex-direction: column; gap: 1px; }
    .route-popup-row { display: grid; grid-template-columns: minmax(48px, 1fr) 86px 10px; align-items: center; gap: 5px; padding: 4px 5px; border-bottom: 1px solid rgba(255,255,255,.1); white-space: nowrap; }
    .route-popup-row:last-child { border-bottom: 0; }
    .route-popup-row.is-link { cursor: pointer; border-radius: 3px; }
    .route-popup-row.is-link:hover, .route-popup-row.is-link:focus-visible { background: rgba(255,255,255,.14); outline: none; }
    .route-popup-row strong { overflow: hidden; text-overflow: ellipsis; }
    .route-popup-row span { color: rgba(255,255,255,.76); }
    .route-popup-row .open-hint { color: rgba(255,255,255,.5); text-align: right; font-size: 14px; line-height: 1; }
    .map-legend { position: absolute; top: 12px; left: 12px; z-index: 30; display: flex; align-items: center; gap: 10px; padding: 5px 9px; border-radius: 4px; box-shadow: 0 1px 6px rgba(0,0,0,.25); font: 11px/1.2 sans-serif; pointer-events: none; background: ${darkMode ? 'rgba(10,16,22,.74)' : 'rgba(255,255,255,.9)'}; color: ${darkMode ? '#FFF' : 'rgba(10,16,22,.78)'}; }
    .map-legend-title { opacity: .72; }
    .map-legend-item { display: inline-flex; align-items: center; gap: 4px; }
    .map-legend-sample { display: inline-block; border-radius: 999px; background: ${darkMode ? '#ECFFB1' : '#7A4B00'}; }
    .map-legend-sample.sample-low { width: 14px; height: 3px; opacity: .55; }
    .map-legend-sample.sample-high { width: 24px; height: 7px; }
  </style>
</head>
<body>
  <div id="map"></div>
  <div class="map-legend" aria-hidden="true">
    <span class="map-legend-title">经过次数</span>
    <span class="map-legend-item"><i class="map-legend-sample sample-low"></i>少</span>
    <span class="map-legend-item"><i class="map-legend-sample sample-high"></i>多</span>
  </div>
  <script src="$apiBaseUrl/api/amap/sdk/maps.js"></script>
  <script src="$apiBaseUrl/api/amap/sdk/loca.js"></script>
  <script>
    const routes = $routeJson;
    const colorByRoute = $colorByRoute;
    const tripLinks = $tripLinks;
    const directionColor = (direction) =>
      direction === 'direction1' ? '#7DD3FC' : '#FDBA74';

    // 弹窗里的点击要送回宿主（Flutter）才能跳进行程详情。
    // iOS/Android 走 WebViewController 的 JavaScriptChannel，Windows 的
    // WebView2 走 chrome.webview。两边都收到同一段 JSON 文本。
    const postToHost = (message) => {
      const payload = JSON.stringify(message);
      if (window.TripMapBridge && typeof window.TripMapBridge.postMessage === 'function') {
        window.TripMapBridge.postMessage(payload);
      } else if (window.chrome && window.chrome.webview) {
        window.chrome.webview.postMessage(payload);
      }
    };

    const map = new AMap.Map('map', {
      zoom: 4.5,
      center: [104.2, 35.7],
      showLabel: ${detailLevel.showLabel},
      features: $featuresJson,
      // 底图的地名和 POI 默认在 PC 上会悬停高亮、看着像能点，但点了什么也不会发生
      // （我们的点击处理全在自绘的折线上）。关掉，免得空欢喜。
      isHotspot: false,
      viewMode: '3D',
      resizeEnable: true,
      zoomEnable: true,
      scrollWheel: true,
      touchZoomCenter: 1,
      mapStyle: 'amap://styles/${darkMode ? 'dark' : 'whitesmoke'}'
    });
    map.addControl(new AMap.Scale());
    map.addControl(new AMap.ToolBar({ position: 'RB' }));

    // 一段路要画几条线、各自什么走向：单向一条，双向就把同一条中心线画正反两遍。
    // frequency 是该方向上的行程次数——双向段的两条线各算各的。
    const routeLines = (route) => {
      const forward = route.coordinates;
      const back = forward.slice().reverse();
      const forwardFrequency = route.entries.filter(
        (entry) => entry.direction === 'direction1').length;
      const backwardFrequency = route.entries.filter(
        (entry) => entry.direction === 'direction2').length;
      if (route.direction === 'direction2') {
        return [{ coordinates: back, frequency: backwardFrequency }];
      }
      if (route.direction === 'bidirectional') {
        return [
          { coordinates: forward, frequency: forwardFrequency },
          { coordinates: back, frequency: backwardFrequency }
        ];
      }
      return [{ coordinates: forward, frequency: forwardFrequency }];
    };

    if (routes.length) {
      const features = routes.flatMap((route) => routeLines(route).map((line) => ({
        type: 'Feature',
        properties: {
          name: route.name,
          direction: route.direction,
          frequency: line.frequency
        },
        geometry: { type: 'LineString', coordinates: line.coordinates }
      })));
      if (colorByRoute) {
        // 单趟行程的地图：每段折线直接使用简图里同一条线路的颜色（实线），
        // 不再按经过次数做脉冲着色。地图内的「经过次数」图例也随之隐藏，
        // 线路颜色与里程由地图下方的图例说明。
        const legend = document.querySelector('.map-legend');
        if (legend) legend.style.display = 'none';
        const polylines = routes.flatMap((route) => routeLines(route).map((line) =>
          new AMap.Polyline({
            path: line.coordinates,
            strokeColor: route.color || directionColor(route.direction),
            strokeOpacity: 0.95,
            strokeWeight: 5,
            lineJoin: 'round',
            lineCap: 'round',
            zIndex: 11,
            bubble: false
          })));
        map.add(polylines);
      } else {
        const source = new Loca.GeoJSONSource({
          data: { type: 'FeatureCollection', features }
        });
        const loca = new Loca.Container({ map });
        const lines = new Loca.PulseLineLayer({
          zIndex: 11,
          opacity: 1,
          visible: true,
          zooms: [2, 22]
        });
        lines.setSource(source);

        // 经过次数决定线宽与亮度：按对数拉开差距，常走的线又粗又亮，只走过一次的
        // 线仍看得见。Loca 的 style 支持按 feature 取值的函数（属性级样式）。
        const maxFrequency = features.reduce(
          (max, feature) => Math.max(max, feature.properties.frequency), 1);
        // 只有一趟行程时所有线一样粗，图例没有意义。
        if (maxFrequency <= 1) {
          const legend = document.querySelector('.map-legend');
          if (legend) legend.style.display = 'none';
        }
        const frequencyOf = (feature) => {
          const value = feature && feature.properties && feature.properties.frequency;
          return typeof value === 'number' && value > 0 ? value : 1;
        };
        const intensityOf = (feature) => maxFrequency <= 1
          ? 1
          : Math.log(frequencyOf(feature)) / Math.log(maxFrequency);
        const lineWidthOf = (source, feature) => maxFrequency <= 1
          ? 4
          : 3 + 8 * intensityOf(feature);
        const headColorOf = (source, feature) => 'rgba(${darkMode ? '236,255,177' : '122,75,0'},' +
          (${darkMode ? '0.62' : '0.55'} + ${darkMode ? '0.38' : '0.45'} * intensityOf(feature)) + ')';
        const trailColorOf = (source, feature) => 'rgba(${darkMode ? '255,178,6' : '180,72,0'},' +
          (${darkMode ? '0.10' : '0.36'} + ${darkMode ? '0.24' : '0.42'} * intensityOf(feature)) + ')';

        lines.setStyle({
          altitude: 0,
          lineWidth: lineWidthOf,
          headColor: headColorOf,
          trailColor: trailColorOf,
          interval: 0.45,
          duration: 3200
        });
        loca.add(lines);
        loca.animate.start();
      }

      // Loca renders the animated line but does not expose a consistent hit
      // target across WebView platforms. Add a transparent, wider AMap
      // polyline for reliable click handling.
      const hitLines = routes.flatMap((route) => routeLines(route).map((line) => {
        const hitLine = new AMap.Polyline({
          path: line.coordinates,
          strokeColor: '#000000',
          // 完全透明时部分渲染器不会把它当作可点击图形；留一点点透明度，
          // 肉眼看不出，但点击一定能命中。
          strokeOpacity: 0.01,
          strokeWeight: 16,
          lineJoin: 'round',
          lineCap: 'round',
          zIndex: 12,
          bubble: false,
          cursor: 'pointer'
        });
        hitLine.on('click', (event) => {
          const content = document.createElement('div');
          content.className = 'route-popup';
          if (route.entries.length) {
            const summary = document.createElement('div');
            summary.className = 'route-popup-summary';
            summary.textContent = route.entries.length + ' 次经过';
            content.append(summary);
          }
          const list = document.createElement('div');
          list.className = 'route-popup-list';
          route.entries.forEach((entry) => {
            const row = document.createElement('div');
            // 有 id 才能跳到行程详情：自己的行程用本地 id，他人主页的公开行程用
            // 票据 id，由 Flutter 那侧按来源决定打开哪一种详情页。
            const canOpen = tripLinks &&
              (entry.tripId != null || entry.ticketId != null);
            row.className = canOpen ? 'route-popup-row is-link' : 'route-popup-row';
            const train = document.createElement('strong');
            train.textContent = entry.trainNumber || '未填写车次';
            const date = document.createElement('span');
            date.textContent = entry.departureDate;
            date.style.color = directionColor(entry.direction);
            train.style.color = directionColor(entry.direction);
            row.append(train, date);
            if (canOpen) {
              row.tabIndex = 0;
              const hint = document.createElement('span');
              hint.className = 'open-hint';
              hint.textContent = '›';
              row.append(hint);
              const openTrip = () => postToHost({
                type: 'openTrip',
                tripId: entry.tripId,
                ticketId: entry.ticketId
              });
              row.addEventListener('click', (clickEvent) => {
                clickEvent.stopPropagation();
                openTrip();
              });
              row.addEventListener('keydown', (keyEvent) => {
                if (keyEvent.key === 'Enter' || keyEvent.key === ' ') {
                  keyEvent.preventDefault();
                  openTrip();
                }
              });
            }
            list.append(row);
          });
          list.addEventListener('wheel', (wheelEvent) => wheelEvent.stopPropagation(), { passive: true });
          if (!route.entries.length) list.textContent = '未填写车次';
          content.append(list);
          new AMap.InfoWindow({
            isCustom: true,
            autoMove: true,
            closeWhenClickMap: true,
            content,
            offset: new AMap.Pixel(0, -8)
          }).open(map, event.lnglat);
        });
        return hitLine;
      }));
      map.add(hitLines);

      ${showStationMarkers ? '''const endpoints = $endpointJson;
      const markers = endpoints.map((endpoint) => {
        const label = document.createElement('span');
            label.textContent = endpoint.station;
        return new AMap.Marker({
          position: new AMap.LngLat(endpoint.position[0], endpoint.position[1]),
          icon: new AMap.Icon({
            size: new AMap.Size(25, 34),
            image: 'https://webapi.amap.com/theme/v1.3/markers/n/mark_r.png',
            imageSize: new AMap.Size(25, 34)
          }),
          offset: new AMap.Pixel(-13, -30),
          label: {
            content: label.outerHTML,
            direction: 'right',
            offset: new AMap.Pixel(8, 0)
          },
          zIndex: 20
        });
      });
      map.add(markers);''' : ''}

      // 默认视角要装得下整条轨迹。内嵌 WebView 在脚本刚执行时容器可能还没
      // 拿到最终尺寸，setFitView 会按错误视口计算缩放，所以布局完成后再套一次；
      // 窗口尺寸变化时也重新套。
      const fitRoute = () => map.setFitView(hitLines, false, [48, 48, 48, 48]);
      fitRoute();
      setTimeout(fitRoute, 200);
      window.addEventListener('resize', fitRoute);
    }
  </script>
</body>
</html>''';
}

class _TripMapRouteGroup {
  _TripMapRouteGroup({
    required this.tracks,
    required this.fromStation,
    required this.toStation,
    required this.fromCoordinate,
    required this.toCoordinate,
  });

  /// 折线索引；为 null 时整组都画站间直线。
  final RailTrackIndex? tracks;

  /// 这一段的起终站名（原文，用来查折线，也用来显示）。
  final String fromStation;
  final String toStation;
  final StationCoordinate fromCoordinate;
  final StationCoordinate toCoordinate;

  /// 这一对坐标上各趟车给出的线路名（同一条线的大小写/空白差异会并到一组）。
  ///
  /// 建组时只拿得到第一趟车的线路名——它可能查不到折线（行程没标线路名、线路名没解析
  /// 出来），整组就会被判成直线。所以名字都收着，到出图时再挑第一个查得到折线的。
  final List<String> _routeNames = [];
  final List<TripMapRouteEntry> _direction1Entries = [];
  final List<TripMapRouteEntry> _direction2Entries = [];
  List<StationCoordinate>? _geometry;

  void addTrip(
    String trainNumber,
    DateTime departureDate,
    String routeName,
    StationCoordinate origin, {
    int? tripId,
    int? ticketId,
  }) {
    final trimmed = routeName.trim();
    if (trimmed.isNotEmpty && !_routeNames.contains(trimmed)) {
      _routeNames.add(trimmed);
      _geometry = null; // 多了个候选线路名，重新解析
    }
    final isDirection1 = _sameCoordinate(origin, fromCoordinate);
    final entries = isDirection1 ? _direction1Entries : _direction2Entries;
    entries.add(
      TripMapRouteEntry(
        trainNumber: trainNumber,
        departureDate: departureDate,
        direction: isDirection1
            ? TripMapDirection.direction1
            : TripMapDirection.direction2,
        tripId: tripId,
        ticketId: ticketId,
      ),
    );
  }

  /// 贴轨的点：拿每个候选线路名去查，第一个命中的就用它；都没命中退回站间直线。
  List<StationCoordinate> get _resolvedGeometry {
    final cached = _geometry;
    if (cached != null) return cached;
    for (final routeName in _routeNames) {
      final track = tracks?.findOriented(routeName, fromStation, toStation);
      if (track == null || track.isEmpty) continue;
      return _geometry = _trackPoints(track, fromCoordinate, toCoordinate);
    }
    return _geometry = _trackPoints(null, fromCoordinate, toCoordinate);
  }

  TripMapRoute toRoute() {
    final entries = [..._direction1Entries, ..._direction2Entries]
      ..sort((a, b) => b.departureDate.compareTo(a.departureDate));
    return TripMapRoute(
      name: '$fromStation - $toStation',
      lineName: _routeNames.isEmpty ? null : _routeNames.first,
      entries: entries,
      direction: _directionOf(entries),
      fromStation: fromStation,
      toStation: toStation,
      fromCoordinate: fromCoordinate,
      toCoordinate: toCoordinate,
      points: _resolvedGeometry,
    );
  }
}

/// 一组车次整体的走向：只有上行、只有下行，还是两种都有。
TripMapDirection _directionOf(List<TripMapRouteEntry> entries) {
  final hasDirection1 = entries.any(
    (entry) => entry.direction == TripMapDirection.direction1,
  );
  final hasDirection2 = entries.any(
    (entry) => entry.direction == TripMapDirection.direction2,
  );
  if (hasDirection1 && hasDirection2) return TripMapDirection.bidirectional;
  if (hasDirection2) return TripMapDirection.direction2;
  return TripMapDirection.direction1;
}

List<TripMapRoute> _mergeAdjacentRoutes(
  List<TripMapRoute> routes, {
  required bool mergeAcrossLines,
}) {
  final merged = <TripMapRoute>[];
  for (final route in routes) {
    if (merged.isNotEmpty) {
      final previous = merged.last;
      final sameEntries =
          _entryKey(previous.entries) == _entryKey(route.entries);
      final connected = _sameCoordinate(
        previous.points.last,
        route.points.first,
      );
      final sameDirection = previous.direction == route.direction;
      // 单趟行程要按线路分色时，跨线路合并会把两条线画成一条同色折线。
      final sameLine =
          mergeAcrossLines ||
          _lineNameKey(previous.lineName) == _lineNameKey(route.lineName);
      if (sameEntries && connected && sameDirection && sameLine) {
        merged[merged.length - 1] = TripMapRoute(
          name: previous.name,
          lineName: previous.lineName ?? route.lineName,
          entries: previous.entries,
          direction: previous.direction,
          fromStation: previous.fromStation,
          toStation: route.toStation,
          fromCoordinate: previous.fromCoordinate,
          toCoordinate: route.toCoordinate,
          points: [...previous.points, ...route.points.skip(1)],
        );
        continue;
      }
    }
    merged.add(route);
  }
  return merged;
}

String _lineNameKey(String? value) => (value ?? '').trim().toLowerCase();

/// 消掉「被真实折线盖住的站间直线」。
///
/// 同一段路可能被两种粒度各建了一条 route：一条是逐站展开、贴着真实轨道的折线，另一
/// 条因为线路名没解析出来（查不到折线）而退回站间直线。两者分组键里的线路名不一样
/// （一个是空的），对不上就合并不到一起，于是地图上并排出现「真实折线 + 一条直线」。
///
/// 这里把直线上的车次并进盖住它的那条折线 route，再丢掉直线——既不再画那条多余的直线，
/// 也不丢车次。折线 route 的走向可能与直线相反，并进去时把车次的上下行一起翻过来。
List<TripMapRoute> _absorbShadowedStraightRoutes(List<TripMapRoute> routes) {
  final realIndexes = [
    for (var index = 0; index < routes.length; index++)
      if (routes[index].points.length > 2) index,
  ];
  if (realIndexes.isEmpty) return routes;

  final absorbed = <int, List<TripMapRouteEntry>>{};
  final dropped = <int>{};
  for (var index = 0; index < routes.length; index++) {
    final straight = routes[index];
    if (straight.points.length > 2) continue;
    final target = _coveringRouteIndex(straight, routes, realIndexes);
    if (target == null) continue;
    dropped.add(index);
    final flipped = !_sameCoordinate(
      straight.points.first,
      routes[target].points.first,
    );
    absorbed.putIfAbsent(target, () => []).addAll([
      for (final entry in straight.entries) _flipEntry(entry, flipped),
    ]);
  }
  if (dropped.isEmpty) return routes;

  return [
    for (var index = 0; index < routes.length; index++)
      if (!dropped.contains(index))
        absorbed.containsKey(index)
            ? _withEntries(routes[index], [
                ...routes[index].entries,
                ...absorbed[index]!,
              ])
            : routes[index],
  ];
}

/// 点最多的那条、且两端都落在这条直线端点上的 route 下标；没有则为 null。
int? _coveringRouteIndex(
  TripMapRoute straight,
  List<TripMapRoute> routes,
  List<int> candidates,
) {
  int? best;
  for (final index in candidates) {
    final points = routes[index].points;
    if (!points.any((point) => _sameCoordinate(point, straight.points.first))) {
      continue;
    }
    if (!points.any((point) => _sameCoordinate(point, straight.points.last))) {
      continue;
    }
    if (best == null || points.length > routes[best].points.length) {
      best = index;
    }
  }
  return best;
}

TripMapRouteEntry _flipEntry(TripMapRouteEntry entry, bool flipped) {
  if (!flipped) return entry;
  return TripMapRouteEntry(
    trainNumber: entry.trainNumber,
    departureDate: entry.departureDate,
    direction: entry.direction == TripMapDirection.direction1
        ? TripMapDirection.direction2
        : TripMapDirection.direction1,
    tripId: entry.tripId,
    ticketId: entry.ticketId,
  );
}

/// 换一组车次，走向按车次重新推导——并进别的 route 后可能两个方向都有了。
TripMapRoute _withEntries(
  TripMapRoute route,
  List<TripMapRouteEntry> entries,
) {
  final sorted = [...entries]
    ..sort((a, b) => b.departureDate.compareTo(a.departureDate));
  return TripMapRoute(
    name: route.name,
    lineName: route.lineName,
    color: route.color,
    entries: sorted,
    direction: _directionOf(sorted),
    fromStation: route.fromStation,
    toStation: route.toStation,
    fromCoordinate: route.fromCoordinate,
    toCoordinate: route.toCoordinate,
    points: route.points,
  );
}

String _entryKey(List<TripMapRouteEntry> entries) => entries
    .map(
      (entry) =>
          '${entry.trainNumber}|${entry.departureDate.toIso8601String()}|${entry.direction.name}',
    )
    .join(';');

bool _sameCoordinate(StationCoordinate a, StationCoordinate b) =>
    a.latitude == b.latitude && a.longitude == b.longitude;

void _addEndpoint(
  Map<String, TripMapEndpoint> endpoints,
  String station,
  StationCoordinateIndex coordinates,
) {
  final coordinate = coordinates.find(station);
  if (coordinate == null) return;
  final key =
      '${station.trim()}|${coordinate.latitude}|${coordinate.longitude}';
  endpoints.putIfAbsent(
    key,
    () => TripMapEndpoint(station: station, coordinate: coordinate),
  );
}

String _dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// 建组用的线路名：去首尾空白、大小写不敏感（客里表里同一条线的写法并不统一）。
String _lineKey(String routeName) => routeName.trim().toLowerCase();

String _routeKey(Iterable<StationCoordinate> points) => points
    .map(
      (point) =>
          '${point.latitude.toStringAsFixed(6)},${point.longitude.toStringAsFixed(6)}',
    )
    .join(';');

Iterable<String> _stationKeys(String value) sync* {
  final trimmed = value.trim().replaceAll('（', '(').replaceAll('）', ')');
  if (trimmed.isEmpty) return;
  yield trimmed.toLowerCase();

  var normalized = trimmed.replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '');
  normalized = normalized.replaceFirst(RegExp(r'(火车站|站)$'), '');
  normalized = normalized.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  if (normalized.isNotEmpty) yield normalized;
}

List<double> _wgs84ToGcj02(double latitude, double longitude) {
  if (longitude < 72.004 ||
      longitude > 137.8347 ||
      latitude < 0.8293 ||
      latitude > 55.8271) {
    return [longitude, latitude];
  }

  const axis = 6378245.0;
  const eccentricitySquared = 0.006693421622965943;
  var latitudeOffset = _latitudeOffset(longitude - 105, latitude - 35);
  var longitudeOffset = _longitudeOffset(longitude - 105, latitude - 35);
  final radians = latitude / 180 * math.pi;
  var magic = math.sin(radians);
  magic = 1 - eccentricitySquared * magic * magic;
  final squareRoot = math.sqrt(magic);
  latitudeOffset =
      (latitudeOffset * 180) /
      ((axis * (1 - eccentricitySquared)) / (magic * squareRoot) * math.pi);
  longitudeOffset =
      (longitudeOffset * 180) /
      (axis / squareRoot * math.cos(radians) * math.pi);
  return [longitude + longitudeOffset, latitude + latitudeOffset];
}

double _latitudeOffset(double x, double y) =>
    -100 +
    2 * x +
    3 * y +
    0.2 * y * y +
    0.1 * x * y +
    0.2 * math.sqrt(x.abs()) +
    (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) * 2 / 3 +
    (20 * math.sin(y * math.pi) + 40 * math.sin(y / 3 * math.pi)) * 2 / 3 +
    (160 * math.sin(y / 12 * math.pi) + 320 * math.sin(y * math.pi / 30)) *
        2 /
        3;

double _longitudeOffset(double x, double y) =>
    300 +
    x +
    2 * y +
    0.1 * x * x +
    0.1 * x * y +
    0.1 * math.sqrt(x.abs()) +
    (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) * 2 / 3 +
    (20 * math.sin(x * math.pi) + 40 * math.sin(x / 3 * math.pi)) * 2 / 3 +
    (150 * math.sin(x / 12 * math.pi) + 300 * math.sin(x / 30 * math.pi)) *
        2 /
        3;
