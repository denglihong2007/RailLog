import 'package:flutter/material.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/services/entity_review_navigation.dart';
import 'package:raillog/src/services/entity_review_service.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/entity_review_card.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

/// 「出行指南」完整列表。主页只预览前几条，排序切换与翻页都在这里。
class TravelGuidePage extends StatefulWidget {
  const TravelGuidePage({super.key});

  @override
  State<TravelGuidePage> createState() => _TravelGuidePageState();
}

class _TravelGuidePageState extends State<TravelGuidePage> {
  TravelGuideMode _mode = TravelGuideMode.hot;
  final List<EntityReview> _reviews = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _loaded = false;
  bool _hasMore = true;
  Object? _error;
  int _offset = 0;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _loaded = false;
      _error = null;
    });
    try {
      final page = await EntityReviewService.fetchTravelGuidePage(mode: _mode);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _reviews
          ..clear()
          ..addAll(page);
        _offset = page.length;
        _hasMore = page.length >= EntityReviewService.pageSize;
        _loading = false;
        _loaded = true;
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
    if (_loading ||
        _loadingMore ||
        !_loaded ||
        !_hasMore ||
        _error != null) {
      return;
    }
    final requestId = _requestId;
    setState(() => _loadingMore = true);
    try {
      final page = await EntityReviewService.fetchTravelGuidePage(
        mode: _mode,
        offset: _offset,
      );
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
      // 翻页失败不清空已有内容，滚动到底可以再试。
      setState(() => _loadingMore = false);
    }
  }

  void _changeMode(TravelGuideMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      // 两种排序的内容互不相干，换挡时先清掉，免得旧排序的条目留在新排序下面。
      _reviews.clear();
      _offset = 0;
      _hasMore = true;
    });
    _load();
  }

  /// 只替换被回应的那一条，不重拉列表。
  void _updateReactions(int reviewId, List<EntityReviewReaction> reactions) {
    final index = _reviews.indexWhere((review) => review.id == reviewId);
    if (index < 0) return;
    setState(() {
      _reviews[index] = _reviews[index].withReactions(reactions);
    });
  }

  bool _handleScroll(ScrollNotification notification) {
    if (notification.metrics.axis == Axis.vertical &&
        notification.metrics.extentAfter < 320) {
      _loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('出行指南')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.wideContentMaxWidth,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<TravelGuideMode>(
                    showSelectedIcon: false,
                    segments: [
                      for (final option in TravelGuideMode.values)
                        ButtonSegment<TravelGuideMode>(
                          value: option,
                          label: Text(option.label),
                        ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (selection) =>
                        _changeMode(selection.first),
                  ),
                ),
              ),
              Expanded(child: _buildBody(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _reviews.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _reviews.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _StatusCard(
            icon: Icons.cloud_off_outlined,
            message: '当前无法获取出行指南',
            onRetry: _load,
          ),
        ],
      );
    }
    if (_loaded && _reviews.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: const [
          _StatusCard(icon: Icons.explore_outlined, message: '暂无出行指南'),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScroll,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: _reviews.length + 1,
          itemBuilder: (context, index) {
            if (index == _reviews.length) return _buildFooter(context);
            final review = _reviews[index];
            final isLast = index == _reviews.length - 1;
            return EntityReviewCard(
              key: ValueKey(review.id),
              review: review,
              showTarget: true,
              showTripLinks: true,
              showDivider: !isLast,
              contentPadding: EdgeInsets.fromLTRB(
                0,
                index == 0 ? 0 : 12,
                0,
                isLast ? 0 : 14,
              ),
              onChanged: _load,
              onReactionChanged: (reactions) =>
                  _updateReactions(review.id, reactions),
              onTargetTap: () => openEntityReviewTarget(context, review),
              onTripTap: (trip) => _openTrip(context, trip),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          '没有更多了',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  void _openTrip(BuildContext context, TripRecord trip) {
    Navigator.of(context).push(
      m3PageRoute(
        builder: (_) =>
            TripRecordDetailsPage.public(ticketId: trip.ticketId ?? trip.id),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard.outlined(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon),
        title: Text(message),
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
