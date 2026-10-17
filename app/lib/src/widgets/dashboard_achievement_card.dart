import 'package:flutter/material.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

class DashboardAchievementCard extends StatelessWidget {
  const DashboardAchievementCard({
    super.key,
    required this.achievement,
    this.onTap,
    this.justUnlocked = false,
  });

  final DashboardAchievement achievement;

  /// 整卡只有一个点击目标：有明细的先进达成要求，其余已解锁的进解锁行程。
  final VoidCallback? onTap;

  /// 本次会话里刚解锁的那一张。它挂载时会把底色从默认色补间到解锁色，
  /// 作为成就页「定位到该成就」的那一下强调；别处不传。
  final bool justUnlocked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;
    final unlocked = achievement.isUnlocked;
    final narrative = achievement.narrativeNote?.trim();
    final hasNarrative = unlocked && (narrative?.isNotEmpty ?? false);
    final note = achievement.note?.trim();
    final hasNote = note?.isNotEmpty ?? false;
    final secondaryColor = unlocked
        ? colors.onTertiaryContainer.withValues(alpha: 0.76)
        : colors.onSurfaceVariant;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 圆形徽章把「成就」这一身份和进度合在一起：外圈就是进度环，
              // 解锁后环走满并挂上对勾，不再额外占一条横向进度条。
              _AchievementMedallion(
                icon: dashboardAchievementIconKey(achievement.iconKey),
                unlocked: unlocked,
                progress: achievement.hasProgress
                    ? achievement.progressValue
                    : null,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            achievement.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (hasNote) ...[
                          const SizedBox(width: AppSpacing.xs),
                          _AchievementNoteIcon(
                            note: note!,
                            color: secondaryColor,
                          ),
                        ],
                        if (achievement.experience > 0) ...[
                          const SizedBox(width: AppSpacing.sm),
                          _AchievementExperienceChip(
                            experience: achievement.experience,
                            unlocked: unlocked,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // 达成条件始终可见，解锁与否都回答「这条成就要求什么」。
                    Text(
                      achievement.requirement,
                      maxLines: hasNarrative ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: secondaryColor,
                      ),
                    ),
                    if (hasNarrative) ...[
                      const SizedBox(height: 2),
                      // 解锁后多出的那一行才是「奖励」：叙述性说明。
                      Text(
                        narrative!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: secondaryColor,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        _AchievementFooter(
          achievement: achievement,
          secondaryColor: secondaryColor,
          tappable: onTap != null,
        ),
      ],
    );
    // 未解锁时不能沿用原来的 `null`（交给 AppCard 取默认色）：TweenAnimationBuilder
    // 断言 tween.end 非空，null 会在构建期抛异常，而卡片是在 SliverGrid 的
    // layout 回调里构建的 —— 异常会中断整个网格的布局，页面上几乎全是未解锁卡片，
    // 于是每帧重试、每帧再抛，界面直接卡死。这里显式取 AppCard.filled 的默认色
    // （见 app_card.dart 的 `color ?? colors.surfaceContainerLow`）。
    final fill = unlocked
        ? colors.tertiaryContainer
        : colors.surfaceContainerLow;
    // 刚解锁的那张从默认色起步，于是在挂载时亮一次；其余卡片 begin 与 end 取同一个
    // 值，冷启动与列表重排都不会播放动画。TweenAnimationBuilder 只在 begin != end 时
    // 于挂载时补间，之后也只在 tween.end 变化时才补间 —— 两种情况互不干扰，所以
    // 「锁定 -> 解锁」那一次的补间不受影响。
    final from = justUnlocked ? colors.surfaceContainerLow : fill;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(begin: from, end: fill),
      duration: m3MotionDurationShort,
      curve: Easing.standardDecelerate,
      builder: (context, color, _) => AppCard.filled(
        padding: EdgeInsets.zero,
        color: color,
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// 左侧圆形徽章：图标坐在内圆里，外圈是进度环。
///
/// 进度环是这张卡片唯一的「图形化进度」，所以底部那条状态行不必再画一遍进度条；
/// 未解锁且没有进度数据时环是空的，也仍然比一个锁角标更像一枚成就徽章。
class _AchievementMedallion extends StatelessWidget {
  const _AchievementMedallion({
    required this.icon,
    required this.unlocked,
    required this.progress,
  });

  final IconData icon;
  final bool unlocked;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final value = unlocked ? 1.0 : (progress?.clamp(0.0, 1.0) ?? 0.0);
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: 3,
              strokeCap: StrokeCap.round,
              color: colors.primary,
              backgroundColor: colors.primary.withValues(alpha: 0.14),
              semanticsLabel: '成就进度',
              semanticsValue: '${(value * 100).round()}%',
            ),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: unlocked
                  ? colors.surface.withValues(alpha: 0.6)
                  : colors.surfaceContainerHighest,
            ),
            child: Icon(
              icon,
              size: 20,
              color: unlocked
                  ? colors.onTertiaryContainer
                  : colors.onSurfaceVariant,
            ),
          ),
          if (unlocked)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                  // 与卡片的解锁底色隔开，徽章压在进度环上也不会糊成一团。
                  border: Border.all(color: colors.tertiaryContainer, width: 2),
                ),
                child: Icon(Icons.check, size: 9, color: colors.onPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

/// 经验值做成一个小胶囊：它是卡片里唯一带「奖励」意味的数字，值得有自己的形状。
class _AchievementExperienceChip extends StatelessWidget {
  const _AchievementExperienceChip({
    required this.experience,
    required this.unlocked,
  });

  final int experience;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: unlocked
            ? colors.surface.withValues(alpha: 0.55)
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        '$experience XP',
        style: theme.textTheme.labelSmall?.copyWith(
          color: unlocked ? colors.onTertiaryContainer : colors.secondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 技术性说明（如席别清单、时段范围）只在存在时出现，点一下看全文。
class _AchievementNoteIcon extends StatelessWidget {
  const _AchievementNoteIcon({required this.note, required this.color});

  final String note;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '技术说明：$note',
      child: Tooltip(
        message: note,
        triggerMode: TooltipTriggerMode.tap,
        child: Icon(Icons.info_outline, size: 15, color: color),
      ),
    );
  }
}

/// 卡片底部的整条信息带：用一层比卡片略亮的底色把它和正文分开。
///
/// 只留一行「状态 + 稀有度」，右侧一个箭头表示整卡可点；达成要求入口并进了整卡
/// 点击，不再单独放一颗按钮 —— 这正是之前最显乱的一处。
class _AchievementFooter extends StatelessWidget {
  const _AchievementFooter({
    required this.achievement,
    required this.secondaryColor,
    required this.tappable,
  });

  final DashboardAchievement achievement;
  final Color secondaryColor;
  final bool tappable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final unlocked = achievement.isUnlocked;
    final entry = achievement.unlockedBy;
    final foreground = unlocked
        ? colors.onTertiaryContainer.withValues(alpha: 0.86)
        : secondaryColor;

    final String status;
    if (!unlocked && achievement.hasProgress) {
      status =
          '已达成 ${_formatProgress(achievement.progressCurrent!)}/'
          '${_formatProgress(achievement.progressTarget!)}';
    } else if (unlocked) {
      status = entry == null
          ? '已解锁'
          : '${_formatDate(entry.departureTime)} · '
                '${_trainLabel(entry.trainNumber)} 解锁';
    } else {
      status = '尚未解锁';
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      color: colors.surface.withValues(alpha: 0.5),
      padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (achievement.hidden) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              '隐藏成就',
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                color: secondaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else if (achievement.totalUserCount > 0) ...[
            const SizedBox(width: AppSpacing.sm),
            _AchievementRarity(
              unlockedUserCount: achievement.unlockedUserCount,
              percentage: achievement.unlockedPercentage,
              color: secondaryColor,
            ),
          ],
          if (tappable) ...[
            const SizedBox(width: AppSpacing.xxs),
            Icon(Icons.chevron_right, size: 16, color: secondaryColor),
          ],
        ],
      ),
    );
  }
}

class _AchievementRarity extends StatelessWidget {
  const _AchievementRarity({
    required this.unlockedUserCount,
    required this.percentage,
    required this.color,
  });

  final int unlockedUserCount;
  final double percentage;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // _formatPercentage 已经带 %，别再拼一个。
    final label = _formatPercentage(percentage);
    return Tooltip(
      message: '$unlockedUserCount 位用户已解锁',
      child: Semantics(
        label: '$unlockedUserCount 位用户已解锁，占 $label',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 13, color: color),
            const SizedBox(width: 2),
            Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
  'sailing_outlined' => Icons.sailing_outlined,
  'mode_fan_off' => Icons.mode_fan_off,
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
  'anchor' => Icons.anchor,
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
  'heart_broken_outlined' => Icons.heart_broken_outlined,
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
  'menu_book_outlined' => Icons.menu_book_outlined,
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
  'tsunami' => Icons.tsunami,
  'view_day_outlined' => Icons.view_day_outlined,
  'waves_outlined' => Icons.waves_outlined,
  'wb_twilight_outlined' => Icons.wb_twilight_outlined,
  'card_giftcard_outlined' => Icons.card_giftcard_outlined,
  'rv_hookup' => Icons.rv_hookup,
  'event_seat_outlined' => Icons.event_seat_outlined,
  'sync_alt_outlined' => Icons.sync_alt_outlined,
  'inventory_2_outlined' => Icons.inventory_2_outlined,
  'car_repair_outlined' => Icons.car_repair_outlined,
  'travel_explore' => Icons.travel_explore,
  'military_tech' => Icons.military_tech,
  'numbers' => Icons.numbers,
  'person_outline' => Icons.person_outline,
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
