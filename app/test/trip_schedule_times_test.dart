import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';
import 'package:raillog/src/models/trip_schedule_times.dart';

DateTime _at(int hour, int minute) => DateTime(2026, 1, 1, hour, minute);

TrainScheduleStop _stop(
  String station,
  DateTime? arrival,
  DateTime? departure, {
  double? mileage,
}) {
  return TrainScheduleStop(
    stationName: station,
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
}

TripScheduleStop _scheduleStop(
  String station,
  DateTime? arrival,
  DateTime? departure, {
  double? mileage,
}) {
  return TripScheduleStop(
    stationName: station,
    arrival: arrival,
    departure: departure,
    mileage: mileage,
  );
}

List<TripScheduleStop> _scheduleStops() => [
  _scheduleStop('北京南', null, _at(8, 0), mileage: 0),
  _scheduleStop('沧州西', _at(8, 40), _at(8, 42), mileage: 210),
  // 快照里有这一站，却没有到发时刻（通过站）。
  _scheduleStop('德州东', null, null, mileage: 315),
  _scheduleStop('济南西', _at(9, 30), _at(9, 35), mileage: 400),
  _scheduleStop('上海虹桥', _at(12, 0), null, mileage: 1323),
];

const _diagramStations = ['北京南', '沧州西', '廊坊', '德州东', '济南西', '上海虹桥'];
const _diagramMileage = [0.0, 210.0, 260.0, 315.0, 400.0, 1323.0];

void main() {
  group('TripScheduleTimes.match', () {
    final stops = [
      _stop('北京南', null, _at(8, 0), mileage: 0),
      _stop('沧州西', _at(8, 40), _at(8, 42), mileage: 210),
      _stop('德州东', null, null, mileage: 315),
      _stop('济南西', _at(9, 30), _at(9, 35), mileage: 400),
      _stop('上海虹桥', _at(12, 0), null, mileage: 1323),
    ];

    test('发车与到站时刻都相同时才匹配，秒被忽略', () {
      final times = TripScheduleTimes.match(
        resolvedStops: stops,
        boardingIndex: 0,
        alightingIndex: 4,
        departureTime: DateTime(2026, 1, 1, 8, 0, 30),
        arrivalTime: DateTime(2026, 1, 1, 12, 0, 45),
      );

      expect(times, isNotNull);
      expect(times!.boardingIndex, 0);
      expect(times.alightingIndex, 4);
      expect(times.hasIntermediateStops, isTrue);
    });

    test('发车时刻对不上时不匹配', () {
      expect(
        TripScheduleTimes.match(
          resolvedStops: stops,
          boardingIndex: 0,
          alightingIndex: 4,
          departureTime: _at(8, 1),
          arrivalTime: _at(12, 0),
        ),
        isNull,
      );
    });

    test('到站时刻对不上时不匹配', () {
      expect(
        TripScheduleTimes.match(
          resolvedStops: stops,
          boardingIndex: 0,
          alightingIndex: 4,
          departureTime: _at(8, 0),
          arrivalTime: _at(12, 1),
        ),
        isNull,
      );
    });

    test('行程没记录到站时刻时只校验发车时刻', () {
      expect(
        TripScheduleTimes.match(
          resolvedStops: stops,
          boardingIndex: 0,
          alightingIndex: 4,
          departureTime: _at(8, 0),
          arrivalTime: null,
        ),
        isNotNull,
      );
    });

    test('上车站晚于始发站时按上车站的发点比较', () {
      final times = TripScheduleTimes.match(
        resolvedStops: stops,
        boardingIndex: 1,
        alightingIndex: 3,
        departureTime: _at(8, 42),
        arrivalTime: _at(9, 30),
      );

      expect(times, isNotNull);
      expect(times!.boardingIndex, 1);
    });
  });

  group('TripScheduleTimes.annotate', () {
    test('停站显示到发时刻，缺时刻的站与简图上的野站都按匀速模型估算', () {
      final times = TripScheduleTimes(
        stops: _scheduleStops(),
        boardingIndex: 0,
        alightingIndex: 4,
      );

      final result = times.annotate(
        stationNames: _diagramStations,
        mileage: _diagramMileage,
      );

      // 行程自身的首末站不叠时刻。
      expect(result.first, isNull);
      expect(result.last, isNull);

      final cangzhou = result[1]!;
      expect(cangzhou.isStop, isTrue);
      expect(cangzhou.arrival, _at(8, 40));
      expect(cangzhou.departure, _at(8, 42));
      expect(cangzhou.dwellMinutes, 2);

      // 廊坊：简图有、时刻表没有，夹在沧州西与德州东之间。
      final langfang = result[2]!;
      expect(langfang.isStop, isFalse);
      expect(langfang.estimated, isTrue);
      expect(langfang.passTime, _at(8, 55));

      // 德州东：时刻表有这一站但没给到发时刻，夹在沧州西与济南西之间。
      final dezhou = result[3]!;
      expect(dezhou.isStop, isFalse);
      expect(dezhou.estimated, isTrue);
      expect(dezhou.passTime, _at(9, 9));

      final jinan = result[4]!;
      expect(jinan.isStop, isTrue);
      expect(jinan.dwellMinutes, 5);
    });

    test('手动矫正后的时刻参与后续通过站的估算', () {
      final times = TripScheduleTimes(
        stops: _scheduleStops(),
        boardingIndex: 0,
        alightingIndex: 4,
      );
      final corrected = times.withStops([
        _scheduleStop('北京南', null, _at(8, 0), mileage: 0),
        _scheduleStop('沧州西', _at(8, 40), _at(8, 52), mileage: 210),
        _scheduleStop('德州东', null, null, mileage: 315),
        _scheduleStop('济南西', _at(9, 30), _at(9, 35), mileage: 400),
        _scheduleStop('上海虹桥', _at(12, 0), null, mileage: 1323),
      ]);

      final result = corrected.annotate(
        stationNames: _diagramStations,
        mileage: _diagramMileage,
      );

      expect(result[1]!.departure, _at(8, 52));
      expect(result[3]!.passTime, _at(9, 13));
      expect(result[2]!.passTime, _at(9, 2));
    });

    test('站名差一个「站」字也能对上', () {
      final times = TripScheduleTimes(
        stops: _scheduleStops(),
        boardingIndex: 0,
        alightingIndex: 4,
      );

      final result = times.annotate(
        stationNames: ['北京南站', '沧州西站', '上海虹桥站'],
        mileage: [0, 210, 1323],
      );

      expect(result[1]!.isStop, isTrue);
      expect(result[1]!.arrival, _at(8, 40));
    });

    test('简图不足三站时没有中间站可叠加', () {
      final times = TripScheduleTimes(
        stops: _scheduleStops(),
        boardingIndex: 0,
        alightingIndex: 4,
      );

      expect(
        times.annotate(stationNames: ['北京南', '上海虹桥'], mileage: [0, 1323]),
        [null, null],
      );
    });
  });

  group('findJourneyStopIndexes', () {
    test('按上车站之后第一次遇到的下车站取下标', () {
      final stops = [
        _stop('北京南', null, _at(8, 0)),
        _stop('沧州西', _at(8, 40), _at(8, 42)),
        _stop('上海虹桥', _at(12, 0), null),
      ];

      expect(findJourneyStopIndexes(stops, '北京南站', '上海虹桥站'), (0, 2));
      expect(findJourneyStopIndexes(stops, '沧州西', '上海虹桥'), (1, 2));
    });

    test('站序里找不到车站或下车站不在上车站之后时返回 null', () {
      final stops = [
        _stop('北京南', null, _at(8, 0)),
        _stop('上海虹桥', _at(12, 0), null),
      ];

      expect(findJourneyStopIndexes(stops, '济南西', '上海虹桥'), isNull);
      expect(findJourneyStopIndexes(stops, '上海虹桥', '北京南'), isNull);
    });
  });
}
