import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/widgets/dashboard_achievement_card.dart';

void main() {
  test('server achievement resolves its trigger ticket and percentage', () {
    final trigger = _trip(ticketId: 42);
    final achievements = dashboardAchievementsFromJson(
      {
        'totalUserCount': 10,
        'achievements': [
          {
            'id': 'oneYuanJourney',
            'icon': 'currency_yen',
            'title': '一元旅程',
            'description': '单次行程票价为 1 元',
            'status': 'unlocked',
            'triggerTripId': 42,
            'unlockedUserCount': 2,
          },
        ],
      },
      [trigger],
    );

    expect(achievements.single.isUnlocked, isTrue);
    expect(achievements.single.unlockedBy, same(trigger));
    expect(achievements.single.unlockedPercentage, 20);
  });

  testWidgets('achievement card shows global unlock users and percentage', (
    tester,
  ) async {
    final achievement = dashboardAchievementsFromJson({
      'totalUserCount': 10,
      'achievements': [
        {
          'id': 'oneYuanJourney',
          'icon': 'currency_yen',
          'title': '一元旅程',
          'description': '单次行程票价为 1 元',
          'status': 'locked',
          'triggerTripId': null,
          'unlockedUserCount': 2,
        },
      ],
    }, const []).single;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 140,
            child: DashboardAchievementCard(achievement: achievement),
          ),
        ),
      ),
    );

    expect(find.text('2 位用户 · 20%'), findsOneWidget);
  });
}

DashboardTripEntry _trip({required int ticketId}) => DashboardTripEntry(
  id: 7,
  ticketId: ticketId,
  trainNumber: 'G1',
  fromStation: '北京南站',
  toStation: '上海虹桥站',
  departureTime: DateTime(2026, 1, 1, 8),
  arrivalTime: DateTime(2026, 1, 1, 12),
  mileageKm: 1000,
  seatType: '二等座',
  seatNumber: '01车01A号',
  price: 1,
  isRailTrip: true,
);
