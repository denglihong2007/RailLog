import 'package:flutter/material.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/services/entity_review_service.dart';
import 'package:raillog/src/services/route_service.dart';
import 'package:raillog/src/theme/app_theme.dart';

/// 评价编辑器。实体详情页与设置里的「我的评价」共用同一个弹窗，
/// 因此这里的行程候选、换乘配对、线路站点都按同一套规则算。
const reviewTransferWindow = Duration(hours: 24);

final ButtonStyle _ratingIconStyle = IconButton.styleFrom(
  minimumSize: const Size.square(48),
  maximumSize: const Size.square(48),
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.padded,
  visualDensity: VisualDensity.standard,
  iconSize: 26,
);

class ReviewDraft {
  const ReviewDraft({
    required this.rating,
    required this.comment,
    this.tripId,
    this.secondTripId,
    this.transferMinutes,
    this.routeFromStation,
    this.routeToStation,
    this.dish,
    this.price,
  });

  final int rating;
  final String comment;
  final int? tripId;
  final int? secondTripId;
  final int? transferMinutes;
  final String? routeFromStation;
  final String? routeToStation;
  final String? dish;
  final double? price;
}

class ReviewEditorDialog extends StatefulWidget {
  const ReviewEditorDialog({
    super.key,
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
  State<ReviewEditorDialog> createState() => _ReviewEditorDialogState();
}

class _ReviewEditorDialogState extends State<ReviewEditorDialog> {
  late final List<TripRecord> _trips;
  late final TextEditingController _comment;
  late final TextEditingController _dish;
  late final TextEditingController _price;
  late int _rating;
  int? _tripId;
  int? _secondTripId;
  List<String> _routeStationOptions = const [];
  String? _routeFromStation;
  String? _routeToStation;
  String? _routeStationsError;
  bool _loadingRouteStations = false;
  int _routeStationLoadId = 0;

  bool get _isTransfer => widget.reviewType == 'transfer';
  bool get _isMeal => widget.reviewType == 'meal';
  bool get _isRoute => widget.reviewType == 'route';
  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _trips = widget.trips.where(canUseAsReviewTrip).toList()
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
    _tripId = initial == null
        ? (primaryOptions.isEmpty ? null : primaryOptions.first.ticketId)
        : (primaryOptions.any((trip) => trip.ticketId == tripId)
              ? tripId
              : null);
    final secondTripId = initial?.secondTripId;
    _secondTripId =
        _secondTripOptions.any((trip) => trip.ticketId == secondTripId)
        ? secondTripId
        : null;
    _routeFromStation = initial?.routeFromStation;
    _routeToStation = initial?.routeToStation;
    if (_isRoute) {
      _loadingRouteStations = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadRouteStations(resetSelection: false);
      });
    }
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
      if (trip.ticketId == _tripId) return trip;
    }
    return null;
  }

  /// 到达本站，且能在 [reviewTransferWindow] 内接上从本站出发的下一趟行程。
  List<TripRecord> get _primaryTripOptions {
    if (!_isTransfer) return _trips;
    return _trips.where((trip) => _followingTripsFor(trip).isNotEmpty).toList();
  }

  List<TripRecord> _followingTripsFor(TripRecord primary) =>
      transferFollowingTrips(primary, _trips, widget.stationName);

  List<TripRecord> get _secondTripOptions {
    final primary = _primaryTrip;
    if (!_isTransfer || primary == null) return const [];
    return _followingTripsFor(primary);
  }

  List<String> get _routeEndOptions {
    final fromStation = _routeFromStation;
    if (fromStation == null) return const [];
    final index = _routeStationOptions.indexOf(fromStation);
    if (index < 0 || index + 1 >= _routeStationOptions.length) {
      return const [];
    }
    return _routeStationOptions.sublist(index + 1);
  }

  bool get _hasRouteRange =>
      _routeFromStation != null && _routeToStation != null;

  Future<void> _loadRouteStations({required bool resetSelection}) async {
    final loadId = ++_routeStationLoadId;
    final trip = _primaryTrip;
    setState(() {
      _loadingRouteStations = true;
      _routeStationsError = null;
      if (resetSelection) {
        _routeFromStation = null;
        _routeToStation = null;
      }
    });
    if (trip == null) {
      if (!mounted || loadId != _routeStationLoadId) return;
      setState(() {
        _routeStationOptions = const [];
        _loadingRouteStations = false;
      });
      return;
    }
    try {
      final stations = await routeStationsForReview(trip, widget.stationName);
      if (!mounted || loadId != _routeStationLoadId) return;
      setState(() {
        _routeStationOptions = stations;
        _loadingRouteStations = false;
        if (!stations.contains(_routeFromStation)) {
          _routeFromStation = null;
        }
        if (_routeFromStation == null ||
            !_routeEndOptions.contains(_routeToStation)) {
          _routeToStation = null;
        }
        if (stations.length < 2) {
          _routeStationsError = '该行程没有足够的线路站点可供选择';
        }
      });
    } catch (_) {
      if (!mounted || loadId != _routeStationLoadId) return;
      setState(() {
        _routeStationOptions = const [];
        _routeFromStation = null;
        _routeToStation = null;
        _loadingRouteStations = false;
        _routeStationsError = '读取线路站点失败';
      });
    }
  }

  void _selectPrimaryTrip(int value) {
    setState(() {
      _tripId = value;
      final primary = _primaryTrip;
      final second = _secondTripId;
      if (primary == null || second == null) return;
      if (_followingTripsFor(
        primary,
      ).every((trip) => trip.ticketId != second)) {
        _secondTripId = null;
      }
    });
    if (_isRoute) _loadRouteStations(resetSelection: true);
  }

  int? get _transferMinutes {
    final secondTripId = _secondTripId;
    final primary = _primaryTrip;
    if (!_isTransfer || secondTripId == null || primary == null) return null;
    final arrivalTime = primary.arrivalTime;
    if (arrivalTime == null) return null;
    for (final trip in _trips) {
      if (trip.ticketId == secondTripId) {
        return trip.departureTime.difference(arrivalTime).inMinutes;
      }
    }
    return null;
  }

  void _submit() {
    final comment = _comment.text.trim();
    if (comment.isEmpty) return;
    if (_isTransfer && (_tripId == null || _secondTripId == null)) return;
    if (_isRoute && !_hasRouteRange) return;
    Navigator.of(context).pop(
      ReviewDraft(
        rating: _rating,
        comment: comment,
        tripId: _tripId,
        secondTripId: _isTransfer ? _secondTripId : null,
        transferMinutes: _isTransfer ? _transferMinutes : null,
        routeFromStation: _isRoute ? _routeFromStation : null,
        routeToStation: _isRoute ? _routeToStation : null,
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
        (!_isTransfer || (_tripId != null && _secondTripId != null)) &&
        (!_isRoute ||
            (_tripId != null &&
                !_loadingRouteStations &&
                _routeStationsError == null &&
                _hasRouteRange));
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
                Text(widget.title, style: textTheme.titleLarge),
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
                  borderRadius: BorderRadius.circular(AppRadius.small),
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
                          value: trip.ticketId!,
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
                if (_isRoute) ...[
                  const SizedBox(height: 16),
                  if (_loadingRouteStations)
                    const LinearProgressIndicator(minHeight: 3),
                  if (_routeStationsError != null)
                    Text(
                      _routeStationsError!,
                      style: textTheme.bodySmall?.copyWith(color: colors.error),
                    ),
                  if (!_loadingRouteStations &&
                      _routeStationsError == null) ...[
                    DropdownMenu<String>(
                      key: ValueKey(
                        'reviewRouteFrom-${_tripId ?? 'none'}-${_routeFromStation ?? 'none'}',
                      ),
                      initialSelection: _routeFromStation,
                      selectOnly: true,
                      expandedInsets: EdgeInsets.zero,
                      menuHeight: 320,
                      label: const Text('评价起点'),
                      hintText: '选择起点站',
                      leadingIcon: const Icon(Icons.trip_origin, size: 20),
                      textStyle: textTheme.bodyMedium,
                      inputDecorationTheme: _reviewFieldTheme(context),
                      dropdownMenuEntries: _routeStationOptions
                          .map(
                            (station) => DropdownMenuEntry<String>(
                              value: station,
                              label: station,
                            ),
                          )
                          .toList(),
                      onSelected: (value) {
                        if (value == null) return;
                        setState(() {
                          _routeFromStation = value;
                          _routeToStation = null;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownMenu<String>(
                      key: ValueKey(
                        'reviewRouteTo-${_tripId ?? 'none'}-${_routeFromStation ?? 'none'}-${_routeToStation ?? 'none'}',
                      ),
                      initialSelection: _routeToStation,
                      selectOnly: true,
                      enabled: _routeFromStation != null,
                      expandedInsets: EdgeInsets.zero,
                      menuHeight: 320,
                      label: const Text('评价终点'),
                      hintText: _routeFromStation == null ? '请先选择起点站' : '选择终点站',
                      leadingIcon: const Icon(Icons.place_outlined, size: 20),
                      textStyle: textTheme.bodyMedium,
                      inputDecorationTheme: _reviewFieldTheme(context),
                      dropdownMenuEntries: _routeEndOptions
                          .map(
                            (station) => DropdownMenuEntry<String>(
                              value: station,
                              label: station,
                            ),
                          )
                          .toList(),
                      onSelected: (value) =>
                          setState(() => _routeToStation = value),
                    ),
                  ],
                ],
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
                            value: trip.ticketId!,
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
        borderRadius: BorderRadius.circular(AppRadius.small),
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

/// 只有带云端 Id 且非「仅本地」的行程才能挂到评价上。
bool canUseAsReviewTrip(TripRecord trip) =>
    trip.ticketId != null && !trip.isLocalOnly;

/// [primary] 到达 [stationName] 后，[reviewTransferWindow] 内从同一车站出发的后序行程。
List<TripRecord> transferFollowingTrips(
  TripRecord primary,
  Iterable<TripRecord> trips,
  String stationName,
) {
  final arrivalTime = primary.arrivalTime;
  if (arrivalTime == null ||
      _normalize(primary.toStation) != _normalize(stationName)) {
    return const [];
  }
  final latest = arrivalTime.add(reviewTransferWindow);
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

/// 线路评价的可选站点：优先用行程里的线路分段，其次查线路库，最后退回分段端点。
Future<List<String>> routeStationsForReview(
  TripRecord trip,
  String routeName,
) async {
  final segments = trip.viaRouteSegments
      .where(
        (segment) => _normalize(segment.routeName) == _normalize(routeName),
      )
      .toList();
  if (segments.isEmpty) {
    return RouteService.getStationsForRoute(routeName);
  }
  final stations = await RouteService.getStationsBetweenRoute(
    routeName,
    segments.first.fromStation,
    segments.last.toStation,
  );
  if (stations.isNotEmpty) {
    return stations.map((station) => station.name).toList();
  }
  final fallback = <String>[];
  void append(String value) {
    final station = value.trim();
    if (station.isNotEmpty && (fallback.isEmpty || fallback.last != station)) {
      fallback.add(station);
    }
  }

  append(segments.first.fromStation);
  for (final segment in segments) {
    append(segment.toStation);
  }
  return fallback;
}

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
  final radius = BorderRadius.circular(AppRadius.small);
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

String _formatTripDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
