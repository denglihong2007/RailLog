import 'package:material_ui/material_ui.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/pages/achievement_unlock_trips_page.dart';
import 'package:raillog/src/pages/home_page.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/dashboard_achievement_card.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

class AchievementRequirementsPage extends StatelessWidget {
  const AchievementRequirementsPage({
    super.key,
    required this.achievement,
    this.ownerName,
    this.ownerUserId,
  });

  final DashboardAchievement achievement;

  /// 看别人的进度时传昵称，标题里标明这是 TA 的页面。
  final String? ownerName;

  /// 看别人的进度时一并传 userId，行程详情里才能跳回 TA 的主页。
  final String? ownerUserId;

  @override
  Widget build(BuildContext context) {
    final requirements = [
      ...achievement.requirements.where((requirement) => requirement.completed),
      ...achievement.requirements.where(
        (requirement) => !requirement.completed,
      ),
    ];
    final ownerName = this.ownerName;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          ownerName == null
              ? '${achievement.title} · 达成要求'
              : '$ownerName 的成就进度',
        ),
        actions: [
          // 从解锁行程排行榜点进来的页面，排行榜就在下一层，不再重复放入口。
          if (achievement.isUnlocked && ownerName == null)
            IconButton(
              tooltip: '查看解锁行程',
              onPressed: () => Navigator.of(context).push(
                m3PageRoute(
                  builder: (_) =>
                      AchievementUnlockTripsPage(achievement: achievement),
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
                  ownerUserId: ownerUserId,
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
  const AchievementRequirementRow({
    super.key,
    required this.requirement,
    this.ownerUserId,
  });

  final DashboardAchievementRequirement requirement;

  /// 非空表示这些行程属于该用户（看别人的进度），详情页需要能跳回 TA 的主页。
  final String? ownerUserId;

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
        onTap: trip == null ? null : () => _openTrip(context, trip),
      ),
    );
  }

  /// 自己的达成要求优先走本地可编辑详情；别人的只读，并把作者卡片接到 TA 的主页。
  Future<void> _openTrip(
    BuildContext context,
    AchievementRequirementTrip trip,
  ) async {
    final navigator = Navigator.of(context);
    final ownerUserId = this.ownerUserId;
    if (ownerUserId == null) {
      final local = await DbHelper.instance.getTripByTicketId(trip.ticketId);
      if (local != null) {
        navigator.push(
          m3PageRoute(builder: (_) => TripRecordDetailsPage(tripId: local.id)),
        );
        return;
      }
    }
    navigator.push(
      m3PageRoute(
        builder: (_) => TripRecordDetailsPage.public(
          ticketId: trip.ticketId,
          onOwnerTap: ownerUserId == null
              ? null
              : () => navigator.push(
                  m3PageRoute(
                    builder: (_) => PublicUserPage(userId: ownerUserId),
                  ),
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
