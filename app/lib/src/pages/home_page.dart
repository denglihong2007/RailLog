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
import 'package:raillog/src/pages/more_statistics_page.dart';
import 'package:raillog/src/pages/partner_applications_page.dart';
import 'package:raillog/src/pages/travel_guide_page.dart';
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
import 'package:raillog/src/services/trip_map_service.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/cached_avatar.dart';
import 'package:raillog/src/widgets/dashboard_achievement_card.dart';
import 'package:raillog/src/widgets/entity_review_card.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';
import 'package:raillog/src/widgets/user_level_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dashboardMaxWidth = 1200.0;
const _dashboardPreviewLimit = 6;

/// 页面左右留白的分档（逻辑像素，指本页内容区的宽度）。数值与主导航的
/// 600 / 840 对齐：侧栏形态切到哪一档，内容留白就在同一宽度跟上，不会出现
/// 「侧栏已经变成手机底栏、正文还按桌面留 32」的错位。
const _homeCompactBreakpoint = 600.0;
const _homeMediumBreakpoint = 840.0;

/// 网格里一张卡的最小可读宽度。足迹卡取 150：360dp 的手机页宽 311，正好排
/// 两列；再往上一点点，最常见的手机就会掉回单列。成就卡还要放徽章、标题、
/// 说明和底栏，因此下限高得多。
const _achievementCardMinWidth = 265.0;
const _metricCardMinWidth = 150.0;
const _dashboardGridSpacing = 12.0;

/// 足迹卡窄到这个宽度（正好是手机上并排两列时的一格），左右内边距从 16 收到
/// 12，让「同一线路只算一次」这类八字段说明不被省略号截断。
const _metricCardTightBreakpoint = 170.0;

/// 概览卡片里的三项累计：一项里最长的是「419 时 29 分」这类数值，约 110 宽，
/// 留出余量取 146；两条竖分隔线各占 16。三项放得下就并排，放不下改三行表格。
const _overviewMetricMinWidth = 146.0;
const _overviewMetricDividerWidth = 16.0;

/// 概览卡片窄到这个宽度，标题行与分隔线的上下留白收紧一档。
const _overviewCardTightBreakpoint = 380.0;

/// 区块标题行放不下三个「图标 + 文字」入口时，收成只有图标的按钮。
const _sectionActionsCompactBreakpoint = 420.0;

const _travelGuidePreviewLimit = 5;
const _dismissedBannerKey = 'home.dismissedBanner';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.refreshToken = 0, this.onAddTrip});

  final int refreshToken;

  /// 首次使用时的「添加第一段行程」入口，由主导航切到「添加行程」页。
  final VoidCallback? onAddTrip;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<TripDashboardStats> _statsFuture;
  late Future<PartnerAdvertisement?> _advertisementFuture;
  Future<List<DashboardAchievement>>? _achievementsFuture;
  TripDashboardStats? _lastStats;
  bool _isResetting = false;

  /// 主页只展示出行指南的少量预览，完整列表在 [TravelGuidePage]。
  final List<EntityReview> _travelGuidePreview = [];
  bool _travelGuideLoading = false;
  Object? _travelGuideError;
  int _travelGuideRequestId = 0;

  @override
  void initState() {
    super.initState();
    _statsFuture = DbHelper.instance.getDashboardStats();
    _advertisementFuture = _loadAdvertisement();
    if (SessionService.instance.isSignedIn) {
      _achievementsFuture = AchievementService.fetchCurrent();
      _loadTravelGuidePreview();
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

  /// 取首页「出行指南」的混排预览（热门 + 相关），只留前几条。
  Future<void> _loadTravelGuidePreview() async {
    final requestId = ++_travelGuideRequestId;
    if (!SessionService.instance.isSignedIn) {
      setState(() {
        _travelGuidePreview.clear();
        _travelGuideLoading = false;
        _travelGuideError = null;
      });
      return;
    }
    setState(() {
      _travelGuideLoading = true;
      _travelGuideError = null;
    });
    try {
      final page = await EntityReviewService.fetchHomeTravelGuide();
      if (!mounted || requestId != _travelGuideRequestId) return;
      setState(() {
        _travelGuidePreview
          ..clear()
          ..addAll(page.take(_travelGuidePreviewLimit));
        _travelGuideLoading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _travelGuideRequestId) return;
      setState(() {
        _travelGuideError = error;
        _travelGuideLoading = false;
      });
    }
  }

  /// 只替换被回应的那一条，不重拉列表。回应接口不返回新状态，本地按后端的
  /// 「每人每条评价至多一个表情」规则推算；列表长度不变，滚动位置也就不会跳。
  void _updateTravelGuideReactions(
    int reviewId,
    List<EntityReviewReaction> reactions,
  ) {
    final index = _travelGuidePreview.indexWhere(
      (review) => review.id == reviewId,
    );
    if (index < 0) return;
    setState(() {
      _travelGuidePreview[index] = _travelGuidePreview[index].withReactions(
        reactions,
      );
    });
  }

  /// 地图弹窗里点自己的行程：打开本地详情页，自己可以编辑/删除。
  Future<bool?> _openTripFromMap(BuildContext context, TripMapTripRef trip) {
    final tripId = trip.tripId;
    if (tripId == null) return Future.value(null);
    return Navigator.of(context).push<bool>(
      m3PageRoute(builder: (_) => TripRecordDetailsPage(tripId: tripId)),
    );
  }

  Future<void> _refresh() async {
    final statsFuture = DbHelper.instance.getDashboardStats();
    final advertisementFuture = _loadAdvertisement();
    final signedIn = SessionService.instance.isSignedIn;
    final achievementsFuture = signedIn
        ? AchievementService.fetchCurrent()
        : null;
    setState(() {
      _statsFuture = statsFuture;
      _advertisementFuture = advertisementFuture;
      _achievementsFuture = achievementsFuture;
    });
    final travelGuideFuture = signedIn
        ? _loadTravelGuidePreview()
        : Future<void>.value();
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

  /// 读取失败时，「重置数据库」不再和「重试」并排出现，而是收进这个高级入口。
  Future<void> _showAdvancedRecoveryOptions() async {
    final colors = Theme.of(context).colorScheme;
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('高级选项'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('重试后仍无法读取数据时，可以重置本地数据库。'),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.settings_backup_restore,
                color: colors.error,
              ),
              title: Text(
                '重置本地数据库',
                style: TextStyle(color: colors.error),
              ),
              subtitle: const Text('清空本机缓存与设置'),
              onTap: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    if (shouldReset == true && mounted) await _confirmResetDatabase();
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
            message: '读取本地行程失败',
            hint: '可能有其他程序正在占用数据库，请稍后重试。',
            actionLabel: '重试',
            onAction: _refresh,
            onAdvancedAction: _showAdvancedRecoveryOptions,
            isBusy: _isResetting,
          );
        }
        if (!snapshot.hasData) {
          return const _HomeStatus(isLoading: true, message: '正在汇总行程数据');
        }

        final stats = snapshot.data!;
        _lastStats = stats;
        final signedIn = SessionService.instance.isSignedIn;
        final isFirstRun = stats.tripCount == 0;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return _DashboardScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: _dashboardPadding(
                  constraints,
                  MediaQuery.paddingOf(context).bottom,
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        M3AnimatedVisibility(
                          visible: !signedIn,
                          child: const Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: M3Reveal(child: _SignInBanner()),
                          ),
                        ),
                        if (isFirstRun)
                          M3Reveal(
                            child: _FirstRunCard(onAddTrip: widget.onAddTrip),
                          )
                        else ...[
                          M3Reveal(
                            child: _OverviewSection(
                              stats: stats,
                              onChanged: _refresh,
                              openMapTrip: _openTripFromMap,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _StatsGrid(stats: stats, onChanged: _refresh),
                          const SizedBox(height: 24),
                          if (signedIn) ...[
                            _AchievementsLoader(
                              future: _achievementsFuture,
                              signedIn: signedIn,
                              onRetry: _refresh,
                              onChanged: _refresh,
                            ),
                            const SizedBox(height: 24),
                            _HomeTravelGuideSection(
                              reviews: _travelGuidePreview,
                              loading: _travelGuideLoading,
                              error: _travelGuideError,
                              onRetry: _loadTravelGuidePreview,
                              onReactionsChanged: _updateTravelGuideReactions,
                              onOpenAll: _openTravelGuide,
                            ),
                            const SizedBox(height: 24),
                          ],
                          _PartnerAdvertisementLoader(
                            future: _advertisementFuture,
                          ),
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
    );
  }

  Future<void> _openTravelGuide() async {
    await Navigator.of(
      context,
    ).push<void>(m3PageRoute(builder: (_) => const TravelGuidePage()));
    if (!mounted) return;
    await _loadTravelGuidePreview();
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
  /// 关闭过的那一条横幅的签名。同一广告/公告在下次启动时不再出现。
  String? _dismissedSignature;
  bool _preferencesLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadDismissedSignature();
  }

  Future<void> _loadDismissedSignature() async {
    String? saved;
    try {
      final preferences = await SharedPreferences.getInstance();
      saved = preferences.getString(_dismissedBannerKey);
    } catch (_) {
      // 读取失败就当作没关闭过，不能因此挡住横幅。
    }
    if (!mounted) return;
    setState(() {
      _dismissedSignature = saved;
      _preferencesLoaded = true;
    });
  }

  String _signature(PartnerAdvertisement advertisement) =>
      '${advertisement.isAnnouncement ? 'announcement' : 'partner'}:'
      '${advertisement.partnerId}:${advertisement.text}';

  Future<void> _dismiss(PartnerAdvertisement advertisement) async {
    final signature = _signature(advertisement);
    setState(() => _dismissedSignature = signature);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_dismissedBannerKey, signature);
    } catch (_) {
      // 只影响下次启动是否重现，忽略即可。
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_preferencesLoaded) return const SizedBox.shrink();
    return FutureBuilder<PartnerAdvertisement?>(
      future: widget.future,
      builder: (context, snapshot) {
        final advertisement = snapshot.data;
        if (advertisement == null) return const SizedBox.shrink();
        if (_signature(advertisement) == _dismissedSignature) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: M3Reveal(
            child: _PartnerAdvertisementBanner(
              advertisement: advertisement,
              onClose: () => _dismiss(advertisement),
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

  /// 地图弹窗里点 TA 的行程：只读的公开详情，不能编辑/删除。
  Future<bool?> _openTripFromMap(BuildContext context, TripMapTripRef trip) {
    final ticketId = trip.ticketId;
    if (ticketId == null) return Future.value(null);
    return Navigator.of(context).push<bool>(
      m3PageRoute(
        builder: (_) => TripRecordDetailsPage.public(ticketId: ticketId),
      ),
    );
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
                  padding: _dashboardPadding(
                    constraints,
                    MediaQuery.paddingOf(context).bottom,
                  ),
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
                            openMapTrip: _openTripFromMap,
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
                            const _PublicEmptyStateCard(),
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
EdgeInsets _dashboardPadding(BoxConstraints constraints, double bottomInset) {
  final pagePadding = switch (constraints.maxWidth) {
    < _homeCompactBreakpoint => 16.0,
    < _homeMediumBreakpoint => 24.0,
    _ => 32.0,
  };
  final horizontal = constraints.maxWidth - pagePadding * 2 > _dashboardMaxWidth
      ? (constraints.maxWidth - _dashboardMaxWidth) / 2
      : pagePadding;
  return EdgeInsets.fromLTRB(horizontal, 24, horizontal, 32 + bottomInset);
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
    // 未登录时整段隐藏：登录提示只在页面顶部的横幅出现一次。
    if (!signedIn || achievementsFuture == null) {
      return const SizedBox.shrink();
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
            message: '当前无法获取成就，请检查网络后重试。',
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
    // 预览只露前几张，所以按最近解锁排序：把「刚点亮的那几张」放在最前面。
    // 「查看全部」里仍是完整的分类视图，顺序不受影响。
    final ordered = sortAchievementsByLatestUnlock(achievements);
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
              label: const Text('查看全部'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = _dashboardGridColumns(
              constraints.maxWidth,
              minCardWidth: _achievementCardMinWidth,
            );
            return GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: _dashboardGridSpacing,
                crossAxisSpacing: _dashboardGridSpacing,
                mainAxisExtent: 132,
              ),
              itemCount: ordered.length > _dashboardPreviewLimit
                  ? _dashboardPreviewLimit
                  : ordered.length,
              itemBuilder: (context, index) => M3Reveal(
                delay: m3RevealDelay(index),
                distance: 8,
                child: DashboardAchievementCard(
                  key: ValueKey(ordered[index].id),
                  achievement: ordered[index],
                  // 与成就页保持一致：有子项先看达成要求，其余已解锁的进解锁行程。
                  onTap: ordered[index].hasRequirements
                      ? () => _openRequirements(context, ordered[index])
                      : ordered[index].unlockedBy != null
                      ? () => _openAchievement(context, ordered[index])
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

/// 主页上的出行指南只做少量预览，排序切换与翻页都在 [TravelGuidePage] 里。
class _HomeTravelGuideSection extends StatelessWidget {
  const _HomeTravelGuideSection({
    required this.reviews,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onReactionsChanged,
    required this.onOpenAll,
  });

  final List<EntityReview> reviews;
  final bool loading;
  final Object? error;
  final Future<void> Function() onRetry;
  final void Function(int reviewId, List<EntityReviewReaction> reactions)
      onReactionsChanged;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionHeading(title: '出行指南')),
            TextButton.icon(
              onPressed: reviews.isEmpty ? null : onOpenAll,
              icon: const Icon(Icons.arrow_forward, size: 18),
              iconAlignment: IconAlignment.end,
              label: const Text('查看全部'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (reviews.isEmpty)
          _buildStatus(context)
        else
          for (var index = 0; index < reviews.length; index++)
            _buildCard(context, reviews[index], index),
      ],
    );
  }

  Widget _buildCard(BuildContext context, EntityReview review, int index) {
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
        isLast ? 0 : 14,
      ),
      onChanged: onRetry,
      onReactionChanged: (reactions) =>
          onReactionsChanged(review.id, reactions),
      onTargetTap: () => openEntityReviewTarget(context, review),
      onTripTap: (trip) => _openTrip(context, review, trip),
    );
  }

  Widget _buildStatus(BuildContext context) {
    // 已经有内容时不因为刷新而清空，重载进度由下拉刷新自己的指示器表达。
    if (loading) return const LinearProgressIndicator();
    if (error != null) {
      return _HomeTravelGuideStatus(
        icon: Icons.cloud_off_outlined,
        message: '当前无法获取出行指南',
        onRetry: onRetry,
      );
    }
    return const _HomeTravelGuideStatus(message: '暂无出行指南');
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

/// 出行指南的「没有内容 / 出错」提示条。
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
              '尚未登录，行程仅保存在本机。登录后可同步并查看成就与出行指南。',
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
    this.openMapTrip,
    this.mapTrips,
    this.subject = '你',
    this.enableTripManagement = true,
  });

  final TripDashboardStats stats;
  final Future<void> Function() onChanged;
  final TripEntryOpener? openTrip;
  final TripMapTripOpener? openMapTrip;
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
        LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < _sectionActionsCompactBreakpoint;
            return Row(
              children: [
                const Expanded(child: _SectionHeading(title: '铁路行程总览')),
                _SectionAction(
                  compact: compact,
                  icon: Icons.show_chart,
                  label: '趋势',
                  tooltip: '里程趋势',
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
                ),
                if (enableTripManagement || mapTrips != null)
                  _SectionAction(
                    compact: compact,
                    icon: Icons.map_outlined,
                    label: '地图',
                    tooltip: '行程地图',
                    onPressed: stats.tripCount == 0
                        ? null
                        : () => Navigator.of(context).push<void>(
                            m3PageRoute(
                              builder: (_) => TripMapPage(
                                trips: mapTrips,
                                openTrip: openMapTrip,
                              ),
                            ),
                          ),
                  ),
                _SectionAction(
                  compact: compact,
                  icon: Icons.format_list_bulleted,
                  label: '全部',
                  tooltip: '全部行程',
                  onPressed: stats.allTrips.isEmpty ? null : openAllTrips,
                ),
              ],
            );
          },
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
            '$subject已累计出发 ${_group('${stats.tripCount}')} 次',
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
              final isCompact =
                  constraints.maxWidth < _overviewCardTightBreakpoint;
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
        if (constraints.maxWidth <
            _overviewMetricMinWidth * 3 + _overviewMetricDividerWidth * 2) {
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
      child: VerticalDivider(
        width: _overviewMetricDividerWidth,
        color: color.withValues(alpha: 0.24),
      ),
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
        '乘坐线路',
        '${stats.routeCount}',
        '同一线路只算一次',
        Icons.route_outlined,
        onTap: () => _showUnlocks(
          context,
          title: '乘坐线路',
          icon: Icons.route_outlined,
          entries: stats.routeUnlocks,
          allTrips: stats.allTrips,
          progressCatalog: RouteService.getRouteNames(),
          entityType: EntityType.route,
        ),
      ),
      _Metric(
        '乘坐车次',
        '${stats.trainCount}',
        '同一车次只算一次',
        Icons.confirmation_number_outlined,
        onTap: () => _showUnlocks(
          context,
          title: '乘坐车次',
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
        '记录过的不同车型',
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
        '不同的担当单位',
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
        '始发、终到站',
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
        '乘车区间',
        '${stats.routePairCount}',
        '始发、终到组合',
        Icons.alt_route_outlined,
        onTap: () => _showUnlocks(
          context,
          title: '乘车区间',
          icon: Icons.alt_route_outlined,
          entries: stats.routePairUnlocks,
          allTrips: stats.allTrips,
        ),
      ),
      _Metric(
        '到访城市',
        '${stats.cityCount}',
        '车站所在城市',
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
        LayoutBuilder(
          builder: (context, constraints) {
            // 这一行只有一个入口，手机上放得下文字，不必按三个入口的门槛收成图标。
            final compact = constraints.maxWidth < 240;
            return Row(
              children: [
                const Expanded(child: _SectionHeading(title: '铁路足迹')),
                _SectionAction(
                  compact: compact,
                  icon: Icons.query_stats,
                  label: '更多统计',
                  tooltip: '更多统计',
                  onPressed: stats.tripCount == 0
                      ? null
                      : () async {
                          final changed = await Navigator.of(context)
                              .push<bool>(
                                m3PageRoute(
                                  builder: (_) => MoreStatisticsPage(
                                    trips: stats.allTrips,
                                    openTrip: openTrip,
                                  ),
                                ),
                              );
                          if (changed == true) await onChanged();
                        },
                ),
              ],
            );
          },
        ),
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
    return Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// 区块标题行右侧的入口。放得下时是「图标 + 文字」，放不下时只留图标，
/// 含义交给 tooltip —— 三个带文字的按钮在 360 宽的屏上会把标题行挤爆。
class _SectionAction extends StatelessWidget {
  const _SectionAction({
    required this.compact,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final bool compact;
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.cards});

  final List<_Metric> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _dashboardGridColumns(
          constraints.maxWidth,
          minCardWidth: _metricCardMinWidth,
        );
        final compact =
            _dashboardCellWidth(constraints.maxWidth, columns) <
            _metricCardTightBreakpoint;
        return GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: _dashboardGridSpacing,
            crossAxisSpacing: _dashboardGridSpacing,
            mainAxisExtent: 120,
          ),
          itemCount: cards.length,
          itemBuilder: (context, index) {
            return M3Reveal(
              delay: m3RevealDelay(index),
              distance: 8,
              child: _MetricCard(metric: cards[index], compact: compact),
            );
          },
        );
      },
    );
  }
}

/// 主页两张网格共用的列数规则：一张卡至少要 [minCardWidth] 宽才排得下，
/// 宽度每多放得下一张卡就加一列。阈值不在两处各写一套死数字，而是由卡片的
/// 最小可读宽度推出来，信息更密的成就卡自然比足迹卡更早止步于少列。
int _dashboardGridColumns(double width, {required double minCardWidth}) {
  final columns =
      ((width + _dashboardGridSpacing) / (minCardWidth + _dashboardGridSpacing))
          .floor();
  return columns.clamp(1, 4);
}

/// 网格里一格算上间距后的宽度，卡片据此决定内边距收不收。
double _dashboardCellWidth(double width, int columns) =>
    (width - _dashboardGridSpacing * (columns - 1)) / columns;

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric, this.compact = false});

  final _Metric metric;

  /// 一格里放不下常规内边距时收紧到 12，说明文字才不会被省略号吃掉。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final content = Padding(
      padding: EdgeInsets.all(compact ? 12 : 16),
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

/// 没有任何铁路行程时的首屏。只保留一件事：去添加第一段行程。
class _FirstRunCard extends StatelessWidget {
  const _FirstRunCard({this.onAddTrip});

  final VoidCallback? onAddTrip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard.filled(
      color: colors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.train_outlined,
                size: 32,
                color: colors.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有铁路行程记录',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '添加第一段行程后，里程、车站、车次和成就会自动汇总在这里。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (onAddTrip != null) ...[
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: onAddTrip,
                icon: const Icon(Icons.add),
                label: const Text('添加第一段行程'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 别人主页上「没有行程」的提示，不给出添加入口。
class _PublicEmptyStateCard extends StatelessWidget {
  const _PublicEmptyStateCard();

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
          const Expanded(child: Text('TA 还没有铁路行程记录。')),
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
    this.onAdvancedAction,
    this.isBusy = false,
  });

  final String message;
  final IconData? icon;
  final bool isLoading;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final String? hint;

  /// 破坏性/低频的恢复手段收在这一层后面，不和「重试」并列。
  final VoidCallback? onAdvancedAction;

  /// Disables both actions while a recovery operation is running.
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
            if (onAdvancedAction != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: isBusy ? null : onAdvancedAction,
                child: const Text('高级选项'),
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

String _km(double value) => '${_group(value.round().toString())} km';
String _money(double value) => '¥${_number(value)}';

String _duration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  if (hours == 0) return '$minutes 分';
  return minutes == 0 ? '$hours 时' : '$hours 时 $minutes 分';
}

String _number(double value) {
  final parts = value.toStringAsFixed(2).split('.');
  return '${_group(parts.first)}.${parts.last}';
}

/// 千分位。数字一长，「48039」和「15140.50」都要眯眼数位数。
String _group(String digits) {
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}
