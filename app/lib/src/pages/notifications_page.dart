import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:raillog/src/models/user_notification.dart';
import 'package:raillog/src/pages/entity_detail_page.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/notification_service.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/login_required_view.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final List<UserNotification> _notifications = [];
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int _offset = 0;
  int _total = 0;
  int _unreadCount = 0;
  int _requestId = 0;

  bool get _hasMore => _notifications.length < _total;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await NotificationService.fetchPage(offset: 0);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _notifications
          ..clear()
          ..addAll(page.items);
        _offset = page.items.length;
        _total = page.total;
        _unreadCount = page.unreadCount;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || !_hasMore) return;
    setState(() => _loadingMore = true);
    final requestId = _requestId;
    try {
      final page = await NotificationService.fetchPage(offset: _offset);
      if (!mounted || requestId != _requestId) return;
      final seen = _notifications.map((item) => item.id).toSet();
      setState(() {
        _notifications.addAll(
          page.items.where((item) => seen.add(item.id)),
        );
        _offset += page.items.length;
        _total = page.total;
        _unreadCount = page.unreadCount;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _loadingMore = false);
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis == Axis.vertical &&
        notification.metrics.extentAfter < 320) {
      _loadMore();
    }
    return false;
  }

  Future<void> _markAllRead() async {
    if (_unreadCount == 0) return;
    setState(() {
      for (var index = 0; index < _notifications.length; index++) {
        _notifications[index] = _notifications[index].asRead();
      }
      _unreadCount = 0;
    });
    try {
      await NotificationService.markRead();
    } catch (_) {
      // 标记失败不打断浏览；下次进入页面会以服务端状态为准。
    }
  }

  Future<void> _open(UserNotification item) async {
    _markReadLocally(item);
    unawaited(NotificationService.markRead(ids: [item.id]).catchError((_) {}));

    if (item.isTripDeleted || item.isReviewDeleted) {
      final message = item.isTripDeleted ? '该行程已被系统删除' : '该评价已被系统删除';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    if (item.isTripUpdated && item.tripId != null) {
      await Navigator.of(context).push(
        m3PageRoute(
          builder: (_) =>
              TripRecordDetailsPage.forTicket(ticketId: item.tripId!),
        ),
      );
      return;
    }

    final entityType = _entityType(item.entityType);
    final entityKey = item.entityKey?.trim() ?? '';
    if ((item.isReviewUpdated || item.isReaction || item.isMention) &&
        entityType != null &&
        entityKey.isNotEmpty) {
      await Navigator.of(context).push(
        m3PageRoute(
          builder: (_) => EntityDetailPage(
            type: entityType,
            name: entityKey,
            focusReviewId: item.reviewId,
          ),
        ),
      );
    }
  }

  void _markReadLocally(UserNotification item) {
    if (!item.isUnread) return;
    final index = _notifications.indexWhere((value) => value.id == item.id);
    if (index < 0) return;
    setState(() {
      _notifications[index] = _notifications[index].asRead();
      if (_unreadCount > 0) _unreadCount--;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('全部已读'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedBuilder(
        animation: SessionService.instance,
        builder: (context, _) => SessionService.instance.isSignedIn
            ? RefreshIndicator(onRefresh: _reload, child: _buildList())
            : LoginRequiredView(
                message: '登录后可以查看通知。',
                icon: Icons.notifications_outlined,
                onSignedIn: _reload,
              ),
      ),
    );
  }

  Widget _buildList() {
    final error = _error;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Column(
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 12),
                const Text('当前无法获取通知'),
                const SizedBox(height: 4),
                Text(
                  apiErrorMessage(error),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _reload, child: const Text('重试')),
              ],
            ),
          ),
        ],
      );
    }
    if (_notifications.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Icon(Icons.notifications_none, size: 48),
          SizedBox(height: 12),
          Center(child: Text('暂无通知')),
        ],
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _notifications.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= _notifications.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _NotificationTile(
            notification: _notifications[index],
            onTap: () => _open(_notifications[index]),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final UserNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final unread = notification.isUnread;
    return AppCard.outlined(
      padding: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: unread
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          child: Icon(
            _notificationIcon(notification.type),
            size: 20,
            color: unread ? colors.onPrimaryContainer : colors.onSurfaceVariant,
          ),
        ),
        title: Text(
          notification.message,
          style: unread
              ? textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)
              : textTheme.bodyMedium,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            _formatTime(notification.createdAt),
            style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
        trailing: unread
            ? Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
              )
            : null,
      ),
    );
  }
}

EntityType? _entityType(String? wire) => switch (wire?.toLowerCase()) {
  'station' => EntityType.station,
  'route' => EntityType.route,
  'company' => EntityType.company,
  'rollingstock' => EntityType.rollingStock,
  'train' => EntityType.train,
  _ => null,
};

IconData _notificationIcon(String type) => switch (type) {
  'trip_deleted' => Icons.delete_outline,
  'trip_updated' => Icons.edit_outlined,
  'review_deleted' => Icons.delete_forever_outlined,
  'review_updated' => Icons.edit_note,
  'review_reaction' => Icons.chat_bubble_outline,
  'review_mention' => Icons.alternate_email,
  _ => Icons.notifications_outlined,
};

String _formatTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
