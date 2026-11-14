import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/trip_chart_series.dart';
import 'package:raillog/src/models/trip_metrics_statistics.dart';
import 'package:raillog/src/pages/all_trips_page.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/trip_metrics_section.dart';

enum _TripChartStyle { trend, heatmap }

enum _QuickRange { all, oneYear, threeYears }

class TripChartPage extends StatefulWidget {
  const TripChartPage({super.key, required this.trips, this.openTrip});

  final List<DashboardTripEntry> trips;
  final TripEntryOpener? openTrip;

  @override
  State<TripChartPage> createState() => _TripChartPageState();
}

class _TripChartPageState extends State<TripChartPage> {
  TripChartMetric _metric = TripChartMetric.count;
  late TripChartInterval _interval;
  bool _intervalManuallySet = false;
  TripChartRailFilter _railFilter = TripChartRailFilter.all;
  _TripChartStyle _style = _TripChartStyle.trend;
  bool _isLoadingChart = false;
  late DateTimeRange _range;
  late final DateTime _firstTripDate;
  late final DateTime _lastTripDate;
  late final DateTime _today;
  final _heatmapScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _today = _dateOnly(DateTime.now());
    final dates =
        widget.trips.map((trip) => _dateOnly(trip.departureTime)).toList()
          ..sort();
    final first = dates.isEmpty ? _today : dates.first;
    final last = dates.isEmpty ? _today : dates.last;
    _firstTripDate = first;
    _lastTripDate = last;
    _range = DateTimeRange(start: first, end: last);
    _interval = suggestTripChartInterval(rangeStart: first, rangeEnd: last);
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
    final filteredTrips = widget.trips
        .where(
          (trip) =>
              _inRange(_dateOnly(trip.departureTime)) &&
              _matchesRailFilter(trip),
        )
        .toList(growable: false);
    final metrics = TripMetricsStatistics.fromTrips(filteredTrips);
    final comparison = _comparisonFor(total);
    final heatmapScale = TripChartHeatmapScale.fromValues(
      points.map((point) => point.value),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('行程趋势')),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppLayout.dashboardMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MetricSelector(
                    value: _metric,
                    onChanged: (value) => setState(() => _metric = value),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            alignment: Alignment.centerLeft,
                          ),
                          onPressed: _openFilterSheet,
                          icon: const Icon(Icons.tune, size: 18),
                          label: Text(
                            _filterSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _ChartStyleToggle(
                        value: _style,
                        onChanged: _changeChartStyle,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppCard.outlined(
                    color: colors.surface,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SummaryHeader(
                          metricLabel: _metricLabel(_metric),
                          value: _formatMetricValue(_metric, total),
                          tripCount: filteredTrips.length,
                          comparison: comparison,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (_isLoadingChart)
                          const SizedBox(
                            height: 200,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (filteredTrips.isEmpty)
                          SizedBox(
                            height: 240,
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
                        else if (_style == _TripChartStyle.trend)
                          _TripTrendChart(
                            points: points,
                            metric: _metric,
                            interval: _interval,
                          )
                        else
                          _CalendarHeatmap(
                            points: points,
                            trips: filteredTrips,
                            metric: _metric,
                            interval: _interval,
                            scale: heatmapScale,
                            onCellTap: _showBucketTrips,
                            scrollController: _heatmapScrollController,
                          ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          '${_railFilterLabel(_railFilter)} · 按${_intervalLabel(_interval)}汇总 · ${_formatDate(_range.start)} 至 ${_formatDate(_range.end)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (filteredTrips.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.section),
                    TripMetricsSection(
                      metrics: metrics,
                      onOpenTrips: _openMetricTrips,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _filterSummary =>
      '${_railFilterLabel(_railFilter)} · ${_intervalLabel(_interval)} · '
      '${_formatShortRange(_range)}';

  bool _inRange(DateTime date) =>
      !date.isBefore(_range.start) && !date.isAfter(_range.end);

  bool _matchesRailFilter(DashboardTripEntry trip) => switch (_railFilter) {
    TripChartRailFilter.all => true,
    TripChartRailFilter.rail => trip.isRailTrip,
    TripChartRailFilter.nonRail => !trip.isRailTrip,
  };

  /// 与当前范围等长的上一周期比较；数据在此之前开始时返回 null。
  _PeriodComparison? _comparisonFor(double total) {
    final days = _range.end.difference(_range.start).inDays + 1;
    final previousEnd = _range.start.subtract(const Duration(days: 1));
    final previousStart = previousEnd.subtract(Duration(days: days - 1));
    if (previousStart.isBefore(_firstTripDate)) return null;

    var previous = 0.0;
    var hasPreviousTrips = false;
    for (final trip in widget.trips) {
      final day = _dateOnly(trip.departureTime);
      if (day.isBefore(previousStart) || day.isAfter(previousEnd)) continue;
      if (!_matchesRailFilter(trip)) continue;
      hasPreviousTrips = true;
      previous += tripChartMetricValue(trip, _metric);
    }
    if (!hasPreviousTrips) {
      return const _PeriodComparison(
        icon: Icons.fiber_new_outlined,
        text: '上一周期无行程',
      );
    }
    if (previous <= 0) return null;

    final delta = (total - previous) / previous * 100;
    if (delta.abs() < 0.5) {
      return const _PeriodComparison(
        icon: Icons.trending_flat,
        text: '与上一周期持平',
      );
    }
    final sign = delta > 0 ? '+' : '-';
    return _PeriodComparison(
      icon: delta > 0 ? Icons.trending_up : Icons.trending_down,
      text: '较上一周期 $sign${_trimNumber(delta.abs(), 1)}%',
    );
  }

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<_ChartFilterResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ChartFilterSheet(
        initialRange: _range,
        initialRailFilter: _railFilter,
        initialInterval: _interval,
        initialIntervalManual: _intervalManuallySet,
        firstDate: _firstTripDate,
        lastDate: _lastTripDate,
        today: _today,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _range = result.range;
      _railFilter = result.railFilter;
      _interval = result.interval;
      _intervalManuallySet = result.intervalManual;
    });
    if (_style == _TripChartStyle.heatmap) await _scrollHeatmapToEnd();
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

  Future<void> _openMetricTrips(
    String title,
    List<DashboardTripEntry> trips,
  ) async {
    if (!mounted || trips.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AllTripsPage(
          trips: trips,
          title: title,
          showTripKindFilter: false,
          openTrip: widget.openTrip,
        ),
      ),
    );
  }

  Future<void> _showBucketTrips(TripChartPoint point) async {
    final end = _nextBucket(point.bucketStart, _interval);
    final trips =
        widget.trips
            .where(
              (trip) =>
                  _inRange(_dateOnly(trip.departureTime)) &&
                  !trip.departureTime.isBefore(point.bucketStart) &&
                  trip.departureTime.isBefore(end) &&
                  _matchesRailFilter(trip),
            )
            .toList()
          ..sort((a, b) => b.departureTime.compareTo(a.departureTime));
    if (!mounted || trips.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AllTripsPage(
          trips: trips,
          title:
              '${_bucketTooltip(point.bucketStart, _interval)} · ${trips.length} 段行程',
          showTripKindFilter: false,
          openTrip: widget.openTrip,
        ),
      ),
    );
  }
}

class _PeriodComparison {
  const _PeriodComparison({required this.icon, required this.text});

  final IconData icon;
  final String text;
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.metricLabel,
    required this.value,
    required this.tripCount,
    required this.comparison,
  });

  final String metricLabel;
  final String value;
  final int tripCount;
  final _PeriodComparison? comparison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metricLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: theme.textTheme.headlineMedium),
              ),
              if (comparison != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Icon(
                      comparison!.icon,
                      size: 16,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        comparison!.text,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '$tripCount 段行程',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
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
          ButtonSegment(value: TripChartMetric.count, label: Text('次数')),
          ButtonSegment(value: TripChartMetric.mileage, label: Text('里程')),
          ButtonSegment(value: TripChartMetric.duration, label: Text('时长')),
          ButtonSegment(value: TripChartMetric.spending, label: Text('花费')),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

class _ChartStyleToggle extends StatelessWidget {
  const _ChartStyleToggle({required this.value, required this.onChanged});

  final _TripChartStyle value;
  final ValueChanged<_TripChartStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_TripChartStyle>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity(horizontal: -2, vertical: -1),
      ),
      segments: const [
        ButtonSegment(
          value: _TripChartStyle.trend,
          icon: Icon(Icons.show_chart),
          tooltip: '趋势图',
        ),
        ButtonSegment(
          value: _TripChartStyle.heatmap,
          icon: Icon(Icons.grid_view),
          tooltip: '日历热力图',
        ),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _ChartFilterResult {
  const _ChartFilterResult({
    required this.range,
    required this.railFilter,
    required this.interval,
    required this.intervalManual,
  });

  final DateTimeRange range;
  final TripChartRailFilter railFilter;
  final TripChartInterval interval;
  final bool intervalManual;
}

class _ChartFilterSheet extends StatefulWidget {
  const _ChartFilterSheet({
    required this.initialRange,
    required this.initialRailFilter,
    required this.initialInterval,
    required this.initialIntervalManual,
    required this.firstDate,
    required this.lastDate,
    required this.today,
  });

  final DateTimeRange initialRange;
  final TripChartRailFilter initialRailFilter;
  final TripChartInterval initialInterval;
  final bool initialIntervalManual;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime today;

  @override
  State<_ChartFilterSheet> createState() => _ChartFilterSheetState();
}

class _ChartFilterSheetState extends State<_ChartFilterSheet> {
  late DateTimeRange _range;
  late TripChartRailFilter _railFilter;
  late TripChartInterval _interval;
  late bool _intervalManual;

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange;
    _railFilter = widget.initialRailFilter;
    _interval = widget.initialInterval;
    _intervalManual = widget.initialIntervalManual;
  }

  DateTimeRange get _fullRange =>
      DateTimeRange(start: widget.firstDate, end: widget.lastDate);

  DateTimeRange _quickRange(_QuickRange range) => switch (range) {
    _QuickRange.all => _fullRange,
    _QuickRange.oneYear => DateTimeRange(
      start: widget.today.subtract(const Duration(days: 364)),
      end: widget.today,
    ),
    _QuickRange.threeYears => DateTimeRange(
      start: widget.today.subtract(const Duration(days: 1094)),
      end: widget.today,
    ),
  };

  bool _isQuickRange(_QuickRange range) {
    final candidate = _quickRange(range);
    return _sameDay(candidate.start, _range.start) &&
        _sameDay(candidate.end, _range.end);
  }

  void _setRange(DateTimeRange range) {
    setState(() {
      _range = range;
      if (!_intervalManual) {
        _interval = suggestTripChartInterval(
          rangeStart: range.start,
          rangeEnd: range.end,
        );
      }
    });
  }

  Future<void> _pickCustomRange() async {
    final earliest = widget.firstDate.isBefore(_range.start)
        ? widget.firstDate
        : _range.start;
    final firstDate = earliest.isBefore(DateTime(2000))
        ? earliest
        : DateTime(2000);
    var lastDate = widget.today.add(const Duration(days: 365));
    if (widget.lastDate.isAfter(lastDate)) lastDate = widget.lastDate;
    if (_range.end.isAfter(lastDate)) lastDate = _range.end;
    final selected = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: _range,
      helpText: '选择统计日期范围',
      saveText: '确定',
      cancelText: '取消',
    );
    if (selected != null && mounted) _setRange(selected);
  }

  void _reset() {
    setState(() {
      _range = _fullRange;
      _railFilter = TripChartRailFilter.all;
      _interval = suggestTripChartInterval(
        rangeStart: _range.start,
        rangeEnd: _range.end,
      );
      _intervalManual = false;
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      _ChartFilterResult(
        range: _range,
        railFilter: _railFilter,
        interval: _interval,
        intervalManual: _intervalManual,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return SafeArea(
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.sheetMaxWidth),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('筛选', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xl),
                Text('行程类型', style: labelStyle),
                const SizedBox(height: AppSpacing.sm),
                SegmentedButton<TripChartRailFilter>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: TripChartRailFilter.all,
                      label: Text('全部'),
                    ),
                    ButtonSegment(
                      value: TripChartRailFilter.rail,
                      label: Text('铁路'),
                    ),
                    ButtonSegment(
                      value: TripChartRailFilter.nonRail,
                      label: Text('非铁路'),
                    ),
                  ],
                  selected: {_railFilter},
                  onSelectionChanged: (selection) =>
                      setState(() => _railFilter = selection.first),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('汇总粒度', style: labelStyle),
                const SizedBox(height: AppSpacing.sm),
                SegmentedButton<TripChartInterval>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: TripChartInterval.year,
                      label: Text('年'),
                    ),
                    ButtonSegment(
                      value: TripChartInterval.month,
                      label: Text('月'),
                    ),
                    ButtonSegment(
                      value: TripChartInterval.week,
                      label: Text('周'),
                    ),
                  ],
                  selected: {_interval},
                  onSelectionChanged: (selection) => setState(() {
                    _interval = selection.first;
                    _intervalManual = true;
                  }),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('日期范围', style: labelStyle),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final range in _QuickRange.values)
                      ChoiceChip(
                        label: Text(_quickRangeLabel(range)),
                        selected: _isQuickRange(range),
                        onSelected: (_) => _setRange(_quickRange(range)),
                      ),
                    OutlinedButton.icon(
                      onPressed: _pickCustomRange,
                      icon: const Icon(Icons.date_range_outlined, size: 18),
                      label: const Text('自定义…'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${_formatDate(_range.start)} 至 ${_formatDate(_range.end)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  children: [
                    TextButton(onPressed: _reset, child: const Text('重置')),
                    const Spacer(),
                    FilledButton(onPressed: _apply, child: const Text('完成')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TripTrendChart extends StatelessWidget {
  const _TripTrendChart({
    required this.points,
    required this.metric,
    required this.interval,
  });

  final List<TripChartPoint> points;
  final TripChartMetric metric;
  final TripChartInterval interval;

  @override
  Widget build(BuildContext context) {
    if (metric == TripChartMetric.count) {
      return _TripBarChart(points: points, interval: interval);
    }
    return _TripLineChart(points: points, metric: metric, interval: interval);
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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
                        _axisLabel(metric, value),
                        style: theme.textTheme.labelSmall,
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
                          style: theme.textTheme.labelSmall,
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

class _TripBarChart extends StatelessWidget {
  const _TripBarChart({required this.points, required this.interval});

  final List<TripChartPoint> points;
  final TripChartInterval interval;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final maxValue = points.fold<double>(0, (value, point) {
      return math.max(value, point.value);
    });
    final step = _niceAxisStep(maxValue / 4);
    final chartMaxY = step * 4;

    return LayoutBuilder(
      builder: (context, constraints) {
        final targetLabels = math.max(
          2,
          math.min(7, (constraints.maxWidth / 88).floor()),
        );
        final labelStep = math.max(1, (points.length / targetLabels).ceil());
        final slot = constraints.maxWidth / math.max(1, points.length);
        final barWidth = (slot * 0.55).clamp(2.0, 18.0);
        return SizedBox(
          height: 300,
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: chartMaxY,
              alignment: BarChartAlignment.spaceEvenly,
              groupsSpace: 0,
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: step,
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
                    interval: step,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(
                        _axisLabel(TripChartMetric.count, value),
                        style: theme.textTheme.labelSmall,
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
                          style: theme.textTheme.labelSmall,
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => colors.inverseSurface,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final index = group.x;
                    if (index < 0 || index >= points.length) return null;
                    final point = points[index];
                    return BarTooltipItem(
                      '${_bucketTooltip(point.bucketStart, interval)}\n${_formatMetricValue(TripChartMetric.count, point.value)}',
                      TextStyle(color: colors.onInverseSurface),
                    );
                  },
                ),
              ),
              barGroups: points.indexed
                  .map(
                    (entry) => BarChartGroupData(
                      x: entry.$1,
                      barRods: [
                        BarChartRodData(
                          toY: entry.$2.value,
                          width: barWidth,
                          color: colors.primary,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(barWidth >= 6 ? 2 : 0),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          ),
        );
      },
    );
  }
}

class _CalendarHeatmap extends StatelessWidget {
  const _CalendarHeatmap({
    required this.points,
    required this.trips,
    required this.metric,
    required this.interval,
    required this.scale,
    required this.onCellTap,
    required this.scrollController,
  });

  final List<TripChartPoint> points;

  /// 已按日期范围与行程类型筛好，热力图不再重复判断。
  final List<DashboardTripEntry> trips;
  final TripChartMetric metric;
  final TripChartInterval interval;
  final TripChartHeatmapScale scale;
  final ValueChanged<TripChartPoint> onCellTap;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final layout = _buildHeatmapLayout(points, interval);
    final bucketsWithTrips = <DateTime>{};
    for (final trip in trips) {
      bucketsWithTrips.add(
        _bucketStart(_dateOnly(trip.departureTime), interval),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeatmapGrid(
          layout: layout,
          metric: metric,
          interval: interval,
          scale: scale,
          colors: colors,
          bucketsWithTrips: bucketsWithTrips,
          onCellTap: onCellTap,
          scrollController: scrollController,
        ),
        const SizedBox(height: AppSpacing.sm),
        _HeatmapLegend(scale: scale, colors: colors, metric: metric),
        if (layout.axisHint.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            layout.axisHint,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _HeatmapLegend extends StatelessWidget {
  const _HeatmapLegend({
    required this.scale,
    required this.colors,
    required this.metric,
  });

  final TripChartHeatmapScale scale;
  final ColorScheme colors;
  final TripChartMetric metric;

  @override
  Widget build(BuildContext context) {
    final entries = <Widget>[
      _LegendSwatch(color: colors.surfaceContainerHighest, label: '0'),
    ];
    if (scale.hasValues) {
      if (scale.thresholds.isEmpty) {
        entries.add(
          _LegendSwatch(
            color: _heatmapColor(colors, scale.levelCount, scale.levelCount),
            label: '有行程',
          ),
        );
      } else {
        for (var index = 0; index < scale.thresholds.length; index++) {
          entries.add(
            _LegendSwatch(
              color: _heatmapColor(colors, index + 1, scale.levelCount),
              label:
                  '≥${_heatmapThresholdLabel(metric, scale.thresholds[index])}',
            ),
          );
        }
      }
    }
    return Wrap(spacing: 12, runSpacing: 4, children: entries);
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppRadius.extraSmall),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _HeatmapGrid extends StatelessWidget {
  const _HeatmapGrid({
    required this.layout,
    required this.metric,
    required this.interval,
    required this.scale,
    required this.colors,
    required this.bucketsWithTrips,
    required this.onCellTap,
    required this.scrollController,
  });

  static const _minPitch = 22.0;
  static const _maxPitch = 32.0;
  static const _cellGap = 3.0;
  static const _groupHeaderHeight = 18.0;
  static const _columnHeaderHeight = 20.0;
  static const _headerGap = 4.0;
  static const _rowLabelWidth = 52.0;
  static const _rowLabelGap = 6.0;

  final _HeatmapLayout layout;
  final TripChartMetric metric;
  final TripChartInterval interval;
  final TripChartHeatmapScale scale;
  final ColorScheme colors;
  final Set<DateTime> bucketsWithTrips;
  final ValueChanged<TripChartPoint> onCellTap;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final columnCount = layout.columnLabels.length;
    if (columnCount == 0) return const SizedBox.shrink();

    final showRowLabels = layout.rows.any((row) => row.label.isNotEmpty);
    final labelWidth = showRowLabels ? _rowLabelWidth + _rowLabelGap : 0.0;
    final headerHeight =
        (layout.groups.isNotEmpty ? _groupHeaderHeight + _headerGap : 0.0) +
        _columnHeaderHeight +
        _headerGap;
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      fontSize: 10,
      color: colors.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
    final rowLabelStyle = theme.textTheme.labelSmall?.copyWith(
      fontSize: 10,
      color: colors.onSurfaceVariant,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.max(0.0, constraints.maxWidth - labelWidth);
        final pitch = (available / columnCount).clamp(_minPitch, _maxPitch);
        final cellSize = pitch - _cellGap;
        final content = SizedBox(
          width: columnCount * pitch,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (layout.groups.isNotEmpty) ...[
                SizedBox(
                  height: _groupHeaderHeight,
                  child: Row(
                    children: [
                      for (final group in layout.groups)
                        SizedBox(
                          width: group.span * pitch,
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                group.label,
                                maxLines: 1,
                                style: headerStyle,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: _headerGap),
              ],
              SizedBox(
                height: _columnHeaderHeight,
                child: Row(
                  children: [
                    for (final label in layout.columnLabels)
                      SizedBox(
                        width: pitch,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label,
                                maxLines: 1,
                                style: headerStyle,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: _headerGap),
              for (final row in layout.rows)
                SizedBox(
                  height: pitch,
                  child: Row(
                    children: [
                      for (var index = 0; index < columnCount; index++)
                        _cellFor(row, index, pitch, cellSize),
                    ],
                  ),
                ),
            ],
          ),
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showRowLabels)
              SizedBox(
                width: _rowLabelWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(height: headerHeight),
                    for (final row in layout.rows)
                      SizedBox(
                        height: pitch,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              row.label,
                              maxLines: 1,
                              style: rowLabelStyle,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (showRowLabels) const SizedBox(width: _rowLabelGap),
            Expanded(
              child: _HeatmapScroller(
                controller: scrollController,
                child: content,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _cellFor(_HeatmapRow row, int index, double pitch, double cellSize) {
    final point = index < row.cells.length ? row.cells[index] : null;
    final tappable =
        point != null && bucketsWithTrips.contains(point.bucketStart);
    return SizedBox(
      width: pitch,
      height: pitch,
      child: Center(
        child: _HeatmapSlot(
          point: point,
          size: cellSize,
          color: point == null
              ? colors.surfaceContainerHighest
              : _heatmapColor(
                  colors,
                  scale.levelFor(point.value),
                  scale.levelCount,
                ),
          metric: metric,
          interval: interval,
          onTap: tappable ? () => onCellTap(point) : null,
        ),
      ),
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
      // 只接管横向滚动；竖直滚动留给页面，避免滚轮被热力图吃掉。
      final delta = event.scrollDelta.dx;
      if (delta == 0) return;
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
      child: ScrollConfiguration(
        behavior: const _HeatmapScrollBehavior(),
        child: SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: child,
        ),
      ),
    ),
  );
}

class _HeatmapSlot extends StatelessWidget {
  const _HeatmapSlot({
    required this.point,
    required this.size,
    required this.color,
    required this.metric,
    required this.interval,
    required this.onTap,
  });

  /// null 表示该周期不在所选日期范围内，留空而不是画成「0」。
  final TripChartPoint? point;
  final double size;
  final Color color;
  final TripChartMetric metric;
  final TripChartInterval interval;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final point = this.point;
    if (point == null) return SizedBox(width: size, height: size);

    final radius = BorderRadius.circular(math.max(3, size * 0.16));
    return Tooltip(
      message:
          '${_bucketTooltip(point.bucketStart, interval)}\n${_formatMetricValue(metric, point.value)}',
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      textStyle: TextStyle(
        color: Theme.of(context).colorScheme.onInverseSurface,
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, borderRadius: radius),
        ),
      ),
    );
  }
}

class _HeatmapLayout {
  const _HeatmapLayout({
    required this.columnLabels,
    required this.rows,
    required this.axisHint,
    this.groups = const [],
  });

  final List<String> columnLabels;
  final List<_HeatmapRow> rows;
  final List<_HeatmapGroup> groups;
  final String axisHint;
}

class _HeatmapRow {
  const _HeatmapRow({required this.label, required this.cells});

  final String label;
  final List<TripChartPoint?> cells;
}

class _HeatmapGroup {
  const _HeatmapGroup({required this.label, required this.span});

  final String label;
  final int span;
}

_HeatmapLayout _buildHeatmapLayout(
  List<TripChartPoint> points,
  TripChartInterval interval,
) {
  if (points.isEmpty) {
    return const _HeatmapLayout(columnLabels: [], rows: [], axisHint: '');
  }
  return switch (interval) {
    TripChartInterval.year => _buildYearLayout(points),
    TripChartInterval.month => _buildMonthLayout(points),
    TripChartInterval.week => _buildWeekLayout(points),
  };
}

/// 年粒度：一行年份，每列一个年份。
_HeatmapLayout _buildYearLayout(List<TripChartPoint> points) {
  final byYear = <int, TripChartPoint>{};
  final years = <int>[];
  for (final point in points) {
    final year = point.bucketStart.year;
    byYear[year] = point;
    years.add(year);
  }
  return _HeatmapLayout(
    columnLabels: [for (final year in years) '$year'],
    rows: [
      _HeatmapRow(label: '', cells: [for (final year in years) byYear[year]]),
    ],
    axisHint: '每列一年',
  );
}

/// 月粒度：一行一年，十二列对应十二个月，左列年份可固定不随横向滚动。
_HeatmapLayout _buildMonthLayout(List<TripChartPoint> points) {
  final byMonth = <int, TripChartPoint>{};
  final years = <int>[];
  for (final point in points) {
    final year = point.bucketStart.year;
    if (years.isEmpty || years.last != year) years.add(year);
    byMonth[year * 100 + point.bucketStart.month] = point;
  }
  return _HeatmapLayout(
    columnLabels: const [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '10',
      '11',
      '12',
    ],
    rows: [
      for (final year in years)
        _HeatmapRow(
          label: '$year',
          cells: [
            for (var month = 1; month <= 12; month++)
              byMonth[year * 100 + month],
          ],
        ),
    ],
    axisHint: '行为年份，列为月份',
  );
}

/// 周粒度：一行是当月第几周，一列是一个月。
/// 周归属哪个月按该周周四（ISO 周的中位日）判断，跨月周不会被算到上个月。
_HeatmapLayout _buildWeekLayout(List<TripChartPoint> points) {
  DateTime anchorOf(TripChartPoint point) =>
      point.bucketStart.add(const Duration(days: 3));

  final firstAnchor = anchorOf(points.first);
  final lastAnchor = anchorOf(points.last);
  final startMonth = DateTime(firstAnchor.year, firstAnchor.month);
  final endMonth = DateTime(lastAnchor.year, lastAnchor.month);
  final months = <DateTime>[];
  for (
    var month = startMonth;
    !month.isAfter(endMonth);
    month = DateTime(month.year, month.month + 1)
  ) {
    months.add(month);
  }

  final byMonth = <int, Map<int, TripChartPoint>>{};
  for (final point in points) {
    final anchor = anchorOf(point);
    final monthIndex =
        (anchor.year - startMonth.year) * 12 +
        (anchor.month - startMonth.month);
    final week = ((anchor.day - 1) ~/ 7) + 1;
    (byMonth[monthIndex] ??= {})[week] = point;
  }

  return _HeatmapLayout(
    columnLabels: [for (final month in months) '${month.month}'],
    groups: _groupMonthsByYear(months),
    rows: [
      for (var week = 1; week <= 5; week++)
        _HeatmapRow(
          label: '第$week周',
          cells: [
            for (var index = 0; index < months.length; index++)
              byMonth[index]?[week],
          ],
        ),
    ],
    axisHint: '行为当月第几周，列为月份',
  );
}

List<_HeatmapGroup> _groupMonthsByYear(List<DateTime> months) {
  final groups = <_HeatmapGroup>[];
  for (final month in months) {
    final label = '${month.year}';
    if (groups.isNotEmpty && groups.last.label == label) {
      groups[groups.length - 1] = _HeatmapGroup(
        label: label,
        span: groups.last.span + 1,
      );
    } else {
      groups.add(_HeatmapGroup(label: label, span: 1));
    }
  }
  return groups;
}

Color _heatmapColor(ColorScheme colors, int level, int levelCount) {
  if (level <= 0 || levelCount <= 0) return colors.surfaceContainerHighest;
  final strength = levelCount <= 1 ? 1.0 : 0.3 + 0.7 * (level / levelCount);
  return Color.lerp(colors.primaryContainer, colors.primary, strength)!;
}

String _heatmapThresholdLabel(TripChartMetric metric, double value) =>
    switch (metric) {
      TripChartMetric.mileage => '${_groupNumber(value, 0)} km',
      TripChartMetric.count => '${value.round()} 次',
      TripChartMetric.duration => '${_trimNumber(value, 1)} h',
      TripChartMetric.spending => '¥${_groupNumber(value, 0)}',
    };

String _metricLabel(TripChartMetric metric) => switch (metric) {
  TripChartMetric.mileage => '累计里程',
  TripChartMetric.count => '行程次数',
  TripChartMetric.duration => '累计时长',
  TripChartMetric.spending => '累计花费',
};

String _formatMetricValue(TripChartMetric metric, double value) =>
    switch (metric) {
      TripChartMetric.mileage => '${_groupNumber(value, 1)} km',
      TripChartMetric.count => '${value.round()} 次',
      TripChartMetric.duration => '${_trimNumber(value, 1)} 小时',
      TripChartMetric.spending => '¥${_groupNumber(value, 2)}',
    };

String _axisLabel(TripChartMetric metric, double value) {
  if (value == 0) return '0';
  if (value.abs() >= 10000) {
    return '${_trimNumber(value / 10000, 1)}万';
  }
  if (metric == TripChartMetric.count || value == value.roundToDouble()) {
    return value.round().toString();
  }
  return _trimNumber(value, 1);
}

String _bucketLabel(DateTime date, TripChartInterval interval) =>
    switch (interval) {
      TripChartInterval.year => '${date.year}',
      TripChartInterval.month => '${date.year % 100}/${date.month}',
      TripChartInterval.week => '${date.month}/${date.day}',
    };

String _bucketTooltip(
  DateTime date,
  TripChartInterval interval,
) => switch (interval) {
  TripChartInterval.year => '${date.year} 年',
  TripChartInterval.month => '${date.year} 年 ${date.month} 月',
  TripChartInterval.week =>
    '${_formatDate(date)} – ${_formatDate(date.add(const Duration(days: 6)))}',
};

String _quickRangeLabel(_QuickRange range) => switch (range) {
  _QuickRange.all => '全部',
  _QuickRange.oneYear => '近一年',
  _QuickRange.threeYears => '近三年',
};

/// 去掉小数末尾的 0，`1.50 → 1.5`、`2.00 → 2`。
String _trimNumber(double value, int decimals) {
  final text = value.toStringAsFixed(decimals);
  if (!text.contains('.')) return text;
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// 整数部分加千分位，`12345.5 → 12,345.5`。
String _groupNumber(double value, int decimals) {
  final text = _trimNumber(value, decimals);
  final dot = text.indexOf('.');
  final integer = dot < 0 ? text : text.substring(0, dot);
  final fraction = dot < 0 ? '' : text.substring(dot);
  final buffer = StringBuffer();
  for (var index = 0; index < integer.length; index++) {
    if (index > 0 && (integer.length - index) % 3 == 0) buffer.write(',');
    buffer.write(integer[index]);
  }
  return '$buffer$fraction';
}

/// 把 `max / 4` 向上取整到 1、2、5 的整数倍，避免出现 0.8、8 这类刻度。
double _niceAxisStep(double rough) {
  if (rough <= 1) return 1;
  final magnitude = math
      .pow(10, (math.log(rough) / math.ln10).floor())
      .toDouble();
  final normalized = rough / magnitude;
  final nice = normalized <= 1
      ? 1.0
      : normalized <= 2
      ? 2.0
      : normalized <= 5
      ? 5.0
      : 10.0;
  return nice * magnitude;
}

String _formatShortRange(DateTimeRange range) {
  final left = '${range.start.year}.${range.start.month}';
  final right = '${range.end.year}.${range.end.month}';
  return left == right ? left : '$left–$right';
}

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

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

String _railFilterLabel(TripChartRailFilter filter) => switch (filter) {
  TripChartRailFilter.all => '全部行程',
  TripChartRailFilter.rail => '铁路行程',
  TripChartRailFilter.nonRail => '非铁路行程',
};

String _intervalLabel(TripChartInterval interval) => switch (interval) {
  TripChartInterval.year => '年',
  TripChartInterval.month => '月',
  TripChartInterval.week => '周',
};
