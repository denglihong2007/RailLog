import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';
import 'package:raillog/src/services/timetable_rebuild_service.dart';

TrainScheduleStop _stop(
  String name, {
  String arrive = '',
  String start = '',
  int dayDiff = 0,
  double? mileage,
}) {
  return TrainScheduleStop(
    stationName: name,
    stationNo: name,
    arriveTime: arrive,
    startTime: start,
    runningTime: '',
    arriveDay: '',
    arriveDayDifference: dayDiff,
    mileage: mileage,
  );
}

void main() {
  final departure = DateTime(2024, 1, 1, 8);

  group('matchHistoricalSegment', () {
    test('按站序找到车票区间与到点', () {
      final stops = [
        _stop('北京南', start: '08:00'),
        _stop('济南西', arrive: '09:30', start: '09:32'),
        _stop('南京南', arrive: '12:00'),
      ];

      final match = TimetableRebuildService.matchHistoricalSegment(
        stops: stops,
        fromStation: '北京南',
        toStation: '南京南',
        departureTime: departure,
      );

      expect(match, isNotNull);
      expect(match!.departureIndex, 0);
      expect(match.arrivalIndex, 2);
      expect(match.arrivalTime, DateTime(2024, 1, 1, 12));
    });

    test('站名带「站」也能对上', () {
      final stops = [
        _stop('北京南', start: '08:00'),
        _stop('南京南', arrive: '12:00'),
      ];

      final match = TimetableRebuildService.matchHistoricalSegment(
        stops: stops,
        fromStation: '北京南站',
        toStation: '南京南站',
        departureTime: departure,
      );

      expect(match?.arrivalTime, DateTime(2024, 1, 1, 12));
    });

    test('跨零点按 arrive_day_diff 落到次日', () {
      final stops = [
        _stop('北京南', start: '22:00'),
        _stop('上海', arrive: '06:30', dayDiff: 1),
      ];

      final match = TimetableRebuildService.matchHistoricalSegment(
        stops: stops,
        fromStation: '北京南',
        toStation: '上海',
        departureTime: DateTime(2024, 1, 1, 22),
      );

      expect(match?.arrivalTime, DateTime(2024, 1, 2, 6, 30));
    });

    test('折返车按发车时刻选对同名站的出现位置', () {
      // 西安换向：灞桥出现两次，去程与回程各一次。
      final stops = [
        _stop('灞桥', start: '08:00'),
        _stop('西安', arrive: '08:20', start: '08:40'),
        _stop('灞桥', arrive: '09:00', start: '09:05'),
        _stop('田王', arrive: '09:30'),
      ];

      final outbound = TimetableRebuildService.matchHistoricalSegment(
        stops: stops,
        fromStation: '灞桥',
        toStation: '西安',
        departureTime: DateTime(2024, 1, 1, 8),
      );
      expect(outbound?.departureIndex, 0);
      expect(outbound?.arrivalTime, DateTime(2024, 1, 1, 8, 20));

      final returnLeg = TimetableRebuildService.matchHistoricalSegment(
        stops: stops,
        fromStation: '灞桥',
        toStation: '田王',
        departureTime: DateTime(2024, 1, 1, 9, 5),
      );
      expect(returnLeg?.departureIndex, 2);
      expect(returnLeg?.arrivalIndex, 3);
      expect(returnLeg?.arrivalTime, DateTime(2024, 1, 1, 9, 30));
    });

    test('区间在站序中不存在时返回 null', () {
      final stops = [
        _stop('北京南', start: '08:00'),
        _stop('南京南', arrive: '12:00'),
      ];

      final match = TimetableRebuildService.matchHistoricalSegment(
        stops: stops,
        fromStation: '北京南',
        toStation: '杭州东',
        departureTime: departure,
      );

      expect(match, isNull);
    });
  });
}
