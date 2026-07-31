import 'package:raillog/src/models/dashboard_trip_entry.dart';

class DashboardAchievement {
  const DashboardAchievement({
    required this.id,
    required this.iconKey,
    required this.title,
    required this.requirement,
    required this.unlocked,
    required this.triggerTripId,
    required this.unlockedUserCount,
    required this.totalUserCount,
    this.unlockedBy,
  });

  factory DashboardAchievement.fromJson(
    Map<String, dynamic> json, {
    required int totalUserCount,
    required Map<int, DashboardTripEntry> tripsByTicketId,
  }) {
    final triggerTripId = (json['triggerTripId'] as num?)?.toInt();
    return DashboardAchievement(
      id: json['id'] as String,
      iconKey: json['icon'] as String,
      title: json['title'] as String,
      requirement: json['description'] as String,
      unlocked: json['status'] == 'unlocked',
      triggerTripId: triggerTripId,
      unlockedBy: triggerTripId == null ? null : tripsByTicketId[triggerTripId],
      unlockedUserCount: (json['unlockedUserCount'] as num).toInt(),
      totalUserCount: totalUserCount,
    );
  }

  final String id;
  final String iconKey;
  final String title;
  final String requirement;
  final bool unlocked;
  final int? triggerTripId;
  final int unlockedUserCount;
  final int totalUserCount;
  final DashboardTripEntry? unlockedBy;

  bool get isUnlocked => unlocked;
  double get unlockedPercentage =>
      totalUserCount == 0 ? 0 : unlockedUserCount * 100 / totalUserCount;
}

List<DashboardAchievement> dashboardAchievementsFromJson(
  Map<String, dynamic> json,
  Iterable<DashboardTripEntry> trips,
) {
  final totalUserCount = (json['totalUserCount'] as num).toInt();
  final tripsByTicketId = <int, DashboardTripEntry>{
    for (final trip in trips)
      if (trip.ticketId != null) trip.ticketId!: trip,
  };
  return (json['achievements'] as List<dynamic>)
      .map(
        (item) => DashboardAchievement.fromJson(
          item as Map<String, dynamic>,
          totalUserCount: totalUserCount,
          tripsByTicketId: tripsByTicketId,
        ),
      )
      .toList(growable: false);
}
