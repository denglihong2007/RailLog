import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/dashboard_unlock_entry.dart';
import 'package:raillog/src/pages/all_trips_page.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

enum _UnlockSortField { unlockTime, tripCount }

class DashboardUnlocksPage extends StatefulWidget {
  const DashboardUnlocksPage({
    super.key,
    required this.title,
    required this.icon,
    required this.entries,
    required this.allTrips,
    this.showTrainNumber = true,
    this.openTrip,
  });

  final String title;
  final IconData icon;
  final List<DashboardUnlockEntry> entries;
  final List<DashboardTripEntry> allTrips;
  final bool showTrainNumber;
  final TripEntryOpener? openTrip;

  @override
  State<DashboardUnlocksPage> createState() => _DashboardUnlocksPageState();
}

class _DashboardUnlocksPageState extends State<DashboardUnlocksPage> {
  _UnlockSortField _sortField = _UnlockSortField.tripCount;
  bool _descending = true;

  List<DashboardUnlockEntry> get _sortedEntries {
    final entries = widget.entries.toList()..sort(_compareEntries);
    return entries;
  }

  int _compareEntries(DashboardUnlockEntry a, DashboardUnlockEntry b) {
    final comparison = switch (_sortField) {
      _UnlockSortField.unlockTime => a.unlockTime.compareTo(b.unlockTime),
      _UnlockSortField.tripCount => a.tripCount.compareTo(b.tripCount),
    };
    if (comparison != 0) return _descending ? -comparison : comparison;
    final byUnlockTime = b.unlockTime.compareTo(a.unlockTime);
    return byUnlockTime != 0 ? byUnlockTime : a.name.compareTo(b.name);
  }

  Future<void> _showSortPanel() async {
    var sortField = _sortField;
    var descending = _descending;
    final settings = await showModalBottomSheet<_UnlockSortSettings>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('排序方式', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<_UnlockSortField>(
                      initialValue: sortField,
                      decoration: const InputDecoration(
                        labelText: '排序依据',
                        prefixIcon: Icon(Icons.sort),
                        border: OutlineInputBorder(),
                      ),
                      items: _UnlockSortField.values
                          .map(
                            (field) => DropdownMenuItem(
                              value: field,
                              child: Text(_sortFieldLabel(field)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setSheetState(() => sortField = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('升序'),
                          icon: Icon(Icons.arrow_upward),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('降序'),
                          icon: Icon(Icons.arrow_downward),
                        ),
                      ],
                      selected: {descending},
                      onSelectionChanged: (selection) {
                        setSheetState(() => descending = selection.first);
                      },
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(
                          _UnlockSortSettings(
                            sortField: sortField,
                            descending: descending,
                          ),
                        ),
                        child: const Text('应用'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (settings == null || !mounted) return;
    setState(() {
      _sortField = settings.sortField;
      _descending = settings.descending;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final entries = _sortedEntries;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '排序方式',
            onPressed: _showSortPanel,
            icon: const Icon(Icons.sort),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: entries.length + 2,
              separatorBuilder: (context, index) => index <= 1
                  ? const SizedBox(height: 8)
                  : const Divider(height: 1, indent: 56),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _UnlockPieChart(entries: entries, icon: widget.icon);
                }
                if (index == 1) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(widget.icon, color: colors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${entries.length} 项 · '
                            '${_sortFieldLabel(_sortField)}'
                            '${_descending ? '降序' : '升序'}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final entry = entries[index - 2];
                final animationStep = index > 8 ? 8 : index;
                return M3Reveal(
                  duration: Duration(milliseconds: 220 + animationStep * 30),
                  distance: 6,
                  child: ListTile(
                    onTap: () => _openMatchingTrips(entry),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    leading: SizedBox(
                      width: 32,
                      child: Text(
                        (index - 1).toString(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    title: Text(
                      entry.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_tripDescription(entry)),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${entry.tripCount} 次',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: colors.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _tripDescription(DashboardUnlockEntry entry) {
    final date = _formatDate(entry.unlockTime);
    if (!widget.showTrainNumber) return '$date 解锁';
    final train = _trainLabel(entry.trainNumber);
    return switch (entry.action) {
      DashboardUnlockAction.ride => '$date 乘坐 $train 解锁',
      DashboardUnlockAction.departStation => '$date 从该站乘坐 $train',
      DashboardUnlockAction.arriveStation => '$date 乘坐 $train 到达该站',
    };
  }

  Future<void> _openMatchingTrips(DashboardUnlockEntry entry) async {
    final tripIds = entry.tripIds.toSet();
    final trips = widget.allTrips
        .where((trip) => tripIds.contains(trip.id))
        .toList();
    final changed = trips.length == 1 && widget.openTrip != null
        ? await widget.openTrip!(context, trips.single)
        : await Navigator.of(context).push<bool>(
            m3PageRoute(
              builder: (context) => trips.length == 1
                  ? TripRecordDetailsPage(tripId: trips.single.id)
                  : AllTripsPage(
                      title: entry.name,
                      trips: trips,
                      showTripKindFilter: false,
                      openTrip: widget.openTrip,
                    ),
            ),
          );
    if (changed == true && mounted) Navigator.of(context).pop(true);
  }
}

class _UnlockPieChart extends StatelessWidget {
  const _UnlockPieChart({required this.entries, required this.icon});

  final List<DashboardUnlockEntry> entries;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final slices = _buildPieSlices(entries);
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.count);
    final pieColors = _pieColors(colors, slices.length);

    return Card.outlined(
      margin: EdgeInsets.zero,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 21,
                    color: colors.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '次数占比',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (slices.isEmpty)
              SizedBox(
                height: 144,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.donut_large_outlined,
                        size: 32,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '暂无统计数据',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final chart = _Pie(
                    slices: slices,
                    total: total,
                    colors: pieColors,
                  );
                  final legend = _PieLegend(
                    slices: slices,
                    total: total,
                    colors: pieColors,
                  );
                  if (constraints.maxWidth < 600) {
                    return Column(
                      children: [
                        SizedBox(height: 260, child: chart),
                        const SizedBox(height: 16),
                        legend,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(width: 288, height: 288, child: chart),
                      const SizedBox(width: 24),
                      Expanded(child: legend),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Pie extends StatelessWidget {
  const _Pie({required this.slices, required this.total, required this.colors});

  final List<_PieSlice> slices;
  final int total;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: slices
          .map(
            (slice) => '${slice.name} ${_formatPercentage(slice.count, total)}',
          )
          .join('，'),
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              centerSpaceRadius: 58,
              sectionsSpace: 3,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(enabled: false),
              sections: slices.indexed
                  .map((item) {
                    final slice = item.$2;
                    final color = colors[item.$1];
                    final showTitle = slice.count * 100 >= total * 5;
                    return PieChartSectionData(
                      value: slice.count.toDouble(),
                      color: color,
                      radius: 62,
                      title: showTitle
                          ? _formatPercentage(slice.count, total)
                          : '',
                      titleStyle: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(
                            color:
                                ThemeData.estimateBrightnessForColor(color) ==
                                    Brightness.dark
                                ? Colors.white
                                : Colors.black87,
                            fontWeight: FontWeight.w700,
                          ),
                      titlePositionPercentageOffset: 0.54,
                    );
                  })
                  .toList(growable: false),
            ),
            duration: const Duration(milliseconds: 350),
          ),
          ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$total',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '总次数',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PieLegend extends StatefulWidget {
  const _PieLegend({
    required this.slices,
    required this.total,
    required this.colors,
  });

  final List<_PieSlice> slices;
  final int total;
  final List<Color> colors;

  @override
  State<_PieLegend> createState() => _PieLegendState();
}

class _PieLegendState extends State<_PieLegend> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 340 ? 2 : 1;
        final collapsedCount = columns * 6;
        final canExpand = widget.slices.length > collapsedCount;
        final visibleItems = _expanded || !canExpand
            ? widget.slices.indexed.toList(growable: false)
            : _collapsedLegendItems(collapsedCount);
        final itemWidth = columns == 2
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: visibleItems
                  .map((item) {
                    final slice = item.$2;
                    return SizedBox(
                      width: itemWidth,
                      height: 36,
                      child: Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: widget.colors[item.$1],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${slice.name} · ${slice.count}次',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatPercentage(slice.count, widget.total),
                            style: textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
            if (canExpand) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                  label: Text(
                    _expanded
                        ? '收起'
                        : '展开其余 ${widget.slices.length - visibleItems.length} 项',
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  List<(int, _PieSlice)> _collapsedLegendItems(int limit) {
    final indexed = widget.slices.indexed.toList(growable: false);
    if (indexed.length <= limit) return indexed;
    final other = indexed.last.$2.name == '其他' ? indexed.last : null;
    if (other == null) return indexed.take(limit).toList(growable: false);
    return [...indexed.take(limit - 1), other];
  }
}

class _PieSlice {
  const _PieSlice({required this.name, required this.count});

  final String name;
  final int count;
}

List<_PieSlice> _buildPieSlices(List<DashboardUnlockEntry> entries) {
  final sorted = entries.where((entry) => entry.tripCount > 0).toList()
    ..sort((a, b) {
      final byCount = b.tripCount.compareTo(a.tripCount);
      return byCount != 0 ? byCount : a.name.compareTo(b.name);
    });
  if (sorted.length <= 5) {
    return sorted
        .map((entry) => _PieSlice(name: entry.name, count: entry.tripCount))
        .toList(growable: false);
  }
  final total = sorted.fold<int>(0, (sum, entry) => sum + entry.tripCount);
  var visibleCount = 5;
  while (visibleCount < sorted.length &&
      sorted[visibleCount].tripCount * 100 >= total * 2) {
    visibleCount++;
  }
  final result = sorted
      .take(visibleCount)
      .map((entry) => _PieSlice(name: entry.name, count: entry.tripCount))
      .toList();
  if (visibleCount == sorted.length) return result;
  result.add(
    _PieSlice(
      name: '其他',
      count: sorted
          .skip(visibleCount)
          .fold(0, (sum, entry) => sum + entry.tripCount),
    ),
  );
  return result;
}

List<Color> _pieColors(ColorScheme colors, int count) {
  final result = <Color>[
    colors.primary,
    colors.tertiary,
    colors.secondary,
    colors.error,
    colors.inversePrimary,
    colors.outline,
  ];
  final seedHue = HSLColor.fromColor(colors.primary).hue;
  while (result.length < count) {
    final index = result.length;
    result.add(
      HSLColor.fromAHSL(
        1,
        (seedHue + index * 47) % 360,
        0.62 + (index % 3) * 0.06,
        ThemeData.estimateBrightnessForColor(colors.surface) == Brightness.dark
            ? 0.62
            : 0.46,
      ).toColor(),
    );
  }
  return result.take(count).toList(growable: false);
}

String _formatPercentage(int value, int total) {
  if (total <= 0) return '0%';
  final percentage = value * 100 / total;
  final rounded = percentage.roundToDouble();
  return percentage == rounded
      ? '${rounded.toInt()}%'
      : '${percentage.toStringAsFixed(1)}%';
}

class _UnlockSortSettings {
  const _UnlockSortSettings({
    required this.sortField,
    required this.descending,
  });

  final _UnlockSortField sortField;
  final bool descending;
}

String _sortFieldLabel(_UnlockSortField field) => switch (field) {
  _UnlockSortField.unlockTime => '解锁时间',
  _UnlockSortField.tripCount => '次数',
};

String _trainLabel(String value) {
  final trainNumber = value.trim();
  return trainNumber.isEmpty ? '未填写车次' : trainNumber;
}

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
