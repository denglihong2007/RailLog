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
    required this.experience,
    required this.hidden,
    required this.narrativeNote,
    this.progressCurrent,
    this.progressTarget,
    this.note,
    this.unlockedBy,
    this.requirements = const [],
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
      progressCurrent: (json['progressCurrent'] as num?)?.toDouble(),
      progressTarget: (json['progressTarget'] as num?)?.toDouble(),
      experience: (json['experience'] as num?)?.toInt() ?? 0,
      hidden: json['hidden'] as bool? ?? false,
      note: json['note'] as String?,
      narrativeNote: json['narrativeNote'] as String?,
      requirements: (json['requirements'] as List<dynamic>? ?? const [])
          .map(
            (item) => DashboardAchievementRequirement.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(growable: false),
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
  final int experience;
  final bool hidden;
  final String? narrativeNote;
  final double? progressCurrent;
  final double? progressTarget;
  final String? note;
  final DashboardTripEntry? unlockedBy;
  final List<DashboardAchievementRequirement> requirements;

  bool get isUnlocked => unlocked;
  bool get hasProgress => progressCurrent != null && progressTarget != null;
  bool get hasRequirements => requirements.isNotEmpty;
  int get completedRequirementCount =>
      requirements.where((requirement) => requirement.completed).length;
  double get progressValue {
    final current = progressCurrent;
    final target = progressTarget;
    if (current == null || target == null || target <= 0) return 0;
    return (current / target).clamp(0, 1);
  }

  double get unlockedPercentage =>
      totalUserCount == 0 ? 0 : unlockedUserCount * 100 / totalUserCount;
}

class DashboardAchievementRequirement {
  const DashboardAchievementRequirement({
    required this.key,
    required this.label,
    required this.completed,
    this.trip,
  });

  factory DashboardAchievementRequirement.fromJson(Map<String, dynamic> json) {
    final tripJson = json['trip'];
    return DashboardAchievementRequirement(
      key: json['key'] as String,
      label: json['label'] as String,
      completed: json['completed'] as bool? ?? tripJson is Map<String, dynamic>,
      trip: tripJson is Map<String, dynamic>
          ? AchievementRequirementTrip.fromJson(tripJson)
          : null,
    );
  }

  final String key;
  final String label;
  final bool completed;
  final AchievementRequirementTrip? trip;
}

class AchievementRequirementTrip {
  const AchievementRequirementTrip({
    required this.ticketId,
    required this.createdAt,
    required this.trainNumber,
    required this.fromStation,
    required this.toStation,
    required this.departureTime,
    required this.arrivalTime,
    required this.mileageKm,
    required this.seatType,
    required this.seatNumber,
    required this.price,
    required this.isRailTrip,
  });

  factory AchievementRequirementTrip.fromJson(Map<String, dynamic> json) =>
      AchievementRequirementTrip(
        ticketId: (json['ticketId'] as num).toInt(),
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        trainNumber: json['trainNumber'] as String,
        fromStation: json['fromStation'] as String,
        toStation: json['toStation'] as String,
        departureTime: _optionalDate(json['departureTime']),
        arrivalTime: _optionalDate(json['arrivalTime']),
        mileageKm: (json['mileageKm'] as num).toDouble(),
        seatType: json['seatType'] as String?,
        seatNumber: json['seatNumber'] as String?,
        price: (json['price'] as num).toDouble(),
        isRailTrip: json['isRailTrip'] as bool? ?? true,
      );

  final int ticketId;
  final DateTime createdAt;
  final String trainNumber;
  final String fromStation;
  final String toStation;
  final DateTime? departureTime;
  final DateTime? arrivalTime;
  final double mileageKm;
  final String? seatType;
  final String? seatNumber;
  final double price;
  final bool isRailTrip;

  DateTime get occurredAt => departureTime ?? createdAt;
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

DateTime? _optionalDate(Object? value) =>
    value is String ? DateTime.parse(value).toLocal() : null;
