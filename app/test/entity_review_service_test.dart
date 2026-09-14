import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/services/entity_review_service.dart';

void main() {
  test('EntityReview parses associated public trips', () {
    final review = EntityReview.fromJson({
      'id': 1,
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

    expect(review.trip?.ticketId, 101);
    expect(review.trip?.fromStation, '北京南');
    expect(review.secondTrip?.ticketId, 102);
    expect(review.secondTrip?.toStation, '上海虹桥');
    expect(review.transferMinutes, 35);
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
