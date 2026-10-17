import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/achievement_unlock_trip.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/pages/achievement_requirements_page.dart';
import 'package:raillog/src/pages/achievement_unlock_trips_page.dart';
import 'package:raillog/src/theme/app_theme.dart';
import 'package:raillog/src/widgets/app_card.dart';
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

  testWidgets('achievement card has one tap target and shows a chevron', (
    tester,
  ) async {
    var cardTaps = 0;
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
              height: 132,
              child: DashboardAchievementCard(
                achievement: achievement,
                onTap: () => cardTaps++,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final technicalInfoX = tester.getCenter(find.byIcon(Icons.info_outline)).dx;
    final experienceX = tester.getCenter(find.text('40 XP')).dx;
    expect(technicalInfoX, lessThan(experienceX));
    // 要求入口并进了整卡点击，底部只留一个表示可点击的箭头。
    expect(find.byTooltip('达成要求'), findsNothing);
    expect(find.text('明细'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    await tester.tap(find.text('我全都要'));
    expect(cardTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locked achievement card uses the default fill, never null', (
    tester,
  ) async {
    // 未解锁卡片走的是「沿用 AppCard 默认填充色」的分支，这里必须落成一个具体颜色：
    // TweenAnimationBuilder 断言 tween.end 非空，而卡片是在 SliverGrid 的 layout
    // 回调里构建的 —— 把 null 交给它会在构建期抛异常、中断整个网格的布局，并且每帧
    // 重来一次，成就页因此直接卡死（列表里绝大多数卡片都是未解锁的）。
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
      note: null,
      narrativeNote: null,
      progressCurrent: 1,
      progressTarget: 2,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        ),
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: 420,
                height: 132,
                child: DashboardAchievementCard(achievement: achievement),
              ),
              // 对照组：不传 color 的 AppCard.filled。显式给默认色只是为了让
              // TweenAnimationBuilder 拿到非空 end，外观不该有任何变化。
              const SizedBox(
                width: 420,
                height: 132,
                child: AppCard.filled(child: SizedBox.expand()),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final fills = tester
        .widgetList<Card>(find.byType(Card))
        .map((card) => card.color)
        .toList();
    expect(fills, hasLength(2));
    expect(fills.first, isNotNull);
    expect(fills.first, fills.last);
    // 未解锁且带进度：进度环在徽章上，底部只报一次数字，不再重复「尚未解锁」。
    expect(find.text('已达成 1/2'), findsOneWidget);
    expect(find.text('尚未解锁'), findsNothing);
    // _formatPercentage 自带 %，这里只该出现一个。
    expect(find.text('12%'), findsOneWidget);
    expect(find.text('12%%'), findsNothing);
  });

  testWidgets('unlock keeps the requirement and adds the narrative', (
    tester,
  ) async {
    DashboardAchievement build({required bool unlocked}) =>
        DashboardAchievement(
          id: 'allSeatTypes',
          category: AchievementCategory.railwayCatalog,
          iconKey: 'checklist_outlined',
          title: '我全都要',
          requirement: '分别乘坐全部常规席别',
          unlocked: unlocked,
          triggerTripId: unlocked ? 42 : null,
          unlockedUserCount: 12,
          totalUserCount: 100,
          experience: 40,
          hidden: false,
          note: null,
          narrativeNote: '能看出你很热衷于尝试未体验过的事物',
          progressCurrent: 1,
          progressTarget: 2,
        );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        ),
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 132,
            child: DashboardAchievementCard(
              achievement: build(unlocked: false),
            ),
          ),
        ),
      ),
    );

    // 未解锁时看到的仍是「要做什么」。
    expect(find.text('分别乘坐全部常规席别'), findsOneWidget);
    expect(find.text('能看出你很热衷于尝试未体验过的事物'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        ),
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 132,
            child: DashboardAchievementCard(achievement: build(unlocked: true)),
          ),
        ),
      ),
    );

    // 解锁后达成条件仍然可见，叙述性说明作为额外的一行补在下面。
    expect(find.text('分别乘坐全部常规席别'), findsOneWidget);
    expect(find.text('能看出你很热衷于尝试未体验过的事物'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card survives the narrowest two-column grid cell', (
    tester,
  ) async {
    // 600px 视口会切成两列，此时卡片内宽只有 ~242px。这里取最高的形态：解锁后
    // 达成条件 + 叙述两行都在，底部还要同时放稀有度和点击箭头。
    final achievement = DashboardAchievement(
      id: 'allSeatTypes',
      category: AchievementCategory.railwayCatalog,
      iconKey: 'checklist_outlined',
      title: '我全都要',
      requirement: '分别乘坐全部常规席别',
      unlocked: true,
      triggerTripId: 42,
      unlockedUserCount: 1234,
      totalUserCount: 5678,
      experience: 40,
      hidden: false,
      note: '无座、硬座、软座、二等座、一等座、特等座、优选一等座、商务座',
      narrativeNote: '能看出你很热衷于尝试未体验过的事物',
      progressCurrent: 1,
      progressTarget: 2,
      requirements: const [
        DashboardAchievementRequirement(
          key: '二等座',
          label: '二等座',
          completed: true,
        ),
        DashboardAchievementRequirement(
          key: '商务座',
          label: '商务座',
          completed: false,
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
              width: 270,
              height: 132,
              child: DashboardAchievementCard(
                achievement: achievement,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('just unlocked card lights up on mount', (tester) async {
    // 成就页定位到刚解锁的那张卡片时传 justUnlocked，它要在挂载时把底色从默认色
    // 补间到解锁色 —— 这是「就是它」的那一下强调。
    final theme = AppTheme.build(
      ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
    );
    final colors = theme.colorScheme;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              height: 132,
              child: DashboardAchievementCard(
                achievement: _unlockedAchievement(),
                justUnlocked: true,
              ),
            ),
          ),
        ),
      ),
    );

    // 起点仍是「未解锁」时的默认底色：观感上就是刚刚还没亮。
    expect(_fillOf(tester), colors.surfaceContainerLow.toARGB32());

    await tester.pump(const Duration(milliseconds: 100));
    final mid = _fillOf(tester);
    expect(mid, isNot(colors.surfaceContainerLow.toARGB32()));
    expect(mid, isNot(colors.tertiaryContainer.toARGB32()));

    await tester.pump(const Duration(milliseconds: 200));
    expect(_fillOf(tester), colors.tertiaryContainer.toARGB32());
  });

  testWidgets('plain unlocked card is already lit on mount', (tester) async {
    // 对照组：不传 justUnlocked 时不该有这次补间 —— 冷启动与列表重排都不该重放，
    // 全页只剩「刚解锁的那一张」会亮，否则这个强调就不成其为强调。
    final theme = AppTheme.build(
      ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
    );
    final colors = theme.colorScheme;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              height: 132,
              child: DashboardAchievementCard(
                achievement: _unlockedAchievement(),
              ),
            ),
          ),
        ),
      ),
    );

    expect(_fillOf(tester), colors.tertiaryContainer.toARGB32());
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

  testWidgets('unlock trip row shows the route just like a requirement row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        ),
        home: Scaffold(
          body: AchievementTripRow(
            trip: AchievementUnlockTrip(
              ticketId: 42,
              userId: 'u1',
              displayName: '测试用户',
              avatarUrl: null,
              occurredAt: DateTime(2026, 9, 2, 9),
              trainNumber: 'G1',
              fromStation: '北京南',
              toStation: '上海虹桥',
              isCurrentUser: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('2026-09-02 · G1 · 北京南 → 上海虹桥'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// 卡片当前渲染出来的填充色。
int _fillOf(WidgetTester tester) =>
    tester.widget<Card>(find.byType(Card)).color!.toARGB32();

DashboardAchievement _unlockedAchievement() => DashboardAchievement(
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
  note: null,
  narrativeNote: null,
  progressCurrent: 1,
  progressTarget: 2,
);
