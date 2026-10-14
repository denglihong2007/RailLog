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

  group('historicalSectionDistancesFromReference', () {
    test('折返处同名站出现两次，两段各取自己那一次的里程', () {
      // 西安换向：列车在 灞桥→西安→灞桥→田王 里把灞桥走了两遍，
      // 历史站序的累计里程一路递增（100 / 110 / 120 / 130）。
      final stops = _stops([
        ('灞桥', null),
        ('西安', null),
        ('灞桥', null),
        ('田王', null),
      ]);
      final reference = _stops([
        ('灞桥', 100),
        ('西安', 110),
        ('灞桥', 120),
        ('田王', 130),
      ]);

      final sections = historicalSectionDistancesFromReference(
        stops,
        reference,
        0,
        3,
      );

      // 查表（站名 → 里程）只能取到去程的 100，回程那一段会算成 |130 - 100| = 30；
      // 单调游标才会落到回程的 120，两段都是 10。
      expect(sections.map((section) => section.distanceKm), [10.0, 10.0, 10.0]);
    });

    test('参照缺一个中间站时游标不推进，后面的站照常对齐', () {
      final stops = _stops([
        ('北京南', null),
        ('沧州西', null),
        ('德州东', null),
        ('曲阜东', null),
      ]);
      // 历史站序里没有沧州西。
      final reference = _stops([('北京南', 0), ('德州东', 315), ('曲阜东', 537)]);

      final sections = historicalSectionDistancesFromReference(
        stops,
        reference,
        0,
        3,
      );

      // 关键是最后一段仍在：对齐失败时若把游标推到末尾，德州东/曲阜东会一起报废。
      expect(sections.map((section) => section.distanceKm), [null, null, 222.0]);
    });

    test('在线站序多出一站时只拖垮挨着它的两段', () {
      final stops = _stops([
        ('北京南', null),
        ('廊坊', null),
        ('天津南', null),
        ('济南西', null),
      ]);
      // 历史站序里没有廊坊。
      final reference = _stops([('北京南', 0), ('天津南', 120), ('济南西', 400)]);

      final sections = historicalSectionDistancesFromReference(
        stops,
        reference,
        0,
        3,
      );

      expect(sections.map((section) => section.distanceKm), [null, null, 280.0]);
      expect(sections.map((section) => section.toStation), [
        '廊坊',
        '天津南',
        '济南西',
      ]);
    });

    test('参照里 0.0 的里程按缺失处理，不当作「从 0 起算」', () {
      final stops = _stops([
        ('北京南', null),
        ('沧州西', null),
        ('德州东', null),
        ('曲阜东', null),
      ]);
      // 建库时缺失里程落成 0.0（不是 NULL），始发站的 0 才是真的 0。
      final reference = _stops([
        ('北京南', 0),
        ('沧州西', 0),
        ('德州东', 315),
        ('曲阜东', 537),
      ]);

      final sections = historicalSectionDistancesFromReference(
        stops,
        reference,
        0,
        3,
      );

      // 挨着沧州西的两段都得留空 —— 不能拿 |315 - 0| 冒充沧州西→德州东。
      expect(sections.map((section) => section.distanceKm), [null, null, 222.0]);
    });

    test('参照压根不是同一趟车时整段留空', () {
      final stops = _stops([('北京南', null), ('济南西', null)]);
      final reference = _stops([('成都东', 0), ('重庆北', 300)]);

      final sections = historicalSectionDistancesFromReference(
        stops,
        reference,
        0,
        1,
      );

      expect(sections, hasLength(1));
      expect(sections.single.distanceKm, isNull);
    });

    test('站名差一个「站」字也能对上，且段里保留在线站序的站名', () {
      final stops = _stops([('北京南站', null), ('济南西', null)]);
      final reference = _stops([('北京南', 0), ('济南西站', 400)]);

      final sections = historicalSectionDistancesFromReference(
        stops,
        reference,
        0,
        1,
      );

      expect(sections.single.distanceKm, 400.0);
      expect(sections.single.fromStation, '北京南站');
      expect(sections.single.toStation, '济南西');
    });

    test('站数不足或下标越界时返回空表', () {
      final stops = _stops([('北京南', null), ('济南西', null)]);

      expect(
        historicalSectionDistancesFromReference(const [], const [], 0, 1),
        isEmpty,
      );
      expect(
        historicalSectionDistancesFromReference(stops, stops, 2, 2),
        isEmpty,
      );
      expect(
        historicalSectionDistancesFromReference(stops, stops, 0, stops.length),
        isEmpty,
      );
      expect(
        historicalSectionDistancesFromReference(stops, const [], 0, 1).single
            .distanceKm,
        isNull,
      );
    });
  });

  group('normalizeStationName', () {
    test('去掉首尾空白与结尾的「站」', () {
      expect(normalizeStationName(' 北京南站 '), '北京南');
      expect(normalizeStationName('北京南'), '北京南');
      // 只去结尾那一个，站名中间的原样保留。
      expect(normalizeStationName('上海虹桥站'), '上海虹桥');
    });
  });
}
