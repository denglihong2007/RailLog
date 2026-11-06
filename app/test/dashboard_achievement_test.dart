import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/achievement_unlock_trip.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
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

  test('latest unlock comes first and locked entries keep their order', () {
    final ordered = sortAchievementsByLatestUnlock([
      _unlocked('早期', DateTime(2024, 1, 1)),
      _locked('未解锁 A'),
      _unlocked('时间未知'),
      _unlocked('最近', DateTime(2026, 1, 1)),
      _locked('未解锁 B'),
      _unlocked('中间', DateTime(2025, 1, 1)),
    ]);

    expect(ordered.map((item) => item.id), [
      '最近',
      '中间',
      '早期',
      '时间未知',
      '未解锁 A',
      '未解锁 B',
    ]);
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

  testWidgets('unlocked experience chip walks the seven-colour scale', (
    tester,
  ) async {
    // 七种初始经验值（10/15/20/25/30/40/50）各占一色，「不霁何虹」要求集齐
    // 这七档，所以颜色本身就是这七档的索引：经验值越高，色相越靠后。
    const tierExperiences = [10, 15, 20, 25, 30, 40, 50];
    final tierBackgrounds = <int, int>{};
    for (final experience in tierExperiences) {
      await _pumpCard(tester, experience: experience);
      tierBackgrounds[experience] = _chipBackground(tester, experience);
    }

    expect(tierBackgrounds.values.toSet(), hasLength(tierExperiences.length));

    // 80 分的大成就没有第八种颜色，并入最高一档。
    await _pumpCard(tester, experience: 80);
    expect(_chipBackground(tester, 80), tierBackgrounds[50]);

    // 加成里的零头落在最近的一档上，不会退化成没有颜色。
    await _pumpCard(tester, experience: 35);
    expect(_chipBackground(tester, 35), tierBackgrounds[40]);
    await _pumpCard(tester, experience: 12);
    expect(_chipBackground(tester, 12), tierBackgrounds[15]);
  });

  testWidgets('locked experience chip keeps the neutral surface colour', (
    tester,
  ) async {
    await _pumpCard(tester, experience: 40, unlocked: false);
    final neutral = AppTheme.build(
      ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
    ).colorScheme.surfaceContainerHighest;
    expect(_chipBackground(tester, 40), neutral.toARGB32());

    // 同一经验值：解锁前中性、解锁后有颜色，色阶只奖励已点亮的成就。
    await _pumpCard(tester, experience: 40);
    expect(_chipBackground(tester, 40), isNot(neutral.toARGB32()));
  });

  testWidgets('seven-colour experience scale stays legible in both themes', (
    tester,
  ) async {
    const tierExperiences = [10, 15, 20, 25, 30, 40, 50];
    for (final brightness in Brightness.values) {
      for (final experience in tierExperiences) {
        await _pumpCard(tester, experience: experience, brightness: brightness);
        final ratio = _contrastRatio(
          _chipBackground(tester, experience),
          _chipForeground(tester, experience),
        );
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason:
              '$experience XP 的胶囊在 $brightness 下对比度只有 '
              '${ratio.toStringAsFixed(2)}:1',
        );
      }
    }
  });

  test('experience tiers are M3 custom colour roles on the theme', () {
    // 七档色阶不是界面里的硬编码颜色，而是挂在主题上的 M3「自定义色彩角色」，
    // 明暗主题各生成一套成对的填充色，界面只按档位取色。
    final light = AppTheme.build(
      ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
    ).extension<AchievementTierColors>();
    final dark = AppTheme.build(
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF1565C0),
        brightness: Brightness.dark,
      ),
    ).extension<AchievementTierColors>();

    expect(light, isNotNull);
    expect(dark, isNotNull);
    expect(light!.filled, hasLength(7));
    expect(light.onFilled, hasLength(7));
    expect(dark!.filled, hasLength(7));
    expect(dark.onFilled, hasLength(7));

    // 同一档在明暗主题下是同一色相的两个深浅，而不是同一个十六进制值。
    expect(light.filled, isNot(equals(dark.filled)));
  });
}

/// 渲染一张固定尺寸的成就卡，卡片里的经验胶囊显示 `experience`。
Future<void> _pumpCard(
  WidgetTester tester, {
  required int experience,
  bool unlocked = true,
  Brightness brightness = Brightness.light,
}) async {
  final theme = AppTheme.build(
    ColorScheme.fromSeed(
      seedColor: const Color(0xFF1565C0),
      brightness: brightness,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 420,
            height: 132,
            child: DashboardAchievementCard(
              achievement: _achievementWithExperience(
                experience: experience,
                unlocked: unlocked,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 经验胶囊当前的填充色。
int _chipBackground(WidgetTester tester, int experience) {
  final container = tester.widget<Container>(
    find
        .ancestor(
          of: find.text('$experience XP'),
          matching: find.byType(Container),
        )
        .first,
  );
  return (container.decoration! as BoxDecoration).color!.toARGB32();
}

/// 经验胶囊里文字的颜色。
int _chipForeground(WidgetTester tester, int experience) =>
    tester.widget<Text>(find.text('$experience XP')).style!.color!.toARGB32();

double _contrastRatio(int first, int second) {
  final firstLuminance = Color(first).computeLuminance();
  final secondLuminance = Color(second).computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

/// 卡片当前渲染出来的填充色。
int _fillOf(WidgetTester tester) =>
    tester.widget<Card>(find.byType(Card)).color!.toARGB32();

/// 已解锁成就；传 [departureTime] 表示触发行程已知，不传则本地缺这条行程。
DashboardAchievement _unlocked(String id, [DateTime? departureTime]) =>
    DashboardAchievement(
      id: id,
      category: AchievementCategory.milestones,
      iconKey: 'checklist_outlined',
      title: id,
      requirement: '达成条件',
      unlocked: true,
      triggerTripId: 1,
      unlockedBy: departureTime == null
          ? null
          : DashboardTripEntry(
              id: -1,
              ticketId: 1,
              trainNumber: 'G1',
              fromStation: '北京南',
              toStation: '上海虹桥',
              departureTime: departureTime,
              arrivalTime: null,
              mileageKm: 1318,
              seatType: null,
              seatNumber: null,
              price: 662,
              isRailTrip: true,
            ),
      unlockedUserCount: 1,
      totalUserCount: 10,
      experience: 10,
      hidden: false,
      narrativeNote: null,
    );

DashboardAchievement _locked(String id) => DashboardAchievement(
  id: id,
  category: AchievementCategory.milestones,
  iconKey: 'checklist_outlined',
  title: id,
  requirement: '达成条件',
  unlocked: false,
  triggerTripId: null,
  unlockedUserCount: 0,
  totalUserCount: 10,
  experience: 10,
  hidden: false,
  narrativeNote: null,
);

DashboardAchievement _unlockedAchievement() =>
    _achievementWithExperience(experience: 40, unlocked: true);

DashboardAchievement _achievementWithExperience({
  required int experience,
  required bool unlocked,
}) => DashboardAchievement(
  id: 'allSeatTypes',
  category: AchievementCategory.railwayCatalog,
  iconKey: 'checklist_outlined',
  title: '我全都要',
  requirement: '分别乘坐全部常规席别',
  unlocked: unlocked,
  triggerTripId: unlocked ? 42 : null,
  unlockedUserCount: 12,
  totalUserCount: 100,
  experience: experience,
  hidden: false,
  note: null,
  narrativeNote: null,
  progressCurrent: 1,
  progressTarget: 2,
);
