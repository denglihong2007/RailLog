import 'package:raillog/src/models/public_user_dashboard.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/session_service.dart';

class EntityReview {
  EntityReview.fromJson(Map<String, dynamic> json)
    : id = json['id'] as int,
      reviewType = json['reviewType'] as String,
      userId = json['userId'] as String,
      displayName = json['displayName'] as String,
      avatarUrl = json['avatarUrl'] as String?,
      rating = json['rating'] as int,
      comment = json['comment'] as String,
      tripId = (json['tripId'] as num?)?.toInt(),
      secondTripId = (json['secondTripId'] as num?)?.toInt(),
      transferMinutes = (json['transferMinutes'] as num?)?.toInt(),
      dish = json['dish'] as String?,
      price = (json['price'] as num?)?.toDouble(),
      createdAt = json['createdAt'] as String,
      trip = _reviewTrip(json['trip'], json['userId'] as String),
      secondTrip = _reviewTrip(json['secondTrip'], json['userId'] as String);
  final int id;
  final String reviewType;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final int rating;
  final String comment;
  final int? tripId;
  final int? secondTripId;
  final int? transferMinutes;
  final String? dish;
  final double? price;
  final String createdAt;
  final TripRecord? trip;
  final TripRecord? secondTrip;
}

TripRecord? _reviewTrip(Object? value, String userId) {
  if (value is! Map) return null;
  return publicTripFromJson(Map<String, dynamic>.from(value), userId);
}

class EntityReviewService {
  static Future<int> fetchCount(String type, String key) async {
    final response = await ApiClient.instance.dio.get(
      '/api/entities/${Uri.encodeComponent(type)}/${Uri.encodeComponent(key)}/count',
    );
    return (response.data as Map<String, dynamic>)['totalCount'] as int;
  }

  static Future<List<EntityReview>> fetch(String type, String key) async {
    final response = await ApiClient.instance.dio.get(
      '/api/entities/${Uri.encodeComponent(type)}/${Uri.encodeComponent(key)}/reviews',
    );
    return (response.data as List)
        .map((e) => EntityReview.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
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
}
