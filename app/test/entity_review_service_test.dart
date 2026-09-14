import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/services/entity_review_service.dart';

void main() {
  test('EntityReview parses associated public trips', () {
    final review = EntityReview.fromJson({
      'id': 1,
      'entityType': 'station',
      'entityKey': '济南西',
      'reviewType': 'transfer',
      'userId': 'user-1',
      'displayName': '测试用户',
      'avatarUrl': null,
      'rating': 5,
      'comment': '换乘方便',
      'tripId': 101,
      'secondTripId': 102,
      'transferMinutes': 35,
      'dish': null,
      'price': null,
      'createdAt': '2026-09-14T10:00:00Z',
      'trip': _tripJson(101, 'G1', '北京南', '济南西'),
      'secondTrip': _tripJson(102, 'G2', '济南西', '上海虹桥'),
    });

    expect(review.entityType, 'station');
    expect(review.entityKey, '济南西');
    expect(review.trip?.ticketId, 101);
    expect(review.trip?.fromStation, '北京南');
    expect(review.secondTrip?.ticketId, 102);
    expect(review.secondTrip?.toStation, '上海虹桥');
    expect(review.transferMinutes, 35);
  });

  test('EntityReview parses the selected route segment', () {
    final review = EntityReview.fromJson({
      'id': 2,
      'entityType': 'route',
      'entityKey': '京沪高铁',
      'reviewType': 'route',
      'userId': 'user-1',
      'displayName': '测试用户',
      'avatarUrl': null,
      'rating': 5,
      'comment': '沿途风景不错',
      'tripId': 101,
      'secondTripId': null,
      'transferMinutes': null,
      'routeFromStation': '北京南',
      'routeToStation': '济南西',
      'dish': null,
      'price': null,
      'createdAt': '2026-09-14T10:00:00Z',
      'trip': _tripJson(101, 'G1', '北京南', '上海虹桥'),
      'secondTrip': null,
      'reactions': [
        {'emoji': '👍', 'count': 3, 'reactedByCurrentUser': true},
      ],
    });

    expect(review.routeFromStation, '北京南');
    expect(review.routeToStation, '济南西');
    expect(review.reactions.single.emoji, '👍');
    expect(review.reactions.single.count, 3);
    expect(review.reactions.single.reactedByCurrentUser, isTrue);
  });
}

Map<String, dynamic> _tripJson(
  int ticketId,
  String trainNumber,
  String fromStation,
  String toStation,
) => {
  'ticketId': ticketId,
  'createdAt': '2026-09-14T08:00:00Z',
  'trainNumber': trainNumber,
  'rollingStock': null,
  'companyName': null,
  'fromStation': fromStation,
  'toStation': toStation,
  'departureTime': '2026-09-14T08:00:00Z',
  'arrivalTime': '2026-09-14T09:00:00Z',
  'mileageKm': 100,
  'viaRoutes': '[]',
  'seatType': '二等座',
  'seatNumber': null,
  'price': 50,
  'notes': null,
  'isRailTrip': true,
};
