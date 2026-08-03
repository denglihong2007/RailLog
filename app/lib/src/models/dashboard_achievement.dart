import 'package:raillog/src/models/dashboard_trip_entry.dart';

enum AchievementCategory {
  milestones('milestones', '历程丰碑'),
  extremeChallenges('extremeChallenges', '极限挑战'),
  railwayCatalog('railwayCatalog', '铁道图鉴'),
  touring('touring', '巡游四方'),
  funJourneys('funJourneys', '趣味旅程');

  const AchievementCategory(this.apiKey, this.label);

  final String apiKey;
  final String label;

  static AchievementCategory fromApiKey(String value) => values.firstWhere(
    (category) => category.apiKey == value,
    orElse: () => throw FormatException('未知成就类型：$value'),
  );
}

class DashboardAchievement {
  const DashboardAchievement({
    required this.id,
    required this.category,
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
      category: AchievementCategory.fromApiKey(json['category'] as String),
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
  final AchievementCategory category;
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
