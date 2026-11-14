import 'package:flutter/material.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/seat_statistics.dart';
import 'package:raillog/src/pages/all_trips_page.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

typedef _OpenTrips =
    Future<void> Function(String title, List<DashboardTripEntry> trips);

/// 铁路足迹区块的「更多统计」：坐席、铺位与席别。
///
/// 数据全部来自本地行程记录，不请求后端。
class MoreStatisticsPage extends StatelessWidget {
  const MoreStatisticsPage({super.key, required this.trips, this.openTrip});

  final List<DashboardTripEntry> trips;
  final TripEntryOpener? openTrip;

  @override
  Widget build(BuildContext context) {
    final statistics = SeatStatistics.fromTrips(trips);
    Future<void> openTrips(String title, List<DashboardTripEntry> trips) =>
        _openTrips(context, title, trips);

    return Scaffold(
      appBar: AppBar(title: const Text('更多统计')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.detailMaxWidth,
            ),
            child: ListView(
              padding: AppSpacing.page,
              children: [
                _SeatPositionCard(
                  statistics: statistics,
                  onOpenTrips: openTrips,
                ),
                const SizedBox(height: AppSpacing.lg),
                _BerthCard(statistics: statistics, onOpenTrips: openTrips),
                const SizedBox(height: AppSpacing.lg),
                _SeatClassCard(statistics: statistics, onOpenTrips: openTrips),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openTrips(
    BuildContext context,
    String title,
    List<DashboardTripEntry> trips,
  ) async {
    if (trips.isEmpty) return;
    final opener = openTrip;
    final Future<bool?> changed;
    if (trips.length == 1) {
      changed = opener != null
          ? opener(context, trips.single)
          : Navigator.of(context).push<bool>(
              m3PageRoute(
                builder: (_) => TripRecordDetailsPage(tripId: trips.single.id),
              ),
            );
    } else {
      changed = Navigator.of(context).push<bool>(
        m3PageRoute(
          builder: (_) => AllTripsPage(
            title: title,
            trips: trips,
            showTripKindFilter: false,
            openTrip: opener,
          ),
        ),
      );
    }
    final didChange = await changed;
    if (didChange == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }
}

class _SeatPositionCard extends StatelessWidget {
  const _SeatPositionCard({
    required this.statistics,
    required this.onOpenTrips,
  });

  final SeatStatistics statistics;
  final _OpenTrips onOpenTrips;

  @override
  Widget build(BuildContext context) {
    final total = statistics.positionedTripCount;
    final positions = statistics.positions;
    final windowSide = positions
        .where((position) => const {'A', 'B', 'C'}.contains(position.letter))
        .toList(growable: false);
    final aisleSide = positions
        .where((position) => const {'D', 'F'}.contains(position.letter))
        .toList(growable: false);
    final windowSeats = _SeatCategoryData(
      label: '靠窗',
      positions: positions
          .where((position) => const {'A', 'F'}.contains(position.letter))
          .toList(growable: false),
    );
    final aisleSeats = _SeatCategoryData(
      label: '靠过道',
      positions: positions
          .where((position) => const {'C', 'D'}.contains(position.letter))
          .toList(growable: false),
    );

    return AppCard.filled(
      title: '坐席统计',
      icon: Icons.event_seat_outlined,
      trailing: _HeaderCount(label: '$total 次'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardDescription(
            '字母为动车组座位，数字为普速车厢座位（按座位号尾数归位）；'
            '按车厢窗、过道、窗的顺序排列，窗与过道两行分别汇总靠窗、靠过道。'
            '百分比按全部有座行程计算。',
          ),
          if (total == 0)
            const _EmptyHint()
          else ...[
            _SeatMarkerRow(
              icon: Icons.window_outlined,
              label: '窗户',
              category: windowSeats,
              total: total,
              onOpenTrips: onOpenTrips,
            ),
            _StatRowList(rows: _seatRows(windowSide, total)),
            _SeatMarkerRow(
              icon: Icons.directions_walk,
              label: '过道',
              category: aisleSeats,
              total: total,
              onOpenTrips: onOpenTrips,
            ),
            _StatRowList(rows: _seatRows(aisleSide, total)),
            const _SeatMarkerRow(icon: Icons.window_outlined, label: '窗户'),
          ],
        ],
      ),
    );
  }

  List<_StatRowData> _seatRows(List<SeatPositionStat> positions, int total) => [
    for (final position in positions)
      _StatRowData(
        label: _seatPositionLabel(position),
        count: position.count,
        total: total,
        onTap: position.count == 0
            ? null
            : () => onOpenTrips('${position.letter} 座', position.trips),
      ),
  ];
}

/// 车厢布局里的一行标记（窗户 / 过道）。靠窗与靠过道的合计直接写在对应
/// 标记行右侧，点开可查看这一类的行程。
class _SeatMarkerRow extends StatelessWidget {
  const _SeatMarkerRow({
    required this.icon,
    required this.label,
    this.category,
    this.total = 0,
    this.onOpenTrips,
  });

  final IconData icon;
  final String label;

  /// 为空时只作布局标记，不带合计。
  final _SeatCategoryData? category;
  final int total;
  final _OpenTrips? onOpenTrips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final data = category;
    final hasTrips = (data?.count ?? 0) > 0;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.small),
        onTap: data != null && hasTrips && onOpenTrips != null
            ? () => onOpenTrips!(data.label, data.trips)
            : null,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            // 带合计的行可以点开，留出更宽松的点击高度。
            vertical: data == null ? AppSpacing.xs : AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: colors.onSurfaceVariant),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (data != null) ...[
                const Spacer(),
                Text(
                  '${data.label} ${data.count} 次 · '
                  '${_formatPercentage(data.count, total)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (hasTrips) ...[
                  const SizedBox(width: AppSpacing.xxs),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SeatCategoryData {
  const _SeatCategoryData({required this.label, required this.positions});

  final String label;
  final List<SeatPositionStat> positions;

  int get count => positions.fold(0, (sum, position) => sum + position.count);

  List<DashboardTripEntry> get trips {
    final merged = [for (final position in positions) ...position.trips];
    merged.sort((a, b) {
      final byTime = b.departureTime.compareTo(a.departureTime);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
    return merged;
  }
}

class _BerthCard extends StatelessWidget {
  const _BerthCard({required this.statistics, required this.onOpenTrips});

  final SeatStatistics statistics;
  final _OpenTrips onOpenTrips;

  @override
  Widget build(BuildContext context) {
    final total = statistics.berthTripCount;
    return AppCard.filled(
      title: '铺位统计',
      icon: Icons.bed_outlined,
      trailing: _HeaderCount(label: '$total 次'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardDescription('百分比按全部有铺位记录的行程计算。'),
          if (total == 0)
            const _EmptyHint()
          else
            _StatRowList(
              rows: [
                for (final berth in statistics.berths)
                  _StatRowData(
                    label: berth.name,
                    count: berth.count,
                    total: total,
                    onTap: berth.count == 0
                        ? null
                        : () => onOpenTrips(berth.name, berth.trips),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SeatClassCard extends StatelessWidget {
  const _SeatClassCard({required this.statistics, required this.onOpenTrips});

  final SeatStatistics statistics;
  final _OpenTrips onOpenTrips;

  @override
  Widget build(BuildContext context) {
    final total = statistics.seatClassTripCount;
    return AppCard.filled(
      title: '席别统计',
      icon: Icons.category_outlined,
      trailing: _HeaderCount(label: '$total 次'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardDescription('百分比按全部有席别记录的行程计算。'),
          if (total == 0)
            const _EmptyHint()
          else
            _StatRowList(
              rows: [
                for (final item in statistics.seatClasses)
                  _StatRowData(
                    label: item.name,
                    count: item.count,
                    total: total,
                    onTap: () => onOpenTrips(item.name, item.trips),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatRowList extends StatelessWidget {
  const _StatRowList({required this.rows});

  final List<_StatRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.sm),
          _StatRow(data: rows[index]),
        ],
      ],
    );
  }
}

class _StatRowData {
  const _StatRowData({
    required this.label,
    required this.count,
    required this.total,
    required this.onTap,
  });

  final String label;
  final int count;
  final int total;
  final VoidCallback? onTap;
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.data});

  final _StatRowData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ratio = data.total == 0 ? 0.0 : data.count / data.total;
    final percentage = _formatPercentage(data.count, data.total);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.small),
        onTap: data.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      data.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${data.count} 次',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 44,
                    child: Text(
                      percentage,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (data.onTap != null) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.extraSmall),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.0, 1.0),
                  minHeight: 4,
                  color: colors.primary,
                  backgroundColor: colors.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ),
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

class _CardDescription extends StatelessWidget {
  const _CardDescription(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
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

/// 座位行只写字母与尾数，窗 / 中间 / 道由分组标题承担。
String _seatPositionLabel(SeatPositionStat position) =>
    '${position.letter} · 尾号 ${_seatTailLabel(position.numberLabel)}';

String _seatTailLabel(String numberLabel) {
  final parts = numberLabel.split('/');
  return parts.length == 2 ? '${parts[1]}、${parts[0]}' : numberLabel;
}

/// 占比优先取整，除不尽时保留一位小数，避免 1/8 被写成 13% 后合计 101%。
String _formatPercentage(int count, int total) {
  if (total <= 0) return '0%';
  final percentage = count * 100 / total;
  final rounded = percentage.roundToDouble();
  return percentage == rounded
      ? '${rounded.toInt()}%'
      : '${percentage.toStringAsFixed(1)}%';
}
