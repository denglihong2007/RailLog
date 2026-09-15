import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/pages/achievement_requirements_page.dart';
import 'package:raillog/src/theme/app_theme.dart';
import 'package:raillog/src/widgets/dashboard_achievement_card.dart';

void main() {
  test('parses achievement requirement details and completion trip', () {
    final achievement = DashboardAchievement.fromJson(
      {
        'id': 'allSeatTypes',
        'category': 'railwayCatalog',
        'icon': 'checklist_outlined',
        'title': '我全都要',
        'description': '分别乘坐全部常规席别',
        'status': 'locked',
        'triggerTripId': null,
        'unlockedUserCount': 12,
        'progressCurrent': 1,
        'progressTarget': 2,
        'experience': 40,
        'hidden': false,
        'note': null,
        'narrativeNote': null,
        'requirements': [
          {
            'key': '二等座',
            'label': '二等座',
            'completed': true,
            'trip': {
              'ticketId': 42,
              'createdAt': '2026-09-01T08:00:00Z',
              'trainNumber': 'G1',
              'fromStation': '北京南',
              'toStation': '上海虹桥',
              'departureTime': '2026-09-02T09:00:00Z',
              'arrivalTime': '2026-09-02T13:30:00Z',
              'mileageKm': 1318,
              'seatType': '二等座',
              'seatNumber': '05车 12A',
              'price': 662,
              'isRailTrip': true,
            },
          },
          {'key': '商务座', 'label': '商务座', 'completed': false, 'trip': null},
        ],
      },
      totalUserCount: 100,
      tripsByTicketId: const {},
    );

    expect(achievement.hasRequirements, isTrue);
    expect(achievement.completedRequirementCount, 1);
    expect(achievement.requirements.first.completed, isTrue);
    expect(achievement.requirements.first.trip?.ticketId, 42);
    expect(achievement.requirements.first.trip?.trainNumber, 'G1');
    expect(achievement.requirements.last.completed, isFalse);
    expect(achievement.requirements.last.trip, isNull);
  });

  testWidgets('achievement card keeps card and requirements actions separate', (
    tester,
  ) async {
    var cardTaps = 0;
    var requirementTaps = 0;
    final achievement = DashboardAchievement(
      id: 'allSeatTypes',
      category: AchievementCategory.railwayCatalog,
      iconKey: 'checklist_outlined',
      title: '我全都要',
      requirement: '分别乘坐全部常规席别',
      unlocked: true,
      triggerTripId: 42,
      unlockedUserCount: 12,
      totalUserCount: 100,
      experience: 40,
      hidden: false,
      note: '技术信息',
      narrativeNote: '能看出你很热衷于尝试未体验过的事物',
      progressCurrent: 1,
      progressTarget: 2,
      requirements: const [
        DashboardAchievementRequirement(
          key: '二等座',
          label: '二等座',
          completed: true,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              height: 120,
              child: DashboardAchievementCard(
                achievement: achievement,
                onTap: () => cardTaps++,
                onRequirementsTap: () => requirementTaps++,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final technicalInfoX = tester.getCenter(find.byIcon(Icons.info_outline)).dx;
    final requirementsButton = find.byTooltip('达成要求');
    final requirementsButtonX = tester.getCenter(requirementsButton).dx;
    final experienceX = tester.getCenter(find.text('40 XP')).dx;
    expect(technicalInfoX, lessThan(requirementsButtonX));
    expect(requirementsButtonX, lessThan(experienceX));

    await tester.tap(find.text('我全都要'));
    expect(cardTaps, 1);
    expect(requirementTaps, 0);

    await tester.tap(requirementsButton);
    expect(cardTaps, 1);
    expect(requirementTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed requirements are displayed before incomplete ones', (
    tester,
  ) async {
    final achievement = DashboardAchievement(
      id: 'allSeatTypes',
      category: AchievementCategory.railwayCatalog,
      iconKey: 'checklist_outlined',
      title: '我全都要',
      requirement: '分别乘坐全部常规席别',
      unlocked: false,
      triggerTripId: null,
      unlockedUserCount: 12,
      totalUserCount: 100,
      experience: 40,
      hidden: false,
      narrativeNote: null,
      progressCurrent: 1,
      progressTarget: 2,
      requirements: const [
        DashboardAchievementRequirement(
          key: '商务座',
          label: '商务座',
          completed: false,
        ),
        DashboardAchievementRequirement(
          key: '二等座',
          label: '二等座',
          completed: true,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        ),
        home: AchievementRequirementsPage(achievement: achievement),
      ),
    );

    final completedTop = tester.getTopLeft(find.text('二等座')).dy;
    final incompleteTop = tester.getTopLeft(find.text('商务座')).dy;
    expect(completedTop, lessThan(incompleteTop));
    expect(tester.takeException(), isNull);
  });
}
