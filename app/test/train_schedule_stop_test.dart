import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';

/// 2026.09.25 快照里 G1（北京南 → 上海虹桥）的真实累计里程。
/// 区间里程改成从站序算之后，这套数字就是唯一的真相来源。
const _g1Mileages = <(String, double)>[
  ('北京南', 0),
  ('沧州西', 210),
  ('德州东', 315),
  ('曲阜东', 537),
  ('南京南', 1027),
  ('苏州北', 1241),
  ('上海虹桥', 1323),
];

List<TrainScheduleStop> _stops(List<(String, double?)> source) {
  return [
    for (final (index, (station, mileage)) in source.indexed)
      TrainScheduleStop(
        stationName: station,
        stationNo: (index + 1).toString().padLeft(2, '0'),
        arriveTime: '',
        startTime: '',
        runningTime: '',
        arriveDay: '',
        arriveDayDifference: 0,
        mileage: mileage,
      ),
  ];
}

void main() {
  group('historicalSectionDistances', () {
    test('区间里程逐段取自站序的累计里程差', () {
      final sections = historicalSectionDistances(
        _stops(_g1Mileages),
        0,
        _g1Mileages.length - 1,
      );

      expect(sections, hasLength(6));
      expect(
        sections.map((section) => section.distanceKm),
        [210.0, 105.0, 222.0, 490.0, 214.0, 82.0],
      );
      expect(
        sections.map((section) => '${section.fromStation}-${section.toStation}'),
        [
          '北京南-沧州西',
          '沧州西-德州东',
          '德州东-曲阜东',
          '曲阜东-南京南',
          '南京南-苏州北',
          '苏州北-上海虹桥',
        ],
      );
    });

    test('逐段之和等于整段里程', () {
      final stops = _stops(_g1Mileages);
      final sections = historicalSectionDistances(stops, 0, stops.length - 1);
      final sum = sections.fold<double>(
        0,
        (total, section) => total + (section.distanceKm ?? 0),
      );

      expect(
        sum,
        historicalJourneyMileage(stops.first, stops.last),
      );
    });

    test('子区间只覆盖它自己的相邻站对', () {
      final stops = _stops(_g1Mileages);
      // 沧州西(1) → 南京南(4)
      final sections = historicalSectionDistances(stops, 1, 4);

      expect(
        sections.map((section) => section.distanceKm),
        [105.0, 222.0, 490.0],
      );
      expect(sections.first.fromStation, '沧州西');
      expect(sections.last.toStation, '南京南');
    });

    test('缺里程的站只拖垮挨着它的那一段，其余照算', () {
      final withGap = _stops([
        ('北京南', 0),
        ('沧州西', 210),
        ('德州东', 315),
        ('曲阜东', null), // 里程缺失
      ]);

      final sections = historicalSectionDistances(withGap, 0, 3);

      expect(
        sections.map((section) => section.distanceKm),
        [210.0, 105.0, null],
      );
    });

    test('站数不足或下标越界时返回空表', () {
      final stops = _stops(_g1Mileages);

      expect(historicalSectionDistances(const [], 0, 1), isEmpty);
      expect(historicalSectionDistances(stops, 2, 2), isEmpty);
      expect(historicalSectionDistances(stops, 3, 1), isEmpty);
      expect(historicalSectionDistances(stops, -1, 2), isEmpty);
      expect(historicalSectionDistances(stops, 0, stops.length), isEmpty);
    });
  });
}
