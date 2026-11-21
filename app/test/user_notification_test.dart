import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/user_notification.dart';

void main() {
  test('UserNotification parses review targets and unread state', () {
    final notification = UserNotification.fromJson({
      'id': 7,
      'type': 'review_mention',
      'actorName': '测试用户',
      'message': '测试用户 在「济南西」的评价中提到了你。',
      'tripId': null,
      'reviewId': 42,
      'entityType': 'station',
      'entityKey': '济南西',
      'createdAt': '2026-11-18T10:00:00Z',
      'readAt': null,
    });

    expect(notification.id, 7);
    expect(notification.isMention, isTrue);
    expect(notification.reviewId, 42);
    expect(notification.entityType, 'station');
    expect(notification.entityKey, '济南西');
    expect(notification.isUnread, isTrue);

    final read = notification.asRead();
    expect(read.isUnread, isFalse);
    expect(read.message, notification.message);
    expect(read.reviewId, notification.reviewId);
  });

  test('admin messages are plain text without a navigation target', () {
    final notification = UserNotification.fromJson({
      'id': 9,
      'type': 'admin_message',
      'actorName': '管理员',
      'message': '系统将于今晚 23:00 进行维护。',
      'createdAt': '2026-11-21T10:00:00Z',
      'readAt': null,
    });

    expect(notification.isAdminMessage, isTrue);
    expect(notification.tripId, isNull);
    expect(notification.reviewId, isNull);
    expect(notification.entityType, isNull);
    expect(notification.entityKey, isNull);
  });

  test('NotificationPage parses empty pages', () {
    final page = NotificationPage.fromJson({
      'items': [],
      'unreadCount': 0,
      'total': 0,
    });

    expect(page.items, isEmpty);
    expect(page.unreadCount, 0);
    expect(page.total, 0);
  });
}
