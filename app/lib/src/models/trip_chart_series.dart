import 'package:raillog/src/models/dashboard_trip_entry.dart';

enum TripChartMetric { count, mileage, duration, spending }

enum TripChartInterval { year, month, week }

enum TripChartRailFilter { all, rail, nonRail }

class TripChartPoint {
  const TripChartPoint({required this.bucketStart, required this.value});

  final DateTime bucketStart;
  final double value;
}

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
    values[bucket] = (values[bucket] ?? 0) + _metricValue(trip, metric);
  }

  return values.entries
      .map(
        (entry) => TripChartPoint(bucketStart: entry.key, value: entry.value),
      )
      .toList(growable: false);
}

double _metricValue(DashboardTripEntry trip, TripChartMetric metric) =>
    switch (metric) {
      TripChartMetric.mileage => trip.mileageKm,
      TripChartMetric.count => 1,
      TripChartMetric.duration => (trip.duration?.inSeconds ?? 0) / 3600,
      TripChartMetric.spending => trip.price,
    };

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
