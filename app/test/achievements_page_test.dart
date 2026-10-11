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

  testWidgets('几乎全是未解锁卡片时，成就页仍能挂载', (tester) async {
    await tester.pumpWidget(_app(_achievements()));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('成就'), findsWidgets);
  });

  testWidgets('有待庆祝的解锁时，彩带进入发射状态且页面不崩', (tester) async {
    final notifier = AchievementUnlockNotifier.instance;
    notifier.ingest(_achievements()); // 基线：只有 a 解锁
    notifier.ingest(_achievements(unlockB: true)); // b 此刻刚解锁

    // 别让这条测试悄悄退化成「其实没有待庆祝项」。
    expect(notifier.pending.map((item) => item.id).toList(), ['b']);

    await tester.pumpWidget(_app(_achievements(unlockB: true)));
    await tester.pump();

    // 彩带必须赶在 ConfettiWidget 挂载前 play：它只在自己的 post-frame 回调里
    // 检查控制器是否已处于 playing，晚一步就永远不会发射。
    final confetti = tester.widget<ConfettiWidget>(find.byType(ConfettiWidget));
    expect(confetti.confettiController.state, ConfettiControllerState.playing);

    // 发射窗口 200ms 结束后粒子靠重力飘完，之后页面上不该再有异常。
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  });
}

Widget _app(List<DashboardAchievement> achievements) => MaterialApp(
  theme: AppTheme.build(
    ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
  ),
  home: AchievementsPage(achievements: achievements),
);

List<DashboardAchievement> _achievements({bool unlockB = false}) => [
  _achievement('a', unlocked: true),
  _achievement('b', unlocked: unlockB, progressCurrent: 1, progressTarget: 3),
  // 一条始终未解锁的：真实的成就页里未解锁卡片占绝大多数，庆祝时也一样。
  _achievement('c', unlocked: false, progressCurrent: 2, progressTarget: 5),
];

DashboardAchievement _achievement(
  String id, {
  required bool unlocked,
  double? progressCurrent,
  double? progressTarget,
}) => DashboardAchievement(
  id: id,
  category: AchievementCategory.milestones,
  iconKey: 'flag_outlined',
  title: '成就$id',
  requirement: '达成要求',
  unlocked: unlocked,
  triggerTripId: null,
  unlockedUserCount: 1,
  totalUserCount: 10,
  experience: 40,
  hidden: false,
  narrativeNote: null,
  progressCurrent: progressCurrent,
  progressTarget: progressTarget,
);
