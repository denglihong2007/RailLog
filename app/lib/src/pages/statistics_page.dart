import 'package:flutter/material.dart';
import 'package:raillog/src/models/global_statistics.dart';
import 'package:raillog/src/models/public_user_dashboard.dart';
import 'package:raillog/src/pages/auth_page.dart';
import 'package:raillog/src/pages/home_page.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/services/statistics_service.dart';
import 'package:raillog/src/widgets/cached_avatar.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

enum _UserMetric { trips, mileage, duration, spending, achievements }

enum _TripMetric {
  spending,
  mileage,
  duration,
  bestValue,
  luxury,
  turtle,
  highSpeed,
}

enum _ElementMetric { stations, routes, trains, rollingStocks, companies }

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  Future<GlobalStatistics>? _statisticsFuture;
  late bool _wasSignedIn;

  @override
  void initState() {
    super.initState();
    _wasSignedIn = SessionService.instance.isSignedIn;
    if (_wasSignedIn) _statisticsFuture = StatisticsService.fetch();
    SessionService.instance.addListener(_handleSessionChanged);
  }

  @override
  void dispose() {
    SessionService.instance.removeListener(_handleSessionChanged);
    super.dispose();
  }

  void _handleSessionChanged() {
    if (!mounted) return;
    final isSignedIn = SessionService.instance.isSignedIn;
    if (isSignedIn == _wasSignedIn) return;
    _wasSignedIn = isSignedIn;
    setState(() {
      _statisticsFuture = isSignedIn ? StatisticsService.fetch() : null;
    });
  }

  Future<void> _refresh() async {
    if (!SessionService.instance.isSignedIn) return;
    final future = StatisticsService.fetch();
    setState(() => _statisticsFuture = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    if (!SessionService.instance.isSignedIn) {
      return _SignedOutStatistics(onSignedIn: _loadAfterSignIn);
    }
    final statisticsFuture = _statisticsFuture ??= StatisticsService.fetch();
    return FutureBuilder<GlobalStatistics>(
      future: statisticsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StatisticsStatus(
            icon: Icons.error_outline,
            message: '读取全站统计失败',
            detail: '${snapshot.error}',
            onRetry: _refresh,
          );
        }
        if (!snapshot.hasData) {
          return const _StatisticsStatus(isLoading: true, message: '正在汇总全站数据');
        }
        final statistics = snapshot.data!;
        return DefaultTabController(
          length: 4,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                            child: Text(
                              '统计',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          const TabBar(
                            dividerHeight: 0,
                            tabs: [
                              Tab(icon: Icon(Icons.public), text: '全站'),
                              Tab(icon: Icon(Icons.people_outline), text: '用户'),
                              Tab(
                                icon: Icon(Icons.confirmation_number_outlined),
                                text: '行程',
                              ),
                              Tab(
                                icon: Icon(Icons.category_outlined),
                                text: '要素',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _SiteStatisticsView(
                        statistics: statistics.site,
                        onRefresh: _refresh,
                      ),
                      _UserLeaderboardView(
                        leaderboards: statistics.users,
                        onRefresh: _refresh,
                      ),
                      _TripLeaderboardView(
                        leaderboards: statistics.trips,
                        onRefresh: _refresh,
                      ),
                      _ElementLeaderboardView(
                        leaderboards: statistics.elements,
                        onRefresh: _refresh,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _loadAfterSignIn() {
    if (!mounted || !SessionService.instance.isSignedIn) return;
    _wasSignedIn = true;
    if (_statisticsFuture != null) return;
    setState(() => _statisticsFuture = StatisticsService.fetch());
  }
}

class _SiteStatisticsView extends StatelessWidget {
  const _SiteStatisticsView({
    required this.statistics,
    required this.onRefresh,
  });

  final SiteStatistics statistics;
  final RefreshCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final items = [
      (
        '累计',
        statistics.totalMetrics,
        Icons.all_inclusive,
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      (
        '本年',
        statistics.thisYearMetrics,
        Icons.calendar_today_outlined,
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      (
        '本月',
        statistics.thisMonthMetrics,
        Icons.calendar_view_month_outlined,
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
      ),
      (
        '本周',
        statistics.thisWeekMetrics,
        Icons.date_range_outlined,
        colors.surfaceContainerHighest,
        colors.onSurface,
      ),
    ];
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 720 ? 4 : 2;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 190,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return M3Reveal(
                        duration: Duration(milliseconds: 240 + index * 50),
                        distance: 8,
                        child: _SiteMetricCard(
                          label: item.$1,
                          value: item.$2,
                          icon: item.$3,
                          backgroundColor: item.$4,
                          foregroundColor: item.$5,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SiteMetricCard extends StatelessWidget {
  const _SiteMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final SitePeriodStatistics value;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Card.filled(
      margin: EdgeInsets.zero,
      color: backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(color: foregroundColor),
                  ),
                ),
                Icon(icon, color: foregroundColor),
              ],
            ),
            const SizedBox(height: 12),
            _SiteMetricLine(
              label: '次数',
              value: '${value.tripCount} 次',
              color: foregroundColor,
            ),
            _SiteMetricLine(
              label: '里程',
              value: '${value.mileageKm.round()} km',
              color: foregroundColor,
            ),
            _SiteMetricLine(
              label: '时长',
              value: _formatSeconds(value.durationSeconds),
              color: foregroundColor,
            ),
            _SiteMetricLine(
              label: '花费',
              value: '¥${value.spending.toStringAsFixed(2)}',
              color: foregroundColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _SiteMetricLine extends StatelessWidget {
  const _SiteMetricLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 27,
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserLeaderboardView extends StatefulWidget {
  const _UserLeaderboardView({
    required this.leaderboards,
    required this.onRefresh,
  });

  final UserLeaderboards leaderboards;
  final RefreshCallback onRefresh;

  @override
  State<_UserLeaderboardView> createState() => _UserLeaderboardViewState();
}

class _UserLeaderboardViewState extends State<_UserLeaderboardView> {
  _UserMetric _metric = _UserMetric.trips;

  List<UserRankingEntry> get _entries => switch (_metric) {
    _UserMetric.spending => widget.leaderboards.totalSpending,
    _UserMetric.trips => widget.leaderboards.tripCount,
    _UserMetric.duration => widget.leaderboards.durationSeconds,
    _UserMetric.mileage => widget.leaderboards.mileageKm,
    _UserMetric.achievements => widget.leaderboards.achievementCount,
  };

  @override
  Widget build(BuildContext context) {
    return _LeaderboardScrollView(
      onRefresh: widget.onRefresh,
      selector: _ModeSelector<_UserMetric>(
        value: _metric,
        options: _UserMetric.values
            .map((metric) => (metric, _userMetricLabel(metric)))
            .toList(growable: false),
        onChanged: (value) => setState(() => _metric = value),
      ),
      children: _entries
          .map(
            (entry) => _UserRankingRow(
              entry: entry,
              value: _formatUserValue(_metric, entry.value),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _TripLeaderboardView extends StatefulWidget {
  const _TripLeaderboardView({
    required this.leaderboards,
    required this.onRefresh,
  });

  final TripLeaderboards leaderboards;
  final RefreshCallback onRefresh;

  @override
  State<_TripLeaderboardView> createState() => _TripLeaderboardViewState();
}

class _TripLeaderboardViewState extends State<_TripLeaderboardView> {
  _TripMetric _metric = _TripMetric.spending;

  List<TripRankingEntry> get _entries => switch (_metric) {
    _TripMetric.spending => widget.leaderboards.singleSpending,
    _TripMetric.mileage => widget.leaderboards.mileageKm,
    _TripMetric.duration => widget.leaderboards.durationSeconds,
    _TripMetric.bestValue => widget.leaderboards.bestValueYuanPerKm,
    _TripMetric.luxury => widget.leaderboards.luxuryYuanPerKm,
    _TripMetric.turtle => widget.leaderboards.slowestAverageSpeedKmh,
    _TripMetric.highSpeed => widget.leaderboards.fastestAverageSpeedKmh,
  };

  @override
  Widget build(BuildContext context) {
    return _LeaderboardScrollView(
      onRefresh: widget.onRefresh,
      selector: _ModeSelector<_TripMetric>(
        value: _metric,
        options: _TripMetric.values
            .map((metric) => (metric, _tripMetricLabel(metric)))
            .toList(growable: false),
        onChanged: (value) => setState(() => _metric = value),
      ),
      children: _entries
          .map(
            (entry) => _TripRankingRow(
              entry: entry,
              value: _formatTripValue(_metric, entry.value),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _ElementLeaderboardView extends StatefulWidget {
  const _ElementLeaderboardView({
    required this.leaderboards,
    required this.onRefresh,
  });

  final ElementLeaderboards leaderboards;
  final RefreshCallback onRefresh;

  @override
  State<_ElementLeaderboardView> createState() =>
      _ElementLeaderboardViewState();
}

class _ElementLeaderboardViewState extends State<_ElementLeaderboardView> {
  _ElementMetric _metric = _ElementMetric.stations;

  List<ElementRankingEntry> get _entries => switch (_metric) {
    _ElementMetric.stations => widget.leaderboards.stations,
    _ElementMetric.routes => widget.leaderboards.routes,
    _ElementMetric.trains => widget.leaderboards.trains,
    _ElementMetric.rollingStocks => widget.leaderboards.rollingStocks,
    _ElementMetric.companies => widget.leaderboards.companies,
  };

  @override
  Widget build(BuildContext context) {
    return _LeaderboardScrollView(
      onRefresh: widget.onRefresh,
      selector: _ModeSelector<_ElementMetric>(
        value: _metric,
        options: _ElementMetric.values
            .map((metric) => (metric, _elementMetricLabel(metric)))
            .toList(growable: false),
        onChanged: (value) => setState(() => _metric = value),
      ),
      children: _entries
          .map((entry) => _ElementRankingRow(entry: entry))
          .toList(growable: false),
    );
  }
}

class _ModeSelector<T> extends StatelessWidget {
  const _ModeSelector({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<T>(
        showSelectedIcon: false,
        segments: options
            .map(
              (option) =>
                  ButtonSegment<T>(value: option.$1, label: Text(option.$2)),
            )
            .toList(growable: false),
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

class _LeaderboardScrollView extends StatelessWidget {
  const _LeaderboardScrollView({
    required this.onRefresh,
    required this.selector,
    required this.children,
  });

  final RefreshCallback onRefresh;
  final Widget selector;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  selector,
                  const SizedBox(height: 16),
                  if (children.isEmpty)
                    const _EmptyLeaderboard()
                  else
                    ..._withSpacing(children),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserRankingRow extends StatelessWidget {
  const _UserRankingRow({required this.entry, required this.value});

  final UserRankingEntry entry;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _RankingRow(
      rank: entry.rank,
      avatar: _StatisticsAvatar(user: entry.user, size: 40),
      title: entry.user.displayName,
      value: value,
      onTap: () => Navigator.of(context).push(
        m3PageRoute(builder: (_) => PublicUserPage(userId: entry.user.id)),
      ),
    );
  }
}

class _TripRankingRow extends StatelessWidget {
  const _TripRankingRow({required this.entry, required this.value});

  final TripRankingEntry entry;
  final String value;

  @override
  Widget build(BuildContext context) {
    final trip = entry.trip;
    return _RankingRow(
      rank: entry.rank,
      avatar: _StatisticsAvatar(user: entry.user, size: 36),
      title: '${entry.user.displayName} · ${_trainLabel(trip.trainNumber)}',
      subtitle: '${trip.fromStation} → ${trip.toStation}',
      value: value,
      onTap: () => Navigator.of(context).push(
        m3PageRoute(
          builder: (_) => TripRecordDetailsPage.public(
            ticketId: trip.ticketId!,
            onOwnerTap: () => Navigator.of(context).push(
              m3PageRoute(
                builder: (_) => PublicUserPage(userId: entry.user.id),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ElementRankingRow extends StatelessWidget {
  const _ElementRankingRow({required this.entry});

  final ElementRankingEntry entry;

  @override
  Widget build(BuildContext context) {
    return _RankingRow(
      rank: entry.rank,
      title: entry.name,
      value: '${entry.value} 次',
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.rank,
    required this.title,
    required this.value,
    this.avatar,
    this.subtitle,
    this.onTap,
  });

  final int rank;
  final Widget? avatar;
  final String title;
  final String? subtitle;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final emphasized = rank <= 3;
    final rankColors = _rankColors(context, rank);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: emphasized
                ? rankColors.$1
                : colors.surfaceContainerHighest,
            foregroundColor: emphasized
                ? rankColors.$2
                : colors.onSurfaceVariant,
            child: Text(
              '$rank',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (avatar != null) ...[const SizedBox(width: 8), avatar!],
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: emphasized ? colors.onSurface : colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 20, color: colors.onSurfaceVariant),
          ],
        ],
      ),
    );
    return Card.filled(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: emphasized
            ? BorderSide(color: rankColors.$3, width: 1.2)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

(Color, Color, Color) _rankColors(BuildContext context, int rank) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch ((dark, rank)) {
    (true, 1) => (
      const Color(0xFF5B4712),
      const Color(0xFFFFE08A),
      const Color(0xFFB89232),
    ),
    (true, 2) => (
      const Color(0xFF45484C),
      const Color(0xFFE3E5E8),
      const Color(0xFF8D939A),
    ),
    (true, 3) => (
      const Color(0xFF563727),
      const Color(0xFFF6C0A0),
      const Color(0xFFB77A56),
    ),
    (false, 1) => (
      const Color(0xFFFFE8A3),
      const Color(0xFF4C3900),
      const Color(0xFFC49A24),
    ),
    (false, 2) => (
      const Color(0xFFE4E7EB),
      const Color(0xFF30343A),
      const Color(0xFF9298A0),
    ),
    (false, 3) => (
      const Color(0xFFF4D0BB),
      const Color(0xFF4E2C1B),
      const Color(0xFFB97954),
    ),
    _ => (
      Theme.of(context).colorScheme.surfaceContainerHighest,
      Theme.of(context).colorScheme.onSurfaceVariant,
      Colors.transparent,
    ),
  };
}

class _StatisticsAvatar extends StatelessWidget {
  const _StatisticsAvatar({required this.user, required this.size});

  final PublicUser user;
  final double size;

  @override
  Widget build(BuildContext context) => CachedAvatar(
    name: user.displayName,
    imageUrl: user.avatarUrl,
    size: size,
  );
}

class _EmptyLeaderboard extends StatelessWidget {
  const _EmptyLeaderboard();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: Text('暂无排行数据')),
    );
  }
}

class _SignedOutStatistics extends StatelessWidget {
  const _SignedOutStatistics({required this.onSignedIn});

  final VoidCallback onSignedIn;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.leaderboard_outlined, size: 40),
            const SizedBox(height: 16),
            const Text('登录后查看全站统计'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                await Navigator.of(
                  context,
                ).push(m3PageRoute(builder: (_) => const AuthPage()));
                if (SessionService.instance.isSignedIn) onSignedIn();
              },
              icon: const Icon(Icons.login),
              label: const Text('登录'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatisticsStatus extends StatelessWidget {
  const _StatisticsStatus({
    required this.message,
    this.detail,
    this.icon,
    this.isLoading = false,
    this.onRetry,
  });

  final String message;
  final String? detail;
  final IconData? icon;
  final bool isLoading;
  final RefreshCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const CircularProgressIndicator()
            else if (icon != null)
              Icon(icon, size: 36),
            const SizedBox(height: 16),
            Text(message),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

List<Widget> _withSpacing(List<Widget> children) {
  final result = <Widget>[];
  for (var index = 0; index < children.length; index++) {
    if (index > 0) result.add(const SizedBox(height: 8));
    result.add(children[index]);
  }
  return result;
}

String _userMetricLabel(_UserMetric metric) => switch (metric) {
  _UserMetric.spending => '累计花费',
  _UserMetric.trips => '行程次数',
  _UserMetric.duration => '累计时长',
  _UserMetric.mileage => '累计里程',
  _UserMetric.achievements => '解锁成就',
};

String _tripMetricLabel(_TripMetric metric) => switch (metric) {
  _TripMetric.spending => '花费',
  _TripMetric.mileage => '里程',
  _TripMetric.duration => '时长',
  _TripMetric.bestValue => '性价比',
  _TripMetric.luxury => '土豪',
  _TripMetric.turtle => '低速',
  _TripMetric.highSpeed => '高速',
};

String _elementMetricLabel(_ElementMetric metric) => switch (metric) {
  _ElementMetric.stations => '车站',
  _ElementMetric.routes => '线路',
  _ElementMetric.trains => '车次',
  _ElementMetric.rollingStocks => '车型',
  _ElementMetric.companies => '承运单位',
};

String _formatUserValue(_UserMetric metric, double value) => switch (metric) {
  _UserMetric.spending => '¥${value.toStringAsFixed(2)}',
  _UserMetric.trips => '${value.round()} 次',
  _UserMetric.duration => _formatSeconds(value),
  _UserMetric.mileage => '${value.round()} km',
  _UserMetric.achievements => '${value.round()} 项',
};

String _formatTripValue(_TripMetric metric, double value) => switch (metric) {
  _TripMetric.spending => '¥${value.toStringAsFixed(2)}',
  _TripMetric.mileage => '${value.round()} km',
  _TripMetric.duration => _formatSeconds(value),
  _TripMetric.bestValue ||
  _TripMetric.luxury => '¥${value.toStringAsFixed(2)}/km',
  _TripMetric.turtle ||
  _TripMetric.highSpeed => '${value.toStringAsFixed(1)} km/h',
};

String _formatSeconds(double value) {
  final duration = Duration(seconds: value.round());
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '$minutes 分';
  return minutes == 0 ? '$hours 时' : '$hours 时 $minutes 分';
}

String _trainLabel(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? '未填写车次' : normalized;
}
