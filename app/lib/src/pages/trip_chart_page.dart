import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/trip_chart_series.dart';
import 'package:raillog/src/pages/all_trips_page.dart';

enum _TripChartStyle { line, heatmap }

class TripChartPage extends StatefulWidget {
  const TripChartPage({super.key, required this.trips});

  final List<DashboardTripEntry> trips;

  @override
  State<TripChartPage> createState() => _TripChartPageState();
}

class _TripChartPageState extends State<TripChartPage> {
  TripChartMetric _metric = TripChartMetric.mileage;
  TripChartInterval _interval = TripChartInterval.month;
  TripChartRailFilter _railFilter = TripChartRailFilter.all;
  _TripChartStyle _style = _TripChartStyle.line;
  bool _isLoadingChart = false;
  late DateTimeRange _range;
  final _heatmapScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final dates = widget.trips.map((trip) => _dateOnly(trip.departureTime));
    if (dates.isEmpty) {
      final today = _dateOnly(DateTime.now());
      _range = DateTimeRange(start: today, end: today);
    } else {
      final sorted = dates.toList()..sort();
      _range = DateTimeRange(start: sorted.first, end: sorted.last);
    }
  }

  @override
  void dispose() {
    _heatmapScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final points = buildTripChartSeries(
      trips: widget.trips,
      rangeStart: _range.start,
      rangeEnd: _range.end,
      metric: _metric,
      interval: _interval,
      railFilter: _railFilter,
    );
    final total = points.fold<double>(0, (sum, point) => sum + point.value);
    final matchingTripCount = widget.trips.where((trip) {
      final date = _dateOnly(trip.departureTime);
      if (date.isBefore(_range.start) || date.isAfter(_range.end)) return false;
      return switch (_railFilter) {
        TripChartRailFilter.all => true,
        TripChartRailFilter.rail => trip.isRailTrip,
        TripChartRailFilter.nonRail => !trip.isRailTrip,
      };
    }).length;

    return Scaffold(
      appBar: AppBar(title: const Text('行程趋势')),
      backgroundColor: colors.surfaceContainerLowest,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MetricSelector(
                    value: _metric,
                    onChanged: (value) => setState(() => _metric = value),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: colors.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: colors.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _TripTypeMenu(
                            value: _railFilter,
                            onChanged: (value) =>
                                setState(() => _railFilter = value),
                          ),
                          _CompactIntervalSelector(
                            value: _interval,
                            onChanged: _changeInterval,
                          ),
                          OutlinedButton.icon(
                            onPressed: _selectDateRange,
                            icon: const Icon(Icons.date_range_outlined),
                            label: Text(
                              '${_formatShortDate(_range.start)} - ${_formatShortDate(_range.end)}',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ChartStyleSelector(
                    value: _style,
                    onChanged: _changeChartStyle,
                  ),
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _metricLabel(_metric),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatMetricValue(_metric, total),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '$matchingTripCount 条行程',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: colors.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        _style == _TripChartStyle.heatmap ? 12 : 24,
                        16,
                        12,
                      ),
                      child: _isLoadingChart
                          ? const SizedBox(
                              height: 154,
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : matchingTripCount == 0
                          ? SizedBox(
                              height: 300,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.show_chart,
                                      size: 32,
                                      color: colors.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 10),
                                    const Text('当前筛选范围内暂无行程'),
                                  ],
                                ),
                              ),
                            )
                          : _style == _TripChartStyle.line
                          ? _TripLineChart(
                              points: points,
                              metric: _metric,
                              interval: _interval,
                            )
                          : _CalendarHeatmap(
                              points: points,
                              trips: widget.trips,
                              metric: _metric,
                              interval: _interval,
                              railFilter: _railFilter,
                              onCellTap: _showBucketTrips,
                              scrollController: _heatmapScrollController,
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '${_railFilterLabel(_railFilter)} · 按${_intervalLabel(_interval)}汇总 · ${_formatDate(_range.start)} 至 ${_formatDate(_range.end)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDateRange() async {
    final tripDates = widget.trips.map((trip) => _dateOnly(trip.departureTime));
    final sorted = tripDates.toList()..sort();
    final baselineFirst = DateTime(2000);
    final baselineLast = _dateOnly(
      DateTime.now().add(const Duration(days: 365)),
    );
    final firstDate = sorted.isNotEmpty && sorted.first.isBefore(baselineFirst)
        ? sorted.first
        : baselineFirst;
    final lastDate = sorted.isNotEmpty && sorted.last.isAfter(baselineLast)
        ? sorted.last
        : baselineLast;
    if (!mounted) return;
    final selected = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: _range,
      helpText: '选择统计日期范围',
      saveText: '确定',
      cancelText: '取消',
    );
    if (selected != null && mounted) {
      setState(() => _range = selected);
      if (_style == _TripChartStyle.heatmap) {
        await _scrollHeatmapToEnd();
      }
    }
  }

  void _changeInterval(TripChartInterval value) {
    if (value == _interval) return;
    setState(() => _interval = value);
    if (_style == _TripChartStyle.heatmap) _scrollHeatmapToEnd();
  }

  Future<void> _changeChartStyle(_TripChartStyle value) async {
    if (value == _style || _isLoadingChart) return;
    setState(() => _isLoadingChart = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() => _style = value);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() => _isLoadingChart = false);
    if (_style == _TripChartStyle.heatmap) await _scrollHeatmapToEnd();
  }

  Future<void> _scrollHeatmapToEnd() async {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_heatmapScrollController.hasClients) return;
    _heatmapScrollController.jumpTo(
      _heatmapScrollController.position.maxScrollExtent,
    );
  }

  Future<void> _showBucketTrips(TripChartPoint point) async {
    final trips = widget.trips.where((trip) {
      final date = _dateOnly(trip.departureTime);
      final end = _nextBucket(point.bucketStart, _interval);
      final matchesFilter = switch (_railFilter) {
        TripChartRailFilter.all => true,
        TripChartRailFilter.rail => trip.isRailTrip,
        TripChartRailFilter.nonRail => !trip.isRailTrip,
      };
      return !date.isBefore(point.bucketStart) &&
          date.isBefore(end) &&
          matchesFilter;
    }).toList()..sort((a, b) => b.departureTime.compareTo(a.departureTime));
    if (!mounted || trips.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AllTripsPage(
          trips: trips,
          title:
              '${_bucketTooltip(point.bucketStart, _interval)} · ${trips.length} 张车票',
          showTripKindFilter: false,
        ),
      ),
    );
  }
}

class _ChartStyleSelector extends StatelessWidget {
  const _ChartStyleSelector({required this.value, required this.onChanged});

  final _TripChartStyle value;
  final ValueChanged<_TripChartStyle> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<_TripChartStyle>(
    showSelectedIcon: false,
    segments: const [
      ButtonSegment(
        value: _TripChartStyle.line,
        icon: Icon(Icons.show_chart),
        label: Text('折线图'),
      ),
      ButtonSegment(
        value: _TripChartStyle.heatmap,
        icon: Icon(Icons.grid_view),
        label: Text('粒度图'),
      ),
    ],
    selected: {value},
    onSelectionChanged: (selection) => onChanged(selection.first),
  );
}

class _MetricSelector extends StatelessWidget {
  const _MetricSelector({required this.value, required this.onChanged});

  final TripChartMetric value;
  final ValueChanged<TripChartMetric> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<TripChartMetric>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: TripChartMetric.mileage,
            icon: Icon(Icons.route_outlined),
            label: Text('里程'),
          ),
          ButtonSegment(
            value: TripChartMetric.count,
            icon: Icon(Icons.confirmation_number_outlined),
            label: Text('次数'),
          ),
          ButtonSegment(
            value: TripChartMetric.duration,
            icon: Icon(Icons.schedule_outlined),
            label: Text('时长'),
          ),
          ButtonSegment(
            value: TripChartMetric.spending,
            icon: Icon(Icons.payments_outlined),
            label: Text('花费'),
          ),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

class _TripTypeMenu extends StatelessWidget {
  const _TripTypeMenu({required this.value, required this.onChanged});

  final TripChartRailFilter value;
  final ValueChanged<TripChartRailFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: TripChartRailFilter.values
          .map(
            (filter) => MenuItemButton(
              onPressed: () => onChanged(filter),
              leadingIcon: Icon(
                filter == value ? Icons.check : _railFilterIcon(filter),
              ),
              child: Text(_railFilterLabel(filter)),
            ),
          )
          .toList(growable: false),
      builder: (context, controller, child) => OutlinedButton.icon(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: Icon(_railFilterIcon(value)),
        label: Text(_railFilterLabel(value)),
      ),
    );
  }
}

class _CompactIntervalSelector extends StatelessWidget {
  const _CompactIntervalSelector({
    required this.value,
    required this.onChanged,
  });

  final TripChartInterval value;
  final ValueChanged<TripChartInterval> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TripChartInterval>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: TripChartInterval.year, label: Text('年')),
        ButtonSegment(value: TripChartInterval.month, label: Text('月')),
        ButtonSegment(value: TripChartInterval.week, label: Text('周')),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
      style: const ButtonStyle(
        visualDensity: VisualDensity(horizontal: -2, vertical: -1),
      ),
    );
  }
}

class _TripLineChart extends StatelessWidget {
  const _TripLineChart({
    required this.points,
    required this.metric,
    required this.interval,
  });

  final List<TripChartPoint> points;
  final TripChartMetric metric;
  final TripChartInterval interval;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final maxValue = points.fold<double>(0, (value, point) {
      return math.max(value, point.value);
    });
    final chartMaxY = maxValue <= 0 ? 1.0 : maxValue * 1.15;
    final horizontalInterval = chartMaxY / 4;

    return LayoutBuilder(
      builder: (context, constraints) {
        final targetLabels = math.max(
          2,
          math.min(7, (constraints.maxWidth / 88).floor()),
        );
        final labelStep = math.max(1, (points.length / targetLabels).ceil());
        return SizedBox(
          height: 300,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: math.max(1, points.length - 1).toDouble(),
              minY: 0,
              maxY: chartMaxY,
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: horizontalInterval,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: colors.outlineVariant.withValues(alpha: 0.55),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 52,
                    interval: horizontalInterval,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(
                        _compactNumber(value),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if (index < 0 || index >= points.length) {
                        return const SizedBox.shrink();
                      }
                      if (index % labelStep != 0 &&
                          index != points.length - 1) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 10,
                        child: Text(
                          _bucketLabel(points[index].bucketStart, interval),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => colors.inverseSurface,
                  getTooltipItems: (spots) => spots
                      .map((spot) {
                        final index = spot.x.round();
                        final point = points[index];
                        return LineTooltipItem(
                          '${_bucketTooltip(point.bucketStart, interval)}\n${_formatMetricValue(metric, point.value)}',
                          TextStyle(color: colors.onInverseSurface),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: points.indexed
                      .map(
                        (entry) => FlSpot(entry.$1.toDouble(), entry.$2.value),
                      )
                      .toList(growable: false),
                  color: colors.primary,
                  barWidth: 2.5,
                  isCurved: points.length > 2,
                  curveSmoothness: 0.16,
                  dotData: FlDotData(show: points.length <= 16),
                  belowBarData: BarAreaData(show: false),
                ),
              ],
            ),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          ),
        );
      },
    );
  }
}

class _TripHeatmap extends StatelessWidget {
  const _TripHeatmap({
    required this.points,
    required this.trips,
    required this.metric,
    required this.interval,
    required this.railFilter,
    required this.onCellTap,
    required this.scrollController,
  });

  final List<TripChartPoint> points;
  final List<DashboardTripEntry> trips;
  final TripChartMetric metric;
  final TripChartInterval interval;
  final TripChartRailFilter railFilter;
  final ValueChanged<TripChartPoint> onCellTap;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final columns = points.length.clamp(1, 10000);
    final scale = _heatmapScale(metric, interval);
    final rowCount = scale.labels.length;
    final tripCounts = <DateTime, int>{};
    for (final trip in trips) {
      final allowed = switch (railFilter) {
        TripChartRailFilter.all => true,
        TripChartRailFilter.rail => trip.isRailTrip,
        TripChartRailFilter.nonRail => !trip.isRailTrip,
      };
      if (!allowed) continue;
      final bucket = _bucketStart(_dateOnly(trip.departureTime), interval);
      tripCounts[bucket] = (tripCounts[bucket] ?? 0) + 1;
    }
    return SizedBox(
      height: 46 + rowCount * 20,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Column(
              children: [
                const SizedBox(height: 26),
                ...scale.labels.indexed.map(
                  (entry) => SizedBox(
                    height: 20,
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Color.lerp(
                              colors.primaryContainer,
                              colors.primary,
                              (rowCount - 1 - entry.$1) /
                                  math.max(1, rowCount - 1),
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            entry.$2,
                            maxLines: 1,
                            softWrap: false,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Listener(
              onPointerSignal: (event) {
                if (event is! PointerScrollEvent ||
                    !scrollController.hasClients) {
                  return;
                }
                final delta = event.scrollDelta.dx != 0
                    ? event.scrollDelta.dx
                    : event.scrollDelta.dy;
                final position = scrollController.position;
                scrollController.jumpTo(
                  (position.pixels + delta).clamp(
                    position.minScrollExtent,
                    position.maxScrollExtent,
                  ),
                );
              },
              child: Scrollbar(
                controller: scrollController,
                thumbVisibility: true,
                child: ScrollConfiguration(
                  behavior: const _HeatmapScrollBehavior(),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: List.generate(
                            columns,
                            (column) => SizedBox(
                              width: 20,
                              height: 20,
                              child: OverflowBox(
                                alignment: Alignment.centerLeft,
                                maxWidth: 80,
                                minHeight: 20,
                                maxHeight: 20,
                                child: Text(
                                  _heatmapColumnLabel(points, column, interval),
                                  style: Theme.of(context).textTheme.labelSmall,
                                  maxLines: 1,
                                  softWrap: false,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List.generate(columns, (column) {
                            final point = points[column];
                            final pointRow =
                                (rowCount - 1) -
                                (_heatmapLevel(point.value, metric) *
                                        (rowCount - 1) /
                                        4)
                                    .round();
                            final tripsInBucket =
                                tripCounts[point.bucketStart] ?? 0;
                            return Padding(
                              padding: EdgeInsets.only(
                                right: column == columns - 1 ? 0 : 4,
                              ),
                              child: Column(
                                children: List.generate(rowCount, (row) {
                                  if (row != pointRow) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Ink(
                                        width: 16,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          color: colors.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Tooltip(
                                      message:
                                          '${_bucketTooltip(point.bucketStart, interval)}\n${_formatMetricValue(metric, point.value)}',
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(3),
                                        onTap: tripsInBucket == 0
                                            ? null
                                            : () => onCellTap(point),
                                        child: Ink(
                                          width: 16,
                                          height: 16,
                                          decoration: BoxDecoration(
                                            color: _heatmapColor(
                                              colors,
                                              point.value,
                                              metric,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              3,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
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

class _CalendarHeatmap extends _TripHeatmap {
  const _CalendarHeatmap({
    required super.points,
    required super.trips,
    required super.metric,
    required super.interval,
    required super.railFilter,
    required super.onCellTap,
    required super.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final columns = _buildHeatmapColumns(points, interval);
    final rowCount = _heatmapRowCount(interval);
    final thresholds = _heatmapThresholds(metric, interval);
    final tripCounts = <DateTime, int>{};
    for (final trip in trips) {
      final allowed = switch (railFilter) {
        TripChartRailFilter.all => true,
        TripChartRailFilter.rail => trip.isRailTrip,
        TripChartRailFilter.nonRail => !trip.isRailTrip,
      };
      if (!allowed) continue;
      final bucket = _bucketStart(_dateOnly(trip.departureTime), interval);
      tripCounts[bucket] = (tripCounts[bucket] ?? 0) + 1;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 42 + rowCount * 20,
          child: _HeatmapScroller(
            controller: scrollController,
            child: SingleChildScrollView(
              controller: scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: columns
                        .map(
                          (column) => SizedBox(
                            width: 20,
                            height: 30,
                            child: OverflowBox(
                              alignment: Alignment.bottomLeft,
                              maxWidth: 48,
                              minHeight: 30,
                              maxHeight: 30,
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: Text(
                                  column.label,
                                  maxLines: 2,
                                  softWrap: false,
                                  style: Theme.of(context).textTheme.labelSmall,
                                  textHeightBehavior: const TextHeightBehavior(
                                    applyHeightToFirstAscent: false,
                                    applyHeightToLastDescent: false,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: columns
                        .map(
                          (column) => SizedBox(
                            width: 20,
                            child: Column(
                              children: column.points.map((point) {
                                if (point == null) {
                                  return _EmptyHeatmapCell(colors: colors);
                                }
                                final count =
                                    tripCounts[point.bucketStart] ?? 0;
                                return _HeatmapCell(
                                  point: point,
                                  color: _intervalHeatmapColor(
                                    colors,
                                    point.value,
                                    thresholds,
                                  ),
                                  metric: metric,
                                  interval: interval,
                                  onTap: count == 0
                                      ? null
                                      : () => onCellTap(point),
                                );
                              }).toList(),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: _HeatmapLegend(
            thresholds: thresholds,
            colors: colors,
            metric: metric,
          ),
        ),
      ],
    );
  }
}

class _HeatmapLegend extends StatelessWidget {
  const _HeatmapLegend({
    required this.thresholds,
    required this.colors,
    required this.metric,
  });

  final List<double> thresholds;
  final ColorScheme colors;
  final TripChartMetric metric;

  @override
  Widget build(BuildContext context) {
    final values = [
      thresholds[3],
      thresholds[2],
      thresholds[1],
      thresholds[0],
      0.0,
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: values.indexed
          .map(
            (entry) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _intervalHeatmapColor(colors, entry.$2, thresholds),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${_heatmapLegendValue(metric, entry.$2)}${entry.$1 == 0 ? '+' : ''}',
                  maxLines: 1,
                  softWrap: false,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          )
          .toList(),
    );
  }
}

class _HeatmapScrollBehavior extends MaterialScrollBehavior {
  const _HeatmapScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}

class _HeatmapScroller extends StatelessWidget {
  const _HeatmapScroller({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: (event) {
      if (event is! PointerScrollEvent || !controller.hasClients) return;
      final delta = event.scrollDelta.dx != 0
          ? event.scrollDelta.dx
          : event.scrollDelta.dy;
      final position = controller.position;
      controller.jumpTo(
        (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    },
    child: Scrollbar(
      controller: controller,
      thumbVisibility: true,
      child: ScrollConfiguration(
        behavior: const _HeatmapScrollBehavior(),
        child: child,
      ),
    ),
  );
}

class _HeatmapCell extends StatelessWidget {
  const _HeatmapCell({
    required this.point,
    required this.color,
    required this.metric,
    required this.interval,
    this.onTap,
  });

  final TripChartPoint point;
  final Color color;
  final TripChartMetric metric;
  final TripChartInterval interval;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Tooltip(
      message:
          '${_bucketTooltip(point.bucketStart, interval)}\n${_formatMetricValue(metric, point.value)}',
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(
        color: Theme.of(context).colorScheme.onInverseSurface,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(3),
        onTap: onTap,
        child: Ink(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    ),
  );
}

class _EmptyHeatmapCell extends StatelessWidget {
  const _EmptyHeatmapCell({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(3),
      ),
    ),
  );
}

class _HeatmapColumn {
  const _HeatmapColumn({required this.label, required this.points});

  final String label;
  final List<TripChartPoint?> points;
}

List<_HeatmapColumn> _buildHeatmapColumns(
  List<TripChartPoint> points,
  TripChartInterval interval,
) {
  if (points.isEmpty) return const [];
  final rowCount = _heatmapRowCount(interval);
  final result = <_HeatmapColumn>[];
  for (var start = 0; start < points.length; start += rowCount) {
    final cells = List<TripChartPoint?>.filled(rowCount, null);
    String label = '';
    for (var row = 0; row < rowCount && start + row < points.length; row++) {
      final index = start + row;
      final point = points[index];
      cells[row] = point;
      final group = _heatmapGroupStart(point.bucketStart, interval);
      final previousGroup = index == 0
          ? null
          : _heatmapGroupStart(points[index - 1].bucketStart, interval);
      if (label.isEmpty && group != previousGroup) {
        label = _heatmapGroupLabel(group, interval);
      }
    }
    result.add(_HeatmapColumn(label: label, points: cells));
  }
  return result;
}

int _heatmapRowCount(TripChartInterval interval) => switch (interval) {
  TripChartInterval.year => 5,
  TripChartInterval.month => 6,
  TripChartInterval.week => 4,
};

DateTime _heatmapGroupStart(DateTime date, TripChartInterval interval) =>
    switch (interval) {
      TripChartInterval.year => DateTime(date.year ~/ 10 * 10),
      TripChartInterval.month => DateTime(date.year),
      TripChartInterval.week => DateTime(date.year, date.month),
    };

String _heatmapGroupLabel(DateTime group, TripChartInterval interval) =>
    switch (interval) {
      TripChartInterval.year => '${group.year}s',
      TripChartInterval.month => '${group.year}',
      TripChartInterval.week =>
        group.month == 1 ? '${group.year}\n1' : '${group.month}',
    };

List<double> _heatmapThresholds(
  TripChartMetric metric,
  TripChartInterval interval,
) => switch ((metric, interval)) {
  (TripChartMetric.count, TripChartInterval.week) => const [1, 2, 4, 7],
  (TripChartMetric.count, TripChartInterval.month) => const [2, 5, 10, 20],
  (TripChartMetric.count, TripChartInterval.year) => const [12, 30, 60, 120],
  (TripChartMetric.mileage, TripChartInterval.week) => const [
    50,
    200,
    500,
    1000,
  ],
  (TripChartMetric.mileage, TripChartInterval.month) => const [
    500,
    2000,
    5000,
    10000,
  ],
  (TripChartMetric.mileage, TripChartInterval.year) => const [
    5000,
    15000,
    30000,
    60000,
  ],
  (TripChartMetric.duration, TripChartInterval.week) => const [1, 4, 10, 24],
  (TripChartMetric.duration, TripChartInterval.month) => const [
    10,
    30,
    80,
    160,
  ],
  (TripChartMetric.duration, TripChartInterval.year) => const [
    100,
    300,
    800,
    1600,
  ],
  (TripChartMetric.spending, TripChartInterval.week) => const [
    50,
    200,
    500,
    1000,
  ],
  (TripChartMetric.spending, TripChartInterval.month) => const [
    500,
    2000,
    5000,
    10000,
  ],
  (TripChartMetric.spending, TripChartInterval.year) => const [
    5000,
    15000,
    30000,
    60000,
  ],
};

Color _intervalHeatmapColor(
  ColorScheme colors,
  double value,
  List<double> thresholds,
) {
  if (value <= 0) return colors.surfaceContainerHighest;
  final level =
      thresholds.lastIndexWhere((threshold) => value >= threshold) + 1;
  return Color.lerp(
    colors.primaryContainer,
    colors.primary,
    level / thresholds.length,
  )!;
}

String _heatmapLegendValue(TripChartMetric metric, double value) =>
    switch (metric) {
      TripChartMetric.mileage => '${_formatWithThousandsSeparator(value)}km',
      TripChartMetric.count => '${_formatWithThousandsSeparator(value)}次',
      TripChartMetric.duration => '${_formatWithThousandsSeparator(value)}h',
      TripChartMetric.spending => '¥${_formatWithThousandsSeparator(value)}',
    };

String _formatWithThousandsSeparator(double value) {
  final digits = value.round().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}

Color _heatmapColor(ColorScheme colors, double value, TripChartMetric metric) {
  if (value <= 0) return colors.surfaceContainerHighest;
  final level = _heatmapLevel(value, metric);
  return Color.lerp(colors.primaryContainer, colors.primary, level / 4)!;
}

int _heatmapLevel(double value, TripChartMetric metric) {
  final thresholds = switch (metric) {
    TripChartMetric.count => const [1, 2, 3, 4],
    TripChartMetric.mileage => const [50, 200, 500, 1000],
    TripChartMetric.duration => const [1, 4, 10, 24],
    TripChartMetric.spending => const [50, 200, 500, 1000],
  };
  return thresholds.lastIndexWhere((threshold) => value >= threshold) + 1;
}

class _HeatmapScale {
  const _HeatmapScale(this.labels);

  final List<String> labels;
}

_HeatmapScale _heatmapScale(
  TripChartMetric metric,
  TripChartInterval interval,
) {
  final thresholds = switch (metric) {
    TripChartMetric.count => const [0, 1, 2, 3, 4],
    TripChartMetric.mileage => const [0, 50, 200, 500, 1000],
    TripChartMetric.duration => const [0, 1, 4, 10, 24],
    TripChartMetric.spending => const [0, 50, 200, 500, 1000],
  };
  final fiveLevels = [
    '${thresholds[4]}${metric == TripChartMetric.count ? '+' : ''}',
    '${thresholds[3]}',
    '${thresholds[2]}',
    '${thresholds[1]}',
    '${thresholds[0]}',
  ];
  return switch (interval) {
    TripChartInterval.year => _HeatmapScale([
      fiveLevels[0],
      fiveLevels[2],
      fiveLevels[4],
    ]),
    TripChartInterval.month => _HeatmapScale(fiveLevels),
    TripChartInterval.week => _HeatmapScale([
      fiveLevels[0],
      fiveLevels[1],
      fiveLevels[2],
      fiveLevels[3],
      '>0',
      fiveLevels[4],
    ]),
  };
}

String _metricLabel(TripChartMetric metric) => switch (metric) {
  TripChartMetric.mileage => '累计里程',
  TripChartMetric.count => '行程次数',
  TripChartMetric.duration => '累计时长',
  TripChartMetric.spending => '累计花费',
};

String _formatMetricValue(TripChartMetric metric, double value) =>
    switch (metric) {
      TripChartMetric.mileage => '${value.toStringAsFixed(1)} km',
      TripChartMetric.count => '${value.round()} 次',
      TripChartMetric.duration => '${value.toStringAsFixed(1)} 小时',
      TripChartMetric.spending => '¥${value.toStringAsFixed(2)}',
    };

String _bucketLabel(DateTime date, TripChartInterval interval) =>
    switch (interval) {
      TripChartInterval.year => '${date.year}',
      TripChartInterval.month => '${date.year % 100}/${date.month}',
      TripChartInterval.week => '${date.month}/${date.day}',
    };

String _heatmapColumnLabel(
  List<TripChartPoint> points,
  int index,
  TripChartInterval interval,
) {
  final date = points[index].bucketStart;
  final previous = index == 0 ? null : points[index - 1].bucketStart;
  return switch (interval) {
    TripChartInterval.year =>
      index == 0 || date.year % 10 == 0 ? '${date.year ~/ 10 * 10}年代' : '',
    TripChartInterval.month =>
      index == 0 || previous!.year != date.year ? '${date.year}' : '',
    TripChartInterval.week =>
      index == 0 || previous!.month != date.month ? '${date.month}月' : '',
  };
}

String _bucketTooltip(DateTime date, TripChartInterval interval) =>
    switch (interval) {
      TripChartInterval.year => '${date.year} 年',
      TripChartInterval.month => '${date.year} 年 ${date.month} 月',
      TripChartInterval.week => '${_formatDate(date)} 起一周',
    };

String _compactNumber(double value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}m';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  if (value >= 10) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _bucketStart(DateTime date, TripChartInterval interval) =>
    switch (interval) {
      TripChartInterval.year => DateTime(date.year),
      TripChartInterval.month => DateTime(date.year, date.month),
      TripChartInterval.week => date.subtract(Duration(days: date.weekday - 1)),
    };

DateTime _nextBucket(DateTime date, TripChartInterval interval) =>
    switch (interval) {
      TripChartInterval.year => DateTime(date.year + 1),
      TripChartInterval.month => DateTime(date.year, date.month + 1),
      TripChartInterval.week => date.add(const Duration(days: 7)),
    };

String _formatShortDate(DateTime date) =>
    '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';

String _railFilterLabel(TripChartRailFilter filter) => switch (filter) {
  TripChartRailFilter.all => '全部行程',
  TripChartRailFilter.rail => '铁路行程',
  TripChartRailFilter.nonRail => '非铁路行程',
};

IconData _railFilterIcon(TripChartRailFilter filter) => switch (filter) {
  TripChartRailFilter.all => Icons.directions_outlined,
  TripChartRailFilter.rail => Icons.train_outlined,
  TripChartRailFilter.nonRail => Icons.directions_bus_outlined,
};

String _intervalLabel(TripChartInterval interval) => switch (interval) {
  TripChartInterval.year => '年',
  TripChartInterval.month => '月',
  TripChartInterval.week => '周',
};
