import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';
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

  group('findDuplicateCopies', () {
    TripRecord trip({
      required int id,
      String train = 'G1',
      DateTime? departure,
      String from = '北京南',
      String to = '上海虹桥',
      int? ticketId,
      DateTime? arrival,
      double mileageKm = 1318,
      List<ViaRouteSegment> via = const [],
      bool isRailTrip = true,
      DateTime? createdAt,
    }) {
      return TripRecord(
        id: id,
        ticketId: ticketId,
        trainNumber: train,
        fromStation: from,
        toStation: to,
        departureTime: departure ?? DateTime(2024, 5, 1, 8),
        arrivalTime: arrival,
        mileageKm: mileageKm,
        viaRouteSegments: via,
        isRailTrip: isRailTrip,
        createdAt: createdAt,
      );
    }

    test('同车次同日同区间只留下多余副本', () {
      final synced = trip(
        id: 1,
        ticketId: 100,
        arrival: DateTime(2024, 5, 1, 12),
      );
      final local = trip(id: 2);

      final copies = TimetableRebuildService.findDuplicateCopies([
        local,
        synced,
      ]);

      expect(copies.map((value) => value.id), [2]);
    });

    test('三条重复时优先保留云端副本，其余都是副本', () {
      final richest = trip(
        id: 1,
        ticketId: 100,
        arrival: DateTime(2024, 5, 1, 12),
        via: const [
          ViaRouteSegment(
            routeName: '京沪高速',
            fromStation: '北京南',
            toStation: '上海虹桥',
          ),
        ],
      );
      final plain = trip(id: 2);
      final middle = trip(id: 3, arrival: DateTime(2024, 5, 1, 12));

      final copies = TimetableRebuildService.findDuplicateCopies([
        plain,
        richest,
        middle,
      ]);

      expect(copies.map((value) => value.id), [2, 3]);
    });

    test('云端副本优先于更早的本地副本', () {
      final local = trip(id: 1, createdAt: DateTime(2024, 1, 1));
      final synced = trip(
        id: 2,
        ticketId: 100,
        createdAt: DateTime(2024, 1, 2),
      );

      final copies = TimetableRebuildService.findDuplicateCopies([
        local,
        synced,
      ]);

      expect(copies.map((value) => value.id), [1]);
    });

    test('同一同步状态下按录入时间保留最早的一条', () {
      final later = trip(id: 1, createdAt: DateTime(2024, 1, 2));
      final earlier = trip(id: 2, createdAt: DateTime(2024, 1, 1));

      final copies = TimetableRebuildService.findDuplicateCopies([
        later,
        earlier,
      ]);

      expect(copies.map((value) => value.id), [1]);
    });

    test('车次号大小写、空白、号对顺序和站名「站」字不影响判重', () {
      final first = trip(
        id: 1,
        train: 'd111/d114',
        departure: DateTime(2024, 5, 1, 8),
        from: '北京南站',
        to: '上海虹桥站',
      );
      final second = trip(
        id: 2,
        train: 'D114 / D111',
        departure: DateTime(2024, 5, 1, 20),
      );

      final copies = TimetableRebuildService.findDuplicateCopies([
        first,
        second,
      ]);

      expect(copies.map((value) => value.id), [2]);
    });

    test('不同日期、不同区间、不同车次都不算重复', () {
      final base = trip(id: 1, arrival: DateTime(2024, 5, 1, 12));

      final copies = TimetableRebuildService.findDuplicateCopies([
        base,
        trip(id: 2, departure: DateTime(2024, 5, 2, 8)),
        trip(id: 3, to: '杭州东'),
        trip(id: 4, train: 'G2'),
      ]);

      expect(copies, isEmpty);
    });

    test('非铁路行程不参与判重', () {
      final copies = TimetableRebuildService.findDuplicateCopies([
        trip(id: 1, isRailTrip: false),
        trip(id: 2, isRailTrip: false),
      ]);

      expect(copies, isEmpty);
    });

    test('副本按传入顺序返回，保持列表原排序', () {
      final first = trip(id: 1, createdAt: DateTime(2024, 1, 1));
      final other = trip(id: 9, train: 'G9');
      final second = trip(id: 2, createdAt: DateTime(2024, 1, 2));
      final third = trip(id: 3, createdAt: DateTime(2024, 1, 3));

      final copies = TimetableRebuildService.findDuplicateCopies([
        second,
        other,
        first,
        third,
      ]);

      expect(copies.map((value) => value.id), [2, 3]);
    });
  });
}
