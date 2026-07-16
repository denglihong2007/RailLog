import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_unlock_entry.dart';
import 'package:raillog/src/models/trip_dashboard_stats.dart';
import 'package:raillog/src/models/trip_record.dart';

void main() {
  test('station unlocks use departure and arrival events respectively', () {
    final stats = TripDashboardStats.fromTrips([
      TripRecord(
        id: 1,
        trainNumber: 'K1',
        fromStation: '甲站',
        toStation: '乙站',
        departureTime: DateTime(2026, 1, 1, 23),
        arrivalTime: DateTime(2026, 1, 2, 1),
        viaRouteSegments: const [],
      ),
    ]);

    final departure = stats.stationUnlocks.singleWhere(
      (entry) => entry.name == '甲站',
    );
    final arrival = stats.stationUnlocks.singleWhere(
      (entry) => entry.name == '乙站',
    );
    expect(departure.unlockTime, DateTime(2026, 1, 1, 23));
    expect(departure.action, DashboardUnlockAction.departStation);
    expect(arrival.unlockTime, DateTime(2026, 1, 2, 1));
    expect(arrival.action, DashboardUnlockAction.arriveStation);
  });

  test('station unlock keeps the earliest arrival or departure event', () {
    final stats = TripDashboardStats.fromTrips([
      TripRecord(
        id: 1,
        trainNumber: 'G1',
        fromStation: '甲站',
        toStation: '中转站',
        departureTime: DateTime(2026, 1, 1, 8),
        arrivalTime: DateTime(2026, 1, 1, 9),
        viaRouteSegments: const [],
      ),
      TripRecord(
        id: 2,
        trainNumber: 'G2',
        fromStation: '中转站',
        toStation: '乙站',
        departureTime: DateTime(2026, 1, 2, 10),
        arrivalTime: DateTime(2026, 1, 2, 11),
        viaRouteSegments: const [],
      ),
    ]);

    final station = stats.stationUnlocks.singleWhere(
      (entry) => entry.name == '中转站',
    );
    expect(station.unlockTime, DateTime(2026, 1, 1, 9));
    expect(station.action, DashboardUnlockAction.arriveStation);
  });
}
