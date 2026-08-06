import 'package:flutter/material.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/route_service.dart';
import 'package:raillog/src/services/trip_map_service.dart';
import 'package:raillog/src/widgets/trip_map_webview.dart';

enum _DatePreset { all, thisYear, recentYear, custom }

class TripMapPage extends StatefulWidget {
  const TripMapPage({super.key, this.trips});

  final List<TripRecord>? trips;

  @override
  State<TripMapPage> createState() => _TripMapPageState();
}

class _TripMapPageState extends State<TripMapPage> {
  late Future<_MapSourceData> _sourceFuture;
  _DatePreset _preset = _DatePreset.all;
  DateTimeRange? _customRange;
  bool _showStationMarkers = true;

  @override
  void initState() {
    super.initState();
    _sourceFuture = _loadSource();
  }

  Future<_MapSourceData> _loadSource() async {
    final trips = widget.trips ?? await DbHelper.instance.getAllTrips();
    final results = await Future.wait([
      TripMapService.loadCoordinates(),
      RouteService.resolveTripStations(trips),
    ]);
    return _MapSourceData(
      trips: trips,
      coordinates: results[0] as StationCoordinateIndex,
      journeyStations: results[1] as Map<String, List<String>>,
    );
  }

  Future<void> _retry() async {
    final future = _loadSource();
    setState(() => _sourceFuture = future);
    await future;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('地图')),
    body: FutureBuilder<_MapSourceData>(
      future: _sourceFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _MapStatus(
            icon: Icons.error_outline,
            message: '读取行程地图失败',
            onRetry: _retry,
          );
        }
        if (!snapshot.hasData) {
          return const _MapStatus(message: '正在生成铁路行程轨迹');
        }

        final range = _selectedRange();
        final data = TripMapService.buildData(
          snapshot.data!.trips,
          snapshot.data!.coordinates,
          journeyStations: snapshot.data!.journeyStations,
          start: range?.start,
          endExclusive: range == null
              ? null
              : DateTime(range.end.year, range.end.month, range.end.day + 1),
        );
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        return Column(
          children: [
            _FilterBar(
              preset: _preset,
              customRange: _customRange,
              data: data,
              showStationMarkers: _showStationMarkers,
              onPresetChanged: (preset) => setState(() => _preset = preset),
              onCustomRange: () => _selectCustomRange(snapshot.data!.trips),
              onShowStationMarkersChanged: (value) =>
                  setState(() => _showStationMarkers = value),
            ),
            Expanded(
              child: data.tripCount == 0
                  ? const _MapStatus(
                      icon: Icons.route_outlined,
                      message: '所选日期内没有铁路行程',
                    )
                  : data.routes.isEmpty
                  ? _MapStatus(
                      icon: Icons.location_off_outlined,
                      message: data.missingViaRouteCount == data.tripCount
                          ? '所选行程缺少经由线路，无法绘制'
                          : '所选行程的车站暂时无法定位',
                    )
                  : TripMapWebView(
                      backgroundColor: theme.colorScheme.surface,
                      html: buildAmapHtml(
                        data.routes,
                        darkMode: isDark,
                        backgroundColor: _cssColor(theme.colorScheme.surface),
                        showStationMarkers: _showStationMarkers,
                        endpoints: data.endpoints,
                      ),
                    ),
            ),
          ],
        );
      },
    ),
  );

  DateTimeRange? _selectedRange() {
    final now = DateTime.now();
    return switch (_preset) {
      _DatePreset.all => null,
      _DatePreset.thisYear => DateTimeRange(
        start: DateTime(now.year),
        end: DateTime(now.year, now.month, now.day),
      ),
      _DatePreset.recentYear => DateTimeRange(
        start: DateTime(now.year - 1, now.month, now.day),
        end: DateTime(now.year, now.month, now.day),
      ),
      _DatePreset.custom => _customRange,
    };
  }

  Future<void> _selectCustomRange(List<TripRecord> trips) async {
    final railDates = trips
        .where((trip) => trip.isRailTrip)
        .map((trip) => trip.departureTime)
        .toList();
    final now = DateTime.now();
    final earliest = railDates.isEmpty
        ? DateTime(now.year - 10)
        : railDates.reduce((a, b) => a.isBefore(b) ? a : b);
    final latest = railDates.isEmpty
        ? now
        : railDates.reduce((a, b) => a.isAfter(b) ? a : b);
    final firstDate = DateTime(earliest.year, earliest.month, earliest.day);
    final lastTripDate = DateTime(latest.year, latest.month, latest.day);
    final today = DateTime(now.year, now.month, now.day);
    final lastDate = lastTripDate.isAfter(today) ? lastTripDate : today;
    final selected = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: _customRange,
      helpText: '筛选出发日期',
      saveText: '应用',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _customRange = selected;
      _preset = _DatePreset.custom;
    });
  }
}

class _MapSourceData {
  const _MapSourceData({
    required this.trips,
    required this.coordinates,
    required this.journeyStations,
  });

  final List<TripRecord> trips;
  final StationCoordinateIndex coordinates;
  final Map<String, List<String>> journeyStations;
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.preset,
    required this.customRange,
    required this.data,
    required this.showStationMarkers,
    required this.onPresetChanged,
    required this.onCustomRange,
    required this.onShowStationMarkersChanged,
  });

  final _DatePreset preset;
  final DateTimeRange? customRange;
  final TripMapData data;
  final bool showStationMarkers;
  final ValueChanged<_DatePreset> onPresetChanged;
  final VoidCallback onCustomRange;
  final ValueChanged<bool> onShowStationMarkersChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _choice('全部', _DatePreset.all),
                    const SizedBox(width: 8),
                    _choice('今年', _DatePreset.thisYear),
                    const SizedBox(width: 8),
                    _choice('近一年', _DatePreset.recentYear),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      avatar: const Icon(Icons.date_range_outlined, size: 18),
                      label: Text(
                        preset == _DatePreset.custom && customRange != null
                            ? '${_date(customRange!.start)} 至 ${_date(customRange!.end)}'
                            : '自定义',
                      ),
                      selected: preset == _DatePreset.custom,
                      onSelected: (_) => onCustomRange(),
                    ),
                    const SizedBox(width: 12),
                    Text('车站标记', style: Theme.of(context).textTheme.labelLarge),
                    Switch(
                      value: showStationMarkers,
                      onChanged: onShowStationMarkersChanged,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${data.mappedTripCount}/${data.tripCount} 段轨迹',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (data.missingStations.isNotEmpty) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: '无法定位：${data.missingStations.join('、')}',
                child: Icon(
                  Icons.location_off_outlined,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _choice(String label, _DatePreset value) => ChoiceChip(
    label: Text(label),
    selected: preset == value,
    onSelected: (_) => onPresetChanged(value),
  );
}

class _MapStatus extends StatelessWidget {
  const _MapStatus({required this.message, this.icon, this.onRetry});

  final String message;
  final IconData? icon;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon == null)
            const CircularProgressIndicator()
          else
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ],
      ),
    ),
  );
}

String _date(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _cssColor(Color color) {
  final value = color.toARGB32().toRadixString(16).padLeft(8, '0');
  return '#${value.substring(2)}';
}
