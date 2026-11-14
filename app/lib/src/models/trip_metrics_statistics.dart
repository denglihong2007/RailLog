import 'dart:math' as math;

import 'package:raillog/src/models/dashboard_trip_entry.dart';

/// 与后端排行榜一致：超过这个均速的行程通常把里程或起止时间填错了。
const _maxSpeedKmh = 360.0;

/// 直方图的一格，[lower, upper) 左闭右开；最后一格包含最大值。
class TripMetricBin {
  const TripMetricBin({
    required this.lower,
    required this.upper,
    required this.count,
    required this.trips,
  });

  final double lower;
  final double upper;
  final int count;

  /// 落进这一格的行程，最近的在前。
  final List<DashboardTripEntry> trips;
}

/// 一项指标的平均值、样本与按固定组距分箱后的分布。
class TripMetricDistribution {
  const TripMetricDistribution({
    required this.average,
    required this.sampleCount,
    required this.binWidth,
    required this.bins,
    required this.trips,
  });

  const TripMetricDistribution.empty(this.binWidth)
    : average = null,
      sampleCount = 0,
      bins = const [],
      trips = const [];

  final double? average;
  final int sampleCount;
  final double binWidth;
  final List<TripMetricBin> bins;

  /// 参与这项指标统计的全部行程，最近的在前。
  final List<DashboardTripEntry> trips;

  bool get isEmpty => sampleCount == 0;

  int get maxBinCount =>
      bins.fold(0, (max, bin) => bin.count > max ? bin.count : max);
}

class TripMetricsStatistics {
  const TripMetricsStatistics({
    required this.speed,
    required this.mileage,
    required this.unitPrice,
    required this.ticketPrice,
    required this.durationMinutes,
  });

  factory TripMetricsStatistics.fromTrips(Iterable<DashboardTripEntry> trips) {
    final speeds = <_MetricSample>[];
    final mileages = <_MetricSample>[];
    final unitPrices = <_MetricSample>[];
    final ticketPrices = <_MetricSample>[];
    final durations = <_MetricSample>[];

    for (final trip in trips) {
      if (!trip.isRailTrip) continue;
      ticketPrices.add(_MetricSample(trip.price, trip));
      mileages.add(_MetricSample(trip.mileageKm, trip));

      final duration = trip.duration;
      final validDuration = duration != null && duration > Duration.zero;
      if (validDuration) {
        final durationHours = duration.inMilliseconds / 3600000;
        final speed = trip.mileageKm / durationHours;
        if (speed > 0 && speed <= _maxSpeedKmh) {
          speeds.add(_MetricSample(speed, trip));
        }
        durations.add(_MetricSample(duration.inSeconds / 60, trip));
      }
      if (trip.mileageKm > 0) {
        unitPrices.add(_MetricSample(trip.price / trip.mileageKm, trip));
      }
    }

    return TripMetricsStatistics(
      speed: _buildDistribution(
        speeds,
        candidates: const [5, 10, 20, 25, 50, 100],
      ),
      mileage: _buildDistribution(
        mileages,
        candidates: const [10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000],
      ),
      unitPrice: _buildDistribution(
        unitPrices,
        candidates: const [0.01, 0.02, 0.05, 0.1, 0.2, 0.25, 0.5, 1, 2, 5],
      ),
      ticketPrice: _buildDistribution(
        ticketPrices,
        candidates: const [5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000],
      ),
      durationMinutes: _buildDistribution(
        durations,
        candidates: const [15, 30, 60, 120, 180, 240, 360, 720, 1440],
      ),
    );
  }

  final TripMetricDistribution speed;

  /// 单程里程，km。
  final TripMetricDistribution mileage;

  /// 每公里票价，元/km。
  final TripMetricDistribution unitPrice;

  /// 单程票价，元。
  final TripMetricDistribution ticketPrice;

  /// 单程时长，分钟。
  final TripMetricDistribution durationMinutes;
}

class _MetricSample {
  const _MetricSample(this.value, this.trip);

  final double value;
  final DashboardTripEntry trip;
}

const _maxBins = 10;

TripMetricDistribution _buildDistribution(
  List<_MetricSample> samples, {
  required List<double> candidates,
}) {
  if (samples.isEmpty) {
    return TripMetricDistribution.empty(candidates.first.toDouble());
  }
  var maxValue = 0.0;
  var sum = 0.0;
  for (final sample in samples) {
    if (sample.value > maxValue) maxValue = sample.value;
    sum += sample.value;
  }
  final binWidth =
      _chooseBinWidth(maxValue, candidates) ?? maxValue / (_maxBins - 1);
  final binCount = math.max(_binIndex(maxValue, binWidth) + 1, 1);
  final counts = List<int>.filled(binCount, 0);
  final binTrips = List.generate(binCount, (_) => <DashboardTripEntry>[]);
  for (final sample in samples) {
    final index = _binIndex(sample.value, binWidth).clamp(0, binCount - 1);
    counts[index]++;
    binTrips[index].add(sample.trip);
  }
  return TripMetricDistribution(
    average: sum / samples.length,
    sampleCount: samples.length,
    binWidth: binWidth,
    bins: List<TripMetricBin>.unmodifiable([
      for (var index = 0; index < binCount; index++)
        TripMetricBin(
          lower: index * binWidth,
          upper: (index + 1) * binWidth,
          count: counts[index],
          trips: _newestFirst(binTrips[index]),
        ),
    ]),
    trips: _newestFirst(samples.map((sample) => sample.trip).toList()),
  );
}

/// 取能装进 [_maxBins] 格的最小候选组距，优先让分布更细。
double? _chooseBinWidth(double maxValue, List<double> candidates) {
  if (maxValue <= 0) return candidates.first.toDouble();
  for (final candidate in candidates) {
    if (_binIndex(maxValue, candidate) + 1 <= _maxBins) {
      return candidate.toDouble();
    }
  }
  return null;
}

/// 0.6 / 0.1 在浮点里是 5.999…，直接取整会把 0.6 落进 [0.5, 0.6)。
int _binIndex(double value, double binWidth) =>
    (value / binWidth + 1e-9).floor();

List<DashboardTripEntry> _newestFirst(List<DashboardTripEntry> trips) {
  final result = trips.toList()
    ..sort((a, b) {
      final byTime = b.departureTime.compareTo(a.departureTime);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
  return List<DashboardTripEntry>.unmodifiable(result);
}
