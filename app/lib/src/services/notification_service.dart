import 'package:raillog/src/models/user_notification.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/session_service.dart';

class NotificationService {
  NotificationService._();

  static const pageSize = 30;

  static Future<NotificationPage> fetchPage({
    int offset = 0,
    int limit = pageSize,
  }) async {
    final token = SessionService.instance.token;
    if (token == null) throw StateError('请先登录');
    final response = await ApiClient.instance.dio.get(
      '/api/notifications',
      queryParameters: {'offset': offset, 'limit': limit},
      options: ApiClient.instance.authorized(token),
    );
    return NotificationPage.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  static Future<int> fetchUnreadCount() async {
    final token = SessionService.instance.token;
    if (token == null) return 0;
    final response = await ApiClient.instance.dio.get(
      '/api/notifications/unread-count',
      options: ApiClient.instance.authorized(token),
    );
    return ((response.data as Map<String, dynamic>)['unreadCount'] as num?)
            ?.toInt() ??
        0;
  }

  /// ids 为空表示全部标为已读。
  static Future<void> markRead({List<int>? ids}) async {
    final token = SessionService.instance.token;
    if (token == null) return;
    await ApiClient.instance.dio.post(
      '/api/notifications/read',
      data: {'ids': ids},
      options: ApiClient.instance.authorized(token),
    );
  }
}
