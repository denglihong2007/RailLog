import 'package:flutter/material.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/pages/home_page.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/entity_review_navigation.dart';
import 'package:raillog/src/services/entity_review_service.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/theme/app_theme.dart';
import 'package:raillog/src/widgets/entity_review_card.dart';
import 'package:raillog/src/widgets/login_required_view.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';
import 'package:raillog/src/widgets/review_editor.dart';

/// 设置里的「我的评价」：当前用户发表过的全部评价，最新在前，向下滚动分页。
/// 卡片与主页「出行指南」用的是同一个 [EntityReviewCard]，
/// 区别只在自己名下多出编辑与删除两个操作。
class MyReviewsPage extends StatefulWidget {
  const MyReviewsPage({super.key});

  @override
  State<MyReviewsPage> createState() => _MyReviewsPageState();
}

class _MyReviewsPageState extends State<MyReviewsPage> {
  final List<EntityReview> _reviews = [];
  List<TripRecord> _trips = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;
  /// 下一页要从服务端跳过的条数。服务端按发表时间倒序，
  /// 本地删掉一条后它后面的条目会整体前移，游标也要跟着退一格，
  /// 否则紧随已加载窗口之后的那条会被跳过。
  int _offset = 0;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    if (SessionService.instance.isSignedIn) {
      _reload();
      _loadTrips();
    } else {
      _loading = false;
    }
  }

  Future<void> _loadTrips() async {
    try {
      final trips = await DbHelper.instance.getAllTrips();
      if (mounted) setState(() => _trips = trips);
    } catch (_) {
      // 编辑弹窗没有候选行程时仍可改评分与正文，这里不必打扰用户。
    }
  }

  Future<void> _reload() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await EntityReviewService.fetchMine();
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _reviews
          ..clear()
          ..addAll(page);
        _offset = page.length;
        _hasMore = page.length >= EntityReviewService.pageSize;
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
    if (_loading || _loadingMore || !_hasMore || _error != null) return;
    final requestId = _requestId;
    setState(() => _loadingMore = true);
    try {
      final page = await EntityReviewService.fetchMine(offset: _offset);
      if (!mounted || requestId != _requestId) return;
      final seen = _reviews.map((review) => review.id).toSet();
      setState(() {
        _offset += page.length;
        _reviews.addAll(page.where((review) => seen.add(review.id)));
        _hasMore = page.length >= EntityReviewService.pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      // 翻页失败只停住加载，已经看到的内容保持不变，滚动到底可再试。
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

  Future<void> _edit(EntityReview review) async {
    final draft = await showDialog<ReviewDraft>(
      context: context,
      builder: (_) => ReviewEditorDialog(
        title: '修改评价',
        reviewType: review.reviewType,
        trips: _trips,
        stationName: review.entityKey,
        initial: review,
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await EntityReviewService.update(
        review,
        rating: draft.rating,
        comment: draft.comment,
        tripId: draft.tripId,
        secondTripId: draft.secondTripId,
        transferMinutes: draft.transferMinutes,
        routeFromStation: draft.routeFromStation,
        routeToStation: draft.routeToStation,
        dish: draft.dish,
        price: draft.price,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(error))));
      }
      return;
    }
    await _reload();
  }

  Future<void> _delete(EntityReview review) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条评价？'),
        content: const Text('删除后无法恢复，别人给它的表情回应也会一并消失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await EntityReviewService.delete(review);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(error))));
      }
      return;
    }
    if (!mounted) return;
    // 就地移除，保住滚动位置与已加载的后续页；游标跟着退一格。
    setState(() {
      _reviews.removeWhere((item) => item.id == review.id);
      if (_offset > 0) _offset--;
    });
  }

  void _openTrip(EntityReview review, TripRecord trip) {
    Navigator.of(context).push(
      m3PageRoute(
        builder: (_) => TripRecordDetailsPage.public(
          ticketId: trip.ticketId ?? trip.id,
          onOwnerTap: () => Navigator.of(context).push(
            m3PageRoute(builder: (_) => PublicUserPage(userId: review.userId)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的评价')),
      body: AnimatedBuilder(
        animation: SessionService.instance,
        builder: (context, _) => SessionService.instance.isSignedIn
            ? RefreshIndicator(onRefresh: _reload, child: _buildList())
            : LoginRequiredView(
                message: '登录后可以查看自己发表过的评价。',
                icon: Icons.rate_review_outlined,
                onSignedIn: () {
                  _reload();
                  _loadTrips();
                },
              ),
      ),
    );
  }

  Widget _buildList() {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppSpacing.page,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppLayout.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildChildren(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildChildren() {
    if (_loading) return const [LinearProgressIndicator()];
    final error = _error;
    if (error != null) {
      return [
        _StatusCard(
          icon: Icons.cloud_off_outlined,
          message: '当前无法获取我的评价',
          hint: apiErrorMessage(error),
          onRetry: _reload,
        ),
      ];
    }
    if (_reviews.isEmpty) {
      return const [
        _StatusCard(icon: Icons.rate_review_outlined, message: '还没有发表过评价'),
      ];
    }
    return [
      for (var index = 0; index < _reviews.length; index++)
        EntityReviewCard(
          review: _reviews[index],
          trips: _trips,
          showTarget: true,
          showTripLinks: true,
          showDivider: index < _reviews.length - 1,
          contentPadding: EdgeInsets.fromLTRB(
            0,
            index == 0 ? 0 : 12,
            0,
            index < _reviews.length - 1 ? 14 : 4,
          ),
          onChanged: _reload,
          onEdit: () => _edit(_reviews[index]),
          onDelete: () => _delete(_reviews[index]),
          onTargetTap: () =>
              openEntityReviewTarget(context, _reviews[index]),
          onTripTap: (trip) => _openTrip(_reviews[index], trip),
        ),
      if (_loadingMore)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (!_hasMore)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(
              '没有更多了',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
    ];
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.message,
    this.hint,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final String? hint;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final hintText = hint;
    return Card.outlined(
      child: ListTile(
        leading: Icon(icon),
        title: Text(message),
        subtitle: hintText == null || hintText.isEmpty ? null : Text(hintText),
        trailing: onRetry == null
            ? null
            : IconButton(
                tooltip: '重试',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
              ),
      ),
    );
  }
}
