import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/pages/achievements_page.dart';
import 'package:raillog/src/services/achievement_unlock_notifier.dart';
import 'package:raillog/src/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 成就页是「点查看更多」之后的整页路径，也是卡片出问题时最惨的地方：列表里绝大
/// 多数成就都处于未解锁状态，卡片一旦在构建期抛异常，抛点还落在 SliverGrid 的
/// layout 回调里 —— 网格布局中断后每帧重试、每帧再抛，界面直接卡死。
void main() {
  setUp(() {
    // 页面里的 EngagementPrompt 会读 SharedPreferences；widget 测试里没人应答
    // 插件通道，不 mock 会挂住。
    SharedPreferences.setMockInitialValues({});
    AchievementUnlockNotifier.instance.reset();
  });

  testWidgets('没有待庆祝项时，成就页照常挂载且不建彩带', (tester) async {
    await tester.pumpWidget(_app(_achievements()));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('成就'), findsWidgets);
    expect(find.byType(ConfettiWidget), findsNothing);
  });

  testWidgets('有待庆祝项时，切到它所属的分类并把它滚进视野再爆彩带', (tester) async {
    final achievements = _achievements();
    final target = achievements.firstWhere(
      (item) => item.id == 'ach$_targetIndex',
    );
    // 基线：目标当时还没解锁（列表里也确实没算它），于是下一次拉取里它成了「刚解锁」。
    AchievementUnlockNotifier.instance.ingest(
      achievements.where((item) => item.id != target.id).toList(),
    );
    AchievementUnlockNotifier.instance.ingest(achievements);
    expect(
      AchievementUnlockNotifier.instance.pending
          .map((item) => item.id)
          .toList(),
      [target.id],
    );

    await tester.pumpWidget(_app(achievements));
    await tester.pump();

    // 起始状态：目标既不在默认标签页里，也还躺在懒加载网格的屏幕外。
    // （这一条同时保证下面的断言不是「本来就在视野里」蒙对的。）
    expect(find.text(target.title), findsNothing);

    expect(await _pumpUntilPlaying(tester), isTrue);
    expect(tester.takeException(), isNull);

    // 开在了目标所属的分类上，而不是默认的第一个。
    expect(
      DefaultTabController.of(tester.element(find.byType(TabBarView))).index,
      AchievementCategory.values.indexOf(target.category),
    );

    // 目标卡片被滚进了视野：懒加载网格此前根本没构建过它。
    final cardRect = tester.getRect(find.text(target.title));
    expect(cardRect.top, greaterThanOrEqualTo(0));
    expect(cardRect.bottom, lessThanOrEqualTo(_screenHeight));
  });
}

const _screenHeight = 600.0;

/// 目标排在这一分类的最末尾：既不在默认标签页，也远在首屏之外。
const _targetIndex = 19;

/// 推进到彩带开始发射为止（定位要等一帧布局，滚动还要 300ms），返回是否真的发射了。
Future<bool> _pumpUntilPlaying(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final playing = tester
        .widgetList<ConfettiWidget>(find.byType(ConfettiWidget))
        .any(
          (widget) =>
              widget.confettiController.state ==
              ConfettiControllerState.playing,
        );
    if (playing) return true;
  }
  return false;
}

Widget _app(List<DashboardAchievement> achievements) => MaterialApp(
  theme: AppTheme.build(
    ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
  ),
  home: AchievementsPage(achievements: achievements),
);

List<DashboardAchievement> _achievements() => [
  // 默认标签页里也放两张，免得「开在第一个标签」和「开在目标标签」看起来一样。
  _achievement(0, AchievementCategory.milestones, unlocked: true),
  _achievement(1, AchievementCategory.milestones),
  for (var index = 2; index <= _targetIndex + 1; index++)
    _achievement(
      index,
      AchievementCategory.railwayCatalog,
      // 只有目标（排在末尾的那张）是已解锁的 —— 它就是要被定位并庆祝的那一张。
      unlocked: index == _targetIndex,
    ),
];

DashboardAchievement _achievement(
  int index,
  AchievementCategory category, {
  bool unlocked = false,
}) => DashboardAchievement(
  id: 'ach$index',
  category: category,
  iconKey: 'flag_outlined',
  title: '成就$index',
  requirement: '达成要求',
  unlocked: unlocked,
  triggerTripId: null,
  unlockedUserCount: 1,
  totalUserCount: 10,
  experience: 40,
  hidden: false,
  narrativeNote: null,
  progressCurrent: 1,
  progressTarget: 3,
);
