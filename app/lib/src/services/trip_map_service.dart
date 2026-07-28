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

class TripMapRoute {
  const TripMapRoute({
    required this.name,
    required this.fromStation,
    required this.toStation,
    required this.fromCoordinate,
    required this.toCoordinate,
    required this.points,
  });

  final String name;
  final String fromStation;
  final String toStation;
  final StationCoordinate? fromCoordinate;
  final StationCoordinate? toCoordinate;
  final List<StationCoordinate> points;
}

class TripMapData {
  const TripMapData({
    required this.routes,
    required this.tripCount,
    required this.missingViaRouteCount,
    required this.missingStations,
  });

  final List<TripMapRoute> routes;
  final int tripCount;
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
    final routes = <TripMapRoute>[];
    final missingStations = <String>{};
    var tripCount = 0;
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
      final points = <StationCoordinate>[];
      for (final station in stationNames) {
        final coordinate = coordinates.find(station);
        if (coordinate == null) {
          final normalized = station.trim();
          if (normalized.isNotEmpty) missingStations.add(normalized);
          continue;
        }
        if (points.isEmpty ||
            points.last.latitude != coordinate.latitude ||
            points.last.longitude != coordinate.longitude) {
          points.add(coordinate);
        }
      }
      if (points.length < 2) continue;

      final train = trip.trainNumber.trim();
      routes.add(
        TripMapRoute(
          name: train.isEmpty
              ? '${trip.fromStation} - ${trip.toStation}'
              : '$train · ${trip.fromStation} - ${trip.toStation}',
          fromStation: trip.fromStation,
          toStation: trip.toStation,
          fromCoordinate: coordinates.find(trip.fromStation),
          toCoordinate: coordinates.find(trip.toStation),
          points: points,
        ),
      );
    }

    return TripMapData(
      routes: routes,
      tripCount: tripCount,
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
}) {
  final apiBaseUrl = ApiClient.baseUrl.replaceFirst(RegExp(r'/+$'), '');
  final routeJson = jsonEncode(
    routes
        .map(
          (route) => {
            'name': route.name,
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

  return '''<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
  <style>
    html, body, #map { width: 100%; height: 100%; margin: 0; overflow: hidden; background: $backgroundColor; }
    .amap-logo, .amap-copyright { opacity: .62; }
    .amap-marker-label { pointer-events: none; padding: 3px 6px; border: 1px solid rgba(255,255,255,.28); border-radius: 3px; background: rgba(10,16,22,.9); color: #FFF; font: 12px/1.25 sans-serif; box-shadow: 0 1px 4px rgba(0,0,0,.45); white-space: nowrap; }
  </style>
</head>
<body>
  <div id="map"></div>
  <script src="$apiBaseUrl/api/amap/sdk/maps.js"></script>
  <script src="$apiBaseUrl/api/amap/sdk/loca.js"></script>
  <script>
    const routes = $routeJson;
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
      const features = routes.map((route) => ({
        type: 'Feature',
        properties: { name: route.name },
        geometry: { type: 'LineString', coordinates: route.coordinates }
      }));
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

      ${showStationMarkers ? '''const endpoints = new Map();
      const addEndpoint = (name, position) => {
        const key = name + '|' + position.join(',');
        if (!endpoints.has(key)) endpoints.set(key, { name, position });
      };
      routes.forEach((route) => {
        if (route.fromPosition) addEndpoint(route.fromStation, route.fromPosition);
        if (route.toPosition) addEndpoint(route.toStation, route.toPosition);
      });
      const markers = Array.from(endpoints.values()).map((endpoint) => {
        const label = document.createElement('span');
        label.textContent = endpoint.name;
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
