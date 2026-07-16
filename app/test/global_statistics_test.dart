import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/global_statistics.dart';

void main() {
  test('parses site, user, trip and element leaderboards', () {
    final user = {
      'id': 'user-1',
      'displayName': '测试用户',
      'avatarUrl': null,
      'bio': null,
      'email': null,
    };
    final trip = {
      'ticketId': 9,
      'createdAt': '2026-07-15T00:00:00Z',
      'trainNumber': 'G1',
      'fromStation': '北京南',
      'toStation': '上海虹桥',
      'departureTime': '2026-07-15T00:00:00Z',
      'arrivalTime': '2026-07-15T04:00:00Z',
      'mileageKm': 1000,
      'seatType': '二等座',
      'seatNumber': '1车1A号',
      'price': 500,
      'isRailTrip': true,
    };
    final statistics = GlobalStatistics.fromJson({
      'site': {
        'total': 10,
        'thisYear': 8,
        'thisMonth': 4,
        'thisWeek': 2,
        'totalMetrics': {
          'tripCount': 10,
          'mileageKm': 12000,
          'durationSeconds': 86400,
          'spending': 3200.5,
        },
        'thisYearMetrics': {
          'tripCount': 8,
          'mileageKm': 9000,
          'durationSeconds': 64800,
          'spending': 2400,
        },
        'thisMonthMetrics': {
          'tripCount': 4,
          'mileageKm': 4000,
          'durationSeconds': 28800,
          'spending': 1200,
        },
        'thisWeekMetrics': {
          'tripCount': 2,
          'mileageKm': 1800,
          'durationSeconds': 14400,
          'spending': 600,
        },
      },
      'users': {
        'totalSpending': [
          {'rank': 1, 'user': user, 'value': 500},
        ],
        'tripCount': [],
        'durationSeconds': [],
        'mileageKm': [],
      },
      'trips': {
        'singleSpending': [
          {'rank': 1, 'user': user, 'trip': trip, 'value': 500},
        ],
        'mileageKm': [],
        'durationSeconds': [],
        'bestValueYuanPerKm': [],
        'luxuryYuanPerKm': [],
      },
      'elements': {
        'stations': [
          {'rank': 1, 'name': '上海虹桥', 'value': 6},
        ],
        'routes': [],
        'trains': [],
      },
    });

    expect(statistics.site.thisWeek, 2);
    expect(statistics.site.totalMetrics.mileageKm, 12000);
    expect(statistics.site.thisWeekMetrics.durationSeconds, 14400);
    expect(statistics.users.totalSpending.single.user.displayName, '测试用户');
    expect(statistics.trips.singleSpending.single.trip.ticketId, 9);
    expect(statistics.elements.stations.single.name, '上海虹桥');
  });
}
