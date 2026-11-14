import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/trip_chart_series.dart';

void main() {
  group('suggestTripChartInterval', () {
    test('短期历史按周', () {
      expect(
        suggestTripChartInterval(
          rangeStart: DateTime(2026, 1, 1),
          rangeEnd: DateTime(2026, 6, 1),
        ),
        TripChartInterval.week,
      );
    });

    test('中等历史按月', () {
      expect(
        suggestTripChartInterval(
          rangeStart: DateTime(2023, 1, 1),
          rangeEnd: DateTime(2026, 1, 1),
        ),
        TripChartInterval.month,
      );
      // 正好一年也用「年 × 12 月」网格。
      expect(
        suggestTripChartInterval(
          rangeStart: DateTime(2025, 1, 1),
          rangeEnd: DateTime(2026, 1, 1),
        ),
        TripChartInterval.month,
      );
    });

    test('长历史按年', () {
      expect(
        suggestTripChartInterval(
          rangeStart: DateTime(2015, 1, 1),
          rangeEnd: DateTime(2026, 1, 1),
        ),
        TripChartInterval.year,
      );
    });
  });

  group('TripChartHeatmapScale', () {
    test('阈值随用户自己的数据上移', () {
      final sparse = TripChartHeatmapScale.fromValues([0, 1, 0, 1, 2, 10]);
      final busy = TripChartHeatmapScale.fromValues([5, 10, 20, 40, 80]);

      expect(sparse.thresholds.first, 1);
      expect(busy.thresholds.first, greaterThan(sparse.thresholds.first));
      expect(sparse.levelFor(0), 0);
      expect(sparse.levelFor(1), 1);
      expect(sparse.levelFor(10), sparse.levelCount);
    });

    test('只有一个非零值时退化为单档', () {
      final scale = TripChartHeatmapScale.fromValues([0, 0, 3, 3]);

      expect(scale.hasValues, isTrue);
      expect(scale.thresholds, isEmpty);
      expect(scale.levelCount, 1);
      expect(scale.levelFor(3), 1);
    });

    test('没有非零值时没有色阶', () {
      final scale = TripChartHeatmapScale.fromValues([0, 0, 0]);

      expect(scale.hasValues, isFalse);
      expect(scale.levelCount, 0);
      expect(scale.levelFor(0), 0);
    });

    test('阈值升序且不超过四档', () {
      final scale = TripChartHeatmapScale.fromValues([1, 2, 3, 4, 5, 6, 7, 8]);

      expect(scale.thresholds.length, inInclusiveRange(1, 4));
      for (var index = 1; index < scale.thresholds.length; index++) {
        expect(
          scale.thresholds[index],
          greaterThan(scale.thresholds[index - 1]),
        );
      }
    });
  });
}
