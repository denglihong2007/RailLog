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
import 'package:raillog/src/widgets/cached_avatar.dart';
import 'package:raillog/src/widgets/login_required_view.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:raillog/src/services/entity_review_service.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/services/intersection_service.dart';
import 'package:raillog/src/models/online_intersection.dart';
import 'package:raillog/src/models/achievement_unlock_trip.dart';
import 'package:raillog/src/pages/achievement_unlock_trips_page.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/pages/home_page.dart';

enum EntityType { station, route, company, rollingStock, train }

const _entityMaxWidth = 820.0;
const _entityCardRadius = 8.0;
const _transferWindow = Duration(hours: 24);
final ButtonStyle _ratingIconStyle = IconButton.styleFrom(
  minimumSize: const Size(40, 40),
  maximumSize: const Size(40, 40),
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.standard,
  iconSize: 26,
);

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
    return trips.where((trip) {
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
  }

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      title: Text(widget.name),
      scrolledUnderElevation: 0,
      backgroundColor: Theme.of(context).colorScheme.surface,
    );
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
          final colors = Theme.of(context).colorScheme;
          return Container(
            color: colors.surface,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
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
                                    onPressed: () async {
                                      final groups =
                                          await IntersectionService.fetch(
                                            _typeKey(widget.type),
                                            widget.name,
                                          );
                                      if (!context.mounted) return;
                                      final ordered = groups
                                          .where(
                                            (i) =>
                                                _normalize(i.location) ==
                                                _normalize(widget.name),
                                          )
                                          .toList();
                                      Navigator.of(context).push(
                                        m3PageRoute(
                                          builder: (_) =>
                                              EntityIntersectionsPage(
                                                title: widget.name,
                                                intersections: ordered,
                                              ),
                                        ),
                                      );
                                    },
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
                                    future: IntersectionService.fetch(
                                      _typeKey(widget.type),
                                      widget.name,
                                    ),
                                    builder: (context, snap) {
                                      if (!snap.hasData) {
                                        return const _EmptyState(
                                          message: '正在加载交集…',
                                          icon: Icons.sync,
                                        );
                                      }
                                      final matches = snap.data!
                                          .where(
                                            (i) =>
                                                _normalize(i.location) ==
                                                _normalize(widget.name),
                                          )
                                          .toList();
                                      final ordered = [...matches]
                                        ..sort(
                                          (a, b) =>
                                              (b.trips.any((t) => t.isStrict)
                                                      ? 1
                                                      : 0)
                                                  .compareTo(
                                                    a.trips.any(
                                                          (t) => t.isStrict,
                                                        )
                                                        ? 1
                                                        : 0,
                                                  ),
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
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.surfaceContainerLow,
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_entityCardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: colors.primary),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (action != null) ...[const Spacer(), action!],
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
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
    return Card.filled(
      color: highlighted
          ? colors.secondaryContainer
          : colors.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_entityCardRadius),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: highlighted ? colors.onSecondaryContainer : colors.primary,
        ),
        title: Text(label),
        trailing: Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
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
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
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
          onPressed: () async {
            final codes = await TrainService.initializeStationCodes();
            final code = codes[name.trim()];
            if (code != null) {
              await launchUrl(
                Uri.parse('https://railgo.dev/station/result?telecode=$code'),
                mode: LaunchMode.externalApplication,
              );
            }
          },
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
          onPressed: () => launchUrl(
            Uri.parse(
              'https://railgo.dev/train/result?keyword=${Uri.encodeQueryComponent(name)}',
            ),
            mode: LaunchMode.externalApplication,
          ),
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
    return Card.filled(
      color: colors.primaryContainer,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_entityCardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 12, 14),
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
                  (action) => Theme(
                    data: Theme.of(context).copyWith(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: IconTheme(
                      data: IconThemeData(color: colors.onPrimaryContainer),
                      child: action,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w700,
                fontFamily:
                    type == EntityType.rollingStock &&
                        TrainModelParser.containsEmu(name)
                    ? 'HVCB'
                    : null,
              ),
            ),
          ],
        ),
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
      widget.trips.toList()
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
                trips: widget.trips,
                enabled: key == 'transfer'
                    ? _hasTransferPair(widget.name, widget.trips)
                    : widget.trips.isNotEmpty,
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
    final draft = await showDialog<_ReviewDraft>(
      context: context,
      builder: (_) => _ReviewEditorDialog(
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

class _ReviewDraft {
  const _ReviewDraft({
    required this.rating,
    required this.comment,
    this.tripId,
    this.secondTripId,
    this.transferMinutes,
    this.dish,
    this.price,
  });

  final int rating;
  final String comment;
  final int? tripId;
  final int? secondTripId;
  final int? transferMinutes;
  final String? dish;
  final double? price;
}

class _ReviewEditorDialog extends StatefulWidget {
  const _ReviewEditorDialog({
    required this.title,
    required this.reviewType,
    required this.trips,
    required this.stationName,
    this.initial,
  });

  final String title;
  final String reviewType;
  final List<TripRecord> trips;
  final String stationName;
  final EntityReview? initial;

  @override
  State<_ReviewEditorDialog> createState() => _ReviewEditorDialogState();
}

class _ReviewEditorDialogState extends State<_ReviewEditorDialog> {
  late final List<TripRecord> _trips;
  late final TextEditingController _comment;
  late final TextEditingController _dish;
  late final TextEditingController _price;
  late int _rating;
  int? _tripId;
  int? _secondTripId;

  bool get _isTransfer => widget.reviewType == 'transfer';
  bool get _isMeal => widget.reviewType == 'meal';
  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _trips = widget.trips.toList()
      ..sort((a, b) => b.departureTime.compareTo(a.departureTime));
    final initial = widget.initial;
    _rating = (initial?.rating ?? 5).clamp(1, 5);
    _comment = TextEditingController(text: initial?.comment ?? '')
      ..addListener(_handleChanged);
    _dish = TextEditingController(text: initial?.dish ?? '');
    final price = initial?.price;
    _price = TextEditingController(
      text: price == null ? '' : price.toStringAsFixed(2),
    );
    final primaryOptions = _primaryTripOptions;
    final tripId = initial?.tripId;
    _tripId = primaryOptions.any((trip) => trip.id == tripId)
        ? tripId
        : (primaryOptions.isEmpty ? null : primaryOptions.first.id);
    final secondTripId = initial?.secondTripId;
    _secondTripId = _secondTripOptions.any((trip) => trip.id == secondTripId)
        ? secondTripId
        : null;
  }

  @override
  void dispose() {
    _comment.dispose();
    _dish.dispose();
    _price.dispose();
    super.dispose();
  }

  void _handleChanged() {
    if (mounted) setState(() {});
  }

  TripRecord? get _primaryTrip {
    if (_tripId == null) return null;
    for (final trip in _trips) {
      if (trip.id == _tripId) return trip;
    }
    return null;
  }

  /// 到达本站，且能在 [_transferWindow] 内接上从本站出发的下一趟行程。
  List<TripRecord> get _primaryTripOptions {
    if (!_isTransfer) return _trips;
    return _trips.where((trip) => _followingTripsFor(trip).isNotEmpty).toList();
  }

  List<TripRecord> _followingTripsFor(TripRecord primary) =>
      _transferFollowingTrips(primary, _trips, widget.stationName);

  List<TripRecord> get _secondTripOptions {
    final primary = _primaryTrip;
    if (!_isTransfer || primary == null) return const [];
    return _followingTripsFor(primary);
  }

  void _selectPrimaryTrip(int value) {
    setState(() {
      _tripId = value;
      final primary = _primaryTrip;
      final second = _secondTripId;
      if (primary == null || second == null) return;
      if (_followingTripsFor(primary).every((trip) => trip.id != second)) {
        _secondTripId = null;
      }
    });
  }

  int? get _transferMinutes {
    final secondTripId = _secondTripId;
    final primary = _primaryTrip;
    if (!_isTransfer || secondTripId == null || primary == null) return null;
    final arrivalTime = primary.arrivalTime;
    if (arrivalTime == null) return null;
    for (final trip in _trips) {
      if (trip.id == secondTripId) {
        return trip.departureTime.difference(arrivalTime).inMinutes;
      }
    }
    return null;
  }

  void _submit() {
    final comment = _comment.text.trim();
    if (comment.isEmpty) return;
    if (_isTransfer && (_tripId == null || _secondTripId == null)) return;
    Navigator.of(context).pop(
      _ReviewDraft(
        rating: _rating,
        comment: comment,
        tripId: _tripId,
        secondTripId: _isTransfer ? _secondTripId : null,
        transferMinutes: _isTransfer ? _transferMinutes : null,
        dish: _isMeal && _dish.text.trim().isNotEmpty
            ? _dish.text.trim()
            : null,
        price: _isMeal ? double.tryParse(_price.text.trim()) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final canSubmit =
        _comment.text.trim().isNotEmpty &&
        (!_isTransfer || (_tripId != null && _secondTripId != null));
    final dishField = TextField(
      controller: _dish,
      decoration: _reviewInputDecoration(
        context,
        label: '菜品',
        prefixIcon: const Icon(Icons.restaurant_outlined, size: 20),
      ),
    );
    final priceField = TextField(
      controller: _price,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _reviewInputDecoration(context, label: '价格', prefixText: '¥'),
    );
    final commentField = TextField(
      controller: _comment,
      minLines: 3,
      maxLines: 6,
      decoration: _reviewInputDecoration(
        context,
        label: '评价内容',
        alignLabelWithHint: true,
      ),
    );
    return AlertDialog(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 440),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      title: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: colors.primaryContainer,
            child: Icon(
              _reviewTypeIcon(widget.reviewType),
              size: 20,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _reviewTypeLabel(widget.reviewType),
                  style: textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '关闭',
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(_entityCardRadius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '评分',
                            style: textTheme.labelLarge?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Text(
                          _ratingLabel(_rating),
                          style: textTheme.titleSmall?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        for (var value = 1; value <= 5; value++)
                          IconButton(
                            tooltip: '$value 星',
                            onPressed: () => setState(() => _rating = value),
                            style: _ratingIconStyle,
                            icon: Icon(
                              value <= _rating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: value <= _rating
                                  ? colors.primary
                                  : colors.outline,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_trips.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownMenu<int>(
                  initialSelection: _tripId,
                  selectOnly: true,
                  expandedInsets: EdgeInsets.zero,
                  menuHeight: 320,
                  label: Text(_isTransfer ? '前序到达' : '关联行程'),
                  leadingIcon: const Icon(
                    Icons.confirmation_number_outlined,
                    size: 20,
                  ),
                  textStyle: textTheme.bodyMedium,
                  inputDecorationTheme: _reviewFieldTheme(context),
                  dropdownMenuEntries: _primaryTripOptions
                      .map(
                        (trip) => DropdownMenuEntry<int>(
                          value: trip.id,
                          label: _tripOptionLabel(trip),
                          labelWidget: Text(
                            _tripOptionLabel(trip),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onSelected: (value) {
                    if (value != null) _selectPrimaryTrip(value);
                  },
                ),
                if (_isTransfer) ...[
                  const SizedBox(height: 16),
                  DropdownMenu<int>(
                    key: ValueKey(
                      'reviewSecondTrip-${_secondTripId ?? 'none'}',
                    ),
                    initialSelection: _secondTripId,
                    selectOnly: true,
                    expandedInsets: EdgeInsets.zero,
                    menuHeight: 320,
                    label: const Text('后序出发'),
                    hintText: '选择 24 小时内从本站出发的行程',
                    leadingIcon: const Icon(Icons.swap_horiz, size: 20),
                    textStyle: textTheme.bodyMedium,
                    inputDecorationTheme: _reviewFieldTheme(context),
                    dropdownMenuEntries: _secondTripOptions
                        .map(
                          (trip) => DropdownMenuEntry<int>(
                            value: trip.id,
                            label: _tripOptionLabel(trip),
                            labelWidget: Text(
                              _tripOptionLabel(trip),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onSelected: (value) =>
                        setState(() => _secondTripId = value),
                  ),
                  const SizedBox(height: 8),
                  _TransferGapHint(minutes: _transferMinutes),
                ],
              ],
              if (_isMeal) ...[
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 300;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: stacked
                              ? constraints.maxWidth
                              : constraints.maxWidth - 128,
                          child: dishField,
                        ),
                        SizedBox(
                          width: stacked ? constraints.maxWidth : 116,
                          child: priceField,
                        ),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
              commentField,
            ],
          ),
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: canSubmit ? _submit : null,
          icon: const Icon(Icons.check, size: 18),
          label: Text(_isEditing ? '保存' : '发布'),
        ),
      ],
    );
  }
}

class _TransferGapHint extends StatelessWidget {
  const _TransferGapHint({required this.minutes});

  final int? minutes;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final value = minutes;
    final invalid = value != null && value < 0;
    final done = value != null && !invalid;
    final text = value == null
        ? '选择后一趟行程后自动计算换乘间隔'
        : invalid
        ? '两趟行程时间顺序有误（${value.abs()} 分钟）'
        : '换乘间隔 $value 分钟';
    final foreground = invalid
        ? colors.onErrorContainer
        : done
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: invalid
            ? colors.errorContainer
            : done
            ? colors.secondaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_entityCardRadius),
      ),
      child: Row(
        children: [
          Icon(
            value == null ? Icons.schedule_outlined : Icons.timelapse,
            size: 16,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodySmall?.copyWith(
                color: foreground,
                fontWeight: done ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
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

String _tripOptionLabel(TripRecord trip) =>
    '${_formatTripDate(trip.departureTime)} · ${trip.trainNumber} · ${trip.fromStation} → ${trip.toStation}';

String _ratingLabel(int rating) => switch (rating) {
  1 => '很差',
  2 => '较差',
  3 => '一般',
  4 => '满意',
  5 => '非常满意',
  _ => '$rating 星',
};

InputDecorationThemeData _reviewFieldTheme(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  final radius = BorderRadius.circular(_entityCardRadius);
  return InputDecorationThemeData(
    filled: true,
    fillColor: colors.surfaceContainerHighest,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: colors.primary, width: 2),
    ),
  );
}

InputDecoration _reviewInputDecoration(
  BuildContext context, {
  required String label,
  bool alignLabelWithHint = false,
  Widget? prefixIcon,
  String? prefixText,
}) => InputDecoration(
  labelText: label,
  alignLabelWithHint: alignLabelWithHint,
  prefixIcon: prefixIcon,
  prefixText: prefixText,
).applyDefaults(_reviewFieldTheme(context));

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
    (trip) => _transferFollowingTrips(trip, candidates, stationName).isNotEmpty,
  );
}

List<TripRecord> _transferFollowingTrips(
  TripRecord primary,
  Iterable<TripRecord> trips,
  String stationName,
) {
  final arrivalTime = primary.arrivalTime;
  if (arrivalTime == null ||
      _normalize(primary.toStation) != _normalize(stationName)) {
    return const [];
  }
  final latest = arrivalTime.add(_transferWindow);
  return trips
      .where(
        (trip) =>
            trip.id != primary.id &&
            _normalize(trip.fromStation) == _normalize(stationName) &&
            !trip.departureTime.isBefore(arrivalTime) &&
            !trip.departureTime.isAfter(latest),
      )
      .toList();
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
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_entityCardRadius),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: enabled ? onReview : null,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('评论'),
              ),
            ],
          ),
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

String _formatReviewDate(String value) {
  final d = DateTime.tryParse(value)?.toLocal();
  if (d == null) return value;
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

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
  Widget build(BuildContext context) {
    final primaryMatches = trips.where((t) => t.id == review.tripId);
    final secondaryMatches = trips.where((t) => t.id == review.secondTripId);
    final primary = primaryMatches.isEmpty ? null : primaryMatches.first;
    final secondary = secondaryMatches.isEmpty ? null : secondaryMatches.first;
    final extra = _reviewExtra(review);
    final seat = review.reviewType == 'rollingStock'
        ? [primary?.seatType, secondary?.seatType]
              .where((value) => value?.trim().isNotEmpty == true)
              .map((value) => value!.trim())
              .toSet()
              .join(' / ')
        : '';
    final routeRange = review.reviewType == 'route' && primary != null
        ? _routeRange(primary, entityName)
        : '';
    return Padding(
      padding: EdgeInsets.only(bottom: showDivider ? 8 : 0),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: showDivider
                ? BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  )
                : BorderSide.none,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 8, showDivider ? 14 : 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => _openUser(context),
                child: CachedAvatar(
                  name: review.displayName,
                  imageUrl: review.avatarUrl,
                  size: 40,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                review.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        if (review.userId == SessionService.instance.user?.id)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '编辑评价',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _editReview(context),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                              ),
                              IconButton(
                                tooltip: '删除评价',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _deleteReview(context),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          '★' * review.rating,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (extra.isNotEmpty ||
                            seat.isNotEmpty ||
                            routeRange.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              [
                                extra,
                                if (seat.isNotEmpty) '席别：$seat',
                                if (routeRange.isNotEmpty) '乘坐区间：$routeRange',
                              ].where((value) => value.isNotEmpty).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ] else
                          const Spacer(),
                        Text(
                          _formatReviewDate(review.createdAt),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      review.comment,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (primary != null)
                      _ReviewTripLink(
                        roleLabel: review.reviewType == 'transfer'
                            ? '前序行程 · 到站 ${_formatTime(primary.arrivalTime)}'
                            : null,
                        trip: primary,
                        userId: review.userId,
                        onwerName: review.displayName,
                        showSeat: false,
                      ),
                    if (secondary != null)
                      _ReviewTripLink(
                        roleLabel:
                            '后续行程 · 发车 ${_formatTime(secondary.departureTime)}',
                        trip: secondary,
                        userId: review.userId,
                        onwerName: review.displayName,
                        showSeat: false,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editReview(BuildContext context) async {
    final draft = await showDialog<_ReviewDraft>(
      context: context,
      builder: (_) => _ReviewEditorDialog(
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
}

class _ReviewTripLink extends StatelessWidget {
  const _ReviewTripLink({
    required this.trip,
    required this.userId,
    required this.onwerName,
    this.roleLabel,
    this.showSeat = false,
  });
  final TripRecord trip;
  final String userId;
  final String onwerName;
  final String? roleLabel;
  final bool showSeat;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final seat = trip.seatType?.trim() ?? '';
    final summary = [
      _formatTripDate(trip.departureTime),
      trip.trainNumber,
      '${trip.fromStation} → ${trip.toStation}',
      if (showSeat && seat.isNotEmpty) seat,
    ].where((part) => part.isNotEmpty).join(' · ');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      leading: const Icon(Icons.confirmation_number_outlined, size: 18),
      title: Text(
        roleLabel ?? summary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: colors.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: roleLabel == null
          ? null
          : Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
      onTap: () => Navigator.of(context).push(
        m3PageRoute(
          builder: (_) => TripRecordDetailsPage.public(
            ticketId: trip.ticketId ?? trip.id,
            onOwnerTap: () => Navigator.of(
              context,
            ).push(m3PageRoute(builder: (_) => PublicUserPage(userId: userId))),
          ),
        ),
      ),
    );
  }
}

String _formatTime(DateTime? value) => value == null
    ? '未记录'
    : '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _routeRange(TripRecord trip, String route) {
  final segment = trip.viaRouteSegments.where(
    (s) => _normalize(s.routeName) == _normalize(route),
  );
  if (segment.isEmpty) return '${trip.fromStation}→${trip.toStation}';
  final first = segment.first;
  final last = segment.last;
  return '${first.fromStation}→${last.toStation}';
}

String _formatTripDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _reviewExtra(EntityReview r) {
  final parts = <String>[];
  if (r.transferMinutes != null) parts.add('换乘 ${r.transferMinutes} 分钟');
  if (r.dish?.isNotEmpty == true) parts.add('菜品：${r.dish}');
  if (r.price != null) parts.add('¥${r.price!.toStringAsFixed(2)}');
  return parts.join(' · ');
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
