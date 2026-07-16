import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/trip_chart_series.dart';

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
  late DateTimeRange _range;

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
                            onChanged: (value) =>
                                setState(() => _interval = value),
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
                      padding: const EdgeInsets.fromLTRB(12, 24, 16, 12),
                      child: matchingTripCount == 0
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
                          : _TripLineChart(
                              points: points,
                              metric: _metric,
                              interval: _interval,
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
    if (selected != null && mounted) setState(() => _range = selected);
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
