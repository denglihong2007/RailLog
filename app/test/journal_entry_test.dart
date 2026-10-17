import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/journal/journal_entry.dart';
import 'package:raillog/src/journal/journal_layout.dart';
import 'package:raillog/src/models/via_route_segment.dart';

import 'support/journal_fixtures.dart';

void main() {
  group('JournalFormatter 日期时刻', () {
    test('日期补零到 ISO 形状', () {
      expect(JournalFormatter.date(DateTime(2026, 8, 2)), '2026-08-02');
      expect(JournalFormatter.date(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('星期表锚在固定日期上', () {
      // 2026-08-02 是周日；往前往后各取一天，确认不是整张表错位。
      expect(JournalFormatter.weekday(DateTime(2026, 8, 2)), '周日');
      expect(JournalFormatter.weekday(DateTime(2026, 8, 1)), '周六');
      expect(JournalFormatter.weekday(DateTime(2026, 8, 3)), '周一');
      expect(JournalFormatter.weekday(DateTime(2026, 7, 27)), '周一');
    });

    test('时刻按 24 小时补零', () {
      expect(JournalFormatter.time(DateTime(2026, 8, 2, 8, 0)), '08:00');
      expect(JournalFormatter.time(DateTime(2026, 8, 2, 23, 5)), '23:05');
    });
  });

  group('JournalFormatter.duration', () {
    test('时分拼法', () {
      expect(
        JournalFormatter.duration(
          DateTime(2026, 8, 2, 8),
          DateTime(2026, 8, 2, 12, 38),
        ),
        '4时38分',
      );
    });

    test('整点不带分、不足一时只写分', () {
      expect(
        JournalFormatter.duration(
          DateTime(2026, 8, 2, 8),
          DateTime(2026, 8, 2, 11),
        ),
        '3时',
      );
      expect(
        JournalFormatter.duration(
          DateTime(2026, 8, 2, 8),
          DateTime(2026, 8, 2, 8, 25),
        ),
        '25分',
      );
    });

    test('到达缺失或早于出发都留空，不印误导的负历时', () {
      expect(JournalFormatter.duration(DateTime(2026, 8, 2, 8), null), '');
      expect(
        JournalFormatter.duration(
          DateTime(2026, 8, 2, 8),
          DateTime(2026, 8, 2, 7),
        ),
        '',
      );
    });
  });

  group('JournalFormatter 数字', () {
    test('里程四舍五入到整数', () {
      expect(JournalFormatter.mileage(1318.4), '1318 km');
      expect(JournalFormatter.mileage(0.6), '1 km');
    });

    test('里程与票价为 0 时给占位符，不印「0 km」', () {
      expect(JournalFormatter.mileage(0), JournalFormatter.unknown);
      expect(JournalFormatter.mileage(-1), JournalFormatter.unknown);
      expect(JournalFormatter.price(0), JournalFormatter.unknown);
      expect(JournalFormatter.price(662), '¥662.00');
    });
  });

  group('JournalFormatter.seat', () {
    test('席别与座位号的各种缺失组合', () {
      expect(JournalFormatter.seat('二等座', '05车12F'), '二等座 · 05车12F');
      expect(JournalFormatter.seat('二等座', null), '二等座');
      expect(JournalFormatter.seat(null, '05车12F'), '05车12F');
      expect(JournalFormatter.seat(null, null), JournalFormatter.unknown);
      expect(JournalFormatter.seat('  ', '  '), JournalFormatter.unknown);
    });
  });

  group('JournalFormatter.routeSummary', () {
    test('无经由线路时留空', () {
      expect(JournalFormatter.routeSummary(const []), '');
      expect(
        JournalFormatter.routeSummary(const [
          ViaRouteSegment(routeName: '  ', fromStation: 'A', toStation: 'B'),
        ]),
        '',
      );
    });

    test('单段与多段', () {
      expect(
        JournalFormatter.routeSummary(const [
          ViaRouteSegment(routeName: '京沪高速铁路', fromStation: 'A', toStation: 'B'),
        ]),
        '经 京沪高速铁路',
      );
      expect(
        JournalFormatter.routeSummary(const [
          ViaRouteSegment(routeName: '京沪高速铁路', fromStation: 'A', toStation: 'B'),
          ViaRouteSegment(routeName: '沪昆高速铁路', fromStation: 'B', toStation: 'C'),
        ]),
        '经 京沪高速铁路 / 沪昆高速铁路',
      );
    });

    test('同名线段只报一次', () {
      expect(
        JournalFormatter.routeSummary(const [
          ViaRouteSegment(routeName: '京沪高速铁路', fromStation: 'A', toStation: 'B'),
          ViaRouteSegment(routeName: '京沪高速铁路', fromStation: 'B', toStation: 'C'),
        ]),
        '经 京沪高速铁路',
      );
    });
  });

  group('JournalFormatter.truncate', () {
    test('短文本原样、长文本留省略号', () {
      expect(JournalFormatter.truncate('北京南', 8), '北京南');
      expect(JournalFormatter.truncate(' 北京南 ', 8), '北京南');
      expect(JournalFormatter.truncate('北京南站', 3), '北京…');
      expect(JournalFormatter.truncate('北京南', 0), '');
    });

    test('按 rune 截，不会把代理对劈成半个字符', () {
      // 一个 emoji 占两个 code unit，按 code unit 截会切出孤立代理。
      final cut = JournalFormatter.truncate('🚄🚄🚄🚄', 3);
      expect(cut, '🚄🚄…');
      expect(cut.runes.where((r) => r >= 0xD800 && r <= 0xDFFF), isEmpty);
      expect(cut.runes.length, 3);
    });
  });

  group('JournalFormatter.fit', () {
    test('半角按 0.55em、全角按 1em 估宽', () {
      expect(
        JournalFormatter.estimateWidth('1234567890', 10),
        closeTo(55, 0.001),
      );
      expect(
        JournalFormatter.estimateWidth('一二三四五六七八九十', 10),
        closeTo(100, 0.001),
      );
    });

    test('放得下就原样返回，放不下才截且截完仍在宽度内', () {
      expect(JournalFormatter.fit('北京南', maxWidth: 100, fontSize: 10), '北京南');
      expect(JournalFormatter.fit('  ', maxWidth: 100, fontSize: 10), '');

      final fitted = JournalFormatter.fit('编' * 200, maxWidth: 100, fontSize: 10);
      expect(fitted, endsWith('…'));
      expect(fitted.runes.length, 10); // 9 个字 + 省略号
      expect(
        JournalFormatter.estimateWidth(fitted, 10),
        lessThanOrEqualTo(100),
      );
    });

    test('同样宽度下，半角串比全角串能多留一倍的字', () {
      // 车组号串 CR400BF-5033&5044 就是靠这条才不至于早早就「…」。
      final ascii = JournalFormatter.fit('A' * 100, maxWidth: 100, fontSize: 10);
      final cjk = JournalFormatter.fit('编' * 100, maxWidth: 100, fontSize: 10);
      expect(ascii.runes.length, greaterThan(cjk.runes.length));
    });
  });

  group('JournalFormatter.train', () {
    test('空车次有能看懂的兜底', () {
      expect(JournalFormatter.train(journalTrip()), 'G1');
      expect(JournalFormatter.train(journalTrip(trainNumber: '  ')), '车次未填');
      expect(
        JournalFormatter.train(journalTrip(trainNumber: '', isRailTrip: false)),
        '班次未填',
      );
    });
  });

  group('JournalEntry.fromTrip', () {
    test('全字段映射', () {
      final entry = JournalEntry.fromTrip(
        journalTrip(
          id: 42,
          ticketId: null,
          rollingStock: '复兴号 CR400BF',
          notes: '第一次坐复兴号',
        ),
      );

      expect(entry.trainLabel, 'G1');
      expect(entry.dateLabel, '2026-08-02');
      expect(entry.weekdayLabel, '周日');
      expect(entry.fromStation, '北京南');
      expect(entry.toStation, '上海虹桥');
      expect(entry.departLabel, '08:00');
      expect(entry.arriveLabel, '12:38');
      expect(entry.durationLabel, '4时38分');
      expect(entry.mileageLabel, '1318 km');
      expect(entry.priceLabel, '¥662.00');
      expect(entry.seatLabel, '二等座 · 05车12F');
      expect(entry.rollingStockLabel, '复兴号 CR400BF');
      expect(entry.routeLabel, '经 京沪高速铁路');
      expect(entry.notesLabel, '第一次坐复兴号');
      expect(entry.kindLabel, '铁路行程');
      expect(entry.isRailTrip, isTrue);
    });

    test('到达时刻缺失时时刻给占位符、历时留空', () {
      final entry = JournalEntry.fromTrip(journalTrip(hasArrival: false));
      expect(entry.arriveLabel, JournalFormatter.unknown);
      expect(entry.durationLabel, '');
    });

    test('非铁路行程换措辞', () {
      final entry = JournalEntry.fromTrip(
        journalTrip(isRailTrip: false, trainNumber: 'CA1831'),
      );
      expect(entry.kindLabel, '非铁路行程');
      expect(entry.isRailTrip, isFalse);
    });

    test('长文本按各自上限截断，不会溢出到带外', () {
      final entry = JournalEntry.fromTrip(
        journalTrip(
          fromStation: '乌鲁木齐南站乌鲁木齐南站',
          rollingStock:
              '复兴号智能动车组技术提升型 CR400BF-Z 长编组 十七辆编组 商务座与一等座合造车',
          departureTime: DateTime(2026, 8, 2, 8),
          notes: '一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十',
          viaRouteSegments: const [
            ViaRouteSegment(
              routeName: '兰新高速铁路第二双线乌鲁木齐至哈密段',
              fromStation: 'A',
              toStation: 'B',
            ),
            ViaRouteSegment(routeName: '徐兰高速铁路', fromStation: 'B', toStation: 'C'),
          ],
        ),
      );
      expect(entry.fromStation.runes.length, 8);
      expect(entry.notesLabel.runes.length, 34);
      expect(entry.routeLabel.runes.length, 26);
      expect(entry.fromStation, endsWith('…'));
      expect(entry.routeLabel, startsWith('经 '));
      // 编组不在这里截——它独占一行，留给排版层按实际宽度裁。
      expect(entry.rollingStockLabel, contains('十七辆编组'));
    });

    test('常见编组在版心宽度内不截断', () {
      // 以前这个字段和席别、票价挤同一行，只能放 14 个字，
      // 动车组号的串动辄三四十个字符，一印出来就是一串「…」。
      final width = JournalLayout.bandWidth - JournalLayout.bandPadding * 2;
      for (final value in [
        '复兴号 CR400BF',
        'CR400BF-5033&5044&5045&5046',
        '复兴号智能动车组技术提升型 CR400BF-Z',
        'CR400BF-5033&5044&5045&5046&5047&5048&5049&5050&5051&5052',
      ]) {
        expect(
          JournalFormatter.fit(value, maxWidth: width, fontSize: 9.5),
          value,
          reason: value,
        );
      }
    });

    test('空白可选字段退化成空串而不是 "null"', () {
      final entry = JournalEntry.fromTrip(
        journalTrip(
          rollingStock: null,
          notes: null,
          seatType: null,
          seatNumber: null,
          viaRouteSegments: const [],
        ),
      );
      expect(entry.rollingStockLabel, '');
      expect(entry.notesLabel, '');
      expect(entry.routeLabel, '');
      expect(entry.seatLabel, JournalFormatter.unknown);
    });
  });
}
