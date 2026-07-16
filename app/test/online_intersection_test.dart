import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/online_intersection.dart';
import 'package:raillog/src/models/public_user_dashboard.dart';

void main() {
  test('parses a strict public trip intersection', () {
    final intersection = OnlineIntersection.fromJson({
      'kind': 'station',
      'location': '上海站',
      'intersectionCount': 1,
      'trips': [
        {
          'ticketId': 42,
          'userId': 'user-2',
          'displayName': '同行者',
          'avatarUrl': 'https://example.com/avatar.png',
          'occurredAt': '2026-07-15T02:00:00Z',
          'isStrict': true,
          'trainNumber': 'G1',
        },
      ],
    });

    expect(intersection.kind, OnlineIntersectionKind.station);
    expect(intersection.location, '上海站');
    expect(intersection.trips.single.isStrict, isTrue);
    expect(intersection.trips.single.ticketId, 42);
    expect(intersection.trips.single.trainNumber, 'G1');
  });

  test('parses a public user dashboard with server ticket identities', () {
    final dashboard = PublicUserDashboard.fromJson({
      'user': {
        'id': 'user-2',
        'displayName': '同行者',
        'avatarUrl': null,
        'bio': '铁路旅行者',
        'email': 'user@example.com',
      },
      'trips': [
        {
          'ticketId': 42,
          'createdAt': '2026-07-15T00:00:00Z',
          'trainNumber': 'G1',
          'rollingStock': null,
          'companyName': null,
          'fromStation': '北京南',
          'toStation': '上海站',
          'departureTime': '2026-07-15T00:00:00Z',
          'arrivalTime': '2026-07-15T02:00:00Z',
          'mileageKm': 1000,
          'viaRoutes': '[]',
          'seatType': '二等座',
          'seatNumber': '1车1A号',
          'price': 553,
          'notes': null,
          'isRailTrip': true,
        },
      ],
    });

    expect(dashboard.user.bio, '铁路旅行者');
    expect(dashboard.user.email, 'user@example.com');
    expect(dashboard.trips.single.ticketId, 42);
    expect(dashboard.trips.single.id, -42);
  });

  test('parses public trip details fetched after list selection', () {
    final details = PublicTripDetails.fromJson({
      'user': {
        'id': 'user-2',
        'displayName': '同行者',
        'avatarUrl': null,
        'bio': '铁路旅行者',
        'email': 'user@example.com',
      },
      'trip': {
        'ticketId': 42,
        'createdAt': '2026-07-15T00:00:00Z',
        'trainNumber': 'G1',
        'rollingStock': 'CR400AF',
        'companyName': '上海局集团',
        'fromStation': '北京南',
        'toStation': '上海站',
        'departureTime': '2026-07-15T00:00:00Z',
        'arrivalTime': '2026-07-15T02:00:00Z',
        'mileageKm': 1000,
        'viaRoutes':
            '[{"routeName":"京沪高速线","fromStation":"北京南","toStation":"上海虹桥","mileageKm":1000}]',
        'seatType': '二等座',
        'seatNumber': '1车1A号',
        'price': 553,
        'notes': '详情备注',
        'isRailTrip': true,
      },
    });

    expect(details.user.displayName, '同行者');
    expect(details.trip.ticketId, 42);
    expect(details.trip.notes, '详情备注');
    expect(details.trip.viaRouteSegments.single.routeName, '京沪高速线');
  });
}
