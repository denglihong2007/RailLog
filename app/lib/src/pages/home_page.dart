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
import 'package:raillog/src/pages/achievement_unlock_trips_page.dart';
import 'package:raillog/src/pages/auth_page.dart';
import 'package:raillog/src/pages/dashboard_unlocks_page.dart';
import 'package:raillog/src/pages/partner_applications_page.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/pages/trip_chart_page.dart';
import 'package:raillog/src/pages/trip_map_page.dart';
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
import 'package:raillog/src/widgets/cached_avatar.dart';
import 'package:raillog/src/widgets/dashboard_achievement_card.dart';
import 'package:raillog/src/widgets/entity_review_card.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';
import 'package:raillog/src/widgets/user_level_badge.dart';

const _dashboardMaxWidth = 1200.0;
const _cardRadius = 8.0;
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
  Future<List<EntityReview>>? _travelGuideFuture;
  TripDashboardStats? _lastStats;

  @override
  void initState() {
    super.initState();
    _statsFuture = DbHelper.instance.getDashboardStats();
    _advertisementFuture = _loadAdvertisement();
    if (SessionService.instance.isSignedIn) {
      _achievementsFuture = AchievementService.fetchCurrent();
      _travelGuideFuture = EntityReviewService.fetchHomeTravelGuide();
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

  Future<void> _refresh() async {
    final statsFuture = DbHelper.instance.getDashboardStats();
    final advertisementFuture = _loadAdvertisement();
    final achievementsFuture = SessionService.instance.isSignedIn
        ? AchievementService.fetchCurrent()
        : null;
    final travelGuideFuture = SessionService.instance.isSignedIn
        ? EntityReviewService.fetchHomeTravelGuide()
        : null;
    setState(() {
      _statsFuture = statsFuture;
      _advertisementFuture = advertisementFuture;
      _achievementsFuture = achievementsFuture;
      _travelGuideFuture = travelGuideFuture;
    });
    await statsFuture;
    await advertisementFuture;
    if (achievementsFuture != null) {
      try {
        await achievementsFuture;
      } catch (_) {
        // The achievement section renders its own offline state.
      }
    }
    if (travelGuideFuture != null) {
      try {
        await travelGuideFuture;
      } catch (_) {
        // The travel guide section renders its own retry state.
      }
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
            actionLabel: '重试',
            onAction: _refresh,
          );
        }
        if (!snapshot.hasData) {
          return const _HomeStatus(isLoading: true, message: '正在汇总行程数据');
        }

        final stats = snapshot.data!;
        _lastStats = stats;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final pagePadding = switch (constraints.maxWidth) {
                < 600 => 16.0,
                < 840 => 24.0,
                _ => 32.0,
              };
              return _DashboardScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(pagePadding, 24, pagePadding, 32),
                children: [
                  _PartnerAdvertisementLoader(future: _advertisementFuture),
                  if (!SessionService.instance.isSignedIn) ...[
                    const M3Reveal(child: _SignInBanner()),
                    const SizedBox(height: 16),
                  ],
                  M3Reveal(
                    child: _OverviewSection(stats: stats, onChanged: _refresh),
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
                  _HomeTravelGuideLoader(
                    future: _travelGuideFuture,
                    signedIn: SessionService.instance.isSignedIn,
                    onRetry: _refresh,
                  ),
                  if (stats.tripCount == 0) ...[
                    const SizedBox(height: 24),
                    const M3Reveal(child: _EmptyStateCard()),
                  ],
                ],
              );
            },
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
    return Card.filled(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                m3PageRoute(builder: (_) => const PartnerApplicationsPage()),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: BorderRadius.circular(_cardRadius),
                      ),
                      child: Icon(
                        Icons.campaign_outlined,
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
                            '合作应用',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            advertisement.text,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  letterSpacing: 0,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: '关闭广告',
            icon: const Icon(Icons.close),
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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
    final future = PublicUserService.fetch(widget.userId);
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
          final stats = TripDashboardStats.fromTrips(dashboard.trips);
          Future<bool?> openTrip(
            BuildContext context,
            DashboardTripEntry entry,
          ) => _openTrip(context, dashboard, entry);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final pagePadding = switch (constraints.maxWidth) {
                  < 600 => 16.0,
                  < 840 => 24.0,
                  _ => 32.0,
                };
                return _DashboardScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    pagePadding,
                    24,
                    pagePadding,
                    32,
                  ),
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

class _DashboardScrollView extends StatelessWidget {
  const _DashboardScrollView({
    required this.children,
    required this.padding,
    this.physics,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: physics,
      slivers: [
        SliverPadding(
          padding: padding,
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _dashboardMaxWidth),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(children: children),
                ),
              ),
            ),
          ),
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
    return Card.outlined(
      margin: EdgeInsets.zero,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
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
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
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
        Card.outlined(
          margin: EdgeInsets.zero,
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
                mainAxisExtent: 120,
              ),
              itemCount: achievements.length > _dashboardPreviewLimit
                  ? _dashboardPreviewLimit
                  : achievements.length,
              itemBuilder: (context, index) => M3Reveal(
                duration: Duration(milliseconds: 620 + index * 45),
                distance: 8,
                child: DashboardAchievementCard(
                  achievement: achievements[index],
                  onTap: achievements[index].unlockedBy == null
                      ? null
                      : () => _openAchievement(context, achievements[index]),
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
}

class _HomeTravelGuideLoader extends StatelessWidget {
  const _HomeTravelGuideLoader({
    required this.future,
    required this.signedIn,
    required this.onRetry,
  });

  final Future<List<EntityReview>>? future;
  final bool signedIn;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final travelGuideFuture = future;
    if (!signedIn || travelGuideFuture == null) {
      return const _HomeTravelGuideStatus(
        icon: Icons.cloud_off_outlined,
        message: _cloudSignInMessage,
      );
    }
    return FutureBuilder<List<EntityReview>>(
      future: travelGuideFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return _HomeTravelGuideSection(
            reviews: snapshot.data!,
            onChanged: onRetry,
          );
        }
        if (snapshot.hasError) {
          return _HomeTravelGuideStatus(
            message: '当前无法获取出行指南',
            onRetry: onRetry,
          );
        }
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeading(title: '出行指南'),
            SizedBox(height: 12),
            LinearProgressIndicator(),
          ],
        );
      },
    );
  }
}

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeading(title: '出行指南'),
        const SizedBox(height: 12),
        Card.outlined(
          margin: EdgeInsets.zero,
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

class _HomeTravelGuideSection extends StatelessWidget {
  const _HomeTravelGuideSection({
    required this.reviews,
    required this.onChanged,
  });

  final List<EntityReview> reviews;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    if (reviews.isEmpty) {
      return const _HomeTravelGuideStatus(message: '暂无出行指南');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeading(title: '出行指南'),
        const SizedBox(height: 12),
        Column(
          children: [
            for (var index = 0; index < reviews.length; index++)
              EntityReviewCard(
                review: reviews[index],
                showTarget: true,
                showTripLinks: true,
                showDivider: index < reviews.length - 1,
                contentPadding: EdgeInsets.fromLTRB(
                  0,
                  index == 0 ? 0 : 12,
                  0,
                  index < reviews.length - 1 ? 14 : 4,
                ),
                onChanged: onChanged,
                onTargetTap: () =>
                    openEntityReviewTarget(context, reviews[index]),
                onTripTap: (trip) => _openTrip(context, reviews[index], trip),
              ),
          ],
        ),
      ],
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

class _SignInBanner extends StatelessWidget {
  const _SignInBanner();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: colors.secondaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
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

    return Card.filled(
      margin: EdgeInsets.zero,
      color: colors.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$subject已累计出发 ${stats.tripCount} 次',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w700,
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
        if (constraints.maxWidth < 380) {
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
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
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
              duration: Duration(milliseconds: 260 + index * 45),
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
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
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

    return Card.filled(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: metric.onTap == null
          ? content
          : Semantics(
              button: true,
              child: InkWell(onTap: metric.onTap, child: content),
            ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard();

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
  });

  final String message;
  final IconData? icon;
  final bool isLoading;
  final String? actionLabel;
  final Future<void> Function()? onAction;

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
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
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
