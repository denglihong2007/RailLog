import 'package:raillog/src/models/public_user_dashboard.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/session_service.dart';

/// 实体的综合星级。后端按评价新鲜度加权，同一用户只算一张选票；
/// 没有评价时 [averageRating] 为空。
class EntityRating {
  const EntityRating({
    required this.averageRating,
    required this.reviewCount,
    required this.raterCount,
  });

  factory EntityRating.fromJson(Map<String, dynamic> json) => EntityRating(
    averageRating: (json['averageRating'] as num?)?.toDouble(),
    reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
    raterCount: (json['raterCount'] as num?)?.toInt() ?? 0,
  );

  final double? averageRating;
  final int reviewCount;
  final int raterCount;
}

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
          .toList(),
      mentions = (json['mentions'] as List? ?? const [])
          .map(
            (value) => EntityReviewMention.fromJson(
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
  final List<EntityReviewMention> mentions;

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
    required this.mentions,
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
        mentions: mentions,
      );
}

/// 评价正文里被 @ 的用户。[mentionedName] 是发表时正文中写的名字（用于定位），
/// [displayName] 是当前名字（用于渲染）。
class EntityReviewMention {
  const EntityReviewMention({
    required this.userId,
    required this.displayName,
    required this.mentionedName,
  });

  factory EntityReviewMention.fromJson(Map<String, dynamic> json) =>
      EntityReviewMention(
        userId: json['userId'] as String,
        displayName: json['displayName'] as String? ?? '',
        mentionedName: json['mentionedName'] as String? ?? '',
      );

  final String userId;
  final String displayName;
  final String mentionedName;
}

class ReviewMentionMatch {
  const ReviewMentionMatch({
    required this.start,
    required this.end,
    required this.mention,
  });

  final int start;
  final int end;
  final EntityReviewMention mention;
}

/// 在正文里找出被 @ 的用户。名字长的优先匹配，避免「张三」把「张三丰」截断；
/// 名字后面紧跟文字/数字时不算提及（防止 @张三 命中 @张三丰 的前缀）。
List<ReviewMentionMatch> matchReviewMentions(
  String comment,
  Iterable<EntityReviewMention> mentions,
) {
  final candidates =
      mentions
          .where(
            (mention) =>
                mention.mentionedName.trim().isNotEmpty &&
                mention.displayName.trim().isNotEmpty,
          )
          .map(
            (mention) =>
                (mention: mention, needle: '@${mention.mentionedName.trim()}'),
          )
          .toList()
        ..sort((a, b) => b.needle.length.compareTo(a.needle.length));
  if (candidates.isEmpty) return const [];

  final matches = <ReviewMentionMatch>[];
  var index = 0;
  while (index < comment.length) {
    if (comment[index] != '@' ||
        (index > 0 && _isMentionNameChar(comment[index - 1]))) {
      index++;
      continue;
    }
    ReviewMentionMatch? found;
    for (final candidate in candidates) {
      final end = index + candidate.needle.length;
      if (end > comment.length ||
          !comment.startsWith(candidate.needle, index)) {
        continue;
      }
      if (end < comment.length && _isMentionNameChar(comment[end])) continue;
      found = ReviewMentionMatch(
        start: index,
        end: end,
        mention: candidate.mention,
      );
      break;
    }
    if (found == null) {
      index++;
      continue;
    }
    matches.add(found);
    index = found.end;
  }
  return matches;
}

/// 把正文里的旧名字统一换成当前显示名，返回新正文。
String normalizeReviewMentionNames(
  String comment,
  Iterable<EntityReviewMention> mentions,
) {
  final matches = matchReviewMentions(comment, mentions);
  if (matches.isEmpty) return comment;
  final buffer = StringBuffer();
  var cursor = 0;
  for (final match in matches) {
    buffer.write(comment.substring(cursor, match.start));
    buffer.write('@${match.mention.displayName.trim()}');
    cursor = match.end;
  }
  buffer.write(comment.substring(cursor));
  return buffer.toString();
}

/// 正文里实际还保留着的提及。编辑时删掉名字后，不应再把该用户存成提及。
List<EntityReviewMention> usedReviewMentions(
  String comment,
  Iterable<EntityReviewMention> mentions,
) {
  final seen = <String>{};
  return [
    for (final match in matchReviewMentions(comment, mentions))
      if (seen.add(match.mention.userId)) match.mention,
  ];
}

bool _isMentionNameChar(String value) {
  final code = value.runes.first;
  return (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A) ||
      code == 0x5F ||
      (code >= 0x3400 && code <= 0x9FFF);
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

  static Future<EntityRating> fetchRating(String type, String key) async {
    final response = await ApiClient.instance.dio.get(
      '/api/entities/${Uri.encodeComponent(type)}/${Uri.encodeComponent(key)}/rating',
    );
    return EntityRating.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
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

  /// 首页「出行指南」预览。不传 mode，后端返回「热门 + 相关」混排。
  static Future<List<EntityReview>> fetchHomeTravelGuide() async {
    final token = SessionService.instance.token;
    if (token == null) throw StateError('请先登录');
    final response = await ApiClient.instance.dio.get(
      '/api/trips/travel-guide',
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
    List<String> mentionUserIds = const [],
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
        'mentionUserIds': mentionUserIds,
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
    List<String> mentionUserIds = const [],
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
        'mentionUserIds': mentionUserIds,
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
