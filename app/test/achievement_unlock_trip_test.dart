import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/achievement_unlock_trip.dart';

AchievementUnlockTrip _trip({
  required int ticketId,
  required int experience,
  DateTime? occurredAt,
  bool isCurrentUser = false,
}) => AchievementUnlockTrip(
  ticketId: ticketId,
  userId: 'u$ticketId',
  displayName: '用户$ticketId',
  avatarUrl: null,
  occurredAt: occurredAt ?? DateTime(2026, 9, ticketId),
  trainNumber: 'G$ticketId',
  fromStation: '北京南',
  toStation: '上海虹桥',
  isCurrentUser: isCurrentUser,
  experience: experience,
);

void main() {
  test('experience-variable achievements rank by experience with ties', () {
    final trips = AchievementUnlockTrips(
      achievementId: 'tightTransfer',
      hasExperienceVariation: true,
      trips: [
        _trip(ticketId: 1, experience: 50),
        _trip(ticketId: 2, experience: 30),
        _trip(ticketId: 3, experience: 30),
        _trip(ticketId: 4, experience: 10),
        _trip(ticketId: 5, experience: 10, isCurrentUser: true),
      ],
    );

    final ranking = trips.ranking;

    // 自己永远置顶，但名次按真实经验算。
    expect(ranking.first.trip.ticketId, 5);
    expect(ranking.first.rank, 4);
    expect(
      [for (final entry in ranking) (entry.trip.ticketId, entry.rank)],
      [(5, 4), (1, 1), (3, 2), (2, 2), (4, 4)],
    );
  });

  test('fixed-experience achievements keep no ranks and pin self first', () {
    final trips = AchievementUnlockTrips(
      achievementId: 'allSeatTypes',
      trips: [
        _trip(ticketId: 1, experience: 40, occurredAt: DateTime(2026, 9, 3)),
        _trip(
          ticketId: 2,
          experience: 40,
          occurredAt: DateTime(2026, 9, 1),
          isCurrentUser: true,
        ),
        _trip(ticketId: 3, experience: 40, occurredAt: DateTime(2026, 9, 2)),
      ],
    );

    final ranking = trips.ranking;

    expect(ranking.every((entry) => entry.rank == null), isTrue);
    expect([for (final entry in ranking) entry.trip.ticketId], [2, 1, 3]);
  });

  test('unlock trips parse experience and variation flag', () {
    final trips = AchievementUnlockTrips.fromJson({
      'achievementId': 'tightTransfer',
      'hasExperienceVariation': true,
      'trips': [
        {
          'ticketId': 42,
          'userId': 'u1',
          'displayName': '测试用户',
          'avatarUrl': null,
          'occurredAt': '2026-09-02T09:00:00Z',
          'trainNumber': 'G1',
          'fromStation': '北京南',
          'toStation': '上海虹桥',
          'isCurrentUser': true,
          'experience': 35,
        },
      ],
    });

    expect(trips.hasExperienceVariation, isTrue);
    expect(trips.trips.single.experience, 35);
  });
}
