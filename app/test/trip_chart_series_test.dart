import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/trip_chart_series.dart';

void main() {
  test('groups monthly mileage and fills empty months', () {
    final points = buildTripChartSeries(
      trips: [
        _trip(DateTime(2026, 1, 10), mileage: 100),
        _trip(DateTime(2026, 3, 5), mileage: 250),
      ],
      rangeStart: DateTime(2026, 1, 1),
      rangeEnd: DateTime(2026, 3, 31),
      metric: TripChartMetric.mileage,
      interval: TripChartInterval.month,
      railFilter: TripChartRailFilter.all,
    );

    expect(points.map((point) => point.value), [100, 0, 250]);
  });

  test('filters railway trips and aggregates weekly duration in hours', () {
    final points = buildTripChartSeries(
      trips: [
        _trip(DateTime(2026, 7, 13), arrivalTime: DateTime(2026, 7, 13, 2)),
        _trip(
          DateTime(2026, 7, 14),
          arrivalTime: DateTime(2026, 7, 14, 5),
          isRailTrip: false,
        ),
      ],
      rangeStart: DateTime(2026, 7, 13),
      rangeEnd: DateTime(2026, 7, 19),
      metric: TripChartMetric.duration,
      interval: TripChartInterval.week,
      railFilter: TripChartRailFilter.rail,
    );

    expect(points.single.value, 2);
  });
}

DashboardTripEntry _trip(
  DateTime departureTime, {
  DateTime? arrivalTime,
  double mileage = 0,
  bool isRailTrip = true,
}) => DashboardTripEntry(
  id: 1,
  trainNumber: 'G1',
  fromStation: '甲',
  toStation: '乙',
  departureTime: departureTime,
  arrivalTime: arrivalTime,
  mileageKm: mileage,
  seatType: null,
  seatNumber: null,
  price: 0,
  isRailTrip: isRailTrip,
);
