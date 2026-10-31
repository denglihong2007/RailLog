import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/pages/achievement_proposal_page.dart';
import 'package:raillog/src/pages/achievement_unlock_trips_page.dart';
import 'package:raillog/src/pages/achievement_requirements_page.dart';
import 'package:raillog/src/services/achievement_unlock_notifier.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/dashboard_achievement_card.dart';
import 'package:raillog/src/widgets/engagement_prompt.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';
import 'package:raillog/src/widgets/user_level_badge.dart';

class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key, required this.achievements});

  final List<DashboardAchievement> achievements;

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage>
    with SingleTickerProviderStateMixin {
  /// 两发彩带之间停多久。够看清卡片、也让上一发的粒子落出屏幕；算上定位本身，
  /// 一张大约 1.1 秒，几张连播也不拖沓。
  static const _dwellBetweenTargets = Duration(milliseconds: 800);

  /// 等网格报出目标偏移最多等几帧。
  static const _offsetWaitFrames = 30;

  /// 页面主体的 Stack，用来把卡片的全局坐标换算成发射点的局部坐标。
  final GlobalKey _bodyKey = GlobalKey();

  /// 挂在当前被定位的那张卡片上。网格是懒加载的，只有它被真正构建出来之后才拿得到坐标。
  final GlobalKey _targetCardKey = GlobalKey();

  final ScrollController _scrollController = ScrollController();

  /// 自己持有，而不是用 `DefaultTabController`：一次解锁多张时，巡回途中要换到
  /// 另一个分类的标签页，需要一个随时能下命令的 controller。
  late final TabController _tabController;

  /// 网格在布局期算出的目标偏移，见 [_GridTargetOffset]。
  final _GridTargetOffset _gridTargetOffset = _GridTargetOffset();

  /// 本次进入页面要**按页面出现顺序**逐个庆祝的成就。
  final List<DashboardAchievement> _targets = [];

  /// 巡回走到第几张；-1 表示当前没有高亮任何一张。
  int _cursor = -1;

  /// 巡回还在不在走。用户中途自己切标签页会把它关掉。
  bool _touring = false;

  /// 巡回里正在等的那一段（两发之间的一拍、换页后的落位）。
  ///
  /// 自己持有而不是用 `Future.delayed`：页面被拆掉时 `Future.delayed` 的定时器还在
  /// 跑，测试框架会把它算成泄漏的 timer。同一时刻只有一段等待，一个字段就够。
  Timer? _waitTimer;

  DashboardAchievement? get _target => _cursor < 0 ? null : _targets[_cursor];

  /// 彩带的发射点（主体 Stack 的局部坐标）。null 表示没能定位到卡片，走兜底位置。
  Offset? _celebrationAnchor;

  /// 彩带要不要上场。定位是异步的（换标签、等布局、等滚动落位），所以单独占一个状态。
  bool _celebrating = false;

  @override
  void initState() {
    super.initState();
    _collectTargets();
    _tabController = TabController(
      length: AchievementCategory.values.length,
      // 直接开在第一个目标所属的分类上，省掉一次换页。
      initialIndex: _targets.isEmpty
          ? 0
          : AchievementCategory.values.indexOf(_targets.first.category),
      // 显式写成全仓的动效预算（也正是 TabController 的默认值）：[_celebrate] 要按
      // 这个时长等目标页滑进来，两者必须对得上。
      animationDuration: m3MotionDuration,
      vsync: this,
    );
    if (_targets.isEmpty) return;
    // 目标在滚动视图里的位置要等这一帧布局完才知道，所以定位推迟到帧后。
    WidgetsBinding.instance.addPostFrameCallback((_) => _runCelebration());
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 把这一批「刚解锁」的成就排成它们在页面上的出现顺序：先按标签页顺序，页内再按
  /// 列表顺序。不这么排的话，定位会在两条线之间来回跳。
  void _collectTargets() {
    final notifier = AchievementUnlockNotifier.instance;
    final pending = notifier.pending;
    if (pending.isEmpty) return;
    // 取走就不再放回：离开成就页再进来不该重放一次。
    notifier.clearPending();
    final pendingIds = {for (final item in pending) item.id};
    for (final category in AchievementCategory.values) {
      for (final achievement in widget.achievements) {
        if (achievement.category == category &&
            pendingIds.contains(achievement.id)) {
          _targets.add(achievement);
        }
      }
    }
  }

  /// 逐个走一遍：定位到第 [index] 张、放彩带、停一拍，再走向下一张。
  ///
  /// 只由 [initState] 启动一次。[mounted] 与 [_touring] 是仅有的两个终止条件 ——
  /// 用户中途退页时，正在 await 的那一步会自然落地然后退出。
  Future<void> _runCelebration() async {
    _touring = true;
    for (var index = 0; index < _targets.length; index++) {
      if (!mounted || !_touring) return;
      await _celebrate(index);
      if (!mounted || !_touring) return;
      // 每一发都停够一拍再往下走，最后一发也不例外 —— 它也要把这一拍飞完，然后才
      // 收工。少了这一步，单张的情形会在「请求发射」的同一帧里就撤销，彩带根本
      // 来不及挂上去。
      await _wait(_dwellBetweenTargets);
    }
    if (!mounted || !_touring) return;
    setState(() {
      _cursor = -1;
      _celebrating = false;
    });
    _touring = false;
  }

  /// 把第 [index] 张滚进视野，然后在它身上放彩带。
  Future<void> _celebrate(int index) async {
    final target = _targets[index];
    final tabIndex = AchievementCategory.values.indexOf(target.category);
    final switchingTab = _tabController.index != tabIndex;
    if (switchingTab) {
      // 直接把下标挪过去，不要求换页动画 —— 但 TabBarView 会自己按 controller 的
      // animationDuration 把目标页滑进来，下面按同一个时长等它。
      _tabController.index = tabIndex;
    }
    // 先把「这次轮到它了」广播出去：分类视图据此给它挂 key 与 justUnlocked，网格据此
    // 把新偏移写进 [_gridTargetOffset]。同时把上一发撤下来 —— 此刻锚点还是上一张的。
    setState(() {
      _cursor = index;
      _celebrating = false;
    });
    if (switchingTab) {
      // 目标页要在滑进来的过程中才布局、才报得出偏移。等它滑完再滚动，免得两段动画
      // 叠在一起。
      await _wait(m3MotionDuration);
      if (!mounted || !_touring) return;
    }

    final offset = await _awaitTargetOffset(target.id);
    if (!mounted || !_touring) return;
    if (offset != null && _scrollController.hasClients) {
      final position = _scrollController.position;
      // 让卡片落在视口偏上的位置：彩带要向上炸开才有空间。
      final destination = (offset - position.viewportDimension * 0.3).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((destination - position.pixels).abs() > 1) {
        await _scrollController.animateTo(
          destination,
          duration: m3MotionDuration,
          curve: Easing.emphasizedDecelerate,
        );
        if (!mounted || !_touring) return;
      }
    }
    // 再等一帧：卡片的 render box 要等滚动落位、它被网格真正构建出来之后才拿得到。
    await _nextFrame();
    if (!mounted || !_touring) return;
    setState(() {
      _celebrationAnchor = _targetCardCenter();
      _celebrating = true;
    });
  }

  /// 用户半路自己切了标签页 —— 说明他不想接着看了，剩下的不播。
  void _cancelCelebration() {
    if (!_touring) return;
    _touring = false;
    setState(() {
      _cursor = -1;
      _celebrating = false;
    });
  }

  /// 等到网格为 [targetId] 报出偏移为止；等不到返回 null，调用方走兜底位置。
  ///
  /// 要等，是因为偏移是布局期的产物，而换了目标之后网格要重新布局才会写新值。按帧数
  /// 等而不是按挂钟时间等：这里等的就是「框架再跑一帧」。
  Future<double?> _awaitTargetOffset(String targetId) async {
    for (var frame = 0; frame < _offsetWaitFrames; frame++) {
      final value = _gridTargetOffset.valueOf(targetId);
      if (value != null) return value;
      await _nextFrame();
      if (!mounted) return null;
    }
    return null;
  }

  /// 等 [duration] 那么久，并且可以被 [dispose] 掐断，见 [_waitTimer]。
  ///
  /// 掐断时不会去完成 [Completer]：调用方此时必然已经 `!mounted`，让它直接吊在那里
  /// 比叫醒它再走一遍终止判断更省事，而且没有定时器就没有泄漏。
  Future<void> _wait(Duration duration) {
    final completer = Completer<void>();
    _waitTimer = Timer(duration, () {
      _waitTimer = null;
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  /// 等下一帧走完。
  ///
  /// 显式要一帧：`addPostFrameCallback` 自己不会催出帧来，而两发彩带之间那一拍里
  /// 没有任何动画在跑，不主动要一帧就会一直等下去。
  Future<void> _nextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance
      ..scheduleFrame()
      ..addPostFrameCallback((_) {
        if (!completer.isCompleted) completer.complete();
      });
    return completer.future;
  }

  /// 目标卡片的中心点，换算成主体 Stack 的局部坐标；拿不到就返回 null。
  Offset? _targetCardCenter() {
    final cardBox =
        _targetCardKey.currentContext?.findRenderObject() as RenderBox?;
    final bodyBox = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (cardBox == null || bodyBox == null || !cardBox.hasSize) return null;
    return bodyBox.globalToLocal(
      cardBox.localToGlobal(cardBox.size.center(Offset.zero)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final achievements = widget.achievements;
    final unlocked = achievements.where((item) => item.isUnlocked).length;
    final totalExperience = achievements
        .where((item) => item.isUnlocked)
        .fold(0, (total, item) => total + item.experience);
    final target = _target;
    return Scaffold(
      appBar: AppBar(
        title: const Text('成就'),
        scrolledUnderElevation: 3,
        actions: [
          IconButton(
            tooltip: '提交成就创意',
            onPressed: _openProposal,
            icon: const Icon(Icons.add),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          // 用户自己切页 = 不想接着看巡回里的下一张了。
          onTap: (_) => _cancelCelebration(),
          labelPadding: EdgeInsets.zero,
          dividerHeight: 1,
          dividerColor: Theme.of(context).colorScheme.outlineVariant,
          tabs: [
            for (final category in AchievementCategory.values)
              Tab(
                icon: Icon(_categoryIcon(category)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(category.label),
                ),
              ),
          ],
        ),
      ),
      body: Stack(
        key: _bodyKey,
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              for (final category in AchievementCategory.values)
                _categoryView(
                  category: category,
                  unlocked: unlocked,
                  totalExperience: totalExperience,
                ),
            ],
          ),
          _AchievementPromptTrigger(unlockedCount: unlocked),
          if (_celebrating && target != null)
            _AchievementConfetti(
              // 一张一个 key：换目标时整棵彩带重新挂载，于是又爆一次。
              key: ValueKey(target.id),
              anchor: _celebrationAnchor,
            ),
        ],
      ),
    );
  }

  Widget _categoryView({
    required AchievementCategory category,
    required int unlocked,
    required int totalExperience,
  }) {
    final achievements = widget.achievements
        .where((item) => item.category == category)
        .toList(growable: false);
    final target = _target;
    final targetIndex = target == null || target.category != category
        ? -1
        : achievements.indexWhere((item) => item.id == target.id);
    return _AchievementCategoryView(
      category: category,
      achievements: achievements,
      totalUnlocked: unlocked,
      totalAchievements: widget.achievements.length,
      totalExperience: totalExperience,
      openAchievement: _openAchievement,
      openRequirements: _openRequirements,
      locate: target == null || targetIndex < 0
          ? null
          : _LocateRequest(
              targetId: target.id,
              index: targetIndex,
              cardKey: _targetCardKey,
              scrollController: _scrollController,
              offsetSink: _gridTargetOffset,
            ),
    );
  }

  void _openProposal() {
    Navigator.of(
      context,
    ).push(m3PageRoute(builder: (_) => const AchievementProposalPage()));
  }

  Future<void> _openAchievement(
    BuildContext context,
    DashboardAchievement achievement,
  ) async {
    await Navigator.of(context).push(
      m3PageRoute(
        builder: (_) => AchievementUnlockTripsPage(
          achievementId: achievement.id,
          title: achievement.title,
        ),
      ),
    );
  }

  Future<void> _openRequirements(
    BuildContext context,
    DashboardAchievement achievement,
  ) async {
    await Navigator.of(context).push(
      m3PageRoute(
        builder: (_) => AchievementRequirementsPage(achievement: achievement),
      ),
    );
  }
}

/// 目标卡片在滚动视图里的绝对偏移。网格在**布局期**写入、页面在帧后读取。
///
/// 用普通字段而不是 `ValueNotifier`：布局期写它会通知监听者 `setState`，而布局中
/// 改状态是框架禁止的。
class _GridTargetOffset {
  /// 这个偏移是给哪个成就的。换了目标之后、新目标所在的那一页还没布局之前，字段里
  /// 留着的仍是上一张的偏移 —— 不比对目标 id 就会滚到上一个目标那里去。
  String? targetId;
  double? value;

  void set(String targetId, double value) {
    this.targetId = targetId;
    this.value = value;
  }

  /// 网格为 [targetId] 报出的偏移；存的若是别人的，就当没有。
  double? valueOf(String targetId) {
    final value = this.value;
    if (targetId != this.targetId || value == null || !value.isFinite) {
      return null;
    }
    return value;
  }
}

/// 页面交给某个分类视图的定位任务：把第 [index] 项滚进视野，并挂在 [cardKey] 上。
class _LocateRequest {
  const _LocateRequest({
    required this.targetId,
    required this.index,
    required this.cardKey,
    required this.scrollController,
    required this.offsetSink,
  });

  final String targetId;
  final int index;
  final GlobalKey cardKey;
  final ScrollController scrollController;
  final _GridTargetOffset offsetSink;
}

class _AchievementCategoryView extends StatelessWidget {
  const _AchievementCategoryView({
    required this.category,
    required this.achievements,
    required this.totalUnlocked,
    required this.totalAchievements,
    required this.totalExperience,
    required this.openAchievement,
    required this.openRequirements,
    this.locate,
  });

  final AchievementCategory category;
  final List<DashboardAchievement> achievements;
  final int totalUnlocked;
  final int totalAchievements;
  final int totalExperience;
  final Future<void> Function(BuildContext, DashboardAchievement)
  openAchievement;
  final Future<void> Function(BuildContext, DashboardAchievement)
  openRequirements;

  /// 非 null 时，本分类里有本次要定位并庆祝的那张卡片。
  final _LocateRequest? locate;

  @override
  Widget build(BuildContext context) {
    final unlocked = achievements.where((item) => item.isUnlocked).length;
    final total = achievements.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          < 600 => 1,
          < 960 => 2,
          _ => 3,
        };
        final horizontalPadding = constraints.maxWidth < 600 ? 16.0 : 24.0;
        return CustomScrollView(
          key: PageStorageKey(category.apiKey),
          controller: locate?.scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppLayout.dashboardMaxWidth,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14, bottom: 12),
                      child: _AchievementProgressSummary(
                        category: category,
                        categoryUnlocked: unlocked,
                        categoryTotal: total,
                        totalUnlocked: totalUnlocked,
                        totalAchievements: totalAchievements,
                        totalExperience: totalExperience,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                0,
                horizontalPadding,
                32,
              ),
              sliver: SliverLayoutBuilder(
                builder: (context, sliverConstraints) {
                  final width = mathMin(
                    sliverConstraints.crossAxisExtent,
                    1200,
                  );
                  final sideInset =
                      (sliverConstraints.crossAxisExtent - width) / 2;
                  final gridDelegate =
                      SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: 132,
                      );
                  final locate = this.locate;
                  final preceding = sliverConstraints.precedingScrollExtent;
                  if (locate != null && preceding.isFinite) {
                    // precedingScrollExtent 是表头（前面那些 sliver）已经吃掉的高度，
                    // geometry.scrollOffset 是目标行在网格内部的偏移，两者相加就是
                    // 它在整个滚动视图里的绝对位置。从 delegate 取而不是手算
                    // 「行号 ×（高度 + 间距）」：后者会把栏数、行高抄成第二份事实。
                    // 布局期只写一个普通字段，不当场 setState。
                    locate.offsetSink.set(
                      locate.targetId,
                      preceding +
                          gridDelegate
                              .getLayout(sliverConstraints)
                              .getGeometryForChildIndex(locate.index)
                              .scrollOffset,
                    );
                  }
                  return SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: sideInset),
                    sliver: SliverGrid(
                      gridDelegate: gridDelegate,
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final achievement = achievements[index];
                        final isTarget =
                            locate != null && locate.index == index;
                        return DashboardAchievementCard(
                          key: isTarget
                              ? locate.cardKey
                              : ValueKey(achievement.id),
                          justUnlocked: isTarget,
                          achievement: achievement,
                          // 有子项就先看子项（达成要求页右上角可进解锁行程）；
                          // 没有子项的已解锁成就才直接进解锁行程。
                          onTap: achievement.hasRequirements
                              ? () => openRequirements(context, achievement)
                              : achievement.unlockedBy != null
                              ? () => openAchievement(context, achievement)
                              : null,
                        );
                      }, childCount: achievements.length),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AchievementProgressSummary extends StatelessWidget {
  const _AchievementProgressSummary({
    required this.category,
    required this.categoryUnlocked,
    required this.categoryTotal,
    required this.totalUnlocked,
    required this.totalAchievements,
    required this.totalExperience,
  });

  final AchievementCategory category;
  final int categoryUnlocked;
  final int categoryTotal;
  final int totalUnlocked;
  final int totalAchievements;
  final int totalExperience;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final levelProgress = userLevelProgressForExperience(totalExperience);
    return AppCard.filled(
      color: colors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _AchievementProgressMetric(
                    icon: Icons.donut_large_outlined,
                    label: '总进度',
                    unlocked: totalUnlocked,
                    total: totalAchievements,
                    indicatorColor: colors.primary,
                    semanticsLabel: '全部成就解锁进度',
                  ),
                ),
                const VerticalDivider(width: 32),
                Expanded(
                  child: _AchievementProgressMetric(
                    icon: _categoryIcon(category),
                    label: category.label,
                    unlocked: categoryUnlocked,
                    total: categoryTotal,
                    indicatorColor: colors.tertiary,
                    semanticsLabel: '${category.label}解锁进度',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: colors.outlineVariant),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(
                Icons.workspace_premium_outlined,
                size: 18,
                color: colors.secondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(child: Text('累计成就经验')),
              Text(
                '$totalExperience XP',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              UserLevelBadge(experience: totalExperience),
              const Spacer(),
              Text(
                levelProgress.isMaxLevel
                    ? '已达最高等级'
                    : '升级还需 ${levelProgress.remainingExperience} XP',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(
            value: levelProgress.value,
            minHeight: 6,
            borderRadius: BorderRadius.circular(AppRadius.small),
            color: colors.secondary,
            backgroundColor: colors.secondary.withValues(alpha: 0.14),
            semanticsLabel: levelProgress.isMaxLevel
                ? '用户等级进度，已满级'
                : '用户等级进度，LV${levelProgress.level} 到 '
                      'LV${levelProgress.level + 1}',
          ),
        ],
      ),
    );
  }
}

class _AchievementProgressMetric extends StatelessWidget {
  const _AchievementProgressMetric({
    required this.icon,
    required this.label,
    required this.unlocked,
    required this.total,
    required this.indicatorColor,
    required this.semanticsLabel,
  });

  final IconData icon;
  final String label;
  final int unlocked;
  final int total;
  final Color indicatorColor;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : unlocked / total;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: indicatorColor),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '$unlocked / $total',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(progress * 100).round()}%',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          minHeight: 6,
          borderRadius: BorderRadius.circular(AppRadius.small),
          color: indicatorColor,
          backgroundColor: indicatorColor.withValues(alpha: 0.14),
          semanticsLabel: semanticsLabel,
        ),
      ],
    );
  }
}

IconData _categoryIcon(AchievementCategory category) => switch (category) {
  AchievementCategory.milestones => Icons.flag_outlined,
  AchievementCategory.extremeChallenges => Icons.bolt_outlined,
  AchievementCategory.railwayCatalog => Icons.train_outlined,
  AchievementCategory.touring => Icons.public_outlined,
  AchievementCategory.funJourneys => Icons.celebration_outlined,
};

class _AchievementPromptTrigger extends StatefulWidget {
  const _AchievementPromptTrigger({required this.unlockedCount});

  final int unlockedCount;

  @override
  State<_AchievementPromptTrigger> createState() =>
      _AchievementPromptTriggerState();
}

class _AchievementPromptTriggerState extends State<_AchievementPromptTrigger> {
  @override
  void initState() {
    super.initState();
    _schedulePrompt();
  }

  @override
  void didUpdateWidget(covariant _AchievementPromptTrigger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unlockedCount != widget.unlockedCount) _schedulePrompt();
  }

  void _schedulePrompt() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      maybeShowAchievementEngagementPrompt(context, widget.unlockedCount);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

double mathMin(double a, double b) => a < b ? a : b;

/// 解锁彩带：围绕刚解锁的那张卡片爆一次。
///
/// 只在被插进树时播放一次 —— 页面每定位到一张新卡片就换一个 key 重新挂载它，
/// 于是一次解锁多张时能一张接一张地各爆一次。
class _AchievementConfetti extends StatefulWidget {
  const _AchievementConfetti({super.key, required this.anchor});

  /// 发射点（主体 Stack 的局部坐标）。null 表示没能定位到卡片 —— 例如网格还没
  /// 报出目标偏移 —— 此时退回页面顶部中央。
  final Offset? anchor;

  @override
  State<_AchievementConfetti> createState() => _AchievementConfettiState();
}

class _AchievementConfettiState extends State<_AchievementConfetti> {
  /// 只决定「发射」的窗口长度；粒子离开发射窗口后由重力接管，飘完自行结束。
  static const _emissionWindow = Duration(milliseconds: 200);

  final ConfettiController _controller = ConfettiController(
    duration: _emissionWindow,
  );

  bool _pendingPlay = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_pendingPlay) return;
    _pendingPlay = false;
    // 减弱动效下整段跳过，与 M3Reveal / M3AnimatedSizeSwitcher 的处置一致。
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return;
    // 这里还在 ConfettiWidget 挂载之前，但那没关系：它在 initState 里给控制器挂了
    // 监听，而且自己的 post-frame 回调还会补查一次状态，两条路都能开始发射。
    _controller.play();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // ConfettiWidget 把发射点钉在自己盒子的左上角，所以用一个 1×1 的盒子来锚定位置。
    final emitter = SizedBox.square(
      dimension: 1,
      child: ConfettiWidget(
        confettiController: _controller,
        blastDirectionality: BlastDirectionality.explosive,
        emissionFrequency: 1,
        numberOfParticles: 10,
        gravity: 0.2,
        minimumSize: const Size(8, 4),
        maximumSize: const Size(14, 8),
        shouldLoop: false,
        colors: [colors.primary, colors.secondary, colors.tertiary],
      ),
    );
    final anchor = widget.anchor;
    return Positioned.fill(
      // 彩带永远不该挡住卡片。confetti 走的是 foregroundPainter，当前其实不吃点击，
      // 这一层是保证。
      child: IgnorePointer(
        child: Stack(
          children: [
            if (anchor == null)
              Align(alignment: const Alignment(0, -0.6), child: emitter)
            else
              Positioned(left: anchor.dx, top: anchor.dy, child: emitter),
          ],
        ),
      ),
    );
  }
}
