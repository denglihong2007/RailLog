import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/services/api_client.dart';

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
  });

  final String trainNumber;
  final DateTime departureDate;
  final TripMapDirection direction;
}

class TripMapEndpoint {
  const TripMapEndpoint({required this.station, required this.coordinate});

  final String station;
  final StationCoordinate coordinate;
}

class TripMapRoute {
  const TripMapRoute({
    required this.name,
    this.entries = const [],
    this.direction = TripMapDirection.direction1,
    required this.fromStation,
    required this.toStation,
    required this.fromCoordinate,
    required this.toCoordinate,
    required this.points,
  });

  final String name;
  final List<TripMapRouteEntry> entries;
  final TripMapDirection direction;
  final String fromStation;
  final String toStation;
  final StationCoordinate? fromCoordinate;
  final StationCoordinate? toCoordinate;
  final List<StationCoordinate> points;
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

  factory StationCoordinateIndex.fromCsv(String csv) {
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
    return StationCoordinateIndex._(coordinates);
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

  static Future<StationCoordinateIndex>? _coordinateRequest;

  static Future<StationCoordinateIndex> loadCoordinates() =>
      _coordinateRequest ??= rootBundle
          .loadString('assets/db/coordinates.csv')
          .then(StationCoordinateIndex.fromCsv);

  static TripMapData buildData(
    Iterable<TripRecord> trips,
    StationCoordinateIndex coordinates, {
    Map<String, List<String>> journeyStations = const {},
    DateTime? start,
    DateTime? endExclusive,
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

      final stationNames =
          journeyStations[trip.clientId] ??
          <String>[
            trip.fromStation,
            ...trip.viaRouteSegments.map((segment) => segment.toStation),
            trip.toStation,
          ];
      final locatedStations = <({String name, StationCoordinate coordinate})>[];
      for (final station in stationNames) {
        final coordinate = coordinates.find(station);
        if (coordinate == null) {
          final normalized = station.trim();
          if (normalized.isNotEmpty) missingStations.add(normalized);
          continue;
        }
        if (locatedStations.isEmpty ||
            locatedStations.last.coordinate.latitude != coordinate.latitude ||
            locatedStations.last.coordinate.longitude != coordinate.longitude) {
          locatedStations.add((name: station, coordinate: coordinate));
        }
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
        final key = forwardKey.compareTo(reverseKey) <= 0
            ? forwardKey
            : reverseKey;
        final group = routeGroups.putIfAbsent(
          key,
          () => _TripMapRouteGroup(
            fromStation: from.name,
            toStation: to.name,
            fromCoordinate: from.coordinate,
            toCoordinate: to.coordinate,
            points: [from.coordinate, to.coordinate],
          ),
        );
        group.addTrip(
          trip.trainNumber.trim(),
          trip.departureTime,
          from.coordinate,
        );
      }
    }

    final routes = _mergeAdjacentRoutes(
      routeGroups.values.map((group) => group.toRoute()).toList(),
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
}

String buildAmapHtml(
  List<TripMapRoute> routes, {
  required bool darkMode,
  required String backgroundColor,
  required bool showStationMarkers,
  List<TripMapEndpoint> endpoints = const [],
}) {
  final apiBaseUrl = ApiClient.baseUrl.replaceFirst(RegExp(r'/+$'), '');
  final routeJson = jsonEncode(
    routes
        .map(
          (route) => {
            'name': route.name,
            'direction': route.direction.name,
            'entries': route.entries
                .map(
                  (entry) => {
                    'trainNumber': entry.trainNumber,
                    'departureDate': _dateOnly(entry.departureDate),
                    'direction': entry.direction.name,
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
    .route-popup { width: 248px; max-width: calc(100vw - 32px); max-height: 240px; overflow-y: auto; padding: 4px; border: 1px solid rgba(255,255,255,.24); border-radius: 4px; background: rgba(10,16,22,.94); color: #FFF; font: 12px/1.35 sans-serif; box-shadow: 0 3px 12px rgba(0,0,0,.32); }
    .route-popup-list { display: flex; flex-direction: column; gap: 1px; }
    .route-popup-row { display: grid; grid-template-columns: minmax(48px, 1fr) 86px; align-items: center; gap: 5px; padding: 4px 5px; border-bottom: 1px solid rgba(255,255,255,.1); white-space: nowrap; }
    .route-popup-row:last-child { border-bottom: 0; }
    .route-popup-row strong { overflow: hidden; text-overflow: ellipsis; }
    .route-popup-row span { color: rgba(255,255,255,.76); }
  </style>
</head>
<body>
  <div id="map"></div>
  <script src="$apiBaseUrl/api/amap/sdk/maps.js"></script>
  <script src="$apiBaseUrl/api/amap/sdk/loca.js"></script>
  <script>
    const routes = $routeJson;
    const directionColor = (direction) =>
      direction === 'direction1' ? '#7DD3FC' : '#FDBA74';
    const map = new AMap.Map('map', {
      zoom: 4.5,
      center: [104.2, 35.7],
      showLabel: false,
      viewMode: '3D',
      resizeEnable: true,
      zoomEnable: true,
      scrollWheel: true,
      touchZoomCenter: 1,
      mapStyle: 'amap://styles/${darkMode ? 'dark' : 'whitesmoke'}'
    });
    map.addControl(new AMap.Scale());
    map.addControl(new AMap.ToolBar({ position: 'RB' }));

    if (routes.length) {
      const features = routes.flatMap((route) => {
        const feature = (coordinates) => ({
          type: 'Feature',
          properties: { name: route.name, direction: route.direction },
          geometry: { type: 'LineString', coordinates }
        });
        if (route.direction === 'direction2') {
          return [feature(route.coordinates.slice().reverse())];
        }
        if (route.direction === 'bidirectional') {
          return [feature(route.coordinates), feature(route.coordinates.slice().reverse())];
        }
        return [feature(route.coordinates)];
      });
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
      lines.setStyle({
        altitude: 0,
        lineWidth: 4,
        headColor: '${darkMode ? '#ECFFB1' : '#7A4B00'}',
        trailColor: '${darkMode ? 'rgba(255,178,6,0.2)' : 'rgba(180,72,0,0.68)'}',
        interval: 0.45,
        duration: 3200
      });
      loca.add(lines);
      loca.animate.start();

      // Loca renders the animated line but does not expose a consistent hit
      // target across WebView platforms. Add a transparent, wider AMap
      // polyline for reliable click handling.
      const hitLines = routes.map((route) => {
        const hitLine = new AMap.Polyline({
          path: route.coordinates,
          strokeColor: '#000000',
          strokeOpacity: 0,
          strokeWeight: 16,
          lineJoin: 'round',
          lineCap: 'round',
          zIndex: 12,
          bubble: false
        });
        hitLine.on('click', (event) => {
          const content = document.createElement('div');
          content.className = 'route-popup';
          const list = document.createElement('div');
          list.className = 'route-popup-list';
          route.entries.forEach((entry) => {
            const row = document.createElement('div');
            row.className = 'route-popup-row';
            const train = document.createElement('strong');
            train.textContent = entry.trainNumber || '未填写车次';
            const date = document.createElement('span');
            date.textContent = entry.departureDate;
            date.style.color = directionColor(entry.direction);
            train.style.color = directionColor(entry.direction);
            row.append(train, date);
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
      });
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

      const firstPoint = routes[0].coordinates[0];
      const firstLngLat = new AMap.LngLat(firstPoint[0], firstPoint[1]);
      const bounds = new AMap.Bounds(firstLngLat, firstLngLat);
      routes.forEach((route) => route.coordinates.forEach((point) =>
        bounds.extend(new AMap.LngLat(point[0], point[1]))));
      map.setBounds(bounds, false, [48, 48, 48, 48]);
    }
  </script>
</body>
</html>''';
}

class _TripMapRouteGroup {
  _TripMapRouteGroup({
    required this.fromStation,
    required this.toStation,
    required this.fromCoordinate,
    required this.toCoordinate,
    required this.points,
  });

  final String fromStation;
  final String toStation;
  final StationCoordinate? fromCoordinate;
  final StationCoordinate? toCoordinate;
  final List<StationCoordinate> points;
  final List<TripMapRouteEntry> _direction1Entries = [];
  final List<TripMapRouteEntry> _direction2Entries = [];
  bool _hasDirection1 = false;
  bool _hasDirection2 = false;

  void addTrip(
    String trainNumber,
    DateTime departureDate,
    StationCoordinate fromCoordinate,
  ) {
    final isDirection1 = _sameCoordinate(fromCoordinate, points.first);
    if (isDirection1) {
      _hasDirection1 = true;
    } else {
      _hasDirection2 = true;
    }
    final entries = isDirection1 ? _direction1Entries : _direction2Entries;
    entries.add(
      TripMapRouteEntry(
        trainNumber: trainNumber,
        departureDate: departureDate,
        direction: isDirection1
            ? TripMapDirection.direction1
            : TripMapDirection.direction2,
      ),
    );
  }

  TripMapRoute toRoute() {
    final direction = _hasDirection1 && _hasDirection2
        ? TripMapDirection.bidirectional
        : _hasDirection2
        ? TripMapDirection.direction2
        : TripMapDirection.direction1;
    final entries = [..._direction1Entries, ..._direction2Entries]
      ..sort((a, b) => b.departureDate.compareTo(a.departureDate));
    return TripMapRoute(
      name: '$fromStation - $toStation',
      entries: entries,
      direction: direction,
      fromStation: fromStation,
      toStation: toStation,
      fromCoordinate: fromCoordinate,
      toCoordinate: toCoordinate,
      points: points,
    );
  }
}

List<TripMapRoute> _mergeAdjacentRoutes(List<TripMapRoute> routes) {
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
      if (sameEntries && connected && sameDirection) {
        merged[merged.length - 1] = TripMapRoute(
          name: previous.name,
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
