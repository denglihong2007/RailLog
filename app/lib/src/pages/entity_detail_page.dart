import 'dart:io';

import 'package:flutter/material.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/train_model_parser.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/pages/all_trips_page.dart';
import 'package:raillog/src/pages/ct_photo_search_page.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/train_service.dart';
import 'package:raillog/src/services/ct_photo_service.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';
import 'package:raillog/src/widgets/login_required_view.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:raillog/src/services/entity_review_service.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/services/intersection_service.dart';
import 'package:raillog/src/widgets/entity_review_card.dart';
import 'package:raillog/src/models/online_intersection.dart';
import 'package:raillog/src/models/achievement_unlock_trip.dart';
import 'package:raillog/src/pages/achievement_unlock_trips_page.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/pages/home_page.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/review_editor.dart';

enum EntityType { station, route, company, rollingStock, train }

const _entityMaxWidth = AppLayout.detailMaxWidth;

class EntityDetailPage extends StatefulWidget {
  const EntityDetailPage({super.key, required this.type, required this.name});
  final EntityType type;
  final String name;

  @override
  State<EntityDetailPage> createState() => _EntityDetailPageState();
}

class _EntityDetailPageState extends State<EntityDetailPage> {
  Future<List<TripRecord>>? _future;
  Future<int>? _globalFuture;
  Future<List<OnlineIntersection>>? _intersectionFuture;
  late bool _wasSignedIn;

  @override
  void initState() {
    super.initState();
    _wasSignedIn = SessionService.instance.isSignedIn;
    if (_wasSignedIn) _loadData();
    SessionService.instance.addListener(_handleSessionChanged);
  }

  @override
  void dispose() {
    SessionService.instance.removeListener(_handleSessionChanged);
    super.dispose();
  }

  void _loadData() {
    _future = DbHelper.instance.getAllTrips();
    _intersectionFuture = null;
    _globalFuture = EntityReviewService.fetchCount(
      _typeKey(widget.type),
      widget.name,
    );
  }

  void _handleSessionChanged() {
    if (!mounted) return;
    final isSignedIn = SessionService.instance.isSignedIn;
    if (isSignedIn == _wasSignedIn) return;
    _wasSignedIn = isSignedIn;
    if (isSignedIn) {
      _loadData();
    } else {
      _future = null;
      _globalFuture = null;
      _intersectionFuture = null;
    }
    setState(() {});
  }

  void _loadAfterSignIn() {
    if (!mounted || !SessionService.instance.isSignedIn) return;
    if (_future == null) _loadData();
    setState(() {});
  }

  List<TripRecord> _matching(List<TripRecord> trips) {
    final key = _normalize(widget.name);
    final matching = trips.where((trip) {
      if (!trip.isRailTrip) return false;
      switch (widget.type) {
        case EntityType.station:
          return _normalize(trip.fromStation) == key ||
              _normalize(trip.toStation) == key;
        case EntityType.route:
          return trip.viaRouteSegments.any(
            (s) => _normalize(s.routeName) == key,
          );
        case EntityType.company:
          return _normalize(trip.companyName ?? '') == key;
        case EntityType.rollingStock:
          // 客车匹配忽略前缀，所有车型匹配均忽略车号。
          return TrainModelParser.parse(
            trip.rollingStock,
          ).any((parsed) => _normalize(parsed.statisticsCode) == key);
        case EntityType.train:
          return _normalize(trip.trainNumber) == key;
      }
    }).toList();
    matching.sort((a, b) => b.departureTime.compareTo(a.departureTime));
    return matching;
  }

  Future<List<OnlineIntersection>> _loadIntersections() =>
      _intersectionFuture ??= IntersectionService.fetch(
        _typeKey(widget.type),
        widget.name,
      );

  List<OnlineIntersection> _matchingIntersections(
    List<OnlineIntersection> groups,
  ) {
    final matches = groups
        .where((item) => _normalize(item.location) == _normalize(widget.name))
        .toList();
    matches.sort(
      (a, b) => (b.trips.any((trip) => trip.isStrict) ? 1 : 0).compareTo(
        a.trips.any((trip) => trip.isStrict) ? 1 : 0,
      ),
    );
    return matches;
  }

  Future<void> _openAllIntersections() async {
    try {
      final groups = await _loadIntersections();
      if (!mounted) return;
      final ordered = _matchingIntersections(groups);
      await Navigator.of(context).push(
        m3PageRoute(
          builder: (_) => EntityIntersectionsPage(
            title: widget.name,
            intersections: ordered,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('读取行程交集失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(title: Text(widget.name), scrolledUnderElevation: 0);
    if (!SessionService.instance.isSignedIn) {
      return Scaffold(
        appBar: appBar,
        body: LoginRequiredView(
          message: '登录后查看${_typeLabel(widget.type)}详情',
          icon: _typeIcon(widget.type),
          onSignedIn: _loadAfterSignIn,
        ),
      );
    }
    final future = _future;
    final globalFuture = _globalFuture;
    if (future == null || globalFuture == null) {
      return Scaffold(
        appBar: appBar,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: appBar,
      body: FutureBuilder<List<TripRecord>>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final trips = _matching(snapshot.data!);
          return ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: ListView(
              padding: AppSpacing.page,
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _entityMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _EntityHeader(type: widget.type, name: widget.name),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 560;
                            final metrics = [
                              FutureBuilder<int>(
                                future: globalFuture,
                                builder: (context, snap) => _MetricCard(
                                  icon: Icons.public,
                                  label: '全站记录',
                                  value: snap.data == null
                                      ? '—'
                                      : '${snap.data} 次',
                                  highlighted: true,
                                ),
                              ),
                              _MetricCard(
                                icon: Icons.person_outline,
                                label: '你的记录',
                                value: '${trips.length} 次',
                              ),
                            ];
                            return wide
                                ? Row(
                                    children: [
                                      Expanded(child: metrics[0]),
                                      const SizedBox(width: 12),
                                      Expanded(child: metrics[1]),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      metrics[0],
                                      const SizedBox(height: 12),
                                      metrics[1],
                                    ],
                                  );
                          },
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          title: '车票列表',
                          icon: Icons.confirmation_number_outlined,
                          action: trips.length > 4
                              ? TextButton.icon(
                                  onPressed: () => Navigator.of(context).push(
                                    m3PageRoute(
                                      builder: (_) => AllTripsPage(
                                        title: widget.name,
                                        trips: trips
                                            .map(DashboardTripEntry.fromTrip)
                                            .toList(),
                                        showTripKindFilter: false,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.arrow_forward,
                                    size: 18,
                                  ),
                                  label: const Text('更多'),
                                )
                              : null,
                          child: trips.isEmpty
                              ? const _EmptyState(
                                  message: '暂无关联车票',
                                  icon: Icons.train_outlined,
                                )
                              : Column(
                                  children: [
                                    _ResponsiveTicketList(
                                      trips: trips.take(4).toList(),
                                    ),
                                  ],
                                ),
                        ),
                        if (widget.type == EntityType.station ||
                            widget.type == EntityType.train) ...[
                          const SizedBox(height: 12),
                          _SectionCard(
                            title: '行程交集',
                            icon: Icons.people_alt_outlined,
                            action: trips.isEmpty
                                ? null
                                : TextButton.icon(
                                    onPressed: _openAllIntersections,
                                    icon: const Icon(
                                      Icons.arrow_forward,
                                      size: 18,
                                    ),
                                    label: const Text('更多'),
                                  ),
                            child: trips.isEmpty
                                ? const _EmptyState(
                                    message: '暂无行程交集',
                                    icon: Icons.group_off_outlined,
                                  )
                                : FutureBuilder<List<OnlineIntersection>>(
                                    future: _loadIntersections(),
                                    builder: (context, snap) {
                                      if (!snap.hasData) {
                                        return const _EmptyState(
                                          message: '正在加载交集…',
                                          icon: Icons.sync,
                                        );
                                      }
                                      final ordered = _matchingIntersections(
                                        snap.data!,
                                      );
                                      final items = _orderedIntersectionTrips(
                                        ordered,
                                      );
                                      return items.isEmpty
                                          ? const _EmptyState(
                                              message: '暂无行程交集',
                                              icon: Icons.group_off_outlined,
                                            )
                                          : Column(
                                              children: [
                                                ...items
                                                    .take(5)
                                                    .map(
                                                      (t) => Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              bottom: 10,
                                                            ),
                                                        child: AchievementTripRow(
                                                          trip:
                                                              _toAchievementTrip(
                                                                t,
                                                              ),
                                                          highlight: t.isStrict,
                                                        ),
                                                      ),
                                                    ),
                                              ],
                                            );
                                    },
                                  ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _ReviewsSection(
                          type: widget.type,
                          name: widget.name,
                          trips: trips,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.action,
  });
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    return AppCard.filled(
      title: title,
      icon: icon,
      trailing: action,
      child: child,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, required this.icon});
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        Icon(icon, size: 32, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 8),
        Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _ResponsiveTicketList extends StatelessWidget {
  const _ResponsiveTicketList({required this.trips});
  final List<TripRecord> trips;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760 ? 2 : 1;
      final cards = trips
          .map(
            (trip) => TripTicketCard(
              trip: DashboardTripEntry.fromTrip(trip),
              selectionMode: false,
              selected: false,
              onToggleSelection: (_) {},
            ),
          )
          .toList();
      if (columns == 1) {
        return Column(
          children: cards
              .map(
                (card) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: card,
                ),
              )
              .toList(),
        );
      }
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: cards
            .map(
              (card) =>
                  SizedBox(width: (constraints.maxWidth - 12) / 2, child: card),
            )
            .toList(),
      );
    },
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    this.highlighted = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool highlighted;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard.filled(
      color: highlighted
          ? colors.secondaryContainer
          : colors.surfaceContainerLow,
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          icon,
          color: highlighted ? colors.onSecondaryContainer : colors.primary,
        ),
        title: Text(label),
        trailing: Text(value, style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}

AchievementUnlockTrip _toAchievementTrip(IntersectionTrip t) =>
    AchievementUnlockTrip(
      ticketId: t.ticketId,
      userId: t.userId,
      displayName: t.displayName,
      avatarUrl: t.avatarUrl,
      occurredAt: t.occurredAt,
      trainNumber: t.trainNumber,
      fromStation: '',
      toStation: '',
      isCurrentUser: false,
    );

class EntityIntersectionsPage extends StatelessWidget {
  const EntityIntersectionsPage({
    super.key,
    required this.title,
    required this.intersections,
  });
  final String title;
  final List<OnlineIntersection> intersections;
  @override
  Widget build(BuildContext context) {
    final trips = _orderedIntersectionTrips(intersections);
    return Scaffold(
      appBar: AppBar(title: Text('$title · 行程交集')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.contentMaxWidth,
          ),
          child: ListView.separated(
            padding: AppSpacing.page,
            itemCount: trips.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final t = trips[i];
              return AchievementTripRow(
                trip: _toAchievementTrip(t),
                highlight: t.isStrict,
              );
            },
          ),
        ),
      ),
    );
  }
}

List<IntersectionTrip> _orderedIntersectionTrips(
  List<OnlineIntersection> groups,
) {
  final trips = groups.expand((group) => group.trips).toList();
  trips.sort((a, b) {
    final strict = (b.isStrict ? 1 : 0).compareTo(a.isStrict ? 1 : 0);
    if (strict != 0) return strict;
    return b.occurredAt.compareTo(a.occurredAt);
  });
  return trips;
}

class _EntityHeader extends StatelessWidget {
  const _EntityHeader({required this.type, required this.name});
  final EntityType type;
  final String name;
  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[];
    if (type == EntityType.station) {
      actions.add(
        IconButton(
          tooltip: 'RailGo 信息',
          icon: const Icon(Icons.open_in_new),
          onPressed: () => _openRailGoStation(context, name),
        ),
      );
      actions.add(
        IconButton(
          tooltip: 'CTPhotos 图片',
          icon: const Icon(Icons.photo_library_outlined),
          onPressed: () => Navigator.of(context).push(
            m3PageRoute(
              builder: (_) => CtPhotoSearchPage(
                keyword: name,
                fieldLabel: '车站',
                filter: CtPhotoSearchFilter.station,
              ),
            ),
          ),
        ),
      );
    } else if (type == EntityType.train) {
      actions.add(
        IconButton(
          tooltip: 'RailGo 信息',
          icon: const Icon(Icons.open_in_new),
          onPressed: () => _openRailGoTrain(context, name),
        ),
      );
      actions.add(
        IconButton(
          tooltip: 'CTPhotos 图片',
          icon: const Icon(Icons.photo_library_outlined),
          onPressed: () => Navigator.of(context).push(
            m3PageRoute(
              builder: (_) => CtPhotoSearchPage(
                keyword: name,
                fieldLabel: '车次',
                filter: CtPhotoSearchFilter.train,
              ),
            ),
          ),
        ),
      );
    } else if (type == EntityType.rollingStock) {
      actions.add(
        IconButton(
          tooltip: 'CTPhotos 图片',
          icon: const Icon(Icons.photo_library_outlined),
          onPressed: () => Navigator.of(context).push(
            m3PageRoute(
              builder: (_) => CtPhotoSearchPage(
                keyword: name,
                fieldLabel: '车型',
                filter: CtPhotoSearchFilter.model,
              ),
            ),
          ),
        ),
      );
    }
    final colors = Theme.of(context).colorScheme;
    final label = _typeLabel(type);
    final entityIcon = _typeIcon(type);
    return AppCard.filled(
      color: colors.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.onPrimaryContainer.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Icon(
                    entityIcon,
                    size: 20,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.onPrimaryContainer,
                ),
              ),
              const Spacer(),
              ...actions.map(
                (action) => IconTheme(
                  data: IconThemeData(color: colors.onPrimaryContainer),
                  child: action,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            name,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: colors.onPrimaryContainer,
              fontFamily:
                  type == EntityType.rollingStock &&
                      TrainModelParser.containsEmu(name)
                  ? 'HVCB'
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewsSection extends StatefulWidget {
  const _ReviewsSection({
    required this.type,
    required this.name,
    required this.trips,
  });
  final EntityType type;
  final String name;
  final List<TripRecord> trips;
  @override
  State<_ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<_ReviewsSection> {
  late Future<List<EntityReview>> _future;
  List<TripRecord> get _reviewTrips =>
      widget.trips.where(canUseAsReviewTrip).toList()
        ..sort((a, b) => b.departureTime.compareTo(a.departureTime));
  @override
  void initState() {
    super.initState();
    _future = EntityReviewService.fetch(_typeKey(widget.type), widget.name);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<EntityReview>>(
    future: _future,
    builder: (context, snapshot) {
      final reviewTrips = _reviewTrips;
      final groups = snapshot.hasData
          ? _groupReviews(snapshot.data!).entries.toList()
          : <MapEntry<String, List<EntityReview>>>[];
      final keys = _reviewKeys(widget.type);
      return Column(
        children: keys
            .map(
              (key) => _ReviewGroupCard(
                title: _reviewTypeLabel(key),
                icon: _reviewTypeIcon(key),
                entityName: widget.name,
                reviews: groups
                    .firstWhere(
                      (g) => g.key == key,
                      orElse: () => MapEntry(key, const <EntityReview>[]),
                    )
                    .value,
                trips: reviewTrips,
                enabled: key == 'transfer'
                    ? _hasTransferPair(widget.name, reviewTrips)
                    : reviewTrips.isNotEmpty,
                onReview: () => _addReview(key),
                onChanged: _refreshReviews,
              ),
            )
            .toList(),
      );
    },
  );
  Future<void> _addReview(String selectedReviewType) async {
    final reviewTrips = _reviewTrips;
    if (reviewTrips.isEmpty) return;
    final draft = await showDialog<ReviewDraft>(
      context: context,
      builder: (_) => ReviewEditorDialog(
        title: '发表评价',
        reviewType: selectedReviewType,
        trips: reviewTrips,
        stationName: widget.name,
      ),
    );
    if (draft == null) return;
    try {
      await EntityReviewService.submit(
        type: _typeKey(widget.type),
        key: widget.name,
        reviewType: selectedReviewType,
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
      return;
    }
    _refreshReviews();
  }

  void _refreshReviews() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _future = EntityReviewService.fetch(_typeKey(widget.type), widget.name);
      });
    });
    WidgetsBinding.instance.scheduleFrame();
  }
}

IconData _reviewTypeIcon(String type) => switch (type) {
  'station' => Icons.train_outlined,
  'transfer' => Icons.swap_horiz,
  'company' => Icons.business_outlined,
  'meal' => Icons.restaurant_outlined,
  'route' => Icons.route_outlined,
  'rollingStock' => Icons.directions_railway_outlined,
  'train' => Icons.confirmation_number_outlined,
  _ => Icons.rate_review_outlined,
};

List<String> _reviewKeys(EntityType type) => switch (type) {
  EntityType.station => ['station', 'transfer'],
  EntityType.company => ['company', 'meal'],
  EntityType.route => ['route'],
  EntityType.rollingStock => ['rollingStock'],
  EntityType.train => ['train'],
};

bool _hasTransferPair(String stationName, Iterable<TripRecord> trips) {
  final candidates = trips.toList();
  return candidates.any(
    (trip) => transferFollowingTrips(trip, candidates, stationName).isNotEmpty,
  );
}

class _ReviewGroupCard extends StatelessWidget {
  const _ReviewGroupCard({
    required this.title,
    required this.icon,
    required this.entityName,
    required this.reviews,
    required this.trips,
    required this.enabled,
    required this.onReview,
    required this.onChanged,
  });
  final String title;
  final IconData icon;
  final String entityName;
  final List<EntityReview> reviews;
  final List<TripRecord> trips;
  final bool enabled;
  final VoidCallback onReview;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => AppCard.filled(
    title: title,
    icon: icon,
    margin: const EdgeInsets.only(bottom: AppSpacing.md),
    trailing: FilledButton.tonalIcon(
      onPressed: enabled ? onReview : null,
      icon: const Icon(Icons.edit_outlined, size: 18),
      label: const Text('评论'),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reviews.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('暂无评价'),
          )
        else
          ...reviews
              .take(10)
              .toList()
              .asMap()
              .entries
              .map(
                (entry) => _ReviewTile(
                  review: entry.value,
                  trips: trips,
                  entityName: entityName,
                  onChanged: onChanged,
                  showDivider: entry.key < reviews.take(10).length - 1,
                ),
              ),
      ],
    ),
  );
}

Map<String, List<EntityReview>> _groupReviews(List<EntityReview> reviews) {
  final result = <String, List<EntityReview>>{};
  for (final review in reviews) {
    (result[review.reviewType] ??= []).add(review);
  }
  return result;
}

String _reviewTypeLabel(String type) => switch (type) {
  'station' => '车站服务',
  'transfer' => '换乘接驳',
  'route' => '乘坐体验',
  'company' => '承运单位服务',
  'meal' => '餐饮服务',
  'rollingStock' => '乘坐体验',
  'train' => '乘坐体验',
  _ => type,
};

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.review,
    required this.trips,
    required this.entityName,
    required this.onChanged,
    required this.showDivider,
  });
  final EntityReview review;
  final List<TripRecord> trips;
  final String entityName;
  final VoidCallback onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => EntityReviewCard(
    review: review,
    trips: trips,
    entityName: entityName,
    showDivider: showDivider,
    contentPadding: EdgeInsets.fromLTRB(12, 12, 8, showDivider ? 14 : 4),
    onChanged: onChanged,
    onEdit: () => _editReview(context),
    onDelete: () => _deleteReview(context),
    onUserTap: () => _openUser(context),
    onTripTap: (trip) => _openTrip(context, trip),
  );

  Future<void> _editReview(BuildContext context) async {
    final draft = await showDialog<ReviewDraft>(
      context: context,
      builder: (_) => ReviewEditorDialog(
        title: '修改评价',
        reviewType: review.reviewType,
        trips: trips,
        stationName: entityName,
        initial: review,
      ),
    );
    if (draft == null) return;
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
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
      return;
    }
    onChanged();
  }

  Future<void> _deleteReview(BuildContext context) async {
    try {
      await EntityReviewService.delete(review);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
      return;
    }
    onChanged();
  }

  void _openUser(BuildContext context) => Navigator.of(
    context,
  ).push(m3PageRoute(builder: (_) => PublicUserPage(userId: review.userId)));

  void _openTrip(BuildContext context, TripRecord trip) =>
      Navigator.of(context).push(
        m3PageRoute(
          builder: (_) => TripRecordDetailsPage.public(
            ticketId: trip.ticketId ?? trip.id,
            onOwnerTap: () => Navigator.of(context).push(
              m3PageRoute(
                builder: (_) => PublicUserPage(userId: review.userId),
              ),
            ),
          ),
        ),
      );
}

String _typeKey(EntityType type) => switch (type) {
  EntityType.station => 'station',
  EntityType.route => 'route',
  EntityType.company => 'company',
  EntityType.rollingStock => 'rollingStock',
  EntityType.train => 'train',
};

String _typeLabel(EntityType type) => switch (type) {
  EntityType.station => '车站',
  EntityType.route => '线路',
  EntityType.company => '承运单位',
  EntityType.rollingStock => '车型',
  EntityType.train => '车次',
};

IconData _typeIcon(EntityType type) => switch (type) {
  EntityType.station => Icons.location_on_outlined,
  EntityType.route => Icons.alt_route,
  EntityType.company => Icons.business_outlined,
  EntityType.rollingStock => Icons.directions_railway_outlined,
  EntityType.train => Icons.train_outlined,
};

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

Future<void> openEntityPage(
  BuildContext context,
  EntityType type,
  String name,
) async {
  final value = name.trim();
  if (value.isEmpty) return;
  await Navigator.of(context).push(
    m3PageRoute(
      builder: (_) => EntityDetailPage(type: type, name: value),
    ),
  );
}

Future<void> _openRailGoStation(BuildContext context, String name) async {
  final codes = await TrainService.initializeStationCodes();
  if (!context.mounted) return;
  final code = codes[name.trim()];
  if (code == null || code.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('未找到$name的车站代码')));
    return;
  }
  final encoded = Uri.encodeQueryComponent(code);
  await _openRailGoLinks(
    context,
    appUri: Uri.parse('railgo://pages/station/result?keyword=$encoded'),
    webUri: Uri.parse('https://railgo.dev/station/result?telecode=$encoded'),
  );
}

Future<void> _openRailGoTrain(BuildContext context, String name) async {
  final encoded = Uri.encodeQueryComponent(name.trim());
  await _openRailGoLinks(
    context,
    appUri: Uri.parse('railgo://pages/train/trainResult?keyword=$encoded'),
    webUri: Uri.parse('https://railgo.dev/train/result?keyword=$encoded'),
  );
}

Future<void> _openRailGoLinks(
  BuildContext context, {
  required Uri appUri,
  required Uri webUri,
}) async {
  var opened = false;
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      opened = await launchUrl(appUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
  }
  if (!opened) {
    try {
      opened = await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法打开 RailGo 链接')));
  }
}
