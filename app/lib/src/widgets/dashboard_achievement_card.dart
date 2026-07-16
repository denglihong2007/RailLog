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
                dashboardAchievementIcon(achievement.kind),
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
          Text(
            entry == null
                ? '尚未解锁'
                : '${_formatDate(entry.departureTime)} 乘坐 ${_trainLabel(entry.trainNumber)} 解锁',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: unlocked ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    return Card.filled(
      margin: EdgeInsets.zero,
      color: unlocked ? colors.tertiaryContainer : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : Semantics(
              button: true,
              child: InkWell(onTap: onTap, child: content),
            ),
    );
  }
}

IconData dashboardAchievementIcon(DashboardAchievementKind kind) =>
    switch (kind) {
      DashboardAchievementKind.freeMeal => Icons.restaurant_outlined,
      DashboardAchievementKind.overnightSeat =>
        Icons.airline_seat_recline_extra_outlined,
      DashboardAchievementKind.tightTransfer => Icons.transfer_within_a_station,
      DashboardAchievementKind.sevenDayStreak => Icons.local_fire_department,
      DashboardAchievementKind.thirtyDayStreak => Icons.calendar_month_outlined,
      DashboardAchievementKind.yearStreak => Icons.event_repeat_outlined,
      DashboardAchievementKind.duration24Hours => Icons.looks_one_outlined,
      DashboardAchievementKind.duration48Hours => Icons.looks_two_outlined,
      DashboardAchievementKind.duration72Hours => Icons.looks_3_outlined,
      DashboardAchievementKind.all25Series => Icons.palette_outlined,
      DashboardAchievementKind.allEmuSeries => Icons.train_outlined,
      DashboardAchievementKind.allSeatTypes => Icons.checklist_outlined,
      DashboardAchievementKind.noSeat12Hours => Icons.accessibility_new,
      DashboardAchievementKind.hundredTickets =>
        Icons.collections_bookmark_outlined,
      DashboardAchievementKind.midnightBoarding => Icons.nightlight_outlined,
      DashboardAchievementKind.wallFacingSeat =>
        Icons.airline_seat_recline_normal,
      DashboardAchievementKind.hundredStations => Icons.location_on_outlined,
      DashboardAchievementKind.thousandKilometers => Icons.route_outlined,
      DashboardAchievementKind.airRail => Icons.connecting_airports_outlined,
      DashboardAchievementKind.railFerry => Icons.directions_boat_outlined,
      DashboardAchievementKind.hundredThousandKilometers =>
        Icons.gps_fixed_outlined,
      DashboardAchievementKind.fTrain => Icons.u_turn_left_outlined,
      DashboardAchievementKind.axleOverheat => Icons.device_thermostat_outlined,
      DashboardAchievementKind.advantageIsMine => Icons.flag_outlined,
      DashboardAchievementKind.platformSubsidence =>
        Icons.vertical_align_bottom_outlined,
    };

String _trainLabel(String value) {
  final train = value.trim();
  return train.isEmpty ? '未填写车次' : train;
}

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
