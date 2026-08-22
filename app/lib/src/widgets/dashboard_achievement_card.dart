import 'package:flutter/material.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';

class DashboardAchievementCard extends StatelessWidget {
  const DashboardAchievementCard({
    super.key,
    required this.achievement,
    this.onTap,
  });

  final DashboardAchievement achievement;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final unlocked = achievement.isUnlocked;
    final entry = achievement.unlockedBy;
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                dashboardAchievementIconKey(achievement.iconKey),
                color: unlocked ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  achievement.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(
                unlocked ? Icons.verified_outlined : Icons.lock_outline,
                size: 20,
                color: unlocked ? colors.primary : colors.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            achievement.requirement,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: Text(
                  !unlocked
                      ? achievement.hasProgress
                            ? '尚未解锁 · ${_formatProgress(achievement.progressCurrent!)}/${_formatProgress(achievement.progressTarget!)}'
                            : '尚未解锁'
                      : entry == null
                      ? '已解锁'
                      : '${_formatDate(entry.departureTime)} 乘坐 ${_trainLabel(entry.trainNumber)} 解锁',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: unlocked ? colors.primary : colors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${achievement.unlockedUserCount} 位用户 · '
                '${_formatPercentage(achievement.unlockedPercentage)}',
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final cardContent = Stack(
      fit: StackFit.expand,
      children: [
        content,
        if (!unlocked && achievement.hasProgress)
          Align(
            alignment: Alignment.bottomCenter,
            child: Semantics(
              label: '${achievement.title}进度',
              value:
                  '${_formatProgress(achievement.progressCurrent!)}/${_formatProgress(achievement.progressTarget!)}',
              child: LinearProgressIndicator(
                value: achievement.progressValue,
                minHeight: 4,
              ),
            ),
          ),
      ],
    );
    return Card.filled(
      margin: EdgeInsets.zero,
      color: unlocked ? colors.tertiaryContainer : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? cardContent
          : Semantics(
              button: true,
              child: InkWell(onTap: onTap, child: cardContent),
            ),
    );
  }
}

IconData dashboardAchievementIconKey(String key) => switch (key) {
  'restaurant_outlined' => Icons.restaurant_outlined,
  'airline_seat_recline_extra_outlined' =>
    Icons.airline_seat_recline_extra_outlined,
  'transfer_within_a_station' => Icons.transfer_within_a_station,
  'schedule_outlined' => Icons.schedule_outlined,
  'local_fire_department' => Icons.local_fire_department,
  'calendar_month_outlined' => Icons.calendar_month_outlined,
  'looks_one_outlined' => Icons.looks_one_outlined,
  'looks_two_outlined' => Icons.looks_two_outlined,
  'looks_3_outlined' => Icons.looks_3_outlined,
  'palette_outlined' => Icons.palette_outlined,
  'train_outlined' => Icons.train_outlined,
  'checklist_outlined' => Icons.checklist_outlined,
  'accessibility_new' => Icons.accessibility_new,
  'collections_bookmark_outlined' => Icons.collections_bookmark_outlined,
  'nightlight_outlined' => Icons.nightlight_outlined,
  'airline_seat_recline_normal' => Icons.airline_seat_recline_normal,
  'location_on_outlined' => Icons.location_on_outlined,
  'route_outlined' => Icons.route_outlined,
  'connecting_airports_outlined' => Icons.connecting_airports_outlined,
  'directions_boat_outlined' => Icons.directions_boat_outlined,
  'engineering_outlined' => Icons.engineering_outlined,
  'visibility_off_outlined' => Icons.visibility_off_outlined,
  'psychology_outlined' => Icons.psychology_outlined,
  'people_outline' => Icons.people_outline,
  'swap_vert' => Icons.swap_vert,
  'swap_horiz' => Icons.swap_horiz,
  'speed_outlined' => Icons.speed_outlined,
  'slow_motion_video_outlined' => Icons.slow_motion_video_outlined,
  'directions_bike_outlined' => Icons.directions_bike_outlined,
  'flash_on_outlined' => Icons.flash_on_outlined,
  'language_outlined' => Icons.language_outlined,
  'map_outlined' => Icons.map_outlined,
  'gps_fixed_outlined' => Icons.gps_fixed_outlined,
  'u_turn_left_outlined' => Icons.u_turn_left_outlined,
  'device_thermostat_outlined' => Icons.device_thermostat_outlined,
  'bolt_outlined' => Icons.bolt_outlined,
  'flag_outlined' => Icons.flag_outlined,
  'wb_sunny_outlined' => Icons.wb_sunny_outlined,
  'vertical_align_bottom_outlined' => Icons.vertical_align_bottom_outlined,
  'history_edu_outlined' => Icons.history_edu_outlined,
  'alt_route_outlined' => Icons.alt_route_outlined,
  'thunderstorm_outlined' => Icons.thunderstorm_outlined,
  'pin_outlined' => Icons.pin_outlined,
  'bedtime_outlined' => Icons.bedtime_outlined,
  'multiple_stop_outlined' => Icons.multiple_stop_outlined,
  'landscape_outlined' => Icons.landscape_outlined,
  'explore_outlined' => Icons.explore_outlined,
  'loop' => Icons.loop,
  'auto_awesome_outlined' => Icons.auto_awesome_outlined,
  'work_outline' => Icons.work_outline,
  'emoji_events_outlined' => Icons.emoji_events_outlined,
  'celebration_outlined' => Icons.celebration_outlined,
  'redeem_outlined' => Icons.redeem_outlined,
  'luggage_outlined' => Icons.luggage_outlined,
  'directions_walk_outlined' => Icons.directions_walk_outlined,
  'account_balance_outlined' => Icons.account_balance_outlined,
  'ac_unit_outlined' => Icons.ac_unit_outlined,
  'filter_3_outlined' => Icons.filter_3_outlined,
  'water_drop_outlined' => Icons.water_drop_outlined,
  'public_outlined' => Icons.public_outlined,
  'precision_manufacturing_outlined' => Icons.precision_manufacturing_outlined,
  'directions_railway_outlined' => Icons.directions_railway_outlined,
  'format_list_numbered_outlined' => Icons.format_list_numbered_outlined,
  'favorite_outline' => Icons.favorite_outline,
  'visibility_outlined' => Icons.visibility_outlined,
  'currency_yen' => Icons.currency_yen,
  'timer_outlined' => Icons.timer_outlined,
  _ => Icons.emoji_events_outlined,
};

String _trainLabel(String value) {
  final train = value.trim();
  return train.isEmpty ? '未填写车次' : train;
}

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _formatPercentage(double value) {
  final rounded = value.roundToDouble();
  return value == rounded
      ? '${rounded.toInt()}%'
      : '${value.toStringAsFixed(1)}%';
}

String _formatProgress(double value) {
  final rounded = value.roundToDouble();
  return value == rounded
      ? rounded.toInt().toString()
      : value.toStringAsFixed(1);
}
