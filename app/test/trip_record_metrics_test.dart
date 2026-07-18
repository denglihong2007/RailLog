import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/trip_record.dart';

void main() {
  test('根据里程、时间和票价计算行程均速与平均价格', () {
    final trip = _trip(
      mileageKm: 300,
      price: 135,
      arrivalTime: DateTime(2026, 7, 18, 12),
    );

    expect(trip.averageSpeedKmh, 100);
    expect(trip.averagePricePerKm, 0.45);
  });

  test('缺少有效里程或时长时不计算派生指标', () {
    final noMileage = _trip(
      mileageKm: 0,
      price: 135,
      arrivalTime: DateTime(2026, 7, 18, 12),
    );
    final noArrival = _trip(mileageKm: 300, price: 135);
    final invalidDuration = _trip(
      mileageKm: 300,
      price: 135,
      arrivalTime: DateTime(2026, 7, 18, 9),
    );

    expect(noMileage.averageSpeedKmh, isNull);
    expect(noMileage.averagePricePerKm, isNull);
    expect(noArrival.averageSpeedKmh, isNull);
    expect(noArrival.averagePricePerKm, 0.45);
    expect(invalidDuration.averageSpeedKmh, isNull);
  });
}

TripRecord _trip({
  required double mileageKm,
  required double price,
  DateTime? arrivalTime,
}) => TripRecord(
  id: 1,
  trainNumber: 'G1',
  fromStation: '北京南',
  toStation: '上海虹桥',
  departureTime: DateTime(2026, 7, 18, 9),
  arrivalTime: arrivalTime,
  mileageKm: mileageKm,
  viaRouteSegments: const [],
  price: price,
);
