import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/timetable_version.dart';

void main() {
  group('parseTimetableVersion', () {
    test('parses a snapshot date', () {
      expect(parseTimetableVersion('2003.11.25'), DateTime(2003, 11, 25));
      expect(parseTimetableVersion('2026.09.25'), DateTime(2026, 9, 25));
    });

    test('rejects malformed versions', () {
      expect(parseTimetableVersion(''), isNull);
      expect(parseTimetableVersion('2003-11-25'), isNull);
      expect(parseTimetableVersion('2003.1.5'), isNull);
      expect(parseTimetableVersion('2023.02.31'), isNull);
    });
  });

  group('resolveTimetableVersion', () {
    // 真实的快照间隔结构：2003→2004 与 2016→2017 各有一个超过一年的空档，
    // 约 20% 的日期会走到「按绝对距离取最近」这条回退分支。
    const versions = [
      '2003.11.25',
      '2004.10.03',
      '2004.11.01',
      '2009.07.01',
      '2009.07.03',
      '2016.08.31',
      '2017.10.20',
      '2026.09.25',
    ];

    test('uses the next snapshot when it is within a month', () {
      expect(resolveTimetableVersion(DateTime(2003, 11, 25), versions),
          '2003.11.25');
      expect(resolveTimetableVersion(DateTime(2004, 9, 20), versions),
          '2004.10.03');
      expect(resolveTimetableVersion(DateTime(2009, 7, 2), versions),
          '2009.07.03');
      expect(resolveTimetableVersion(DateTime(2017, 9, 20), versions),
          '2017.10.20');
    });

    test('falls back to the nearest snapshot when the next is far away', () {
      // 2004.10.03 在 303 天之后，太远 → 取 10 天前的 2003.11.25。
      expect(resolveTimetableVersion(DateTime(2003, 12, 5), versions),
          '2003.11.25');
      // 2017.10.20 在 370 天之后 → 取 45 天前的 2016.08.31。
      expect(resolveTimetableVersion(DateTime(2016, 10, 15), versions),
          '2016.08.31');
    });

    test('the nearest snapshot may still be after the trip date', () {
      // 落在 415 天空档的中点附近：后面那个反而更近，按「绝对距离最近」取它。
      expect(resolveTimetableVersion(DateTime(2017, 6, 1), versions),
          '2017.10.20');
    });

    test('handles dates outside the covered range', () {
      // 晚于最后一个快照。
      expect(resolveTimetableVersion(DateTime(2026, 12, 1), versions),
          '2026.09.25');
      // 早于第一个快照。
      expect(resolveTimetableVersion(DateTime(2001, 1, 1), versions),
          '2003.11.25');
    });

    test('treats the forward window as inclusive at 31 days', () {
      // 行程 2017.09.01：后面的快照正好在 31 天后，仍在窗口内，于是取它
      // （若按距离，7 天前的那个更近——两种规则在这里给出不同答案）。
      const inclusive = ['2017.08.25', '2017.10.02'];
      expect(resolveTimetableVersion(DateTime(2017, 9, 1), inclusive),
          '2017.10.02');

      // 33 天就超出窗口，回退到更近的 2017.08.25。
      const beyond = ['2017.08.25', '2017.10.04'];
      expect(resolveTimetableVersion(DateTime(2017, 9, 1), beyond),
          '2017.08.25');
    });

    test('ignores the time of day on the trip date', () {
      expect(
        resolveTimetableVersion(DateTime(2009, 7, 2, 23, 59), versions),
        '2009.07.03',
      );
    });

    test('accepts unordered input', () {
      const shuffled = ['2026.09.25', '2003.11.25', '2009.07.03'];
      expect(resolveTimetableVersion(DateTime(2009, 7, 2), shuffled),
          '2009.07.03');
    });

    test('returns null when there are no usable versions', () {
      expect(resolveTimetableVersion(DateTime(2020, 1, 1), const []), isNull);
      expect(
        resolveTimetableVersion(DateTime(2020, 1, 1), const ['not-a-date']),
        isNull,
      );
    });
  });
}
