import 'package:flutter/material.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/pages/all_trips_page.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/widgets/dashboard_achievement_card.dart';
import 'package:raillog/src/widgets/engagement_prompt.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

class AchievementsPage extends StatelessWidget {
  const AchievementsPage({
    super.key,
    required this.achievements,
    this.openTrip,
  });

  final List<DashboardAchievement> achievements;
  final TripEntryOpener? openTrip;

  @override
  Widget build(BuildContext context) {
    final unlocked = achievements.where((item) => item.isUnlocked).length;
    return DefaultTabController(
      length: AchievementCategory.values.length,
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
          children: [
            TabBarView(
              children: [
                for (final category in AchievementCategory.values)
                  _AchievementCategoryView(
                    category: category,
                    achievements: achievements
                        .where((item) => item.category == category)
                        .toList(growable: false),
                    totalUnlocked: unlocked,
                    totalAchievements: achievements.length,
                    openAchievement: _openAchievement,
                  ),
              ],
            ),
            _AchievementPromptTrigger(unlockedCount: unlocked),
          ],
        ),
      ),
    );
  }

  Future<void> _openAchievement(
    BuildContext context,
    DashboardTripEntry trip,
  ) async {
    final changed = openTrip == null
        ? await Navigator.of(context).push<bool>(
            m3PageRoute(builder: (_) => TripRecordDetailsPage(tripId: trip.id)),
          )
        : await openTrip!(context, trip);
    if (changed == true && context.mounted) Navigator.of(context).pop(true);
  }
}

class _AchievementCategoryView extends StatelessWidget {
  const _AchievementCategoryView({
    required this.category,
    required this.achievements,
    required this.totalUnlocked,
    required this.totalAchievements,
    required this.openAchievement,
  });

  final AchievementCategory category;
  final List<DashboardAchievement> achievements;
  final int totalUnlocked;
  final int totalAchievements;
  final Future<void> Function(BuildContext, DashboardTripEntry) openAchievement;

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
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14, bottom: 12),
                      child: _AchievementProgressSummary(
                        category: category,
                        categoryUnlocked: unlocked,
                        categoryTotal: total,
                        totalUnlocked: totalUnlocked,
                        totalAchievements: totalAchievements,
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
                  return SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: sideInset),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: 120,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final achievement = achievements[index];
                        return DashboardAchievementCard(
                          achievement: achievement,
                          onTap: achievement.unlockedBy == null
                              ? null
                              : () => openAchievement(
                                  context,
                                  achievement.unlockedBy!,
                                ),
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
  });

  final AchievementCategory category;
  final int categoryUnlocked;
  final int categoryTotal;
  final int totalUnlocked;
  final int totalAchievements;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: IntrinsicHeight(
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
            const SizedBox(width: 6),
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const SizedBox(height: 10),
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
          borderRadius: BorderRadius.circular(6),
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
