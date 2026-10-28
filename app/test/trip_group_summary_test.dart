import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/trip_group_summary.dart';

void main() {
  test('sorts members and aggregates dates, duration, mileage and price', () {
    final group = TripGroupSummary.fromTrips('京沪往返', [
      _entry(
        id: 3,
        from: '南京南',
        to: '上海虹桥',
        departure: DateTime(2026, 1, 2, 9),
        arrival: DateTime(2026, 1, 2, 11),
        mileage: 300,
        price: 150,
      ),
      _entry(
        id: 1,
        from: '北京南',
        to: '济南西',
        departure: DateTime(2026, 1, 1, 8),
        arrival: DateTime(2026, 1, 1, 9),
        mileage: 200,
        price: 100,
      ),
      _entry(
        id: 2,
        from: '济南西',
        to: '南京南',
        departure: DateTime(2026, 1, 1, 10),
        arrival: DateTime(2026, 1, 1, 12),
        mileage: 300,
        price: 150,
      ),
    ]);

    expect(group.name, '京沪往返');
    expect(group.count, 3);
    expect(group.trips.map((trip) => trip.id), [1, 2, 3]);
    expect(group.fromStation, '北京南');
    expect(group.earliestDeparture, DateTime(2026, 1, 1, 8));
    expect(group.latestDeparture, DateTime(2026, 1, 2, 9));
    expect(group.toStation, '上海虹桥');
    expect(group.latestArrival, DateTime(2026, 1, 2, 11));
    expect(group.totalDuration, const Duration(hours: 5));
    expect(group.totalMileageKm, 800);
    expect(group.totalPrice, 400);
  });

  test('falls back to departure time for members without arrival', () {
    final group = TripGroupSummary.fromTrips('无到达时间', [
      _entry(id: 1, from: '北京南', to: '天津西', departure: DateTime(2026, 1, 1, 8)),
      _entry(id: 2, from: '天津西', to: '唐山', departure: DateTime(2026, 1, 1, 20)),
    ]);

    expect(group.totalDuration, isNull);
    expect(group.latestArrivalTrip.id, 2);
    expect(group.latestArrival, isNull);
    expect(group.toStation, '唐山');
  });

  test('sums only the members that have a usable duration', () {
    final group = TripGroupSummary.fromTrips('混合', [
      _entry(
        id: 1,
        from: 'A',
        to: 'B',
        departure: DateTime(2026, 1, 1, 8),
        arrival: DateTime(2026, 1, 1, 10),
      ),
      _entry(id: 2, from: 'B', to: 'C', departure: DateTime(2026, 1, 1, 11)),
      _entry(
        id: 3,
        from: 'C',
        to: 'D',
        departure: DateTime(2026, 1, 1, 12),
        arrival: DateTime(2026, 1, 1, 11, 30),
      ),
    ]);

    expect(group.totalDuration, const Duration(hours: 2));
  });

  test('round trip uses the last turnaround station as destination', () {
    final group = TripGroupSummary.fromTrips('环线', [
      _entry(id: 1, from: '北京南', to: '济南西'),
      _entry(id: 2, from: '济南西', to: '上海虹桥'),
      _entry(id: 3, from: '上海虹桥', to: '济南西'),
      _entry(id: 4, from: '济南西', to: '北京南'),
    ]);

    expect(group.fromStation, '北京南');
    expect(group.isRoundTrip, isTrue);
    expect(group.roundTripStation, '上海虹桥');
    expect(group.toStation, '上海虹桥');
  });

  test('keeps the same station when a round trip has no turnaround', () {
    final group = TripGroupSummary.fromTrips('原地', [
      _entry(id: 1, from: '北京南', to: '北京南'),
    ]);

    expect(group.isRoundTrip, isTrue);
    expect(group.roundTripStation, isNull);
    expect(group.toStation, '北京南');
  });

  test('seat summary picks the most common type and appends 等 when mixed', () {
    final uniform = TripGroupSummary.fromTrips('同席别', [
      _entry(id: 1, from: 'A', to: 'B', seatType: '二等座'),
      _entry(id: 2, from: 'B', to: 'C', seatType: '二等座'),
    ]);
    expect(uniform.dominantSeatType, '二等座');
    expect(uniform.seatSummary, '二等座');

    final mixed = TripGroupSummary.fromTrips('混合席别', [
      _entry(id: 1, from: 'A', to: 'B', seatType: '二等座'),
      _entry(id: 2, from: 'B', to: 'C', seatType: '一等座'),
      _entry(id: 3, from: 'C', to: 'D', seatType: '二等座'),
    ]);
    expect(mixed.dominantSeatType, '二等座');
    expect(mixed.hasMixedSeatTypes, isTrue);
    expect(mixed.seatSummary, '二等座等');

    final unrecorded = TripGroupSummary.fromTrips('无席别', [
      _entry(id: 1, from: 'A', to: 'B'),
    ]);
    expect(unrecorded.dominantSeatType, isNull);
    expect(unrecorded.seatSummary, isNull);
  });
}

DashboardTripEntry _entry({
  required int id,
  required String from,
  required String to,
  DateTime? departure,
  DateTime? arrival,
  double mileage = 0,
  double price = 0,
  String? seatType,
}) => DashboardTripEntry(
  id: id,
  trainNumber: 'G$id',
  fromStation: from,
  toStation: to,
  departureTime: departure ?? DateTime(2026, 1, 1, 8),
  arrivalTime: arrival,
  mileageKm: mileage,
  seatType: seatType,
  seatNumber: null,
  price: price,
  isRailTrip: true,
);
