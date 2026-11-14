import 'package:raillog/src/models/dashboard_trip_entry.dart';

enum TripChartMetric { count, mileage, duration, spending }

enum TripChartInterval { year, month, week }

enum TripChartRailFilter { all, rail, nonRail }

class TripChartPoint {
  const TripChartPoint({required this.bucketStart, required this.value});

  final DateTime bucketStart;
  final double value;
}

/// 单条行程对趋势图所选指标的贡献值。
double tripChartMetricValue(DashboardTripEntry trip, TripChartMetric metric) =>
    switch (metric) {
      TripChartMetric.mileage => trip.mileageKm,
      TripChartMetric.count => 1,
      TripChartMetric.duration => (trip.duration?.inSeconds ?? 0) / 3600,
      TripChartMetric.spending => trip.price,
    };

List<TripChartPoint> buildTripChartSeries({
  required Iterable<DashboardTripEntry> trips,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required TripChartMetric metric,
  required TripChartInterval interval,
  required TripChartRailFilter railFilter,
}) {
  final start = _dateOnly(rangeStart);
  final end = _dateOnly(rangeEnd);
  if (end.isBefore(start)) return const [];

  final values = <DateTime, double>{};
  for (
    var bucket = _bucketStart(start, interval);
    !bucket.isAfter(_bucketStart(end, interval));
    bucket = _nextBucket(bucket, interval)
  ) {
    values[bucket] = 0;
  }

  for (final trip in trips) {
    final day = _dateOnly(trip.departureTime);
    if (day.isBefore(start) || day.isAfter(end)) continue;
    if (railFilter == TripChartRailFilter.rail && !trip.isRailTrip) continue;
    if (railFilter == TripChartRailFilter.nonRail && trip.isRailTrip) continue;

    final bucket = _bucketStart(day, interval);
    values[bucket] = (values[bucket] ?? 0) + tripChartMetricValue(trip, metric);
  }

  return values.entries
      .map(
        (entry) => TripChartPoint(bucketStart: entry.key, value: entry.value),
      )
      .toList(growable: false);
}

/// 按跨度给出默认汇总粒度：短期看周，中等历史看月，长历史看年。
TripChartInterval suggestTripChartInterval({
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  final days = _dateOnly(rangeEnd).difference(_dateOnly(rangeStart)).inDays;
  if (days >= 365 * 6) return TripChartInterval.year;
  if (days >= 365) return TripChartInterval.month;
  return TripChartInterval.week;
}

/// 热力图色阶。阈值取自用户自己的非零分桶值，只有几次行程时也能分出深浅。
class TripChartHeatmapScale {
  const TripChartHeatmapScale._({
    required this.thresholds,
    required this.levelCount,
    required this.hasValues,
  });

  factory TripChartHeatmapScale.fromValues(Iterable<double> values) {
    final sorted = values.where((value) => value > 0).toList()..sort();
    if (sorted.isEmpty) {
      return const TripChartHeatmapScale._(
        thresholds: [],
        levelCount: 0,
        hasValues: false,
      );
    }

    var hasVariation = false;
    for (var index = 1; index < sorted.length; index++) {
      if (sorted[index] != sorted.first) {
        hasVariation = true;
        break;
      }
    }
    if (!hasVariation) {
      return const TripChartHeatmapScale._(
        thresholds: [],
        levelCount: 1,
        hasValues: true,
      );
    }

    // 第一档固定取最小值，保证最小的非零值不会落成「无数据」色。
    const quantiles = [0.0, 0.5, 0.75, 0.9];
    final thresholds = <double>[];
    for (final quantile in quantiles) {
      final value = sorted[((sorted.length - 1) * quantile).round()];
      if (thresholds.isEmpty || value > thresholds.last) {
        thresholds.add(value);
      }
    }
    return TripChartHeatmapScale._(
      thresholds: List<double>.unmodifiable(thresholds),
      levelCount: thresholds.length,
      hasValues: true,
    );
  }

  /// 升序阈值，最多四档；只有一种非零值时为空（退化为单档）。
  final List<double> thresholds;

  /// 非空色阶数量；[hasValues] 为 false 时为 0。
  final int levelCount;

  final bool hasValues;

  /// 0 表示无记录，其余为 1–[levelCount]。
  int levelFor(double value) {
    if (value <= 0) return 0;
    if (thresholds.isEmpty) return levelCount;
    return thresholds.lastIndexWhere((threshold) => value >= threshold) + 1;
  }
}

DateTime _bucketStart(DateTime date, TripChartInterval interval) =>
    switch (interval) {
      TripChartInterval.year => DateTime(date.year),
      TripChartInterval.month => DateTime(date.year, date.month),
      TripChartInterval.week => date.subtract(Duration(days: date.weekday - 1)),
    };

DateTime _nextBucket(DateTime date, TripChartInterval interval) =>
    switch (interval) {
      TripChartInterval.year => DateTime(date.year + 1),
      TripChartInterval.month => DateTime(date.year, date.month + 1),
      TripChartInterval.week => date.add(const Duration(days: 7)),
    };

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
