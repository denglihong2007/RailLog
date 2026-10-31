import 'package:flutter/material.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/dashboard_unlock_entry.dart';
import 'package:raillog/src/models/partner_advertisement.dart';
import 'package:raillog/src/models/public_user_dashboard.dart';
import 'package:raillog/src/models/railway_bureau.dart';
import 'package:raillog/src/models/trip_dashboard_stats.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/pages/all_trips_page.dart';
import 'package:raillog/src/pages/achievements_page.dart';
import 'package:raillog/src/pages/achievement_requirements_page.dart';
import 'package:raillog/src/pages/achievement_unlock_trips_page.dart';
import 'package:raillog/src/pages/auth_page.dart';
import 'package:raillog/src/pages/dashboard_unlocks_page.dart';
import 'package:raillog/src/pages/partner_applications_page.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/pages/trip_chart_page.dart';
import 'package:raillog/src/pages/trip_map_page.dart';
import 'package:raillog/src/services/cloud_sync_service.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/achievement_service.dart';
import 'package:raillog/src/services/entity_review_navigation.dart';
import 'package:raillog/src/services/entity_review_service.dart';
import 'package:raillog/src/pages/entity_detail_page.dart';
import 'package:raillog/src/services/partner_application_service.dart';
import 'package:raillog/src/services/public_user_service.dart';
import 'package:raillog/src/services/route_service.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/services/train_service.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/cached_avatar.dart';
import 'package:raillog/src/widgets/dashboard_achievement_card.dart';
import 'package:raillog/src/widgets/entity_review_card.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';
import 'package:raillog/src/widgets/user_level_badge.dart';

const _dashboardMaxWidth = 1200.0;
const _dashboardPreviewLimit = 6;
const _cloudSignInMessage = '登录并同步行程后即可查看。';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.refreshToken = 0});

  final int refreshToken;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<TripDashboardStats> _statsFuture;
  late Future<PartnerAdvertisement?> _advertisementFuture;
  Future<List<DashboardAchievement>>? _achievementsFuture;
  TripDashboardStats? _lastStats;
  bool _isResetting = false;

  // 「出行指南」的排序方式与分页游标。两类共用一个页码游标，
  // 切换排序方式时整段重来。
  TravelGuideMode _travelGuideMode = TravelGuideMode.hot;
  final List<EntityReview> _travelGuideReviews = [];
  bool _travelGuideLoading = false;
  bool _travelGuideLoadingMore = false;
  bool _travelGuideLoaded = false;
  bool _travelGuideHasMore = true;
  Object? _travelGuideError;
  int _travelGuideOffset = 0;
  int _travelGuideRequestId = 0;

  @override
  void initState() {
    super.initState();
    _statsFuture = DbHelper.instance.getDashboardStats();
    _advertisementFuture = _loadAdvertisement();
    if (SessionService.instance.isSignedIn) {
      _achievementsFuture = AchievementService.fetchCurrent();
      _loadTravelGuide();
    }
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
  }

  Future<PartnerAdvertisement?> _loadAdvertisement() async {
    try {
      return await PartnerApplicationService.fetchAdvertisement();
    } catch (_) {
      return null;
    }
  }

  /// 重新取「出行指南」的第一页。切换排序方式、下拉刷新、登录状态变化都走这里。
  Future<void> _loadTravelGuide() async {
    final requestId = ++_travelGuideRequestId;
    if (!SessionService.instance.isSignedIn) {
      setState(() {
        _travelGuideReviews.clear();
        _travelGuideOffset = 0;
        _travelGuideLoaded = false;
        _travelGuideLoading = false;
        _travelGuideError = null;
      });
      return;
    }
    setState(() {
      _travelGuideLoading = true;
      _travelGuideLoaded = false;
      _travelGuideError = null;
    });
    try {
      final page = await EntityReviewService.fetchTravelGuidePage(
        mode: _travelGuideMode,
      );
      if (!mounted || requestId != _travelGuideRequestId) return;
      setState(() {
        _travelGuideReviews
          ..clear()
          ..addAll(page);
        _travelGuideOffset = page.length;
        _travelGuideHasMore = page.length >= EntityReviewService.pageSize;
        _travelGuideLoading = false;
        _travelGuideLoaded = true;
      });
    } catch (error) {
      if (!mounted || requestId != _travelGuideRequestId) return;
      setState(() {
        _travelGuideError = error;
        _travelGuideLoading = false;
      });
    }
  }

  /// 主页滚到底时追加下一页。热门排序按反应数衰减打分，跨请求可能有细微抖动，
  /// 所以这里按 id 去重，避免同一条被追加两次。
  Future<void> _loadMoreTravelGuide() async {
    if (!SessionService.instance.isSignedIn ||
        _travelGuideLoading ||
        _travelGuideLoadingMore ||
        !_travelGuideLoaded ||
        !_travelGuideHasMore ||
        _travelGuideError != null) {
      return;
    }
    final requestId = _travelGuideRequestId;
    setState(() => _travelGuideLoadingMore = true);
    try {
      final page = await EntityReviewService.fetchTravelGuidePage(
        mode: _travelGuideMode,
        offset: _travelGuideOffset,
      );
      if (!mounted || requestId != _travelGuideRequestId) return;
      final seen = _travelGuideReviews.map((review) => review.id).toSet();
      setState(() {
        _travelGuideOffset += page.length;
        _travelGuideReviews.addAll(
          page.where((review) => seen.add(review.id)),
        );
        _travelGuideHasMore = page.length >= EntityReviewService.pageSize;
        _travelGuideLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || requestId != _travelGuideRequestId) return;
      // 翻页失败不清空已有内容，滚动到底可以再试。
      setState(() => _travelGuideLoadingMore = false);
    }
  }

  void _changeTravelGuideMode(TravelGuideMode mode) {
    if (mode == _travelGuideMode) return;
    setState(() {
      _travelGuideMode = mode;
      // 两种排序的内容互不相干，换挡时先清掉，免得旧排序的条目留在新排序下面。
      _travelGuideReviews.clear();
      _travelGuideOffset = 0;
      _travelGuideHasMore = true;
    });
    _loadTravelGuide();
  }

  /// 只替换被回应的那一条，不重拉列表。回应接口不返回新状态，本地按后端的
  /// 「每人每条评价至多一个表情」规则推算；列表长度不变，滚动位置也就不会跳。
  void _updateTravelGuideReactions(
    int reviewId,
    List<EntityReviewReaction> reactions,
  ) {
    final index = _travelGuideReviews.indexWhere(
      (review) => review.id == reviewId,
    );
    if (index < 0) return;
    setState(() {
      _travelGuideReviews[index] = _travelGuideReviews[index].withReactions(
        reactions,
      );
    });
  }

  bool _handleDashboardScroll(ScrollNotification notification) {
    if (notification.metrics.axis == Axis.vertical &&
        notification.metrics.extentAfter < 320) {
      _loadMoreTravelGuide();
    }
    return false;
  }

  Future<void> _refresh() async {
    final statsFuture = DbHelper.instance.getDashboardStats();
    final advertisementFuture = _loadAdvertisement();
    final achievementsFuture = SessionService.instance.isSignedIn
        ? AchievementService.fetchCurrent()
        : null;
    setState(() {
      _statsFuture = statsFuture;
      _advertisementFuture = advertisementFuture;
      _achievementsFuture = achievementsFuture;
    });
    final travelGuideFuture = _loadTravelGuide();
    await statsFuture;
    await advertisementFuture;
    if (achievementsFuture != null) {
      try {
        await achievementsFuture;
      } catch (_) {
        // The achievement section renders its own offline state.
      }
    }
    await travelGuideFuture;
  }

  Future<void> _confirmResetDatabase() async {
    final signedIn = SessionService.instance.isSignedIn;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重置本地数据库？'),
        content: Text(
          signedIn
              ? '将删除并重建本机数据库，本机缓存的行程与设置都会被清空。'
                    '已同步到云端的行程会在重置后自动拉回；'
                    '标记为仅本地、或从未同步的行程会永久丢失，无法恢复。'
              : '将删除并重建本机数据库，本机上的全部行程与设置都会被清空，'
                    '此操作无法撤销。未同步到云端的行程会永久丢失。',
        ),
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
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _resetLocalDatabase();
  }

  Future<void> _resetLocalDatabase() async {
    setState(() => _isResetting = true);
    try {
      await DbHelper.instance.resetDatabase();
      // The auth token lives in the same database, so re-seed it before syncing.
      // Without this the user is signed out, and the trips pulled back down carry
      // an owner_user_id that `getAllTrips` filters out while signed out.
      await SessionService.instance.persistCurrentSession();
      var restored = false;
      if (SessionService.instance.isSignedIn) {
        try {
          await CloudSyncService.instance.sync();
          restored = true;
        } on SessionException {
          // Offline or server-side failure: the trips come back on the next sync.
        }
      }
      if (!mounted) return;
      _lastStats = null;
      try {
        await _refresh();
      } catch (_) {
        // Keep the reset result; `_refresh` re-raises its own stats failure.
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            restored ? '本地数据库已重置，已从云端同步' : '本地数据库已重置',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('重置本地数据库失败：$error')));
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TripDashboardStats>(
      future: _statsFuture,
      initialData: _lastStats,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _HomeStatus(
            icon: Icons.error_outline,
            message: '读取行程数据失败',
            hint: SessionService.instance.isSignedIn
                ? '本地数据库可能已损坏。行程已同步到云端，重置后会自动拉回。'
                : '本地数据库可能已损坏。未同步到云端的行程会永久丢失。',
            actionLabel: '重试',
            onAction: _refresh,
            secondaryActionLabel: '重置本地数据库',
            onSecondaryAction: _confirmResetDatabase,
            isBusy: _isResetting,
          );
        }
        if (!snapshot.hasData) {
          return const _HomeStatus(isLoading: true, message: '正在汇总行程数据');
        }

        final stats = snapshot.data!;
        _lastStats = stats;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleDashboardScroll,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return _DashboardScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: _dashboardPadding(constraints),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          _PartnerAdvertisementLoader(
                            future: _advertisementFuture,
                          ),
                          M3AnimatedVisibility(
                            visible: !SessionService.instance.isSignedIn,
                            child: const Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: M3Reveal(child: _SignInBanner()),
                            ),
                          ),
                          M3Reveal(
                            child: _OverviewSection(
                              stats: stats,
                              onChanged: _refresh,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _StatsGrid(stats: stats, onChanged: _refresh),
                          const SizedBox(height: 24),
                          _AchievementsLoader(
                            future: _achievementsFuture,
                            signedIn: SessionService.instance.isSignedIn,
                            onRetry: _refresh,
                            onChanged: _refresh,
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                    _HomeTravelGuideSection(
                      signedIn: SessionService.instance.isSignedIn,
                      mode: _travelGuideMode,
                      reviews: _travelGuideReviews,
                      loading: _travelGuideLoading,
                      loadingMore: _travelGuideLoadingMore,
                      hasMore: _travelGuideHasMore,
                      error: _travelGuideError,
                      onModeChanged: _changeTravelGuideMode,
                      onRetry: _loadTravelGuide,
                      onReactionsChanged: _updateTravelGuideReactions,
                    ),
                    if (stats.tripCount == 0)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(top: 24),
                          child: M3Reveal(child: _EmptyStateCard()),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _PartnerAdvertisementLoader extends StatefulWidget {
  const _PartnerAdvertisementLoader({required this.future});

  final Future<PartnerAdvertisement?> future;

  @override
  State<_PartnerAdvertisementLoader> createState() =>
      _PartnerAdvertisementLoaderState();
}

class _PartnerAdvertisementLoaderState
    extends State<_PartnerAdvertisementLoader> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    return FutureBuilder<PartnerAdvertisement?>(
      future: widget.future,
      builder: (context, snapshot) {
        final advertisement = snapshot.data;
        if (advertisement == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: M3Reveal(
            child: _PartnerAdvertisementBanner(
              advertisement: advertisement,
              onClose: () => setState(() => _dismissed = true),
            ),
          ),
        );
      },
    );
  }
}

class _PartnerAdvertisementBanner extends StatelessWidget {
  const _PartnerAdvertisementBanner({
    required this.advertisement,
    required this.onClose,
  });

  final PartnerAdvertisement advertisement;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isAnnouncement = advertisement.isAnnouncement;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Icon(
              isAnnouncement ? Icons.campaign_outlined : Icons.apps_outlined,
              size: 20,
              color: colors.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isAnnouncement ? '系统公告' : '合作应用',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  advertisement.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          if (!isAnnouncement) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
    return AppCard.filled(
      color: colors.surfaceContainer,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Expanded(
            child: isAnnouncement
                ? content
                : InkWell(
                    onTap: () => Navigator.of(context).push(
                      m3PageRoute(
                        builder: (_) => const PartnerApplicationsPage(),
                      ),
                    ),
                    child: content,
                  ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: isAnnouncement ? '关闭公告' : '关闭广告',
            icon: const Icon(Icons.close),
            iconSize: 18,
            style: IconButton.styleFrom(
              foregroundColor: colors.onSurfaceVariant,
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class PublicUserPage extends StatefulWidget {
  const PublicUserPage({super.key, required this.userId});

  final String userId;

  @override
  State<PublicUserPage> createState() => _PublicUserPageState();
}

class _PublicUserPageState extends State<PublicUserPage> {
  late Future<PublicUserDashboard> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = PublicUserService.fetch(widget.userId);
  }

  Future<void> _refresh() async {
    final future = PublicUserService.fetch(widget.userId, forceRefresh: true);
    setState(() => _dashboardFuture = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('用户主页')),
      body: FutureBuilder<PublicUserDashboard>(
        future: _dashboardFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _HomeStatus(
              icon: Icons.error_outline,
              message: '读取用户主页失败',
              actionLabel: '重试',
              onAction: _refresh,
            );
          }
          if (!snapshot.hasData) {
            return const _HomeStatus(isLoading: true, message: '正在加载用户主页');
          }

          final dashboard = snapshot.data!;
          final stats = dashboard.stats;
          Future<bool?> openTrip(
            BuildContext context,
            DashboardTripEntry entry,
          ) => _openTrip(context, dashboard, entry);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return _DashboardScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: _dashboardPadding(constraints),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          _PublicProfileCard(user: dashboard.user),
                          const SizedBox(height: 24),
                          _OverviewSection(
                            stats: stats,
                            onChanged: _refresh,
                            openTrip: openTrip,
                            mapTrips: dashboard.trips,
                            subject: 'TA',
                            enableTripManagement: false,
                          ),
                          const SizedBox(height: 24),
                          _StatsGrid(
                            stats: stats,
                            onChanged: _refresh,
                            openTrip: openTrip,
                          ),
                          const SizedBox(height: 24),
                          _AchievementsSection(
                            achievements: dashboard.achievements,
                            onChanged: _refresh,
                            openTrip: openTrip,
                          ),
                          if (stats.tripCount == 0) ...[
                            const SizedBox(height: 24),
                            const _EmptyStateCard(),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<bool?> _openTrip(
    BuildContext context,
    PublicUserDashboard dashboard,
    DashboardTripEntry entry,
  ) {
    final ticketId = entry.ticketId;
    if (ticketId == null) return Future.value(false);
    return Navigator.of(context).push<bool>(
      m3PageRoute(
        builder: (_) => TripRecordDetailsPage.public(ticketId: ticketId),
      ),
    );
  }
}

/// 页面内容的左右内边距：窄屏按断点留白，宽屏把内容限制在 [_dashboardMaxWidth]
/// 以内并居中。原来靠 `Center + ConstrainedBox` 做，改成 sliver 列表后只能把
/// 「多出来的宽度」折算进内边距，否则每个条目都要单独包一层居中。
EdgeInsets _dashboardPadding(BoxConstraints constraints) {
  final pagePadding = switch (constraints.maxWidth) {
    < 600 => 16.0,
    < 840 => 24.0,
    _ => 32.0,
  };
  final horizontal = constraints.maxWidth - pagePadding * 2 > _dashboardMaxWidth
      ? (constraints.maxWidth - _dashboardMaxWidth) / 2
      : pagePadding;
  return EdgeInsets.fromLTRB(horizontal, 24, horizontal, 32);
}

class _DashboardScrollView extends StatelessWidget {
  const _DashboardScrollView({
    required this.slivers,
    required this.padding,
    this.physics,
  });

  final List<Widget> slivers;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: physics,
      slivers: [
        SliverPadding(
          padding: padding,
          sliver: SliverMainAxisGroup(slivers: slivers),
        ),
      ],
    );
  }
}

class _PublicProfileCard extends StatelessWidget {
  const _PublicProfileCard({required this.user});

  final PublicUser user;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bio = user.bio?.trim() ?? '';
    final displayBio = bio.isEmpty ? '这个人很懒，还没有个人简介~' : bio;
    final email = user.email?.trim() ?? '';
    return AppCard.outlined(
      color: colors.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PublicProfileAvatar(user: user, size: 64),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    UserLevelBadge(
                      experience: user.achievementExperience,
                      width: 30,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  displayBio,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.email_outlined,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          email,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicProfileAvatar extends StatelessWidget {
  const _PublicProfileAvatar({required this.user, required this.size});

  final PublicUser user;
  final double size;

  @override
  Widget build(BuildContext context) => CachedAvatar(
    name: user.displayName,
    imageUrl: user.avatarUrl,
    size: size,
    textStyle: Theme.of(context).textTheme.headlineSmall,
  );
}

class _AchievementsLoader extends StatelessWidget {
  const _AchievementsLoader({
    required this.future,
    required this.signedIn,
    required this.onRetry,
    required this.onChanged,
  });

  final Future<List<DashboardAchievement>>? future;
  final bool signedIn;
  final Future<void> Function() onRetry;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final achievementsFuture = future;
    if (!signedIn || achievementsFuture == null) {
      return const _AchievementServerStatus(
        icon: Icons.cloud_off_outlined,
        message: _cloudSignInMessage,
      );
    }
    return FutureBuilder<List<DashboardAchievement>>(
      future: achievementsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return _AchievementsSection(
            achievements: snapshot.data!,
            onChanged: onChanged,
          );
        }
        if (snapshot.hasError) {
          return _AchievementServerStatus(
            icon: Icons.cloud_off_outlined,
            message: '当前无法获取成就。请联网并完成行程同步后重试。',
            onRetry: onRetry,
          );
        }
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeading(title: '成就'),
            SizedBox(height: 12),
            LinearProgressIndicator(),
          ],
        );
      },
    );
  }
}

class _AchievementServerStatus extends StatelessWidget {
  const _AchievementServerStatus({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeading(title: '成就'),
        const SizedBox(height: 12),
        AppCard.outlined(
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
        ),
      ],
    );
  }
}

class _AchievementsSection extends StatelessWidget {
  const _AchievementsSection({
    required this.achievements,
    required this.onChanged,
    this.openTrip,
  });

  final List<DashboardAchievement> achievements;
  final Future<void> Function() onChanged;
  final TripEntryOpener? openTrip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionHeading(title: '成就')),
            TextButton.icon(
              onPressed: () => _openAllAchievements(context),
              icon: const Icon(Icons.arrow_forward, size: 18),
              iconAlignment: IconAlignment.end,
              label: const Text('查看更多'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = switch (constraints.maxWidth) {
              < 600 => 1,
              < 960 => 2,
              _ => 3,
            };
            return GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 132,
              ),
              itemCount: achievements.length > _dashboardPreviewLimit
                  ? _dashboardPreviewLimit
                  : achievements.length,
              itemBuilder: (context, index) => M3Reveal(
                delay: m3RevealDelay(index),
                distance: 8,
                child: DashboardAchievementCard(
                  key: ValueKey(achievements[index].id),
                  achievement: achievements[index],
                  // 与成就页保持一致：有子项先看达成要求，其余已解锁的进解锁行程。
                  onTap: achievements[index].hasRequirements
                      ? () => _openRequirements(context, achievements[index])
                      : achievements[index].unlockedBy != null
                      ? () => _openAchievement(context, achievements[index])
                      : null,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _openAllAchievements(BuildContext context) async {
    final changed = await Navigator.of(context).push<bool>(
      m3PageRoute(builder: (_) => AchievementsPage(achievements: achievements)),
    );
    if (changed == true) await onChanged();
  }

  Future<void> _openAchievement(
    BuildContext context,
    DashboardAchievement achievement,
  ) async {
    await Navigator.of(context).push(
      m3PageRoute(
        builder: (_) => AchievementUnlockTripsPage(
          achievementId: achievement.id,
          title: achievement.title,
        ),
      ),
    );
  }

  Future<void> _openRequirements(
    BuildContext context,
    DashboardAchievement achievement,
  ) async {
    await Navigator.of(context).push(
      m3PageRoute(
        builder: (_) => AchievementRequirementsPage(achievement: achievement),
      ),
    );
  }
}

class _HomeTravelGuideSection extends StatelessWidget {
  const _HomeTravelGuideSection({
    required this.signedIn,
    required this.mode,
    required this.reviews,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.error,
    required this.onModeChanged,
    required this.onRetry,
    required this.onReactionsChanged,
  });

  final bool signedIn;
  final TravelGuideMode mode;
  final List<EntityReview> reviews;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final Object? error;
  final ValueChanged<TravelGuideMode> onModeChanged;
  final Future<void> Function() onRetry;
  final void Function(int reviewId, List<EntityReviewReaction> reactions)
      onReactionsChanged;

  bool get _showList => signedIn && reviews.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TravelGuideHeader(mode: mode, onModeChanged: onModeChanged),
              const SizedBox(height: 12),
              if (!_showList) _buildStatus(context),
            ],
          ),
        ),
        if (_showList) ...[
          // 分页会一直往下追加。铺成一个 Column 时所有条目都留在树上，
          // 越往下滑要布局/绘制的内容越多，所以这里必须用懒构建的 SliverList。
          SliverList.builder(
            itemCount: reviews.length,
            itemBuilder: (context, index) {
              final review = reviews[index];
              final isLast = index == reviews.length - 1;
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
                  isLast ? 4 : 14,
                ),
                onChanged: onRetry,
                onReactionChanged: (reactions) =>
                    onReactionsChanged(review.id, reactions),
                onTargetTap: () => openEntityReviewTarget(context, review),
                onTripTap: (trip) => _openTrip(context, review, trip),
              );
            },
          ),
          SliverToBoxAdapter(child: _buildFooter(context)),
        ],
      ],
    );
  }

  Widget _buildStatus(BuildContext context) {
    if (!signedIn) {
      return const _HomeTravelGuideStatus(
        icon: Icons.cloud_off_outlined,
        message: _cloudSignInMessage,
      );
    }
    // 已经有内容时不因为刷新而清空，重载进度由下拉刷新自己的指示器表达。
    if (loading) return const LinearProgressIndicator();
    if (error != null) {
      return _HomeTravelGuideStatus(message: '当前无法获取出行指南', onRetry: onRetry);
    }
    return const _HomeTravelGuideStatus(message: '暂无出行指南');
  }

  Widget _buildFooter(BuildContext context) {
    if (loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (hasMore) return const SizedBox.shrink();
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

  void _openTrip(BuildContext context, EntityReview review, TripRecord trip) {
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
}

/// 「出行指南」的小标题与排序方式切换，两者并排一行。
/// 切换器右对齐，窄屏放不下时自己横向滚动，不会顶破标题。
class _TravelGuideHeader extends StatelessWidget {
  const _TravelGuideHeader({required this.mode, required this.onModeChanged});

  final TravelGuideMode mode;
  final ValueChanged<TravelGuideMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _SectionHeading(title: '出行指南'),
        const SizedBox(width: 12),
        // 标题按内容宽度，剩下的宽度全给切换器；reverse 让它在放得下时靠右。
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: SegmentedButton<TravelGuideMode>(
              showSelectedIcon: false,
              segments: [
                for (final option in TravelGuideMode.values)
                  ButtonSegment<TravelGuideMode>(
                    value: option,
                    label: Text(option.label),
                  ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) =>
                  onModeChanged(selection.first),
            ),
          ),
        ),
      ],
    );
  }
}

/// 出行指南的「没有内容 / 出错 / 未登录」提示条。标题行由 [_TravelGuideHeader] 负责。
class _HomeTravelGuideStatus extends StatelessWidget {
  const _HomeTravelGuideStatus({
    required this.message,
    this.icon = Icons.explore_outlined,
    this.onRetry,
  });

  final String message;
  final IconData icon;
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

class _SignInBanner extends StatelessWidget {
  const _SignInBanner();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard.filled(
      color: colors.secondaryContainer,
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: colors.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '尚未登录，当前行程仅保存在本机',
              style: TextStyle(color: colors.onSecondaryContainer),
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: colors.onSecondaryContainer,
            ),
            onPressed: () => Navigator.of(
              context,
            ).push(m3PageRoute(builder: (_) => const AuthPage())),
            icon: const Icon(Icons.login),
            label: const Text('登录'),
          ),
        ],
      ),
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.stats,
    required this.onChanged,
    this.openTrip,
    this.mapTrips,
    this.subject = '你',
    this.enableTripManagement = true,
  });

  final TripDashboardStats stats;
  final Future<void> Function() onChanged;
  final TripEntryOpener? openTrip;
  final List<TripRecord>? mapTrips;
  final String subject;
  final bool enableTripManagement;

  @override
  Widget build(BuildContext context) {
    Future<void> openAllTrips() async {
      final changed = await Navigator.of(context).push<bool>(
        m3PageRoute(
          builder: (context) => AllTripsPage(
            trips: stats.allTrips,
            openTrip: openTrip,
            enableSelection: enableTripManagement,
            enableGrouping: enableTripManagement,
          ),
        ),
      );
      if (changed == true) await onChanged();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionHeading(title: '铁路行程总览')),
            TextButton.icon(
              onPressed: stats.allTrips.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      m3PageRoute(
                        builder: (_) => TripChartPage(
                          trips: stats.allTrips,
                          openTrip: openTrip,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.show_chart, size: 18),
              label: const Text('趋势'),
            ),
            if (enableTripManagement || mapTrips != null)
              TextButton.icon(
                onPressed: stats.tripCount == 0
                    ? null
                    : () => Navigator.of(context).push<void>(
                        m3PageRoute(
                          builder: (_) => TripMapPage(trips: mapTrips),
                        ),
                      ),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('地图'),
              ),
            TextButton.icon(
              onPressed: stats.allTrips.isEmpty ? null : openAllTrips,
              icon: const Icon(Icons.format_list_bulleted, size: 18),
              label: const Text('全部'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _OverviewCard(stats: stats, subject: subject),
      ],
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.stats, required this.subject});

  final TripDashboardStats stats;
  final String subject;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dateRange = stats.firstRecordAt == null
        ? '添加行程后开始记录'
        : '${_formatDate(stats.firstRecordAt!)} 至 ${_formatDate(stats.lastRecordAt!)}';

    return AppCard.filled(
      color: colors.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$subject已累计出发 ${stats.tripCount} 次',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '记录时间：$dateRange',
            style: TextStyle(color: colors.onPrimaryContainer),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 380;
              return Column(
                children: [
                  SizedBox(height: isCompact ? 12 : 20),
                  Divider(
                    height: isCompact ? 1 : null,
                    color: colors.onPrimaryContainer.withValues(alpha: 0.24),
                  ),
                  SizedBox(height: isCompact ? 6 : 12),
                  _OverviewMetrics(stats: stats),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OverviewMetrics extends StatelessWidget {
  const _OverviewMetrics({required this.stats});

  final TripDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onPrimaryContainer;
    final metrics = [
      _OverviewMetric(
        label: '累计里程',
        value: _km(stats.totalMileage),
        description: '单次最长 ${_km(stats.maxMileage)}',
        icon: Icons.straighten_outlined,
      ),
      _OverviewMetric(
        label: '累计时长',
        value: _duration(stats.totalDuration),
        description: '单次最长 ${_duration(stats.maxDuration)}',
        icon: Icons.schedule_outlined,
      ),
      _OverviewMetric(
        label: '累计花费',
        value: _money(stats.totalCost),
        description: '单次最高 ${_money(stats.maxCost)}',
        icon: Icons.account_balance_wallet_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return _CompactOverviewMetrics(metrics: metrics);
        }
        return Row(
          children: [
            Expanded(child: metrics[0]),
            _OverviewMetricDivider(color: color),
            Expanded(child: metrics[1]),
            _OverviewMetricDivider(color: color),
            Expanded(child: metrics[2]),
          ],
        );
      },
    );
  }
}

class _CompactOverviewMetrics extends StatelessWidget {
  const _CompactOverviewMetrics({required this.metrics});

  final List<_OverviewMetric> metrics;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onPrimaryContainer;
    final theme = Theme.of(context).textTheme;

    return Table(
      columnWidths: const {
        0: FixedColumnWidth(74),
        1: FlexColumnWidth(4),
        2: FlexColumnWidth(5),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: metrics
          .map((metric) {
            return TableRow(
              children: [
                SizedBox(
                  height: 34,
                  child: Row(
                    children: [
                      Icon(metric.icon, size: 18, color: color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          metric.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.labelMedium?.copyWith(color: color),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    metric.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    metric.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.labelSmall?.copyWith(
                      color: color.withValues(alpha: 0.76),
                    ),
                  ),
                ),
              ],
            );
          })
          .toList(growable: false),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.label,
    required this.value,
    required this.description,
    required this.icon,
  });

  final String label;
  final String value;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onPrimaryContainer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: color),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color),
        ),
        const SizedBox(height: 2),
        Text(
          description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: color.withValues(alpha: 0.8)),
        ),
      ],
    );
  }
}

class _OverviewMetricDivider extends StatelessWidget {
  const _OverviewMetricDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: VerticalDivider(color: color.withValues(alpha: 0.24)),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.stats,
    required this.onChanged,
    this.openTrip,
  });
  final TripDashboardStats stats;
  final Future<void> Function() onChanged;
  final TripEntryOpener? openTrip;

  @override
  Widget build(BuildContext context) {
    final footprintCards = [
      _Metric(
        '走过线路',
        '${stats.routeCount}',
        '按经由线路去重',
        Icons.route_outlined,
        onTap: () => _showUnlocks(
          context,
          title: '走过线路',
          icon: Icons.route_outlined,
          entries: stats.routeUnlocks,
          allTrips: stats.allTrips,
          progressCatalog: RouteService.getRouteNames(),
          entityType: EntityType.route,
        ),
      ),
      _Metric(
        '坐过车次',
        '${stats.trainCount}',
        '按坐过车次去重',
        Icons.confirmation_number_outlined,
        onTap: () => _showUnlocks(
          context,
          title: '坐过车次',
          icon: Icons.confirmation_number_outlined,
          entries: stats.trainUnlocks,
          allTrips: stats.allTrips,
          showTrainNumber: false,
          entityType: EntityType.train,
        ),
      ),
      _Metric(
        '车型种类',
        '${stats.rollingStockCount}',
        '已记录的不同车型',
        Icons.train_outlined,
        onTap: () => _showUnlocks(
          context,
          title: '车型种类',
          icon: Icons.train_outlined,
          entries: stats.rollingStockUnlocks,
          allTrips: stats.allTrips,
          entityType: EntityType.rollingStock,
        ),
      ),
      _Metric(
        '承运单位',
        '${stats.companyCount}',
        '按担当公司去重',
        Icons.business_outlined,
        onTap: () => _showUnlocks(
          context,
          title: '承运单位',
          icon: Icons.business_outlined,
          entries: stats.companyUnlocks,
          allTrips: stats.allTrips,
          progressCatalog: Future.value(
            railwayBureauSegments.values
                .expand((companies) => companies)
                .toList(growable: false),
          ),
          entityType: EntityType.company,
        ),
      ),
      _Metric(
        '到访车站',
        '${stats.stationCount}',
        '始发、终到站去重',
        Icons.location_on_outlined,
        onTap: () => _showUnlocks(
          context,
          title: '到访车站',
          icon: Icons.location_on_outlined,
          entries: stats.stationUnlocks,
          allTrips: stats.allTrips,
          progressCatalog: RouteService.getStationNames(),
          entityType: EntityType.station,
        ),
      ),
      _Metric(
        '坐过路线',
        '${stats.routePairCount}',
        '按始发、终到站组合去重',
        Icons.alt_route_outlined,
        onTap: () => _showUnlocks(
          context,
          title: '坐过路线',
          icon: Icons.alt_route_outlined,
          entries: stats.routePairUnlocks,
          allTrips: stats.allTrips,
        ),
      ),
      _Metric(
        '到访城市',
        '${stats.cityCount}',
        '按车站对应城市去重',
        Icons.location_city_outlined,
        onTap: () => _showUnlocks(
          context,
          title: '到访城市',
          icon: Icons.location_city_outlined,
          entries: stats.cityUnlocks,
          allTrips: stats.allTrips,
          progressCatalog: TrainService.getCityNames(),
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeading(title: '铁路足迹'),
        const SizedBox(height: 12),
        _MetricGrid(cards: footprintCards),
      ],
    );
  }

  Future<void> _showUnlocks(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<DashboardUnlockEntry> entries,
    required List<DashboardTripEntry> allTrips,
    Future<List<String>>? progressCatalog,
    bool showTrainNumber = true,
    EntityType? entityType,
  }) async {
    final changed = await _openUnlocks(
      context,
      title: title,
      icon: icon,
      entries: entries,
      allTrips: allTrips,
      progressCatalog: progressCatalog,
      showTrainNumber: showTrainNumber,
      openTrip: openTrip,
      entityType: entityType,
    );
    if (changed == true) await onChanged();
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.cards});

  final List<_Metric> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _dashboardGridColumns(constraints.maxWidth);
        return GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 120,
          ),
          itemCount: cards.length,
          itemBuilder: (context, index) {
            return M3Reveal(
              delay: m3RevealDelay(index),
              distance: 8,
              child: _MetricCard(metric: cards[index]),
            );
          },
        );
      },
    );
  }
}

int _dashboardGridColumns(double width) => switch (width) {
  < 295 => 1,
  < 840 => 2,
  < 1120 => 3,
  _ => 4,
};

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        metric.value,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ),
                ),
                Text(
                  metric.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(metric.icon, color: colors.primary),
              if (metric.onTap != null)
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
            ],
          ),
        ],
      ),
    );

    return AppCard.filled(
      padding: EdgeInsets.zero,
      onTap: metric.onTap,
      child: content,
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard();

  @override
  Widget build(BuildContext context) {
    return AppCard.outlined(
      child: Row(
        children: [
          Icon(
            Icons.info_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Expanded(child: Text('还没有铁路行程记录。添加后，数据会自动汇总在这里。')),
        ],
      ),
    );
  }
}

class _HomeStatus extends StatelessWidget {
  const _HomeStatus({
    required this.message,
    this.icon,
    this.isLoading = false,
    this.actionLabel,
    this.onAction,
    this.hint,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.isBusy = false,
  });

  final String message;
  final IconData? icon;
  final bool isLoading;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final String? hint;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  /// Disables both actions and turns the secondary one into a progress spinner.
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const CircularProgressIndicator()
            else if (icon != null)
              Icon(icon, size: 32, color: colors.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: isBusy ? null : onAction,
                child: Text(actionLabel!),
              ),
            ],
            if (secondaryActionLabel != null && onSecondaryAction != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: isBusy ? null : onSecondaryAction,
                icon: isBusy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.settings_backup_restore),
                label: Text(secondaryActionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metric {
  const _Metric(
    this.label,
    this.value,
    this.description,
    this.icon, {
    this.onTap,
  });
  final String label;
  final String value;
  final String description;
  final IconData icon;
  final VoidCallback? onTap;
}

Future<bool?> _openUnlocks(
  BuildContext context, {
  required String title,
  required IconData icon,
  required List<DashboardUnlockEntry> entries,
  required List<DashboardTripEntry> allTrips,
  Future<List<String>>? progressCatalog,
  bool showTrainNumber = true,
  TripEntryOpener? openTrip,
  EntityType? entityType,
}) {
  return Navigator.of(context).push<bool>(
    m3PageRoute(
      builder: (context) => DashboardUnlocksPage(
        title: title,
        icon: icon,
        entries: entries,
        allTrips: allTrips,
        progressCatalog: progressCatalog,
        showTrainNumber: showTrainNumber,
        openTrip: openTrip,
        entityType: entityType,
      ),
    ),
  );
}

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _km(double value) => '${value.round()} km';
String _money(double value) => '¥${_number(value)}';

String _duration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  if (hours == 0) return '$minutes分';
  return minutes == 0 ? '$hours时' : '$hours时$minutes分';
}

String _number(double value) {
  final fixed = value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'(?=(\\d{3})+(?!\\d))'),
    (_) => ',',
  );
  return '$whole.${parts.last}';
}
