import 'package:raillog/src/models/public_user_dashboard.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/session_service.dart';

class EntityReview {
  EntityReview.fromJson(Map<String, dynamic> json)
    : id = json['id'] as int,
      entityType = json['entityType'] as String? ?? '',
      entityKey = json['entityKey'] as String? ?? '',
      reviewType = json['reviewType'] as String,
      userId = json['userId'] as String,
      displayName = json['displayName'] as String,
      avatarUrl = json['avatarUrl'] as String?,
      rating = json['rating'] as int,
      comment = json['comment'] as String,
      tripId = (json['tripId'] as num?)?.toInt(),
      secondTripId = (json['secondTripId'] as num?)?.toInt(),
      transferMinutes = (json['transferMinutes'] as num?)?.toInt(),
      routeFromStation = json['routeFromStation'] as String?,
      routeToStation = json['routeToStation'] as String?,
      dish = json['dish'] as String?,
      price = (json['price'] as num?)?.toDouble(),
      createdAt = json['createdAt'] as String,
      achievementExperience =
          (json['achievementExperience'] as num?)?.toInt() ?? 0,
      trip = _reviewTrip(json['trip'], json['userId'] as String),
      secondTrip = _reviewTrip(json['secondTrip'], json['userId'] as String),
      reactions = (json['reactions'] as List? ?? const [])
          .map(
            (value) => EntityReviewReaction.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList();
  final int id;
  final String entityType;
  final String entityKey;
  final String reviewType;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final int rating;
  final String comment;
  final int? tripId;
  final int? secondTripId;
  final int? transferMinutes;
  final String? routeFromStation;
  final String? routeToStation;
  final String? dish;
  final double? price;
  final String createdAt;
  final int achievementExperience;
  final TripRecord? trip;
  final TripRecord? secondTrip;
  final List<EntityReviewReaction> reactions;

  EntityReview._({
    required this.id,
    required this.entityType,
    required this.entityKey,
    required this.reviewType,
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
    required this.rating,
    required this.comment,
    required this.tripId,
    required this.secondTripId,
    required this.transferMinutes,
    required this.routeFromStation,
    required this.routeToStation,
    required this.dish,
    required this.price,
    required this.createdAt,
    required this.achievementExperience,
    required this.trip,
    required this.secondTrip,
    required this.reactions,
  });

  /// 只替换表情回应，其余字段不变。回应接口只回 204，列表拿到本地算出的新状态
  /// 后直接换掉这一条即可，不必为了一个表情把整页重新拉回第一页。
  EntityReview withReactions(List<EntityReviewReaction> reactions) =>
      EntityReview._(
        id: id,
        entityType: entityType,
        entityKey: entityKey,
        reviewType: reviewType,
        userId: userId,
        displayName: displayName,
        avatarUrl: avatarUrl,
        rating: rating,
        comment: comment,
        tripId: tripId,
        secondTripId: secondTripId,
        transferMinutes: transferMinutes,
        routeFromStation: routeFromStation,
        routeToStation: routeToStation,
        dish: dish,
        price: price,
        createdAt: createdAt,
        achievementExperience: achievementExperience,
        trip: trip,
        secondTrip: secondTrip,
        reactions: reactions,
      );
}

class EntityReviewReaction {
  const EntityReviewReaction({
    required this.emoji,
    required this.count,
    required this.reactedByCurrentUser,
  });

  factory EntityReviewReaction.fromJson(Map<String, dynamic> json) =>
      EntityReviewReaction(
        emoji: json['emoji'] as String,
        count: (json['count'] as num).toInt(),
        reactedByCurrentUser: json['reactedByCurrentUser'] as bool,
      );

  final String emoji;
  final int count;
  final bool reactedByCurrentUser;
}

/// 本地推算回应后的表情列表，规则与后端一致：每个用户对一条评价至多一个表情，
/// 换表情是旧表情减一、新表情加一，减到 0 的表情不再展示。
/// 顺序也与后端一致（数量降序、同数量按表情），这样回应不会让卡片里的表情乱跳。
List<EntityReviewReaction> reactionsAfterToggle(
  List<EntityReviewReaction> reactions,
  String? currentEmoji,
  String emoji,
) {
  final removing = currentEmoji == emoji;
  final counts = <String, int>{
    for (final reaction in reactions) reaction.emoji: reaction.count,
  };
  if (currentEmoji != null) {
    final left = (counts[currentEmoji] ?? 1) - 1;
    if (left <= 0) {
      counts.remove(currentEmoji);
    } else {
      counts[currentEmoji] = left;
    }
  }
  if (!removing) counts[emoji] = (counts[emoji] ?? 0) + 1;
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  return [
    for (final entry in entries)
      EntityReviewReaction(
        emoji: entry.key,
        count: entry.value,
        reactedByCurrentUser: !removing && entry.key == emoji,
      ),
  ];
}

TripRecord? _reviewTrip(Object? value, String userId) {
  if (value is! Map) return null;
  return publicTripFromJson(Map<String, dynamic>.from(value), userId);
}

/// 「出行指南」的排序方式。原来是「热门 + 相关」混排，现在拆成两种可选。
enum TravelGuideMode {
  hot('hot', '全站热门'),
  related('related', '与我相关');

  const TravelGuideMode(this.wire, this.label);

  final String wire;
  final String label;
}

class EntityReviewService {
  /// 出行指南与「我的评价」共用的分页页大小。
  static const pageSize = 20;

  static Future<int> fetchCount(String type, String key) async {
    final response = await ApiClient.instance.dio.get(
      '/api/entities/${Uri.encodeComponent(type)}/${Uri.encodeComponent(key)}/count',
    );
    return (response.data as Map<String, dynamic>)['totalCount'] as int;
  }

  static Future<List<EntityReview>> fetch(String type, String key) async {
    final token = SessionService.instance.token;
    final response = await ApiClient.instance.dio.get(
      '/api/entities/${Uri.encodeComponent(type)}/${Uri.encodeComponent(key)}/reviews',
      options: token == null ? null : ApiClient.instance.authorized(token),
    );
    return (response.data as List)
        .map((e) => EntityReview.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<List<EntityReview>> fetchForTrip(int ticketId) async {
    final token = SessionService.instance.token;
    final response = await ApiClient.instance.dio.get(
      '/api/trips/$ticketId/reviews',
      options: token == null ? null : ApiClient.instance.authorized(token),
    );
    return (response.data as List)
        .map((e) => EntityReview.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<List<EntityReview>> fetchTravelGuide(int ticketId) async {
    final token = SessionService.instance.token;
    if (token == null) throw StateError('请先登录');
    final response = await ApiClient.instance.dio.get(
      '/api/trips/$ticketId/travel-guide',
      options: ApiClient.instance.authorized(token),
    );
    return (response.data as List)
        .map((e) => EntityReview.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// 首页「出行指南」的某一页。返回条数少于 [limit] 表示已经到底。
  static Future<List<EntityReview>> fetchTravelGuidePage({
    required TravelGuideMode mode,
    int offset = 0,
    int limit = pageSize,
  }) async {
    final token = SessionService.instance.token;
    if (token == null) throw StateError('请先登录');
    final response = await ApiClient.instance.dio.get(
      '/api/trips/travel-guide',
      queryParameters: {'mode': mode.wire, 'offset': offset, 'limit': limit},
      options: ApiClient.instance.authorized(token),
    );
    return _parseReviews(response.data);
  }

  /// 当前用户自己发表的评价，最新在前。设置里「我的评价」的数据源。
  static Future<List<EntityReview>> fetchMine({
    int offset = 0,
    int limit = pageSize,
  }) async {
    final token = SessionService.instance.token;
    if (token == null) throw StateError('请先登录');
    final response = await ApiClient.instance.dio.get(
      '/api/entities/reviews/mine',
      queryParameters: {'offset': offset, 'limit': limit},
      options: ApiClient.instance.authorized(token),
    );
    return _parseReviews(response.data);
  }

  static Future<void> submit({
    required String type,
    required String key,
    required String reviewType,
    required int rating,
    required String comment,
    int? tripId,
    int? secondTripId,
    int? transferMinutes,
    String? routeFromStation,
    String? routeToStation,
    String? dish,
    double? price,
  }) async {
    final token = SessionService.instance.token;
    if (token == null) throw StateError('请先登录');
    final response = await ApiClient.instance.dio.post(
      '/api/entities/${Uri.encodeComponent(type)}/${Uri.encodeComponent(key)}/reviews',
      data: {
        'entityType': type,
        'entityKey': key,
        'reviewType': reviewType,
        'rating': rating,
        'comment': comment,
        'tripId': tripId,
        'secondTripId': secondTripId,
        'transferMinutes': transferMinutes,
        'routeFromStation': routeFromStation,
        'routeToStation': routeToStation,
        'dish': dish,
        'price': price,
      },
      options: ApiClient.instance.authorized(token),
    );
    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      throw StateError('评价提交失败');
    }
  }

  static Future<void> update(
    EntityReview review, {
    required int rating,
    required String comment,
    int? tripId,
    int? secondTripId,
    int? transferMinutes,
    String? routeFromStation,
    String? routeToStation,
    String? dish,
    double? price,
  }) async {
    final token = SessionService.instance.token;
    if (token == null) throw StateError('请先登录');
    await ApiClient.instance.dio.patch(
      '/api/entities/reviews/${review.id}',
      data: {
        'rating': rating,
        'comment': comment,
        'tripId': tripId,
        'secondTripId': secondTripId,
        'transferMinutes': transferMinutes,
        'routeFromStation': routeFromStation,
        'routeToStation': routeToStation,
        'dish': dish,
        'price': price,
      },
      options: ApiClient.instance.authorized(token),
    );
  }

  static Future<void> delete(EntityReview review) async {
    final token = SessionService.instance.token;
    if (token == null) throw StateError('请先登录');
    await ApiClient.instance.dio.delete(
      '/api/entities/reviews/${review.id}',
      options: ApiClient.instance.authorized(token),
    );
  }

  static Future<void> setReaction(EntityReview review, String emoji) async {
    final token = SessionService.instance.token;
    if (token == null) throw StateError('请先登录');
    await ApiClient.instance.dio.put(
      '/api/entities/reviews/${review.id}/reaction',
      data: {'emoji': emoji},
      options: ApiClient.instance.authorized(token),
    );
  }

  static Future<void> removeReaction(EntityReview review) async {
    final token = SessionService.instance.token;
    if (token == null) throw StateError('请先登录');
    await ApiClient.instance.dio.delete(
      '/api/entities/reviews/${review.id}/reaction',
      options: ApiClient.instance.authorized(token),
    );
  }

  static List<EntityReview> _parseReviews(Object? data) => (data as List)
      .map((e) => EntityReview.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
}
