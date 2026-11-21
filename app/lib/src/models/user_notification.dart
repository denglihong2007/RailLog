class UserNotification {
  const UserNotification({
    required this.id,
    required this.type,
    required this.actorName,
    required this.message,
    required this.createdAt,
    this.tripId,
    this.reviewId,
    this.entityType,
    this.entityKey,
    this.readAt,
  });

  factory UserNotification.fromJson(Map<String, dynamic> json) =>
      UserNotification(
        id: (json['id'] as num).toInt(),
        type: json['type'] as String,
        actorName: json['actorName'] as String? ?? '',
        message: json['message'] as String,
        tripId: (json['tripId'] as num?)?.toInt(),
        reviewId: (json['reviewId'] as num?)?.toInt(),
        entityType: json['entityType'] as String?,
        entityKey: json['entityKey'] as String?,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        readAt: DateTime.tryParse(json['readAt'] as String? ?? ''),
      );

  final int id;
  final String type;
  final String actorName;
  final String message;
  final int? tripId;
  final int? reviewId;
  final String? entityType;
  final String? entityKey;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  bool get isTripDeleted => type == 'trip_deleted';
  bool get isTripUpdated => type == 'trip_updated';
  bool get isReviewDeleted => type == 'review_deleted';
  bool get isReviewUpdated => type == 'review_updated';
  bool get isReaction => type == 'review_reaction';
  bool get isMention => type == 'review_mention';
  bool get isAdminMessage => type == 'admin_message';

  UserNotification asRead() => UserNotification(
    id: id,
    type: type,
    actorName: actorName,
    message: message,
    tripId: tripId,
    reviewId: reviewId,
    entityType: entityType,
    entityKey: entityKey,
    createdAt: createdAt,
    readAt: readAt ?? DateTime.now(),
  );
}

class NotificationPage {
  const NotificationPage({
    required this.items,
    required this.unreadCount,
    required this.total,
  });

  factory NotificationPage.fromJson(Map<String, dynamic> json) =>
      NotificationPage(
        items: (json['items'] as List? ?? const [])
            .map(
              (value) => UserNotification.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList(),
        unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
      );

  final List<UserNotification> items;
  final int unreadCount;
  final int total;
}
