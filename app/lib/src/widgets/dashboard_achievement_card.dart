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
    final hasNarrative =
        unlocked && (achievement.narrativeNote?.trim().isNotEmpty ?? false);
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (achievement.experience > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: unlocked
                        ? colors.primaryContainer
                        : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${achievement.experience} XP',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: unlocked
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (achievement.note?.trim().isNotEmpty ?? false) ...[
                const SizedBox(width: 6),
                Semantics(
                  label: '注释：${achievement.note!.trim()}',
                  child: Tooltip(
                    message: achievement.note!.trim(),
                    triggerMode: TooltipTriggerMode.tap,
                    child: Icon(
                      Icons.info_outline,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
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
            maxLines: hasNarrative ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (hasNarrative) ...[
            const SizedBox(height: 4),
            Tooltip(
              message: achievement.narrativeNote!.trim(),
              triggerMode: TooltipTriggerMode.tap,
              child: Text(
                achievement.narrativeNote!.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
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
              if (achievement.hidden)
                Text(
                  '隐藏成就',
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
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
  'help_outline' => Icons.help_outline,
  'account_balance_wallet_outlined' => Icons.account_balance_wallet_outlined,
  'rate_review_outlined' => Icons.rate_review_outlined,
  'calendar_view_day_outlined' => Icons.calendar_view_day_outlined,
  'pin_drop_outlined' => Icons.pin_drop_outlined,
  'severe_cold_outlined' => Icons.severe_cold_outlined,
  'water_outlined' => Icons.water_outlined,
  'architecture_outlined' => Icons.architecture_outlined,
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
  'military_tech_outlined' => Icons.military_tech_outlined,
  'workspace_premium_outlined' => Icons.workspace_premium_outlined,
  'handshake_outlined' => Icons.handshake_outlined,
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
  'abc_outlined' => Icons.abc_outlined,
  'add_road_outlined' => Icons.add_road_outlined,
  'airline_seat_flat_angled_outlined' =>
    Icons.airline_seat_flat_angled_outlined,
  'airline_seat_individual_suite_outlined' =>
    Icons.airline_seat_individual_suite_outlined,
  'assistant_navigation' => Icons.assistant_navigation,
  'auto_stories_outlined' => Icons.auto_stories_outlined,
  'beach_access_outlined' => Icons.beach_access_outlined,
  'call_split_outlined' => Icons.call_split_outlined,
  'campaign_outlined' => Icons.campaign_outlined,
  'confirmation_number_outlined' => Icons.confirmation_number_outlined,
  'departure_board_outlined' => Icons.departure_board_outlined,
  'diamond_outlined' => Icons.diamond_outlined,
  'downhill_skiing_outlined' => Icons.downhill_skiing_outlined,
  'electric_bolt_outlined' => Icons.electric_bolt_outlined,
  'favorite' => Icons.favorite,
  'filter_hdr_outlined' => Icons.filter_hdr_outlined,
  'fitness_center_outlined' => Icons.fitness_center_outlined,
  'flag_circle_outlined' => Icons.flag_circle_outlined,
  'forest_outlined' => Icons.forest_outlined,
  'forum_outlined' => Icons.forum_outlined,
  'foundation_outlined' => Icons.foundation_outlined,
  'groups_outlined' => Icons.groups_outlined,
  'handyman_outlined' => Icons.handyman_outlined,
  'history_outlined' => Icons.history_outlined,
  'hotel_outlined' => Icons.hotel_outlined,
  'hourglass_bottom_outlined' => Icons.hourglass_bottom_outlined,
  'hub_outlined' => Icons.hub_outlined,
  'king_bed_outlined' => Icons.king_bed_outlined,
  'leaderboard_outlined' => Icons.leaderboard_outlined,
  'linear_scale_outlined' => Icons.linear_scale_outlined,
  'list_alt_outlined' => Icons.list_alt_outlined,
  'local_fire_department_outlined' => Icons.local_fire_department_outlined,
  'local_florist_outlined' => Icons.local_florist_outlined,
  'location_city_outlined' => Icons.location_city_outlined,
  'movie_outlined' => Icons.movie_outlined,
  'navigation_outlined' => Icons.navigation_outlined,
  'near_me_outlined' => Icons.near_me_outlined,
  'outbound_outlined' => Icons.outbound_outlined,
  'payments_outlined' => Icons.payments_outlined,
  'pie_chart_outline' => Icons.pie_chart_outline,
  'repeat_outlined' => Icons.repeat_outlined,
  'replay_outlined' => Icons.replay_outlined,
  'rocket_launch_outlined' => Icons.rocket_launch_outlined,
  'savings_outlined' => Icons.savings_outlined,
  'science_outlined' => Icons.science_outlined,
  'signpost_outlined' => Icons.signpost_outlined,
  'sort_by_alpha_outlined' => Icons.sort_by_alpha_outlined,
  'sports_score_outlined' => Icons.sports_score_outlined,
  'stairs_outlined' => Icons.stairs_outlined,
  'stars_outlined' => Icons.stars_outlined,
  'straighten_outlined' => Icons.straighten_outlined,
  'terrain_outlined' => Icons.terrain_outlined,
  'tour_outlined' => Icons.tour_outlined,
  'travel_explore_outlined' => Icons.travel_explore_outlined,
  'trending_up_outlined' => Icons.trending_up_outlined,
  'trip_origin' => Icons.trip_origin,
  'view_day_outlined' => Icons.view_day_outlined,
  'waves_outlined' => Icons.waves_outlined,
  'wb_twilight_outlined' => Icons.wb_twilight_outlined,
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
