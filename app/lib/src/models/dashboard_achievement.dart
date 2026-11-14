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
    this.baseExperience,
    this.progressCurrent,
    this.progressTarget,
    this.maxProgressCurrent,
    this.maxProgressTarget,
    this.maxExperienceReached = false,
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
      baseExperience: (json['baseExperience'] as num?)?.toInt(),
      maxProgressCurrent: (json['maxProgressCurrent'] as num?)?.toDouble(),
      maxProgressTarget: (json['maxProgressTarget'] as num?)?.toDouble(),
      maxExperienceReached: json['maxExperienceReached'] as bool? ?? false,
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

  /// 初始经验（不含分阶加成），经验胶囊的颜色跟随它。
  final int? baseExperience;
  final bool hidden;
  final String? narrativeNote;
  final double? progressCurrent;
  final double? progressTarget;
  final double? maxProgressCurrent;
  final double? maxProgressTarget;

  /// 已解锁且经验触顶；没有进度条但有加成机制的成就也靠它显示满分装饰。
  final bool maxExperienceReached;
  final String? note;
  final DashboardTripEntry? unlockedBy;
  final List<DashboardAchievementRequirement> requirements;

  int get experienceTierValue => baseExperience ?? experience;

  bool get isUnlocked => unlocked;
  bool get hasProgress => progressCurrent != null && progressTarget != null;
  bool get hasRequirements => requirements.isNotEmpty;

  /// 0/1 本质是 true/false：只有同时具备详细进度与满分进度时才外露。
  bool get hasVisibleProgress =>
      hasProgress &&
      (progressTarget! > 1 || (hasRequirements && hasMaxProgress));

  bool get hasMaxProgress =>
      maxProgressCurrent != null && maxProgressTarget != null;

  /// 满分进度条只画「解锁之后」的部分：(当前 - 解锁要求) / (满分要求 - 解锁要求)。
  double? get maxProgressValue {
    if (!hasMaxProgress) return null;
    final maxTarget = maxProgressTarget!;
    if (maxTarget <= 0) return null;
    final unlockTarget = progressTarget;
    // 解锁要求与满分要求不在同一刻度时（如朝花夕拾按年份），直接按满分比例画。
    if (unlockTarget == null || unlockTarget >= maxTarget) {
      return (maxProgressCurrent! / maxTarget).clamp(0.0, 1.0);
    }
    return ((maxProgressCurrent! - unlockTarget) / (maxTarget - unlockTarget))
        .clamp(0.0, 1.0);
  }

  bool get maxProgressReached =>
      hasMaxProgress && maxProgressCurrent! >= maxProgressTarget!;

  bool get isFullMark => maxProgressReached || maxExperienceReached;

  /// 满分外圈的值：有进度数据时按「解锁之后」的比例；
  /// 没有进度但经验触顶的特殊成就，直接画满一圈。
  double? get fullMarkRingValue {
    final progress = maxProgressValue;
    if (progress != null) return progress;
    return maxExperienceReached ? 1 : null;
  }
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

/// 按「最新解锁」重排：解锁时间取触发行程的发生时间，与解锁行程页同一口径；
/// 时间未知的已解锁成就排在它们之后，尚未解锁的保持服务端给的顺序排最后。
List<DashboardAchievement> sortAchievementsByLatestUnlock(
  List<DashboardAchievement> achievements,
) {
  final entries = achievements.indexed.toList(growable: false);
  int rank(DashboardAchievement item) =>
      item.unlockedBy != null ? 0 : (item.isUnlocked ? 1 : 2);
  entries.sort((first, second) {
    final rankOrder = rank(first.$2).compareTo(rank(second.$2));
    if (rankOrder != 0) return rankOrder;
    final firstAt = first.$2.unlockedBy?.departureTime;
    final secondAt = second.$2.unlockedBy?.departureTime;
    if (firstAt != null && secondAt != null) {
      final timeOrder = secondAt.compareTo(firstAt);
      if (timeOrder != 0) return timeOrder;
    }
    return first.$1.compareTo(second.$1);
  });
  return [for (final entry in entries) entry.$2];
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
