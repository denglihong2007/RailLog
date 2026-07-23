import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_unlock_entry.dart';
import 'package:raillog/src/models/trip_dashboard_stats.dart';
import 'package:raillog/src/models/trip_record.dart';

void main() {
  test('探访车站列表计入没有到达时间的终点站', () {
    final departureTime = DateTime(2026, 7, 23, 8);
    final stats = TripDashboardStats.fromTrips([
      TripRecord(
        id: 1,
        trainNumber: 'G1',
        fromStation: '北京南',
        toStation: '上海虹桥',
        departureTime: departureTime,
        viaRouteSegments: const [],
      ),
    ]);

    expect(stats.stationCount, 2);
    final destination = stats.stationUnlocks.singleWhere(
      (entry) => entry.name == '上海虹桥',
    );
    expect(destination.action, DashboardUnlockAction.arriveStation);
    expect(destination.unlockTime, departureTime);
    expect(destination.tripIds, [1]);
  });
}
