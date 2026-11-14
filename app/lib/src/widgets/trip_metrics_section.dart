import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/trip_metrics_statistics.dart';
import 'package:raillog/src/widgets/app_card.dart';

typedef TripListOpener =
    Future<void> Function(String title, List<DashboardTripEntry> trips);

/// 趋势页底部的出行指标：平均值 + 按固定组距分箱的分布。
class TripMetricsSection extends StatelessWidget {
  const TripMetricsSection({
    super.key,
    required this.metrics,
    required this.onOpenTrips,
  });

  final TripMetricsStatistics metrics;
  final TripListOpener onOpenTrips;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricsHeader(
          tripCount: metrics.tripCount,
          showSpeedNote: metrics.speed.sampleCount > 0,
        ),
        const SizedBox(height: AppSpacing.md),
        _TripMetricsGrid(metrics: metrics, onOpenTrips: onOpenTrips),
      ],
    );
  }
}

class _MetricsHeader extends StatelessWidget {
  const _MetricsHeader({required this.tripCount, required this.showSpeedNote});

  final int tripCount;
  final bool showSpeedNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('出行指标', style: theme.textTheme.titleMedium)),
            _HeaderCount(label: '$tripCount 段行程'),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          showSpeedNote ? '按单段行程平均；旅速不含超过 360 km/h 的异常记录。' : '按单段行程平均。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _TripMetricsGrid extends StatelessWidget {
  const _TripMetricsGrid({required this.metrics, required this.onOpenTrips});

  final TripMetricsStatistics metrics;
  final TripListOpener onOpenTrips;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 3
            : constraints.maxWidth >= 720
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - AppSpacing.lg * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.lg,
          children: [
            SizedBox(
              width: width,
              child: _MetricDistributionCard(
                title: '平均旅速',
                icon: Icons.speed_outlined,
                distribution: metrics.speed,
                formatAverage: (value) => '${_trimNumber(value, 1)} km/h',
                formatTick: (value) => _trimNumber(value, 0),
                formatRange: (bin) =>
                    '${_trimNumber(bin.lower, 0)}–${_trimNumber(bin.upper, 0)} km/h',
                formatBinWidth: (value) => '${_trimNumber(value, 0)} km/h',
                onOpenTrips: onOpenTrips,
              ),
            ),
            SizedBox(
              width: width,
              child: _MetricDistributionCard(
                title: '平均里程',
                icon: Icons.straighten_outlined,
                distribution: metrics.mileage,
                formatAverage: (value) => '${_groupNumber(value, 0)} km',
                formatTick: (value) => _groupNumber(value, 0),
                formatRange: (bin) =>
                    '${_groupNumber(bin.lower, 0)}–${_groupNumber(bin.upper, 0)} km',
                formatBinWidth: (value) => '${_groupNumber(value, 0)} km',
                onOpenTrips: onOpenTrips,
              ),
            ),
            SizedBox(
              width: width,
              child: _MetricDistributionCard(
                title: '平均单位票价',
                icon: Icons.price_change_outlined,
                distribution: metrics.unitPrice,
                formatAverage: (value) => '${_trimNumber(value, 2)} 元/km',
                formatTick: (value) => _trimNumber(value, 2),
                formatRange: (bin) =>
                    '${_trimNumber(bin.lower, 2)}–${_trimNumber(bin.upper, 2)} 元/km',
                formatBinWidth: (value) => '${_trimNumber(value, 2)} 元/km',
                onOpenTrips: onOpenTrips,
              ),
            ),
            SizedBox(
              width: width,
              child: _MetricDistributionCard(
                title: '平均单程票价',
                icon: Icons.confirmation_number_outlined,
                distribution: metrics.ticketPrice,
                formatAverage: (value) => '¥${_groupNumber(value, 2)}',
                formatTick: (value) => _groupNumber(value, 0),
                formatRange: (bin) =>
                    '¥${_groupNumber(bin.lower, 0)}–¥${_groupNumber(bin.upper, 0)}',
                formatBinWidth: (value) => '¥${_groupNumber(value, 0)}',
                onOpenTrips: onOpenTrips,
              ),
            ),
            SizedBox(
              width: width,
              child: _MetricDistributionCard(
                title: '平均时长',
                icon: Icons.timer_outlined,
                distribution: metrics.durationMinutes,
                formatAverage: _formatDurationAverage,
                formatTick: _formatDurationTick,
                formatRange: (bin) =>
                    '${_formatDurationTick(bin.lower)}–${_formatDurationTick(bin.upper)}',
                formatBinWidth: _formatDurationTick,
                onOpenTrips: onOpenTrips,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricDistributionCard extends StatelessWidget {
  const _MetricDistributionCard({
    required this.title,
    required this.icon,
    required this.distribution,
    required this.formatAverage,
    required this.formatTick,
    required this.formatRange,
    required this.formatBinWidth,
    required this.onOpenTrips,
  });

  final String title;
  final IconData icon;
  final TripMetricDistribution distribution;
  final String Function(double value) formatAverage;
  final String Function(double value) formatTick;
  final String Function(TripMetricBin bin) formatRange;
  final String Function(double value) formatBinWidth;
  final TripListOpener onOpenTrips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final average = distribution.average;
    return AppCard.filled(
      title: title,
      icon: icon,
      trailing: _HeaderCount(label: '${distribution.sampleCount} 段'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: average == null
          ? const _EmptyHint()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    onTap: () => onOpenTrips(title, distribution.trips),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                formatAverage(average),
                                maxLines: 1,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _Histogram(
                  bins: distribution.bins,
                  maxBinCount: distribution.maxBinCount,
                  average: average,
                  formatAverage: formatAverage,
                  formatTick: formatTick,
                  formatRange: formatRange,
                  onOpenTrips: onOpenTrips,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '组距 ${formatBinWidth(distribution.binWidth)} · 竖线为平均值',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}

class _Histogram extends StatelessWidget {
  const _Histogram({
    required this.bins,
    required this.maxBinCount,
    required this.average,
    required this.formatAverage,
    required this.formatTick,
    required this.formatRange,
    required this.onOpenTrips,
  });

  final List<TripMetricBin> bins;
  final int maxBinCount;
  final double average;
  final String Function(double value) formatAverage;
  final String Function(double value) formatTick;
  final String Function(TripMetricBin bin) formatRange;
  final TripListOpener onOpenTrips;

  static const _barAreaHeight = 88.0;
  static const _countLabelHeight = 16.0;
  static const _maxBarHeight = 68.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final upper = bins.isEmpty ? 0.0 : bins.last.upper;
    final markerFraction = upper > 0 ? (average / upper).clamp(0.0, 1.0) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: _barAreaHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final bin in bins)
                        Expanded(
                          child: _HistogramBar(
                            bin: bin,
                            maxBinCount: maxBinCount,
                            formatRange: formatRange,
                            onOpenTrips: onOpenTrips,
                          ),
                        ),
                    ],
                  ),
                ),
                if (markerFraction != null)
                  Positioned(
                    left: (constraints.maxWidth - 1.5) * markerFraction,
                    top: _countLabelHeight,
                    bottom: 0,
                    child: Tooltip(
                      message: '平均值 ${formatAverage(average)}',
                      child: Container(
                        width: 1.5,
                        decoration: BoxDecoration(
                          color: colors.tertiary,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Container(height: 1, color: colors.outlineVariant),
        const SizedBox(height: AppSpacing.xs),
        _HistogramTicks(bins: bins, formatTick: formatTick),
      ],
    );
  }
}

class _HistogramBar extends StatelessWidget {
  const _HistogramBar({
    required this.bin,
    required this.maxBinCount,
    required this.formatRange,
    required this.onOpenTrips,
  });

  final TripMetricBin bin;
  final int maxBinCount;
  final String Function(TripMetricBin bin) formatRange;
  final TripListOpener onOpenTrips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final active = bin.count > 0;
    final height = active && maxBinCount > 0
        ? math.max(bin.count / maxBinCount * _Histogram._maxBarHeight, 5.0)
        : 2.0;
    final range = formatRange(bin);

    return Tooltip(
      message: '$range · ${bin.count} 次',
      waitDuration: const Duration(milliseconds: 400),
      child: Semantics(
        button: active,
        label: '$range，${bin.count} 次',
        onTap: active ? () => onOpenTrips(range, bin.trips) : null,
        child: ExcludeSemantics(
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.extraSmall),
            onTap: active ? () => onOpenTrips(range, bin.trips) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: _Histogram._countLabelHeight,
                    child: active
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${bin.count}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          )
                        : null,
                  ),
                  Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: active ? colors.primary : colors.outlineVariant,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppRadius.extraSmall),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistogramTicks extends StatelessWidget {
  const _HistogramTicks({required this.bins, required this.formatTick});

  final List<TripMetricBin> bins;
  final String Function(double value) formatTick;

  @override
  Widget build(BuildContext context) {
    if (bins.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant);
    if (bins.length == 1) {
      return DefaultTextStyle(
        style: style ?? const TextStyle(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatTick(bins.first.lower)),
            Text(formatTick(bins.first.upper)),
          ],
        ),
      );
    }
    final middle = bins[bins.length ~/ 2];
    return DefaultTextStyle(
      style: style ?? const TextStyle(),
      child: Row(
        children: [
          Expanded(
            child: Text(
              formatTick(bins.first.lower),
              textAlign: TextAlign.left,
            ),
          ),
          Expanded(
            child: Text(formatTick(middle.lower), textAlign: TextAlign.center),
          ),
          Expanded(
            child: Text(
              formatTick(bins.last.upper),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCount extends StatelessWidget {
  const _HeaderCount({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Text(
        '暂无数据',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 固定小数位后去掉多余的 0，`1.50 → 1.5`、`2.00 → 2`。
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

String _formatDurationAverage(double minutes) {
  final rounded = minutes.round();
  final hours = rounded ~/ 60;
  final remaining = rounded % 60;
  if (hours == 0) return '$remaining 分';
  return remaining == 0 ? '$hours 时' : '$hours 时 $remaining 分';
}

String _formatDurationTick(double minutes) {
  if (minutes >= 60) {
    return '${_trimNumber(minutes / 60, 1)}时';
  }
  return '${_trimNumber(minutes, 0)}分';
}
