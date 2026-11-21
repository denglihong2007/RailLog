import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/journey_stations.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/trip_schedule_times.dart';
import 'package:raillog/src/models/via_route_segment.dart';
import 'package:raillog/src/services/rail_track_service.dart';
import 'package:raillog/src/services/trip_animation_service.dart';
import 'package:raillog/src/services/trip_map_service.dart';

void main() {
  // 三站都在 CSV 里，中间站济南西的站名带注释，靠 StationCoordinateIndex 的
  // 归一化才能查到坐标。
  const csv = '''station_name,latitude,longitude
北京站,39.9022,116.4211
济南西站 (中国铁路),36.6700,116.8900
上海虹桥站,31.1960,121.3160
''';
  final coordinates = StationCoordinateIndex.fromCsv(csv);

  const stations = ['北京站', '济南西站', '上海虹桥站'];
  const lines = ['京沪高速铁路', '京沪高速铁路'];
  const lineColors = {'京沪高速铁路': '#1565C0'};

  // 时刻已经换算成绝对时间；动画服务只关心站名、到发时刻和里程。
  TrainScheduleStop stop({
    required String name,
    DateTime? arrival,
    DateTime? departure,
    double? mileage,
  }) => TrainScheduleStop(
    stationName: name,
    stationNo: '',
    arriveTime: '',
    startTime: '',
    runningTime: '',
    arriveDay: '',
    arriveDayDifference: 0,
    mileage: mileage,
    arrivalDateTime: arrival,
    departureDateTime: departure,
  );

  TripRecord trip({
    DateTime? departureTime,
    DateTime? arrivalTime,
    String fromStation = '北京站',
    String toStation = '上海虹桥站',
  }) => TripRecord(
    id: 1,
    trainNumber: 'G1',
    fromStation: fromStation,
    toStation: toStation,
    departureTime: departureTime ?? DateTime(2026, 1, 1, 8),
    arrivalTime: arrivalTime,
    viaRouteSegments: const [
      ViaRouteSegment(
        routeName: '京沪高速铁路',
        fromStation: '北京站',
        toStation: '上海虹桥站',
      ),
    ],
  );

  TripAnimationPlan? build({
    required TripRecord record,
    List<String> stationNames = stations,
    List<String> legRouteNames = lines,
    TripScheduleOverlay overlay = const TripScheduleOverlay(),
    RailTrackIndex? tracks,
    Map<String, String> colors = lineColors,
    StationCoordinateIndex? coordinateIndex,
  }) => TripAnimationService.build(
    trip: record,
    stationNames: stationNames,
    legRouteNames: legRouteNames,
    coordinates: coordinateIndex ?? coordinates,
    tracks: tracks,
    overlay: overlay,
    lineColors: colors,
    fallbackColor: '#9E9E9E',
  );

  /// 造一份与行程首末时刻一致的历史时刻表；中间站可以指定是通过还是停站。
  ///
  /// 默认中间站到发相同，按通过处理；给 [middleDwell] 才是有停站的办客站。
  TripScheduleOverlay schedule({
    DateTime? departure,
    DateTime? arrival,
    bool middleIsPass = false,
    Duration middleDwell = Duration.zero,
  }) {
    final start = departure ?? DateTime(2026, 1, 1, 8);
    final end = arrival ?? DateTime(2026, 1, 1, 13);
    final middle = start.add(end.difference(start) ~/ 2);
    final middleDeparture = middleIsPass ? middle : middle.add(middleDwell);
    final times = TripScheduleTimes.match(
      resolvedStops: [
        stop(name: '北京站', departure: start, mileage: 0),
        stop(
          name: '济南西站',
          arrival: middle,
          departure: middleDeparture,
          mileage: 400,
        ),
        stop(name: '上海虹桥站', arrival: end, mileage: 1300),
      ],
      boardingIndex: 0,
      alightingIndex: 2,
      departureTime: start,
      arrivalTime: arrival,
    )!;
    return TripScheduleOverlay(times: times);
  }

  group('TripAnimationService.build', () {
    test('没有时刻表时用行程到发时刻按里程插值中间站', () {
      final record = trip(
        departureTime: DateTime(2026, 1, 1, 8),
        arrivalTime: DateTime(2026, 1, 1, 13),
      );
      final plan = build(record: record)!;

      expect(plan.departure, DateTime(2026, 1, 1, 8));
      expect(plan.arrival, DateTime(2026, 1, 1, 13));
      expect(plan.sourceLabel, '行程时刻');
      expect(plan.stops, hasLength(3));
      expect(plan.moves, hasLength(2));

      // 济南西按里程比例落在 8:00–13:00 之间，既不是正中间也不是两端。
      final middle = plan.stops[1];
      expect(middle.estimated, isTrue);
      expect(middle.arrival!.isAfter(plan.departure), isTrue);
      expect(middle.arrival!.isBefore(plan.arrival), isTrue);
      expect(middle.arrival, middle.departure);

      // 首站只有发车、末站只有到达，与简图的显示口径一致。
      expect(plan.stops[0].arrival, isNull);
      expect(plan.stops[0].departure, DateTime(2026, 1, 1, 8));
      expect(plan.stops[2].departure, isNull);
      expect(plan.stops[2].arrival, DateTime(2026, 1, 1, 13));
    });

    test('有历史时刻表时用时刻表的站时刻，并标出来源', () {
      final record = trip();
      final plan = build(
        record: record,
        overlay: schedule(middleDwell: const Duration(minutes: 5)),
      )!;

      expect(plan.sourceLabel, '历史时刻表');
      expect(plan.stops[1].arrival, DateTime(2026, 1, 1, 10, 30));
      expect(plan.stops[1].departure, DateTime(2026, 1, 1, 10, 35));
      expect(plan.stops[1].estimated, isFalse);
      expect(plan.stops[1].kind, TripAnimationStopKind.stop);
      expect(plan.stops[2].arrival, DateTime(2026, 1, 1, 13));
    });

    test('每个区间的起止时刻首尾相接，不会重叠或倒流', () {
      final plan = build(record: trip(), overlay: schedule())!;
      expect(plan.moves[0].start, plan.stops[0].departure);
      expect(plan.moves[0].end, plan.stops[1].arrival);
      expect(plan.moves[1].start, plan.stops[1].departure);
      expect(plan.moves[1].end, plan.stops[2].arrival);
      for (final move in plan.moves) {
        expect(move.end.isAfter(move.start), isTrue);
      }
    });

    test('停站时间计入时间轴，开行时刻从发车而不是到达算起', () {
      final record = trip();
      final plan = build(record: record, overlay: schedule())!;
      // 中间站到发相同（没有停站数据）时，第二段直接接在第一段后面。
      expect(plan.moves[1].start, plan.moves[0].end);

      final withDwell = TripScheduleOverlay(
        customTimes: {
          stationOccurrenceKeys(stations)[1]: StationScheduleTime(
            arrival: DateTime(2026, 1, 1, 10, 30),
            departure: DateTime(2026, 1, 1, 10, 35),
          ),
        },
      );
      final dwellPlan = build(record: record, overlay: withDwell)!;
      expect(dwellPlan.stops[1].arrival, DateTime(2026, 1, 1, 10, 30));
      expect(dwellPlan.stops[1].departure, DateTime(2026, 1, 1, 10, 35));
      expect(dwellPlan.moves[0].end, DateTime(2026, 1, 1, 10, 30));
      expect(dwellPlan.moves[1].start, DateTime(2026, 1, 1, 10, 35));
    });

    test('通过站用同一时刻到达与离开', () {
      final record = trip();
      final overlay = TripScheduleOverlay(
        customTimes: {
          stationOccurrenceKeys(stations)[1]: StationScheduleTime(
            passTime: DateTime(2026, 1, 1, 10),
          ),
        },
      );
      final plan = build(record: record, overlay: overlay)!;
      expect(plan.stops[1].kind, TripAnimationStopKind.pass);
      expect(plan.stops[1].arrival, DateTime(2026, 1, 1, 10));
      expect(plan.stops[1].departure, DateTime(2026, 1, 1, 10));
    });

    test('行程缺到达时刻时按里程估一个终点', () {
      final record = trip(departureTime: DateTime(2026, 1, 1, 8));
      final plan = build(record: record)!;
      expect(plan.sourceLabel, '按里程估算');
      expect(plan.arrival.isAfter(plan.departure), isTrue);
      // 1000km 上下按 200km/h 估算，应在 4~6 小时这个量级。
      final hours = plan.arrival.difference(plan.departure).inMinutes / 60;
      expect(hours, greaterThan(3));
      expect(hours, lessThan(7));
    });

    test('相邻重复坐标被跳过，无法定位的站也不进时间轴', () {
      const withMissing = ['北京站', '不存在的站', '济南西站', '济南西站', '上海虹桥站'];
      const missingLines = [
        '京沪高速铁路',
        '京沪高速铁路',
        '京沪高速铁路',
        '京沪高速铁路',
      ];
      final plan = build(
        record: trip(),
        stationNames: withMissing,
        legRouteNames: missingLines,
      )!;
      expect(plan.stops.map((stop) => stop.name), stations);
      expect(plan.moves, hasLength(2));
    });

    test('站点不足两个坐标时返回 null', () {
      expect(
        build(record: trip(), stationNames: const ['北京站']),
        isNull,
      );
      expect(
        build(
          record: trip(),
          stationNames: const ['北京站', '不存在的站'],
          legRouteNames: const ['京沪高速铁路'],
        ),
        isNull,
      );
    });

    test('区间颜色取自线路配色，缺省退回兜底色', () {
      final plan = build(record: trip())!;
      expect(plan.moves.every((move) => move.color == '#1565C0'), isTrue);

      final fallback = build(record: trip(), colors: const {})!;
      expect(fallback.moves.every((move) => move.color == '#9E9E9E'), isTrue);

      // 手动线路用简图里的「手动线路」颜色。
      final manual = build(
        record: trip(),
        legRouteNames: const ['', ''],
        colors: const {'手动线路': '#FF8F00'},
      )!;
      expect(manual.moves.every((move) => move.color == '#FF8F00'), isTrue);
    });

    test('区间折线贴轨道，首尾是精确站坐标', () {
      // 有轨道索引但这一段查不到折线时退回直线：两点连线。
      final plan = build(record: trip(), tracks: RailTrackIndex.empty())!;
      final points = plan.moves[0].points;
      expect(points.first.latitude, 39.9022);
      expect(points.last.latitude, 36.67);
      expect(points, hasLength(2));
    });

    test('时间轴的时区偏移与行程时刻一致', () {
      final record = trip(departureTime: DateTime(2026, 1, 1, 8));
      final plan = build(record: record)!;
      expect(
        plan.utcOffsetMinutes,
        DateTime(2026, 1, 1, 8).timeZoneOffset.inMinutes,
      );
    });

    test('区间线路名与站序对齐，终到站沿用最后一段', () {
      const mixedLines = ['京沪高速铁路', '京沪高速铁路'];
      final plan = build(record: trip(), legRouteNames: mixedLines)!;
      expect(plan.stops[0].lineName, '京沪高速铁路');
      expect(plan.stops[2].lineName, '京沪高速铁路');
      expect(plan.moves[0].lineName, '京沪高速铁路');
    });
  });

  // 站点顺序与 JourneyStations 的约定一致：legRouteNames[i] 对应
  // stations[i]→stations[i+1]，这里顺带确认服务是按这个约定取线路名的。
  test('JourneyStations 的站序可以直接喂给动画服务', () {
    const journey = JourneyStations(stations: stations, legRouteNames: lines);
    final plan = TripAnimationService.build(
      trip: trip(),
      stationNames: journey.stations,
      legRouteNames: journey.legRouteNames,
      coordinates: coordinates,
      tracks: null,
      overlay: const TripScheduleOverlay(),
      lineColors: lineColors,
      fallbackColor: '#9E9E9E',
    );
    expect(plan, isNotNull);
    expect(plan!.moves, hasLength(journey.stations.length - 1));
  });
}
