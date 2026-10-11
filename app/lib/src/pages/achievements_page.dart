import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
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

class _AchievementsPageState extends State<AchievementsPage> {
  /// 页面主体的 Stack，用来把卡片的全局坐标换算成发射点的局部坐标。
  final GlobalKey _bodyKey = GlobalKey();

  /// 挂在被定位的那张卡片上。网格是懒加载的，只有它被真正构建出来之后才拿得到坐标。
  final GlobalKey _targetCardKey = GlobalKey();

  final ScrollController _scrollController = ScrollController();

  /// 网格在布局期算出的目标偏移，见 [_GridTargetOffset]。
  final _GridTargetOffset _gridTargetOffset = _GridTargetOffset();

  /// 本次进入页面要定位并庆祝的成就；null 表示本次没有。
  DashboardAchievement? _target;

  /// 彩带的发射点（主体 Stack 的局部坐标）。null 表示没能定位到卡片，走兜底位置。
  Offset? _celebrationAnchor;

  /// 彩带要不要上场。定位是异步的（等布局、等滚动落位），所以单独占一个状态。
  bool _celebrating = false;

  @override
  void initState() {
    super.initState();
    final notifier = AchievementUnlockNotifier.instance;
    final pending = notifier.pending;
    if (pending.isEmpty) return;
    // 取走就不再放回：离开成就页再进来不该重放一次。
    notifier.clearPending();
    final pendingIds = {for (final item in pending) item.id};
    // 一次解锁多个时只处理列表里最靠前的那一个，不排队逐个播。
    for (final achievement in widget.achievements) {
      if (pendingIds.contains(achievement.id)) {
        _target = achievement;
        break;
      }
    }
    if (_target == null) return;
    // 目标在滚动视图里的位置要等这一帧布局完才知道，所以定位推迟到帧后。
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateTarget());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 把目标卡片滚进视野，然后在它身上放彩带。
  Future<void> _locateTarget() async {
    if (!mounted) return;
    final targetOffset = _gridTargetOffset.value;
    if (targetOffset != null &&
        targetOffset.isFinite &&
        _scrollController.hasClients) {
      final position = _scrollController.position;
      // 让卡片落在视口偏上的位置：彩带要向上炸开才有空间。
      final destination = (targetOffset - position.viewportDimension * 0.3)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (destination > position.pixels + 1) {
        await _scrollController.animateTo(
          destination,
          duration: m3MotionDuration,
          curve: Easing.emphasizedDecelerate,
        );
        if (!mounted) return;
      }
    }
    // 再等一帧：卡片的 render box 要等滚动落位、它被网格真正构建出来之后才拿得到。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _celebrationAnchor = _targetCardCenter();
        _celebrating = true;
      });
    });
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
    return DefaultTabController(
      length: AchievementCategory.values.length,
      // 直接开在目标分类上。TabBarView 只构建当前页，先开在默认页再切过去的话，
      // 既多一次换页动画，目标页也要晚一帧才布局。
      initialIndex: target == null
          ? 0
          : AchievementCategory.values.indexOf(target.category),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('成就'),
          scrolledUnderElevation: 3,
          bottom: TabBar(
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
            if (_celebrating) _AchievementConfetti(anchor: _celebrationAnchor),
          ],
        ),
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
      locate: targetIndex < 0
          ? null
          : _LocateRequest(
              index: targetIndex,
              cardKey: _targetCardKey,
              scrollController: _scrollController,
              offsetSink: _gridTargetOffset,
            ),
    );
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
  double? value;
}

/// 页面交给某个分类视图的定位任务：把第 [index] 项滚进视野，并挂在 [cardKey] 上。
class _LocateRequest {
  const _LocateRequest({
    required this.index,
    required this.cardKey,
    required this.scrollController,
    required this.offsetSink,
  });

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
                        mainAxisExtent: 120,
                      );
                  final locate = this.locate;
                  final preceding = sliverConstraints.precedingScrollExtent;
                  if (locate != null && preceding.isFinite) {
                    // precedingScrollExtent 是表头（前面那些 sliver）已经吃掉的高度，
                    // geometry.scrollOffset 是目标行在网格内部的偏移，两者相加就是
                    // 它在整个滚动视图里的绝对位置。从 delegate 取而不是手算
                    // 「行号 ×（高度 + 间距）」：后者会把栏数、行高抄成第二份事实。
                    // 布局期只写一个普通字段，不当场 setState。
                    locate.offsetSink.value =
                        preceding +
                        gridDelegate
                            .getLayout(sliverConstraints)
                            .getGeometryForChildIndex(locate.index)
                            .scrollOffset;
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
                          onTap: achievement.unlockedBy == null
                              ? null
                              : () => openAchievement(context, achievement),
                          onRequirementsTap: achievement.hasRequirements
                              ? () => openRequirements(context, achievement)
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

/// 解锁彩带：进入成就页时，若本次会话里有刚解锁的成就，页面会先滚动定位到那张
/// 卡片，然后在这里围绕它爆一次。
///
/// 只在被插进树时播放一次 —— 页面只在定位成功后才构建它。
class _AchievementConfetti extends StatefulWidget {
  const _AchievementConfetti({required this.anchor});

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
