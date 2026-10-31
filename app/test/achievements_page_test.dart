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

  testWidgets('右上角的添加入口打开成就创意表单', (tester) async {
    await tester.pumpWidget(_app(_achievements()));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byTooltip('提交成就创意'));
    await tester.pumpAndSettle();

    expect(find.text('提交成就创意'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '成就名称'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('有待庆祝项时，切到它所属的分类并把它滚进视野再爆彩带', (tester) async {
    final achievements = _achievementsWithFreshUnlocks({_farRailway});
    final target = _byId(achievements, _farRailway);

    await tester.pumpWidget(_app(achievements));
    await tester.pump();

    // 起始状态：目标既不在默认标签页里，也还躺在懒加载网格的屏幕外。
    // （这一条同时保证下面的断言不是「本来就在视野里」蒙对的。）
    expect(find.text(target.title), findsNothing);

    expect(await _pumpUntilBurst(tester, {}, 1), isTrue);
    expect(tester.takeException(), isNull);

    // 开在了目标所属的分类上，而不是默认的第一个。
    expect(_tabIndex(tester), _tabIndexOf(target.category));

    // 目标卡片被滚进了视野：懒加载网格此前根本没构建过它。
    _expectInsideViewport(tester, target.title);
  });

  testWidgets('一次解锁多张时，按页面顺序逐张定位并各爆一次彩带', (tester) async {
    // 前两张在默认分类（第一张本来就在首屏，第二张在七行之下），第三张在另一个
    // 分类的更下面 —— 巡回既要跨分类，也要真的滚动。
    final achievements = _achievementsWithFreshUnlocks({
      _firstMilestone,
      _deepMilestone,
      _farRailway,
    });

    await tester.pumpWidget(_app(achievements));
    await tester.pump();

    expect(_tabIndex(tester), 0);
    // 后两张还没被构建过，所以下面「它们进了视野」的断言才有意义。
    expect(find.text(_deepMilestone), findsNothing);
    expect(find.text(_farRailway), findsNothing);

    // 三发彩带各是一个新 controller，累计着数。
    final seen = <ConfettiController>{};

    // 第一张：默认分类里本来就在首屏，不换页、不滚动。
    expect(await _pumpUntilBurst(tester, seen, 1), isTrue);
    expect(_tabIndex(tester), 0);
    expect(find.text(_firstMilestone), findsOneWidget);

    // 第二张：同一个分类里更靠下的那张 —— 只滚动，不换页。
    expect(await _pumpUntilBurst(tester, seen, 2), isTrue);
    expect(_tabIndex(tester), 0);
    _expectInsideViewport(tester, _deepMilestone);

    // 第三张：换到另一个分类，并且滚到很下面。
    expect(await _pumpUntilBurst(tester, seen, 3), isTrue);
    expect(
      _tabIndex(tester),
      AchievementCategory.values.indexOf(AchievementCategory.railwayCatalog),
    );
    _expectInsideViewport(tester, _farRailway);

    // 走完就收工：彩带卸掉，高亮也撤了。
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(ConfettiWidget), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('巡回途中用户自己切标签页，剩下的不播', (tester) async {
    final achievements = _achievementsWithFreshUnlocks({
      _firstMilestone,
      _deepMilestone,
    });

    await tester.pumpWidget(_app(achievements));
    await tester.pump();
    expect(await _pumpUntilBurst(tester, {}, 1), isTrue);

    // 用户不等第二张，自己切到第二个分类去。
    await tester.tap(find.text(AchievementCategory.values[1].label));
    await tester.pump(const Duration(seconds: 3));

    expect(_tabIndex(tester), 1);
    // 没有第二发：剩下的整段都停了。
    expect(find.byType(ConfettiWidget), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

const _screenHeight = 600.0;

/// 每个分类都铺满这么多张。铺满是必要的：「滚进视野」这件事只有列表比视口长才谈
/// 得上，分类里只放两三张的话目标本来就在首屏，断言等于没测。
const _perCategory = 20;

const _firstMilestone = 'milestones-0';

/// 七行之下，默认分类里的第二张 —— 首屏之外，但不需要换页。
const _deepMilestone = 'milestones-15';

/// 另一个分类的很下面，需要换页 + 滚动。
const _farRailway = 'railwayCatalog-18';

/// 推进到累计见过 [burst] 个不同的彩带 controller 为止，返回是否等到了。
///
/// 按「见到过几个不同的 controller」计数，而不是看当前状态：每发彩带都是换 key 重新
/// 挂载出来的，各带一个全新的 controller；而 `playing` 会持续到粒子落出屏幕，光看
/// 状态数不出先后。
///
/// [seen] 由调用方持有、跨次累加 —— 不能每次调用都从零数：上一发会在下一发开始前
/// 被卸掉，任何一帧里挂着的都只有一发，从零数最多数到 2。
Future<bool> _pumpUntilBurst(
  WidgetTester tester,
  Set<ConfettiController> seen,
  int burst,
) async {
  for (var frame = 0; frame < 300; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
    for (final widget in tester.widgetList<ConfettiWidget>(
      find.byType(ConfettiWidget),
    )) {
      if (widget.confettiController.state == ConfettiControllerState.playing) {
        seen.add(widget.confettiController);
      }
    }
    if (seen.length >= burst) return true;
  }
  return false;
}

/// 当前选中的标签页下标。
int _tabIndex(WidgetTester tester) =>
    tester.widget<TabBarView>(find.byType(TabBarView)).controller!.index;

int _tabIndexOf(AchievementCategory category) =>
    AchievementCategory.values.indexOf(category);

/// [title] 那张卡片当前整个落在视口内。
void _expectInsideViewport(WidgetTester tester, String title) {
  final rect = tester.getRect(find.text(title));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(_screenHeight));
}

Widget _app(List<DashboardAchievement> achievements) => MaterialApp(
  theme: AppTheme.build(
    ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
  ),
  home: AchievementsPage(achievements: achievements),
);

/// 先灌一遍「都还没解锁」当基线，再灌真实数据 —— 于是 [unlocked] 里的那几张成了
/// 本次会话里「刚解锁」的。第一次 ingest 只建立基线，所以必须喂两次。
///
/// 顺手断言 pending 正好是这几张：数据写错时，测试会在这里失败，而不是悄悄退化成
/// 「什么都没发生」也能过。
List<DashboardAchievement> _achievementsWithFreshUnlocks(Set<String> unlocked) {
  final achievements = _achievements(unlocked: unlocked);
  AchievementUnlockNotifier.instance
    ..ingest(_achievements())
    ..ingest(achievements);
  expect(
    AchievementUnlockNotifier.instance.pending.map((item) => item.id).toSet(),
    unlocked,
    reason: '待庆祝项应该正好是刚解锁的那几张',
  );
  return achievements;
}

List<DashboardAchievement> _achievements({Set<String> unlocked = const {}}) => [
  for (final category in AchievementCategory.values)
    for (var index = 0; index < _perCategory; index++)
      _achievement(
        '${category.apiKey}-$index',
        category,
        unlocked: unlocked.contains('${category.apiKey}-$index'),
      ),
];

DashboardAchievement _byId(
  List<DashboardAchievement> achievements,
  String id,
) => achievements.firstWhere((item) => item.id == id);

/// 标题直接用 id：测试里 `find.text(...)` 找的就是它。
DashboardAchievement _achievement(
  String id,
  AchievementCategory category, {
  bool unlocked = false,
}) => DashboardAchievement(
  id: id,
  category: category,
  iconKey: 'flag_outlined',
  title: id,
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
