import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/trip_metrics_statistics.dart';

final _departure = DateTime(2026, 1, 1, 8);

DashboardTripEntry _trip({
  int id = 1,
  double mileageKm = 1000,
  double price = 600,
  Duration? duration = const Duration(hours: 5),
  bool isRailTrip = true,
}) => DashboardTripEntry(
  id: id,
  trainNumber: 'G$id',
  fromStation: '北京南',
  toStation: '上海虹桥',
  departureTime: _departure,
  arrivalTime: duration == null ? null : _departure.add(duration),
  mileageKm: mileageKm,
  seatType: '二等座',
  seatNumber: '5车12A号',
  price: price,
  isRailTrip: isRailTrip,
);

void main() {
  late TripMetricsStatistics statistics;

  setUp(() {
    statistics = TripMetricsStatistics.fromTrips([
      // 1000 km / 5 h，200 km/h，单位票价 0.6 元/km。
      _trip(id: 1),
      // 100 km / 0.5 h，同样 200 km/h，单位票价 0.5 元/km。
      _trip(
        id: 2,
        mileageKm: 100,
        price: 50,
        duration: const Duration(minutes: 30),
      ),
      // 没有到达时间：不参与旅速与时长；里程为 0，也不参与单位票价。
      _trip(id: 3, mileageKm: 0, price: 100, duration: null),
      // 1300 km / 1 h 超过 360 km/h，不参与旅速。
      _trip(
        id: 4,
        mileageKm: 1300,
        price: 780,
        duration: const Duration(hours: 1),
      ),
    ]);
  });

  test('平均旅速排除异常速度', () {
    expect(statistics.speed.sampleCount, 2);
    expect(statistics.speed.average, closeTo(200, 0.001));
    expect(statistics.speed.binWidth, 25);
    expect(statistics.speed.bins, hasLength(9));
    expect(statistics.speed.bins.last.count, 2);
  });

  test('平均里程包含全部行程', () {
    expect(statistics.tripCount, 4);
    expect(statistics.mileage.sampleCount, 4);
    expect(statistics.mileage.average, closeTo(600, 0.001));
    expect(statistics.mileage.binWidth, 200);
    expect(statistics.mileage.bins, hasLength(7));
    expect(statistics.mileage.bins.map((bin) => bin.count), [
      2,
      0,
      0,
      0,
      0,
      1,
      1,
    ]);
  });

  test('平均值与每一格都保留对应行程', () {
    expect(statistics.speed.trips, hasLength(2));
    expect(statistics.speed.trips.map((trip) => trip.id).toSet(), {1, 2});
    expect(statistics.speed.bins.last.trips, hasLength(2));
    expect(statistics.unitPrice.trips, hasLength(3));
  });

  test('平均单位票价只算有里程的行程', () {
    expect(statistics.unitPrice.sampleCount, 3);
    expect(statistics.unitPrice.average, closeTo(0.5666667, 0.0001));
    expect(statistics.unitPrice.binWidth, 0.1);
    expect(statistics.unitPrice.bins, hasLength(7));
    expect(statistics.unitPrice.bins.map((bin) => bin.count), [
      0,
      0,
      0,
      0,
      0,
      1,
      2,
    ]);
  });

  test('平均单程票价包含无到达时间与异常速度的行程', () {
    expect(statistics.ticketPrice.sampleCount, 4);
    expect(statistics.ticketPrice.average, closeTo(382.5, 0.001));
    expect(statistics.ticketPrice.binWidth, 100);
    expect(statistics.ticketPrice.bins, hasLength(8));
    expect(statistics.ticketPrice.bins.map((bin) => bin.count), [
      1,
      1,
      0,
      0,
      0,
      0,
      1,
      1,
    ]);
  });

  test('平均时长只算时长有效的行程', () {
    expect(statistics.durationMinutes.sampleCount, 3);
    expect(statistics.durationMinutes.average, closeTo(130, 0.001));
    expect(statistics.durationMinutes.binWidth, 60);
    expect(statistics.durationMinutes.bins, hasLength(6));
    expect(statistics.durationMinutes.bins.map((bin) => bin.count), [
      1,
      1,
      0,
      0,
      0,
      1,
    ]);
  });

  test('非铁路行程同样参与统计，范围由调用方决定', () {
    final result = TripMetricsStatistics.fromTrips([
      _trip(id: 1, isRailTrip: false),
      _trip(id: 2, mileageKm: 0, price: 0, duration: null, isRailTrip: false),
    ]);

    expect(result.tripCount, 2);
    expect(result.speed.sampleCount, 1);
    expect(result.mileage.sampleCount, 2);
    expect(result.ticketPrice.sampleCount, 2);
    expect(result.unitPrice.sampleCount, 1);
    expect(result.durationMinutes.sampleCount, 1);
  });

  test('没有数据时保留默认组距且不生成柱', () {
    final result = TripMetricsStatistics.fromTrips(const []);

    expect(result.speed.binWidth, 5);
    expect(result.unitPrice.binWidth, 0.01);
    expect(result.ticketPrice.binWidth, 5);
    expect(result.durationMinutes.binWidth, 15);
    expect(result.speed.bins, isEmpty);
  });
}
