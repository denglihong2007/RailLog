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
    return Scaffold(
      appBar: AppBar(title: const Text('成就')),
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = switch (constraints.maxWidth) {
                < 600 => 1,
                < 960 => 2,
                _ => 3,
              };
              final horizontalPadding = constraints.maxWidth < 600
                  ? 16.0
                  : 24.0;
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            16,
                            horizontalPadding,
                            20,
                          ),
                          child: Row(
                            children: [
                              Text(
                                '已解锁 $unlocked',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                ' / ${achievements.length}',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
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
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  mainAxisExtent: 120,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final achievement = achievements[index];
                              return M3Reveal(
                                duration: Duration(
                                  milliseconds: 220 + (index.clamp(0, 8) * 35),
                                ),
                                distance: 6,
                                child: DashboardAchievementCard(
                                  achievement: achievement,
                                  onTap: achievement.unlockedBy == null
                                      ? null
                                      : () => _openAchievement(
                                          context,
                                          achievement.unlockedBy!,
                                        ),
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
          ),
          _AchievementPromptTrigger(unlockedCount: unlocked),
        ],
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
