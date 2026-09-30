import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/journey_stations.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';
import 'package:raillog/src/services/rail_track_service.dart';
import 'package:raillog/src/services/route_service.dart';
import 'package:raillog/src/services/trip_map_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // 测试环境没有注册 path_provider 插件，用临时目录顶替应用支持目录，
  // 否则 RouteService 在展开经由站时会抛 MissingPluginException。
  final supportDirectory = Directory.systemTemp.createTempSync(
    'raillog-route-test-',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => switch (call.method) {
          'getApplicationSupportDirectory' ||
          'getTemporaryDirectory' => supportDirectory.path,
          _ => null,
        },
      );
  tearDownAll(() {
    if (supportDirectory.existsSync()) {
      supportDirectory.deleteSync(recursive: true);
    }
  });

  const csv = '''station_name,latitude,longitude
北京站,39.9022,116.4211
济南西站 (中国铁路),36.6700,116.8900
上海虹桥站,31.1960,121.3160
新立屯,42.017975,112.1711389
''';

  group('StationCoordinateIndex', () {
    test('matches station suffix and annotation variants', () {
      final index = StationCoordinateIndex.fromCsv(csv);

      expect(index.find('北京')?.longitude, 116.4211);
      expect(index.find('济南西站')?.latitude, 36.67);
      expect(index.find('上海虹桥站')?.longitude, 121.316);
    });
  });

  group('StationCoordinateIndex.fromSources', () {
    test('takes the pipeline coordinate over the CSV one', () {
      // coordinates.csv 里北京站是 39.9022/116.4211，管线给的这个更贴轨道，相差约 0.5km。
      final index = StationCoordinateIndex.fromSources({
        '北京站': [39.9049, 116.4274],
      }, csv);

      expect(index.find('北京站')?.latitude, 39.9049);
      expect(index.find('北京')?.longitude, 116.4274);
    });

    test('takes it even when it sits hundreds of kilometres away', () {
      // 关键回归：CSV 里的新立屯命中了内蒙古的同名村庄（42.018/112.171），真实的
      // 新立屯站在辽宁（42.019/122.175），两者相距 826km。管线按「车站必须紧邻本
      // 线路的 way」消歧后给出辽宁的坐标——这里不能再拿「离 CSV 太远」把它挡回去，
      // 否则正需要修的那一类错配会原样留下，地图仍会画到内蒙古。
      final index = StationCoordinateIndex.fromSources({
        '新立屯': [42.0194891, 122.1750221],
      }, csv);

      expect(index.find('新立屯')?.latitude, closeTo(42.0194891, 1e-9));
      expect(index.find('新立屯')?.longitude, closeTo(122.1750221, 1e-9));
    });

    test('fills the gaps the CSV does not cover', () {
      final index = StationCoordinateIndex.fromSources({
        '郑州东站': [34.7566, 113.7734],
      }, csv);

      // CSV 里没有郑州东，管线直接补上；同时 CSV 的站一个不少。
      expect(index.find('郑州东站')?.longitude, 113.7734);
      expect(index.find('上海虹桥站')?.longitude, 121.316);
    });

    test('normalizes OSM station names like CSV ones', () {
      final index = StationCoordinateIndex.fromSources({
        '济南西站 (中国铁路)': [36.75, 116.95],
      }, csv);

      expect(index.find('济南西')?.latitude, 36.75);
    });

    test('skips malformed coordinate rows', () {
      final index = StationCoordinateIndex.fromSources({
        '缺经度': [39.9],
        // 越界/非数坐标不该让 find 抛异常，也不该顶掉 CSV。
        '纬度越界': [139.9, 116.4],
        '非数': [double.nan, 116.4],
        '北京站': [double.infinity, 116.4211],
      }, csv);

      expect(index.find('缺经度'), isNull);
      expect(index.find('纬度越界'), isNull);
      expect(index.find('非数'), isNull);
      // 坏行只是「没被采信」，CSV 的值照旧兜底。
      expect(index.find('北京站')?.latitude, 39.9022);
    });

    test('with no OSM stations behaves like fromCsv', () {
      final index = StationCoordinateIndex.fromSources(const {}, csv);

      expect(index.find('北京站')?.longitude, 116.4211);
      expect(index.find('郑州东站'), isNull);
    });

    test('drops the CSV value for a station the pipeline marks unknown', () {
      // 关键回归：新立屯 的 CSV 值命中了内蒙古的同名村庄，管线按里程判定这个站
      // 没有可信坐标，于是在 stations 表里写成 NULL（空列表）。此时**不能**退回
      // CSV——退回去就是把刚舍掉的错坐标原样捡回来，地图照旧画到内蒙古。
      final index = StationCoordinateIndex.fromSources({
        '新立屯': <double>[],
      }, csv);

      expect(index.find('新立屯'), isNull);
      expect(index.find('新立屯站'), isNull);
      // 别的站不受影响。
      expect(index.find('北京站')?.longitude, 116.4211);
    });

    test('an unknown station wins over another spelling that has a value', () {
      // 「永乐」被判定未知，但同一站的另一种写法「永乐站」在别处带着坐标。
      // 两种写法归一化后共用「永乐」这个键，所以删除必须放在所有写入之后，
      // 否则后写入的那个会把错坐标顺着共用键带回来。
      final index = StationCoordinateIndex.fromSources({
        '永乐': <double>[],
        '永乐站': [39.6528815, 116.7884874],
      }, csv);

      expect(index.find('永乐'), isNull);
      expect(index.find('永乐站'), isNull);
    });

    test('keeps the CSV value when the pipeline simply lacks the station', () {
      // 与上一条配对：管线表里**没有**这一行时，CSV 才是兜底，必须留着。
      final index = StationCoordinateIndex.fromSources({
        '郑州东站': [34.7566, 113.7734],
      }, csv);

      expect(index.find('新立屯')?.latitude, 42.017975);
    });
  });

  group('RailStationIndex', () {
    test('reads name and coordinate rows', () {
      final index = RailStationIndex.fromBatches(const [
        {'station_name': '北京南站', 'latitude': 39.865, 'longitude': 116.378},
        {'station_name': '廊坊站', 'latitude': 39.52, 'longitude': 116.7},
      ]);

      expect(index.length, 2);
      expect(index.all['北京南站'], [39.865, 116.378]);
    });

    test('drops rows that cannot be plotted', () {
      final index = RailStationIndex.fromBatches(const [
        {'station_name': '', 'latitude': 39.9, 'longitude': 116.4},
        // 越界坐标多半是数据错位，画出来会把地图拉到地球另一边。
        {'station_name': '纬度越界', 'latitude': 139.9, 'longitude': 116.4},
        {'station_name': '经度越界', 'latitude': 39.9, 'longitude': 216.4},
        {'station_name': '正常站', 'latitude': 39.9, 'longitude': 116.4},
      ]);

      expect(index.all.keys, ['正常站']);
    });

    test('keeps a null-coordinate row as an explicit unknown', () {
      // NULL 不是「画不出来」而是「管线明确判定它没有可信坐标」。这两种行必须能
      // 区分开：前者不许退回 coordinates.csv，后者才可以。
      final index = RailStationIndex.fromBatches(const [
        {'station_name': '永乐', 'latitude': null, 'longitude': null},
        {'station_name': '正常站', 'latitude': 39.9, 'longitude': 116.4},
      ]);

      expect(index.all['永乐'], isEmpty);
      expect(index.all.keys, ['永乐', '正常站']);
    });

    test('empty index has nothing to offer', () {
      expect(const RailStationIndex.empty().isEmpty, isTrue);
      expect(const RailTrackData.empty().stations.isEmpty, isTrue);
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
          trips.first.clientId: const JourneyStations.of([
            '北京站',
            '济南西站',
            '上海虹桥站',
          ]),
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
          trip.clientId: const JourneyStations.of([
            '未知站',
            '济南西站',
            '上海虹桥站',
          ]),
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
            forward.clientId: const JourneyStations.of([
              '北京站',
              '济南西站',
              '上海虹桥站',
            ]),
            reverse.clientId: const JourneyStations.of([
              '上海虹桥站',
              '济南西站',
              '北京站',
            ]),
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
        longTrip.clientId: const JourneyStations.of([
          '北京站',
          '济南西站',
          '上海虹桥站',
        ]),
        shortTrip.clientId: const JourneyStations.of(['北京站', '济南西站']),
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
    final journey = result[trip.clientId]!;
    final reverseJourney = result[reverseTrip.clientId]!;
    final stations = journey.stations;

    expect(stations.first, '北京南站');
    expect(stations.last, '上海虹桥站');
    expect(stations.length, greaterThan(2));
    expect(reverseJourney.stations, stations.reversed);

    // 每一段都要标注出线路名，否则查不到轨道折线，地图会退回直线。
    expect(journey.legRouteNames, hasLength(stations.length - 1));
    expect(journey.legRouteNames, everyElement('京沪高速线'));
  });

  test('journey stations carry the route each leg belongs to', () async {
    // 两段经由两条不同线路：每段的线路名必须跟着段走，而不是整程一个名字。
    final trip = _trip(
      id: 30,
      date: DateTime(2026, 1, 1),
      fromStation: '北京南站',
      toStation: '上海虹桥站',
      segments: const [
        ViaRouteSegment(
          routeName: '京沪高速铁路',
          fromStation: '北京南站',
          toStation: '济南西站',
        ),
        ViaRouteSegment(
          routeName: '京沪高速铁路',
          fromStation: '济南西站',
          toStation: '上海虹桥站',
        ),
      ],
    );

    final journey = (await RouteService.resolveTripStations([trip]))[trip
        .clientId]!;

    expect(journey.legRouteNames, hasLength(journey.stations.length - 1));
    expect(journey.legRouteNames, everyElement('京沪高速线'));

    // 中途站名来自 routes.db（不带「站」后缀），首尾站名来自行程数据。
    final legIndex = journey.stations.indexOf('济南西');
    expect(legIndex, greaterThan(0));
    expect(journey.routeNameForLeg(legIndex - 1), '京沪高速线');
    expect(journey.routeNameForLeg(legIndex), '京沪高速线');
    expect(journey.routeNameForLeg(journey.legRouteNames.length), '');
  });

  group('track-key normalization', () {
    // 这些期望值取自 tools/osm_update/rail_track_geometry.py 的 track_key()，
    // 两边必须逐字一致，否则管线生成的折线一条都查不到。
    test('matches the Python side key format', () {
      expect(
        trackKeyOf('京沪高速线', '北京南', '廊坊'),
        '京沪高速|北京南|廊坊',
      );
      expect(
        trackKeyOf('京沪高速铁路', '北京南站', '廊坊站'),
        trackKeyOf('京沪高速线', '北京南', '廊坊'),
      );
      // 站名去「站」后缀、去尾部括号注释、去空白、转小写；线路名只去「线/铁路」后缀。
      expect(
        trackKeyOf('宝成线', ' 宝鸡站 (中国铁路) ', '凤州站'),
        '宝成|宝鸡|凤州',
      );
      expect(trackKeyOf('Z99次', 'A站', 'B站'), 'z99次|a|b');
    });
  });

  group('RailTrackIndex', () {
    test('finds a leg by route and station names, both directions', () {
      final tracks = _indexWith({
        '京沪高速线|北京南|廊坊': [
          [39.865, 116.378],
          [39.7, 116.5],
          [39.52, 116.7],
        ],
      });

      expect(tracks.findOriented('京沪高速线', '北京南', '廊坊').single, hasLength(3));
      // 反向乘车用反向键命中同一条折线，渲染层负责倒序。
      expect(tracks.findOriented('京沪高速线', '廊坊', '北京南').single, hasLength(3));
      expect(tracks.findOriented('宝成线', '北京南', '廊坊').isEmpty, isTrue);
      expect(tracks.findOriented('京沪高速线', '北京南', '天津南').isEmpty, isTrue);
    });

    test('empty index reports no tracks', () {
      final track = const RailTrackIndex.empty().findOriented('京沪高速线', '北京南', '廊坊');
      expect(track.isEmpty, isTrue);
      expect(track.isSplit, isFalse);
    });

    test('reads up/down rows as a split pair', () {
      final tracks = _indexWith({
        '阳安线|石泉县|池河': [
          [33.0, 108.0],
          [33.05, 108.0],
          [33.1, 108.0],
        ],
      }, split: {
        '阳安线|石泉县|池河': {
          'up': [
            [33.0, 108.0],
            [33.05, 108.0],
            [33.1, 108.0],
          ],
          'down': [
            [33.0, 108.0],
            [33.05, 108.004],
            [33.1, 108.0],
          ],
        },
      });

      final track = tracks.findOriented('阳安线', '石泉县', '池河');
      expect(track.isSplit, isTrue);
      expect(track.up, hasLength(3));
      expect(track.down, hasLength(3));
      // 单条折线时用上行线；这里不该再看见中心线。
      expect(track.single, isNull);
      expect(track.singleOrUp, same(track.up));
    });

    test('a lone up row falls back to the single line', () {
      // 缺一条就不算分离：画出半截上下行比画一条中心线更糟。
      final tracks = _indexWith(const {}, split: {
        '阳安线|石泉县|池河': {
          'up': [
            [33.0, 108.0],
            [33.1, 108.0],
          ],
        },
      });

      expect(tracks.findOriented('阳安线', '石泉县', '池河').isEmpty, isTrue);
    });
  });

  group('TripMapService polyline injection', () {
    test('draws the railway polyline instead of a straight line', () {
      final index = StationCoordinateIndex.fromCsv(csv);
      final trip = _trip(id: 40, date: DateTime(2026, 1, 1));
      final tracks = _indexWith({
        '京沪高速线|北京|济南西': [
          [39.9022, 116.4211],
          [38.5, 116.6],
          [37.5, 116.75],
          [36.67, 116.89],
        ],
      });

      final data = TripMapService.buildData(
        [trip],
        index,
        journeyStations: {
          trip.clientId: const JourneyStations(
            stations: ['北京站', '济南西站'],
            legRouteNames: ['京沪高速铁路'],
          ),
        },
        tracks: tracks,
      );

      final points = data.routes.single.points;
      expect(points, hasLength(4));
      // 端点必须是精确站坐标，否则相邻区段拼不上、往返方向判定也会错。
      expect(points.first.latitude, 39.9022);
      expect(points.first.longitude, 116.4211);
      expect(points.last.latitude, 36.67);
      expect(points.last.longitude, 116.89);
      // 中间点来自折线，不再是站间直线。
      expect(points[1].latitude, 38.5);
    });

    test('bridges across a station the pipeline marked unknown', () {
      // 关键回归：永乐 的坐标命中了北京的永乐店（39.6529/116.7885），而它在南昆线上，
      // 夹在百色与下塘之间。管线按里程判定它没有可信坐标，写成 NULL 行。App 必须
      // ①不回退 CSV 的那个错坐标、②跳过该站，把百色→下塘合成一段——而管线恰好为
      // 这一段写了折线，所以点开地图看到的是真实走向，不是横穿半个中国的直线。
      const southKunmingCsv = '''station_name,latitude,longitude
百色站,23.8881,106.6607
永乐,39.6528815,116.7884874
下塘站,23.4000,106.9000
''';
      final index = StationCoordinateIndex.fromSources(const {
        '百色站': [23.8881, 106.6607],
        '下塘站': [23.4000, 106.9000],
        // 空列表 = 管线明确说这个站没有可信坐标。
        '永乐': <double>[],
      }, southKunmingCsv);
      final trip = _trip(
        id: 42,
        date: DateTime(2026, 1, 1),
        fromStation: '百色站',
        toStation: '下塘站',
        segments: const [
          ViaRouteSegment(
            routeName: '南昆线',
            fromStation: '百色站',
            toStation: '下塘站',
          ),
        ],
      );
      final tracks = _indexWith({
        '南昆线|百色|下塘': [
          [23.8881, 106.6607],
          [23.6500, 106.8000],
          [23.4000, 106.9000],
        ],
      });

      final data = TripMapService.buildData(
        [trip],
        index,
        journeyStations: {
          trip.clientId: const JourneyStations(
            stations: ['百色站', '永乐', '下塘站'],
            legRouteNames: ['南昆线', '南昆线', '南昆线'],
          ),
        },
        tracks: tracks,
      );

      final points = data.routes.single.points;
      // 中间点是折线，不是绕到北京去的两个直线段。
      expect(points, hasLength(3));
      expect(points[1].latitude, 23.65);
      // 被舍去的那个坐标不该出现在任何地方。
      expect(
        points.map((point) => point.longitude),
        isNot(contains(closeTo(116.7884874, 1e-6))),
      );
      // 站定位不了要如实报给用户，而不是悄悄跳过。
      expect(data.missingStations, contains('永乐'));
    });

    test('falls back to a straight line when no track is available', () {
      final index = StationCoordinateIndex.fromCsv(csv);
      final trip = _trip(id: 41, date: DateTime(2026, 1, 1));

      final data = TripMapService.buildData(
        [trip],
        index,
        journeyStations: {
          trip.clientId: const JourneyStations(
            stations: ['北京站', '济南西站'],
            legRouteNames: ['京沪高速铁路'],
          ),
        },
        tracks: const RailTrackIndex.empty(),
      );

      expect(data.routes.single.points, hasLength(2));
    });

    test('ignores tracks when a leg has no route name', () {
      final index = StationCoordinateIndex.fromCsv(csv);
      final trip = _trip(id: 42, date: DateTime(2026, 1, 1));
      final tracks = _indexWith({
        '京沪高速线|北京|济南西': [
          [39.9022, 116.4211],
          [39.0, 116.6],
          [36.67, 116.89],
        ],
      });

      final data = TripMapService.buildData(
        [trip],
        index,
        // 没有线路标注：查不到折线，只能画直线。
        journeyStations: {
          trip.clientId: const JourneyStations.of(['北京站', '济南西站']),
        },
        tracks: tracks,
      );

      expect(data.routes.single.points, hasLength(2));
    });

    test('injects a polyline per leg when a journey spans two lines', () {
      final index = StationCoordinateIndex.fromCsv(csv);
      final trip = _trip(id: 43, date: DateTime(2026, 1, 1));
      final tracks = _indexWith({
        '京沪高速线|北京|济南西': [
          [39.9022, 116.4211],
          [38.5, 116.6],
          [36.67, 116.89],
        ],
        '胶济客专线|济南西|上海虹桥': [
          [36.67, 116.89],
          [34.0, 118.5],
          [31.196, 121.316],
        ],
      });

      final data = TripMapService.buildData(
        [trip],
        index,
        journeyStations: {
          trip.clientId: const JourneyStations(
            stations: ['北京站', '济南西站', '上海虹桥站'],
            legRouteNames: ['京沪高速铁路', '胶济客专线'],
          ),
        },
        tracks: tracks,
      );

      // 两段首尾相接、同一趟车，会被合并成一条：3 + 3 点去掉重复的交点 = 5 点。
      expect(data.routes, hasLength(1));
      final points = data.routes.single.points;
      expect(points, hasLength(5));
      expect(points.first.latitude, 39.9022);
      expect(points.last.longitude, 121.316);
      // 两段各自的折线都要在：只有一段命中时这里会是直线上的点。
      expect(points.map((point) => point.latitude), contains(38.5));
      expect(points.map((point) => point.latitude), contains(34.0));
      // 交点只保留一次。
      expect(
        points.where((point) => point.latitude == 36.67 && point.longitude == 116.89),
        hasLength(1),
      );
    });

    test('resolves a leg from a later train when the first has no route name', () {
      final index = StationCoordinateIndex.fromCsv(csv);
      final unlabeled = _trip(id: 44, date: DateTime(2026, 1, 1));
      final labeled = _trip(id: 45, date: DateTime(2026, 1, 2));
      final tracks = _indexWith({
        '京沪高速线|北京|济南西': [
          [39.9022, 116.4211],
          [38.5, 116.6],
          [36.67, 116.89],
        ],
      });

      final data = TripMapService.buildData(
        [unlabeled, labeled],
        index,
        journeyStations: {
          // 先来的这趟没标线路名，建组时只能给它画直线。
          unlabeled.clientId: const JourneyStations.of(['北京站', '济南西站']),
          labeled.clientId: const JourneyStations(
            stations: ['北京站', '济南西站'],
            legRouteNames: ['京沪高速铁路'],
          ),
        },
        tracks: tracks,
      );

      // 后一趟的线路名必须能把整组救回折线，否则这段就白白画成直线了。
      expect(data.routes, hasLength(1));
      expect(data.routes.single.points, hasLength(3));
      expect(
        data.routes.single.points.map((point) => point.latitude),
        contains(38.5),
      );
      expect(
        data.routes.single.entries.map((entry) => entry.trainNumber),
        containsAll(['G44', 'G45']),
      );
    });

    test('两条线路共用同一对坐标时各画各的折线', () {
      // 客专线与普速线在同一个城市各有一个坐标接近的车站，客里表把它们并到一处，
      // 两条线的行程于是落在同一对坐标上。按坐标建组的话，先来的那条线的折线会
      // 顶给整组——普速车被画到客专上，而客专的车点开看到的是普速车。
      final index = StationCoordinateIndex.fromCsv(csv);
      final highSpeed = _trip(id: 46, date: DateTime(2026, 1, 1));
      final conventional = _trip(
        id: 47,
        date: DateTime(2026, 1, 2),
        segments: const [
          ViaRouteSegment(
            routeName: '京沪线',
            fromStation: '北京站',
            toStation: '济南西站',
          ),
        ],
      );
      final tracks = _indexWith({
        '京沪高速线|北京|济南西': [
          [39.9022, 116.4211],
          [38.0, 116.7],
          [36.67, 116.89],
        ],
        '京沪线|北京|济南西': [
          [39.9022, 116.4211],
          [38.6, 116.4],
          [36.67, 116.89],
        ],
      });

      final data = TripMapService.buildData(
        [highSpeed, conventional],
        index,
        journeyStations: {
          highSpeed.clientId: const JourneyStations(
            stations: ['北京站', '济南西站'],
            legRouteNames: ['京沪高速铁路'],
          ),
          conventional.clientId: const JourneyStations(
            stations: ['北京站', '济南西站'],
            legRouteNames: ['京沪线'],
          ),
        },
        tracks: tracks,
      );

      expect(data.routes, hasLength(2));
      // 两条折线各自的那一站都要在，且不在一组里。
      final latitudes = [
        for (final route in data.routes)
          [for (final point in route.points) point.latitude],
      ];
      expect(latitudes.where((lats) => lats.contains(38.0)), hasLength(1));
      expect(latitudes.where((lats) => lats.contains(38.6)), hasLength(1));
      // 车次也各归各的：点开客专线只应看到动车，点开普速线只应看到普速车。
      final byHighSpeed = data.routes.firstWhere(
        (route) => route.points.any((point) => point.latitude == 38.0),
      );
      expect(byHighSpeed.entries.map((entry) => entry.trainNumber), ['G46']);
      final byConventional = data.routes.firstWhere(
        (route) => route.points.any((point) => point.latitude == 38.6),
      );
      expect(byConventional.entries.map((entry) => entry.trainNumber), ['G47']);
    });
  });

  group('TripMapService up/down separation', () {
    const splitLines = {
      '京沪高速线|北京|济南西': {
        'up': [
          [39.9022, 116.4211],
          [38.5, 116.60],
          [36.67, 116.89],
        ],
        'down': [
          [39.9022, 116.4211],
          [38.5, 116.70],
          [36.67, 116.89],
        ],
      },
    };

    TripMapData buildSplit({int id = 46}) {
      final index = StationCoordinateIndex.fromCsv(csv);
      final trip = _trip(id: id, date: DateTime(2026, 1, 1));
      return TripMapService.buildData(
        [trip],
        index,
        journeyStations: {
          trip.clientId: const JourneyStations(
            stations: ['北京站', '济南西站'],
            legRouteNames: ['京沪高速铁路'],
          ),
        },
        tracks: _indexWith(const {}, split: splitLines),
      );
    }

    test('carries the down line alongside the up line', () {
      final route = buildSplit().routes.single;

      // 上行线走 points、下行线走 splitPoints，两条都是「从→到」的走向。
      expect(route.points[1].longitude, 116.60);
      expect(route.splitPoints, isNotNull);
      expect(route.splitPoints![1].longitude, 116.70);
      expect(route.splitPoints!.first.latitude, route.points.first.latitude);
      expect(route.splitPoints!.last.latitude, route.points.last.latitude);
    });

    test('renders the down line reversed, never the same line twice', () {
      final routes = buildSplit().routes;
      final down = [
        for (final point in routes.single.splitPoints!) point.amapPosition,
      ];

      final html = buildAmapHtml(
        routes,
        darkMode: false,
        backgroundColor: '#FFFFFF',
        showStationMarkers: false,
      );

      expect(html, contains('"splitCoordinates"'));
      expect(html, contains(jsonEncode(down)));
      // 下行线倒序画：南行列车走的是它，脉冲方向才对得上。
      expect(html, contains('route.splitCoordinates.slice().reverse()'));
    });
  });

  group('TripMapService shadowed straight lines', () {
    // 多一个中间站，好让另一趟车展开成一条盖住直线的折线。
    const expandedCsv = '''station_name,latitude,longitude
北京站,39.9022,116.4211
德州东站,37.4300,116.3600
济南西站 (中国铁路),36.6700,116.8900
''';

    final tracks = {
      '京沪高速线|北京|德州东': [
        [39.9022, 116.4211],
        [38.5, 116.40],
        [37.43, 116.36],
      ],
      '京沪高速线|德州东|济南西': [
        [37.43, 116.36],
        [37.0, 116.60],
        [36.67, 116.89],
      ],
    };

    /// 一趟只记了两站的行程（画直线）+ 一趟展开到中间站的行程（画折线）。
    TripMapData buildShadowed({required List<String> expandedStations}) {
      final index = StationCoordinateIndex.fromCsv(expandedCsv);
      final direct = _trip(
        id: 70,
        date: DateTime(2026, 1, 2),
        toStation: '济南西站',
      );
      final expanded = _trip(id: 71, date: DateTime(2026, 1, 3));
      final labels = [
        for (var i = 0; i < expandedStations.length - 1; i++) '京沪高速铁路',
      ];

      return TripMapService.buildData(
        [direct, expanded],
        index,
        journeyStations: {
          direct.clientId: const JourneyStations.of(['北京站', '济南西站']),
          expanded.clientId: JourneyStations(
            stations: expandedStations,
            legRouteNames: labels,
          ),
        },
        tracks: _indexWith(tracks),
      );
    }

    test('absorbs a straight leg the expanded polyline already covers', () {
      final data = buildShadowed(
        expandedStations: const ['北京站', '德州东站', '济南西站'],
      );

      // 两条 route 的端点坐标不同（一条是直线两端、一条是展开后的合并），分组键对不上，
      // 谁也不合并——不吞掉直线就会并排画出「真实折线 + 直线」两条。
      expect(data.routes, hasLength(1));
      expect(data.routes.single.points.length, greaterThan(2));
      expect(
        data.routes.single.points.map((point) => point.latitude),
        contains(38.5),
      );
      // 车次不能跟着直线一起丢。
      expect(
        data.routes.single.entries.map((entry) => entry.trainNumber),
        containsAll(['G70', 'G71']),
      );
      // 同向并进去，走向不变。
      expect(data.routes.single.direction, TripMapDirection.direction1);
    });

    test('flips an absorbed train when the covering polyline runs the other way', () {
      final data = buildShadowed(
        expandedStations: const ['济南西站', '德州东站', '北京站'],
      );

      final route = data.routes.single;
      expect(data.routes, hasLength(1));
      // 折线是 济南西→北京，直线的车次是 北京→济南西，并进去要翻成反向。
      expect(route.points.first.latitude, 36.67);
      final byTrain = {
        for (final entry in route.entries) entry.trainNumber: entry.direction,
      };
      expect(byTrain['G70'], TripMapDirection.direction2);
      expect(byTrain['G71'], TripMapDirection.direction1);
      expect(route.direction, TripMapDirection.bidirectional);
    });
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

  group('buildAmapHtml 生成的脚本', () {
    // 那段 JS 是手写着一行行拼进 Dart 字符串的，编译期没人管它。少一个括号时浏览器
    // 只抛 SyntaxError，**整段脚本都不执行**——`new AMap.Map` 没跑，地图区域就是一
    // 片白，而 Dart 这边一点异常都没有，测试也照样全绿（2026-09 就是这么白屏的）。
    // 所以这里把脚本块掏出来做一次括号配平，专拦这一类低级错。
    test('括号配平', () {
      final route = TripMapRoute(
        name: '北京站 - 上海虹桥站',
        entries: const [],
        direction: TripMapDirection.direction1,
        fromStation: '北京站',
        toStation: '上海虹桥站',
        fromCoordinate: StationCoordinate(latitude: 39.9, longitude: 116.4),
        toCoordinate: StationCoordinate(latitude: 31.2, longitude: 121.3),
        points: [
          StationCoordinate(latitude: 39.9, longitude: 116.4),
          StationCoordinate(latitude: 31.2, longitude: 121.3),
        ],
        splitPoints: [
          StationCoordinate(latitude: 39.85, longitude: 116.4),
          StationCoordinate(latitude: 31.15, longitude: 121.3),
        ],
      );

      // 带车站标记的那份代码最全（多一段 endpoints/markers）。
      final html = buildAmapHtml(
        [route],
        darkMode: false,
        backgroundColor: '#FFFFFF',
        showStationMarkers: true,
        endpoints: [
          TripMapEndpoint(
            station: '北京站 (中国铁路)',
            coordinate: StationCoordinate(latitude: 39.9, longitude: 116.4),
          ),
        ],
      );

      final match = RegExp(
        r'<script>\n([\s\S]*?)\n\s*</script>',
      ).firstMatch(html);
      expect(match, isNotNull, reason: '没找到内联的 <script> 块');
      expectBalancedBrackets(match!.group(1)!);
    });
  });

  group('反向查到的折线要掉头', () {
    // 管线按方向各存一行，一趟车走过的方向不一定有那一行。这时用反向键命中的折线
    // 必须倒过来再交给渲染层，否则它会被当成 from→to 的点列，首尾各被补上一个站坐标，
    // 画成「站间直线 + 倒着走的真轨 + 站间直线」的往返折返。
    final forward = {
      '京沪高速线|北京|济南西': [
        [39.9022, 116.4211],
        [38.5, 116.6],
        [37.5, 116.75],
        [36.67, 116.89],
      ],
    };

    test('findOriented 命中反向键时把点序倒过来', () {
      final tracks = _indexWith(forward);

      final direct = tracks.findOriented('京沪高速线', '北京', '济南西').single!;
      expect(direct.first, [39.9022, 116.4211]);
      expect(direct.last, [36.67, 116.89]);

      final reversed = tracks.findOriented('京沪高速线', '济南西', '北京').single!;
      expect(reversed.first, [36.67, 116.89]);
      expect(reversed.last, [39.9022, 116.4211]);
    });

    test('上下行分离的折线掉头时上下行对调', () {
      // 「沿 from→to 左手边的是上行」，走向掉个头，原来的下行才是这趟车眼里的上行。
      final tracks = _indexWith(const {}, split: {
        '阳安线|石泉县|池河': {
          'up': [
            [33.0, 108.0],
            [33.05, 108.0],
          ],
          'down': [
            [33.0, 108.004],
            [33.05, 108.004],
          ],
        },
      });

      final track = tracks.findOriented('阳安线', '池河', '石泉县');
      expect(track.isSplit, isTrue);
      expect(track.up!.first, [33.05, 108.004]);
      expect(track.up!.last, [33.0, 108.004]);
      expect(track.down!.first, [33.05, 108.0]);
      expect(track.down!.last, [33.0, 108.0]);
    });

    test('反向乘车的行程贴着轨道，不来回折返', () {
      final index = StationCoordinateIndex.fromCsv(csv);
      // 库里只有北京→济南西这一行，这趟车走的是反方向。
      final tracks = _indexWith(forward);

      ({List<StationCoordinate> points, double km}) routeOf(
        int id,
        String fromStation,
        String toStation,
      ) {
        final trip = _trip(
          id: id,
          date: DateTime(2026, 1, 1),
          fromStation: fromStation,
          toStation: toStation,
        );
        final data = TripMapService.buildData(
          [trip],
          index,
          journeyStations: {
            trip.clientId: JourneyStations(
              stations: [fromStation, toStation],
              legRouteNames: const ['京沪高速铁路'],
            ),
          },
          tracks: tracks,
        );
        final points = data.routes.single.points;
        var km = 0.0;
        for (var index = 0; index < points.length - 1; index++) {
          km += _distanceKm(points[index], points[index + 1]);
        }
        return (points: points, km: km);
      }

      final forwardRoute = routeOf(43, '北京站', '济南西站');
      final reverseRoute = routeOf(44, '济南西站', '北京站');

      expect(reverseRoute.points, hasLength(4));
      expect(reverseRoute.points.first.latitude, 36.67);
      expect(reverseRoute.points.last.latitude, 39.9022);
      // 折返会在首尾各拉一条 300km 的直线，路径长度直接多出一倍多；贴住轨道则长度不变。
      expect(reverseRoute.km, closeTo(forwardRoute.km, 0.01));
    });
  });
}

double _distanceKm(StationCoordinate a, StationCoordinate b) {
  const radius = 6371.0088;
  final latitude1 = a.latitude * math.pi / 180;
  final latitude2 = b.latitude * math.pi / 180;
  final deltaLatitude = latitude2 - latitude1;
  final deltaLongitude = (b.longitude - a.longitude) * math.pi / 180;
  final h =
      math.pow(math.sin(deltaLatitude / 2), 2) +
      math.cos(latitude1) *
          math.cos(latitude2) *
          math.pow(math.sin(deltaLongitude / 2), 2);
  return 2 * radius * math.asin(math.sqrt(h));
}

/// 扫一遍 JS，跳过字符串字面量与 `//` 注释，检查 `()`、`[]`、`{}` 是否配平。
///
/// 只管括号对不对得上——漏个分号、写错个属性名它看不出来，那种错得靠浏览器。
void expectBalancedBrackets(String source) {
  const openers = '([{';
  const closers = ')]}';
  const matching = {'(': ')', '[': ']', '{': '}'};
  final stack = <(String, int)>[];
  var line = 1;
  for (var index = 0; index < source.length; index++) {
    final char = source[index];
    if (char == '\n') {
      line++;
      continue;
    }
    if (char == "'" || char == '"') {
      index++;
      while (index < source.length) {
        final inner = source[index];
        if (inner == r'\') {
          index += 2;
          continue;
        }
        if (inner == '\n') line++;
        if (inner == char) break;
        index++;
      }
      continue;
    }
    if (char == '/' &&
        index + 1 < source.length &&
        source[index + 1] == '/') {
      while (index < source.length && source[index] != '\n') {
        index++;
      }
      continue;
    }
    if (openers.contains(char)) {
      stack.add((char, line));
      continue;
    }
    if (closers.contains(char)) {
      expect(
        stack,
        isNotEmpty,
        reason: '第 $line 行多出一个 $char（前面没有对应的开括号）',
      );
      final (opened, openedLine) = stack.removeLast();
      expect(
        matching[opened],
        char,
        reason: '第 $line 行的 $char 和第 $openedLine 行的 $opened 对不上',
      );
    }
  }
  expect(
    stack,
    isEmpty,
    reason: '这些括号没闭合：'
        '${stack.map((entry) => '第 ${entry.$2} 行的 ${entry.$1}').join('、')}',
  );
}

/// 用 `线路名|起点站|终点站` 造一份轨道索引。
///
/// 键里的名字按 rail_tracks.db 里的原样写（线路名带「线」、站名不带「站」后缀），
/// 由 RailTrackIndex 自己归一化；polyline 走真实的 gzip(JSON) 编码，与管线一致。
///
/// [split] 造上下行分离的两行（`'up'`/`'down'`），与管线的 `direction` 列对应。
RailTrackIndex _indexWith(
  Map<String, List<List<double>>> tracks, {
  Map<String, Map<String, List<List<double>>>> split = const {},
}) {
  final rows = <Map<String, Object?>>[];
  void add(String key, String direction, List<List<double>> points) {
    final parts = key.split('|');
    rows.add({
      'route_name': parts[0],
      'from_station': parts[1],
      'to_station': parts[2],
      'direction': direction,
      'polyline': gzip.encode(utf8.encode(jsonEncode(points))),
    });
  }

  for (final entry in tracks.entries) {
    add(entry.key, '', entry.value);
  }
  for (final entry in split.entries) {
    for (final line in entry.value.entries) {
      add(entry.key, line.key, line.value);
    }
  }
  return RailTrackIndex.fromBatches(rows);
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
