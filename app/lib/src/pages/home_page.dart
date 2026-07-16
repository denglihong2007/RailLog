import 'package:flutter/material.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/dashboard_unlock_entry.dart';
import 'package:raillog/src/models/online_intersection.dart';
import 'package:raillog/src/models/public_user_dashboard.dart';
import 'package:raillog/src/models/trip_dashboard_stats.dart';
import 'package:raillog/src/pages/all_trips_page.dart';
import 'package:raillog/src/pages/achievements_page.dart';
import 'package:raillog/src/pages/auth_page.dart';
import 'package:raillog/src/pages/dashboard_unlocks_page.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/pages/trip_chart_page.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/intersection_service.dart';
import 'package:raillog/src/services/public_user_service.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';
import 'package:raillog/src/widgets/dashboard_achievement_card.dart';

const _dashboardMaxWidth = 1200.0;
const _cardRadius = 8.0;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<TripDashboardStats> _statsFuture;
  late Future<List<OnlineIntersection>> _intersectionsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = DbHelper.instance.getDashboardStats();
    _intersectionsFuture = IntersectionService.fetch();
  }

  Future<void> _refresh() async {
    final statsFuture = DbHelper.instance.getDashboardStats();
    final intersectionsFuture = IntersectionService.fetch();
    setState(() {
      _statsFuture = statsFuture;
      _intersectionsFuture = intersectionsFuture;
    });
    await statsFuture;
    try {
      await intersectionsFuture;
    } on IntersectionException {
      // The online section renders its own retry state.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TripDashboardStats>(
      future: _statsFuture,
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
        return RefreshIndicator(
          onRefresh: _refresh,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final pagePadding = switch (constraints.maxWidth) {
                < 600 => 16.0,
                < 840 => 24.0,
                _ => 32.0,
              };
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(pagePadding, 24, pagePadding, 32),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _dashboardMaxWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!SessionService.instance.isSignedIn) ...[
                            const M3Reveal(child: _SignInBanner()),
                            const SizedBox(height: 16),
                          ],
                          M3Reveal(
                            child: _OverviewSection(
                              stats: stats,
                              onChanged: _refresh,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _StatsGrid(stats: stats, onChanged: _refresh),
                          const SizedBox(height: 24),
                          _AchievementsSection(
                            achievements: stats.achievements,
                            onChanged: _refresh,
                          ),
                          if (stats.tripCount == 0) ...[
                            const SizedBox(height: 24),
                            const M3Reveal(child: _EmptyStateCard()),
                          ],
                          if (SessionService.instance.isSignedIn) ...[
                            const SizedBox(height: 24),
                            _OnlineIntersectionsSection(
                              future: _intersectionsFuture,
                              onRetry: _refresh,
                            ),
                          ],
                        ],
                      ),
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
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    pagePadding,
                    24,
                    pagePadding,
                    32,
                  ),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: _dashboardMaxWidth,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _PublicProfileCard(user: dashboard.user),
                            const SizedBox(height: 24),
                            _OverviewSection(
                              stats: stats,
                              onChanged: _refresh,
                              openTrip: openTrip,
                              subject: 'TA',
                            ),
                            const SizedBox(height: 24),
                            _StatsGrid(
                              stats: stats,
                              onChanged: _refresh,
                              openTrip: openTrip,
                            ),
                            const SizedBox(height: 24),
                            _AchievementsSection(
                              achievements: stats.achievements,
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
                  Text(
                    user.displayName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
  Widget build(BuildContext context) {
    final url = user.avatarUrl?.trim() ?? '';
    final fallback = Center(
      child: Text(
        user.displayName.isEmpty ? '?' : user.displayName[0].toUpperCase(),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    );
    return ClipOval(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: SizedBox.square(
          dimension: size,
          child: url.isEmpty
              ? fallback
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

class _OnlineIntersectionsSection extends StatelessWidget {
  const _OnlineIntersectionsSection({
    required this.future,
    required this.onRetry,
  });

  final Future<List<OnlineIntersection>> future;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeading(title: '同行交集'),
        const SizedBox(height: 12),
        FutureBuilder<List<OnlineIntersection>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            if (snapshot.hasError) {
              return Card.outlined(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: const Text('同行交集暂不可用'),
                  subtitle: Text('${snapshot.error}'),
                  trailing: IconButton(
                    tooltip: '重新加载',
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              );
            }
            final intersections = snapshot.data ?? const [];
            if (intersections.isEmpty) {
              return const Card.outlined(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(Icons.people_outline),
                  title: Text('暂未发现同行交集'),
                ),
              );
            }
            final stationIntersections = intersections
                .where((item) => item.kind == OnlineIntersectionKind.station)
                .toList(growable: false);
            final trainIntersections = intersections
                .where((item) => item.kind == OnlineIntersectionKind.train)
                .toList(growable: false);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (stationIntersections.isNotEmpty) ...[
                  Text('车站交集', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _IntersectionCardWrap(intersections: stationIntersections),
                ],
                if (stationIntersections.isNotEmpty &&
                    trainIntersections.isNotEmpty)
                  const SizedBox(height: 20),
                if (trainIntersections.isNotEmpty) ...[
                  Text('车次交集', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _IntersectionCardWrap(intersections: trainIntersections),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _IntersectionCardWrap extends StatelessWidget {
  const _IntersectionCardWrap({required this.intersections});

  final List<OnlineIntersection> intersections;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final cardWidth = constraints.maxWidth >= 840
            ? (constraints.maxWidth - gap) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: intersections
              .map(
                (intersection) => SizedBox(
                  width: cardWidth,
                  child: _IntersectionCard(intersection: intersection),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _IntersectionCard extends StatelessWidget {
  const _IntersectionCard({required this.intersection});

  final OnlineIntersection intersection;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isStation = intersection.kind == OnlineIntersectionKind.station;
    return Card.filled(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isStation ? Icons.location_on_outlined : Icons.train_outlined,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    intersection.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${intersection.intersectionCount} 条交集',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: colors.primary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('交集', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            _IntersectionAvatarList(trips: intersection.trips),
          ],
        ),
      ),
    );
  }
}

class _IntersectionAvatarList extends StatefulWidget {
  const _IntersectionAvatarList({required this.trips});

  final List<IntersectionTrip> trips;

  @override
  State<_IntersectionAvatarList> createState() =>
      _IntersectionAvatarListState();
}

class _IntersectionAvatarListState extends State<_IntersectionAvatarList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 104),
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        interactive: true,
        child: SingleChildScrollView(
          controller: _scrollController,
          primary: false,
          padding: const EdgeInsets.only(right: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.trips
                .map((trip) => _IntersectionAvatar(trip: trip))
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}

class _IntersectionAvatar extends StatelessWidget {
  const _IntersectionAvatar({required this.trip});

  final IntersectionTrip trip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final url = trip.avatarUrl?.trim() ?? '';
    final fallback = Center(
      child: Text(
        trip.displayName.isEmpty ? '?' : trip.displayName[0].toUpperCase(),
      ),
    );
    return Tooltip(
      message:
          '${trip.displayName} · ${_formatDate(trip.occurredAt)} · ${_trainLabel(trip.trainNumber)}',
      child: Semantics(
        button: true,
        label: '${trip.displayName}的交集行程',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.of(context).push(
            m3PageRoute(
              builder: (_) => TripRecordDetailsPage.public(
                ticketId: trip.ticketId,
                onOwnerTap: () => Navigator.of(context).push(
                  m3PageRoute(
                    builder: (_) => PublicUserPage(userId: trip.userId),
                  ),
                ),
              ),
            ),
          ),
          child: Container(
            width: 48,
            height: 48,
            padding: EdgeInsets.all(trip.isStrict ? 2 : 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: trip.isStrict ? colors.primary : colors.outlineVariant,
                width: trip.isStrict ? 3 : 1,
              ),
            ),
            child: ClipOval(
              child: ColoredBox(
                color: colors.secondaryContainer,
                child: url.isEmpty
                    ? fallback
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => fallback,
                      ),
              ),
            ),
          ),
        ),
      ),
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
              itemCount: achievements.length > 9 ? 9 : achievements.length,
              itemBuilder: (context, index) => M3Reveal(
                duration: Duration(milliseconds: 620 + index * 45),
                distance: 8,
                child: DashboardAchievementCard(
                  achievement: achievements[index],
                  onTap: achievements[index].unlockedBy == null
                      ? null
                      : () => _openAchievement(
                          context,
                          achievements[index].unlockedBy!,
                        ),
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
      m3PageRoute(
        builder: (_) =>
            AchievementsPage(achievements: achievements, openTrip: openTrip),
      ),
    );
    if (changed == true) await onChanged();
  }

  Future<void> _openAchievement(
    BuildContext context,
    DashboardTripEntry trip,
  ) async {
    final changed = openTrip == null
        ? await Navigator.of(context).push<bool>(
            m3PageRoute(builder: (_) => TripRecordDetailsPage(tripId: trip.id)),
          )
        : await openTrip!(context, trip);
    if (changed == true) await onChanged();
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
    this.subject = '你',
  });

  final TripDashboardStats stats;
  final Future<void> Function() onChanged;
  final TripEntryOpener? openTrip;
  final String subject;

  @override
  Widget build(BuildContext context) {
    Future<void> openAllTrips() async {
      final changed = await Navigator.of(context).push<bool>(
        m3PageRoute(
          builder: (context) =>
              AllTripsPage(trips: stats.allTrips, openTrip: openTrip),
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
                        builder: (_) => TripChartPage(trips: stats.allTrips),
                      ),
                    ),
              icon: const Icon(Icons.show_chart, size: 18),
              label: const Text('趋势'),
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
          ],
        ),
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
    final summaryCards = [
      _Metric(
        '累计花费',
        _money(stats.totalCost),
        '单次最高 ${_money(stats.maxCost)}',
        Icons.account_balance_wallet_outlined,
      ),
      _Metric(
        '累计里程',
        _km(stats.totalMileage),
        '单次最长 ${_km(stats.maxMileage)}',
        Icons.straighten_outlined,
      ),
      _Metric(
        '累计时长',
        _duration(stats.totalDuration),
        '最长 ${_duration(stats.maxDuration)}',
        Icons.schedule_outlined,
      ),
    ];
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
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeading(title: '行程累计'),
        const SizedBox(height: 12),
        _MetricGrid(cards: summaryCards),
        const SizedBox(height: 24),
        const _SectionHeading(title: '铁路足迹'),
        const SizedBox(height: 12),
        _MetricGrid(cards: footprintCards, animationOffset: 3),
      ],
    );
  }

  Future<void> _showUnlocks(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<DashboardUnlockEntry> entries,
    required List<DashboardTripEntry> allTrips,
    bool showTrainNumber = true,
  }) async {
    final changed = await _openUnlocks(
      context,
      title: title,
      icon: icon,
      entries: entries,
      allTrips: allTrips,
      showTrainNumber: showTrainNumber,
      openTrip: openTrip,
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
  const _MetricGrid({required this.cards, this.animationOffset = 0});

  final List<_Metric> cards;
  final int animationOffset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          < 600 => 1,
          < 840 => 2,
          < 1120 => 3,
          _ => 4,
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
          itemCount: cards.length,
          itemBuilder: (context, index) {
            final animationIndex = animationOffset + index;
            return M3Reveal(
              duration: Duration(milliseconds: 260 + animationIndex * 45),
              distance: 8,
              child: _MetricCard(metric: cards[index]),
            );
          },
        );
      },
    );
  }
}

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
  bool showTrainNumber = true,
  TripEntryOpener? openTrip,
}) {
  return Navigator.of(context).push<bool>(
    m3PageRoute(
      builder: (context) => DashboardUnlocksPage(
        title: title,
        icon: icon,
        entries: entries,
        allTrips: allTrips,
        showTrainNumber: showTrainNumber,
        openTrip: openTrip,
      ),
    ),
  );
}

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String _trainLabel(String value) {
  final trainNumber = value.trim();
  return trainNumber.isEmpty ? '未填写车次' : trainNumber;
}

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
