import 'package:flutter/material.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/pages/achievement_unlock_trips_page.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/dashboard_achievement_card.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

class AchievementRequirementsPage extends StatelessWidget {
  const AchievementRequirementsPage({super.key, required this.achievement});

  final DashboardAchievement achievement;

  @override
  Widget build(BuildContext context) {
    final requirements = [
      ...achievement.requirements.where((requirement) => requirement.completed),
      ...achievement.requirements.where(
        (requirement) => !requirement.completed,
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('${achievement.title} · 达成要求'),
        actions: [
          if (achievement.isUnlocked)
            IconButton(
              tooltip: '查看解锁行程',
              onPressed: () => Navigator.of(context).push(
                m3PageRoute(
                  builder: (_) => AchievementUnlockTripsPage(
                    achievementId: achievement.id,
                    title: achievement.title,
                  ),
                ),
              ),
              icon: const Icon(Icons.people_outline),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.contentMaxWidth,
          ),
          child: ListView.builder(
            padding: AppSpacing.page,
            itemCount: requirements.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: _RequirementsHeader(achievement: achievement),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AchievementRequirementRow(
                  requirement: requirements[index - 1],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RequirementsHeader extends StatelessWidget {
  const _RequirementsHeader({required this.achievement});

  final DashboardAchievement achievement;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final completed = achievement.completedRequirementCount;
    final total = achievement.requirements.length;
    final progress = total == 0 ? 0.0 : completed / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: achievement.isUnlocked
                    ? colors.tertiaryContainer
                    : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Icon(
                dashboardAchievementIconKey(achievement.iconKey),
                color: achievement.isUnlocked
                    ? colors.onTertiaryContainer
                    : colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    achievement.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    achievement.requirement,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: Text(
                '已完成 $completed / $total',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${(progress * 100).round()}%',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        LinearProgressIndicator(
          value: progress,
          minHeight: 8,
          borderRadius: BorderRadius.circular(AppRadius.small),
          color: colors.primary,
          backgroundColor: colors.primary.withValues(alpha: 0.14),
          semanticsLabel: '${achievement.title}达成要求进度',
        ),
      ],
    );
  }
}

class AchievementRequirementRow extends StatelessWidget {
  const AchievementRequirementRow({super.key, required this.requirement});

  final DashboardAchievementRequirement requirement;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final trip = requirement.trip;
    return AppCard.filled(
      color: requirement.completed
          ? colors.primaryContainer.withValues(alpha: 0.42)
          : colors.surfaceContainerLow,
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: Icon(
          requirement.completed
              ? Icons.check_circle
              : Icons.radio_button_unchecked,
          color: requirement.completed
              ? colors.primary
              : colors.onSurfaceVariant,
        ),
        title: Text(
          requirement.label,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          trip == null
              ? requirement.completed
                    ? '已完成'
                    : '尚未完成'
              : '${_date(trip.occurredAt)} · ${_trainLabel(trip.trainNumber)}'
                    ' · ${trip.fromStation} → ${trip.toStation}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: trip == null ? null : const Icon(Icons.chevron_right),
        onTap: trip == null
            ? null
            : () => Navigator.of(context).push(
                m3PageRoute(
                  builder: (_) =>
                      TripRecordDetailsPage.public(ticketId: trip.ticketId),
                ),
              ),
      ),
    );
  }
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _trainLabel(String value) {
  final trainNumber = value.trim();
  return trainNumber.isEmpty ? '未填写车次' : trainNumber;
}
