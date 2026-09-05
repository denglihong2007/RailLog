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
}

class AchievementUnlockTrips {
  const AchievementUnlockTrips({
    required this.achievementId,
    required this.trips,
  });

  factory AchievementUnlockTrips.fromJson(Map<String, dynamic> json) =>
      AchievementUnlockTrips(
        achievementId: json['achievementId'] as String,
        trips: (json['trips'] as List<dynamic>? ?? const [])
            .map(
              (item) =>
                  AchievementUnlockTrip.fromJson(item as Map<String, dynamic>),
            )
            .toList(growable: false),
      );

  final String achievementId;
  final List<AchievementUnlockTrip> trips;
}
