class AchievementUnlockTrip {
  const AchievementUnlockTrip({
    required this.ticketId,
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
    required this.occurredAt,
    required this.trainNumber,
    required this.fromStation,
    required this.toStation,
    required this.isCurrentUser,
    this.experience = 0,
  });

  factory AchievementUnlockTrip.fromJson(Map<String, dynamic> json) =>
      AchievementUnlockTrip(
        ticketId: (json['ticketId'] as num).toInt(),
        userId: json['userId'] as String,
        displayName: json['displayName'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        occurredAt: DateTime.parse(json['occurredAt'] as String).toLocal(),
        trainNumber: json['trainNumber'] as String,
        fromStation: json['fromStation'] as String,
        toStation: json['toStation'] as String,
        isCurrentUser: json['isCurrentUser'] as bool? ?? false,
        experience: (json['experience'] as num?)?.toInt() ?? 0,
      );

  final int ticketId;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final DateTime occurredAt;
  final String trainNumber;
  final String fromStation;
  final String toStation;
  final bool isCurrentUser;

  /// 该用户在这个成就上取得的经验；固定经验成就里所有人相同。
  final int experience;
}

class AchievementUnlockTrips {
  const AchievementUnlockTrips({
    required this.achievementId,
    required this.trips,
    this.hasExperienceVariation = false,
  });

  factory AchievementUnlockTrips.fromJson(Map<String, dynamic> json) =>
      AchievementUnlockTrips(
        achievementId: json['achievementId'] as String,
        hasExperienceVariation:
            json['hasExperienceVariation'] as bool? ?? false,
        trips: (json['trips'] as List<dynamic>? ?? const [])
            .map(
              (item) =>
                  AchievementUnlockTrip.fromJson(item as Map<String, dynamic>),
            )
            .toList(growable: false),
      );

  final String achievementId;

  /// 经验是否随进度变化。只有这类成就才按经验排出名次。
  final bool hasExperienceVariation;
  final List<AchievementUnlockTrip> trips;

  /// 展示顺序与名次：自己始终第一，其余按经验（有变化时）和发生时间倒序。
  /// 经验相同的人共享名次，下一位跳号（1、2、2、4）。
  List<AchievementUnlockTripRanking> get ranking {
    final ordered = [...trips]
      ..sort((first, second) {
        if (first.isCurrentUser != second.isCurrentUser) {
          return first.isCurrentUser ? -1 : 1;
        }
        if (hasExperienceVariation) {
          final experienceOrder = second.experience.compareTo(first.experience);
          if (experienceOrder != 0) return experienceOrder;
        }
        final timeOrder = second.occurredAt.compareTo(first.occurredAt);
        if (timeOrder != 0) return timeOrder;
        return second.ticketId.compareTo(first.ticketId);
      });
    if (!hasExperienceVariation) {
      return [
        for (final trip in ordered) AchievementUnlockTripRanking(trip: trip),
      ];
    }
    final rankByTicketId = _experienceRanks();
    return [
      for (final trip in ordered)
        AchievementUnlockTripRanking(
          trip: trip,
          rank: rankByTicketId[trip.ticketId],
        ),
    ];
  }

  Map<int, int> _experienceRanks() {
    final byExperience = [...trips]
      ..sort((first, second) => second.experience.compareTo(first.experience));
    final ranks = <int, int>{};
    int? previousExperience;
    var rank = 0;
    for (var index = 0; index < byExperience.length; index++) {
      final trip = byExperience[index];
      if (trip.experience != previousExperience) {
        rank = index + 1;
        previousExperience = trip.experience;
      }
      ranks[trip.ticketId] = rank;
    }
    return ranks;
  }
}

class AchievementUnlockTripRanking {
  const AchievementUnlockTripRanking({required this.trip, this.rank});

  final AchievementUnlockTrip trip;

  /// 经验不随进度变化时为空，表示只借用排行榜版式、不显示名次。
  final int? rank;
}
