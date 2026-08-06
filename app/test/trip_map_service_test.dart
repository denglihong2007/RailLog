import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';
import 'package:raillog/src/services/trip_map_service.dart';
import 'package:raillog/src/services/route_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const csv = '''station_name,latitude,longitude
北京站,39.9022,116.4211
济南西站 (中国铁路),36.6700,116.8900
上海虹桥站,31.1960,121.3160
''';

  group('StationCoordinateIndex', () {
    test('matches station suffix and annotation variants', () {
      final index = StationCoordinateIndex.fromCsv(csv);

      expect(index.find('北京')?.longitude, 116.4211);
      expect(index.find('济南西站')?.latitude, 36.67);
      expect(index.find('上海虹桥站')?.longitude, 121.316);
    });
  });

  group('TripMapService.buildData', () {
    test('keeps only rail trips inside the inclusive date range', () {
      final index = StationCoordinateIndex.fromCsv(csv);
      final trips = [
        _trip(id: 1, date: DateTime(2026, 1, 1)),
        _trip(id: 2, date: DateTime(2026, 1, 2), isRailTrip: false),
        _trip(id: 3, date: DateTime(2026, 1, 3)),
      ];

      final data = TripMapService.buildData(
        trips,
        index,
        journeyStations: {
          trips.first.clientId: const ['北京站', '济南西站', '上海虹桥站'],
        },
        start: DateTime(2026, 1, 1),
        endExclusive: DateTime(2026, 1, 3),
      );

      expect(data.tripCount, 1);
      expect(data.mappedTripCount, 1);
      expect(data.routes, hasLength(1));
      expect(data.routes.single.points, hasLength(3));
    });

    test('reports missing stations while retaining a drawable route', () {
      final index = StationCoordinateIndex.fromCsv(csv);
      final trip = _trip(
        id: 1,
        date: DateTime(2026, 1, 1),
        segments: const [
          ViaRouteSegment(
            routeName: '测试线',
            fromStation: '北京站',
            toStation: '未知站',
          ),
        ],
      );

      final data = TripMapService.buildData([trip], index);

      expect(data.routes, hasLength(1));
      expect(data.missingStations, contains('未知站'));
    });

    test('does not draw a trip without via route information', () {
      final index = StationCoordinateIndex.fromCsv(csv);
      final trip = _trip(id: 4, date: DateTime(2026, 1, 1), segments: const []);

      final data = TripMapService.buildData([trip], index);

      expect(data.tripCount, 1);
      expect(data.mappedTripCount, 0);
      expect(data.routes, isEmpty);
      expect(data.missingViaRouteCount, 1);
    });

    test('does not move a missing endpoint marker to a nearby station', () {
      final index = StationCoordinateIndex.fromCsv(csv);
      final trip = _trip(id: 2, date: DateTime(2026, 1, 1), fromStation: '未知站');

      final data = TripMapService.buildData(
        [trip],
        index,
        journeyStations: {
          trip.clientId: const ['未知站', '济南西站', '上海虹桥站'],
        },
      );

      expect(data.routes, hasLength(1));
      expect(data.routes.single.fromCoordinate, isNotNull);
      expect(data.routes.single.toCoordinate, isNotNull);
      expect(data.routes.single.points, hasLength(2));
    });

    test(
      'deduplicates forward and reverse trips into one bidirectional route',
      () {
        final index = StationCoordinateIndex.fromCsv(csv);
        final forward = _trip(id: 20, date: DateTime(2026, 1, 1));
        final reverse = _trip(
          id: 21,
          date: DateTime(2026, 1, 2),
          fromStation: '上海虹桥站',
          toStation: '北京站',
        );

        final data = TripMapService.buildData(
          [forward, reverse],
          index,
          journeyStations: {
            forward.clientId: const ['北京站', '济南西站', '上海虹桥站'],
            reverse.clientId: const ['上海虹桥站', '济南西站', '北京站'],
          },
        );

        expect(data.tripCount, 2);
        expect(data.mappedTripCount, 2);
        expect(data.routes, hasLength(1));
        expect(
          data.routes.every(
            (route) =>
                route.direction == TripMapDirection.bidirectional &&
                route.entries
                        .map((entry) => entry.trainNumber)
                        .toSet()
                        .length ==
                    2,
          ),
          isTrue,
        );
      },
    );
  });

  test('collects every train that shares part of a route', () {
    final index = StationCoordinateIndex.fromCsv(csv);
    final longTrip = _trip(id: 30, date: DateTime(2026, 1, 1));
    final shortTrip = _trip(
      id: 31,
      date: DateTime(2026, 1, 2),
      toStation: '济南西站',
    );

    final data = TripMapService.buildData(
      [longTrip, shortTrip],
      index,
      journeyStations: {
        longTrip.clientId: const ['北京站', '济南西站', '上海虹桥站'],
        shortTrip.clientId: const ['北京站', '济南西站'],
      },
    );

    expect(data.mappedTripCount, 2);
    expect(data.routes, hasLength(2));
    expect(
      data.routes.map(
        (route) => route.entries.map((entry) => entry.trainNumber).toSet(),
      ),
      containsAll([
        {'G30', 'G31'},
        {'G30'},
      ]),
    );
  });

  test('route database expands a trip into consecutive stations', () async {
    final trip = _trip(
      id: 10,
      date: DateTime(2026, 1, 1),
      fromStation: '北京南站',
      segments: const [
        ViaRouteSegment(
          routeName: '京沪高速铁路',
          fromStation: '北京南站',
          toStation: '上海虹桥站',
        ),
      ],
    );
    final reverseTrip = _trip(
      id: 11,
      date: DateTime(2026, 1, 2),
      fromStation: '上海虹桥站',
      toStation: '北京南站',
      segments: const [
        ViaRouteSegment(
          routeName: '京沪高速铁路',
          fromStation: '上海虹桥站',
          toStation: '北京南站',
        ),
      ],
    );

    final result = await RouteService.resolveTripStations([trip, reverseTrip]);
    final stations = result[trip.clientId]!;
    final reverseStations = result[reverseTrip.clientId]!;

    expect(stations.first, '北京南站');
    expect(stations.last, '上海虹桥站');
    expect(stations.length, greaterThan(2));
    expect(reverseStations, stations.reversed);
  });

  test('map HTML uses API proxies and script-safe route data', () {
    final route = TripMapRoute(
      name: '</script>',
      entries: [
        TripMapRouteEntry(
          trainNumber: 'G1<script>',
          departureDate: DateTime(2026, 1, 1),
          direction: TripMapDirection.direction1,
        ),
      ],
      fromStation: '北京站',
      toStation: '上海虹桥站',
      fromCoordinate: StationCoordinate(latitude: 39.9, longitude: 116.4),
      toCoordinate: StationCoordinate(latitude: 31.2, longitude: 121.3),
      points: [
        StationCoordinate(latitude: 39.9, longitude: 116.4),
        StationCoordinate(latitude: 31.2, longitude: 121.3),
      ],
    );

    final html = buildAmapHtml(
      [route],
      darkMode: true,
      backgroundColor: '#111820',
      showStationMarkers: true,
    );

    expect(html, contains('/api/amap/sdk/maps.js'));
    expect(html, contains('/api/amap/sdk/loca.js'));
    expect(html, isNot(contains('_AMapSecurityConfig')));
    expect(html, isNot(contains('/api/amap/service')));
    expect(html, isNot(contains('key=')));
    expect(html, contains("mapStyle: 'amap://styles/dark'"));
    expect(html, contains("headColor: '#ECFFB1'"));
    expect(html, isNot(contains('const routes = [{"name":"</script>')));
    expect(html, contains(r'\u003c/script>'));
    expect(html, contains(r'G1\u003cscript>'));
    expect(route.points.first.amapPosition[0], closeTo(116.4062, 0.001));
    expect(html, contains("label.textContent = endpoint.station"));
    expect(html, contains('markers/n/mark_r.png'));
    expect(html, isNot(contains('dir-via-marker.png')));
    expect(html, contains("offset: new AMap.Pixel(-13, -30)"));
    expect(html, contains('pointer-events: none'));
    expect(html, contains('scrollWheel: true'));
    expect(html, contains('touchZoomCenter: 1'));
    expect(html, contains("hitLine.on('click'"));
    expect(html, contains('route-popup-row'));
    expect(html, contains('entry.departureDate'));
    expect(
      html,
      contains('train.style.color = directionColor(entry.direction)'),
    );
    expect(
      html,
      contains('date.style.color = directionColor(entry.direction)'),
    );
    expect(html, contains('route.direction === \'bidirectional\''));
    expect(html, contains('const endpoints = []'));
    expect(html, contains('new AMap.InfoWindow'));
    expect(html, contains("strokeOpacity: 0"));

    final lightHtml = buildAmapHtml(
      [route],
      darkMode: false,
      backgroundColor: '#fafafa',
      showStationMarkers: false,
    );
    expect(lightHtml, contains("mapStyle: 'amap://styles/whitesmoke'"));
    expect(lightHtml, contains("headColor: '#7A4B00'"));
    expect(lightHtml, contains("trailColor: 'rgba(180,72,0,0.68)'"));
    expect(lightHtml, isNot(contains('new AMap.Marker')));
  });
}

TripRecord _trip({
  required int id,
  required DateTime date,
  bool isRailTrip = true,
  String fromStation = '北京站',
  String toStation = '上海虹桥站',
  List<ViaRouteSegment>? segments,
}) => TripRecord(
  id: id,
  trainNumber: 'G$id',
  fromStation: fromStation,
  toStation: toStation,
  departureTime: date,
  viaRouteSegments:
      segments ??
      const [
        ViaRouteSegment(
          routeName: '京沪高速铁路',
          fromStation: '北京站',
          toStation: '济南西站',
        ),
      ],
  isRailTrip: isRailTrip,
);
