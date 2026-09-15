import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:raillog/src/models/public_user_dashboard.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/session_service.dart';

class PublicUserService {
  PublicUserService._();

  static const _cacheLifetime = Duration(seconds: 45);
  static final Map<String, _CachedDashboard> _cache = {};
  static final Map<String, Future<PublicUserDashboard>> _requests = {};

  static Future<PublicUserDashboard> fetch(
    String userId, {
    bool forceRefresh = false,
  }) {
    final cached = _cache[userId];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.cachedAt) < _cacheLifetime) {
      return Future.value(cached.dashboard);
    }

    final activeRequest = _requests[userId];
    if (activeRequest != null) return activeRequest;

    late final Future<PublicUserDashboard> request;
    request = _fetch(userId)
        .then((dashboard) {
          _cache[userId] = _CachedDashboard(dashboard, DateTime.now());
          return dashboard;
        })
        .whenComplete(() {
          if (identical(_requests[userId], request)) {
            _requests.remove(userId);
          }
        });
    _requests[userId] = request;
    return request;
  }

  static Future<PublicUserDashboard> _fetch(String userId) async {
    final token = SessionService.instance.token;
    try {
      final response = await ApiClient.instance.dio.get<Map<String, dynamic>>(
        '/api/users/${Uri.encodeComponent(userId)}',
        options: token == null ? null : ApiClient.instance.authorized(token),
      );
      final data = response.data!;
      final trips = data['trips'];
      if (trips is List && trips.length >= 100) {
        return compute(_parseDashboard, data);
      }
      return _parseDashboard(data);
    } on DioException catch (error) {
      throw PublicUserException(apiErrorMessage(error));
    }
  }
}

PublicUserDashboard _parseDashboard(Map<String, dynamic> json) =>
    PublicUserDashboard.fromJson(json);

class _CachedDashboard {
  const _CachedDashboard(this.dashboard, this.cachedAt);

  final PublicUserDashboard dashboard;
  final DateTime cachedAt;
}

class PublicUserException implements Exception {
  const PublicUserException(this.message);

  final String message;

  @override
  String toString() => message;
}
