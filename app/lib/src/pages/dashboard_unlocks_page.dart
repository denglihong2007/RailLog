import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/dashboard_unlock_entry.dart';
import 'package:raillog/src/pages/all_trips_page.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/pages/entity_detail_page.dart';
import 'package:raillog/src/services/pie_chart_settings.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

enum _UnlockSortField { unlockTime, tripCount }

class DashboardUnlocksPage extends StatefulWidget {
  const DashboardUnlocksPage({
    super.key,
    required this.title,
    required this.icon,
    required this.entries,
    required this.allTrips,
    this.progressCatalog,
    this.showTrainNumber = true,
    this.openTrip,
    this.entityType,
  });

  final String title;
  final IconData icon;
  final List<DashboardUnlockEntry> entries;
  final List<DashboardTripEntry> allTrips;
  final Future<List<String>>? progressCatalog;
  final bool showTrainNumber;
  final TripEntryOpener? openTrip;
  final EntityType? entityType;

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

  Future<void> _openPieChart() => Navigator.of(context).push<void>(
    m3PageRoute(
      builder: (context) => _UnlockPieChartPage(
        title: widget.title,
        icon: widget.icon,
        entries: widget.entries,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final entries = _sortedEntries;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '次数占比',
            onPressed: _openPieChart,
            icon: const Icon(Icons.donut_large_outlined),
          ),
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
            constraints: const BoxConstraints(
              maxWidth: AppLayout.detailMaxWidth,
            ),
            child: ListView.separated(
              padding: AppSpacing.page,
              itemCount: entries.length + 1,
              separatorBuilder: (context, index) => index == 0
                  ? const SizedBox(height: 8)
                  : const Divider(height: 1, indent: 56),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.progressCatalog == null)
                          Row(
                            children: [
                              Icon(widget.icon, color: colors.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '${entries.length} 项 · '
                                  '${_sortFieldLabel(_sortField)}'
                                  '${_descending ? '降序' : '升序'}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                            ],
                          )
                        else
                          _UnlockProgress(
                            entries: widget.entries,
                            catalog: widget.progressCatalog!,
                            icon: widget.icon,
                          ),
                      ],
                    ),
                  );
                }

                final entry = entries[index - 1];
                return M3Reveal(
                  delay: m3RevealDelay(index),
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
                        index.toString(),
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
    if (widget.entityType != null) {
      await openEntityPage(context, widget.entityType!, entry.name);
      return;
    }
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

class _UnlockProgress extends StatelessWidget {
  const _UnlockProgress({
    required this.entries,
    required this.catalog,
    required this.icon,
  });

  final List<DashboardUnlockEntry> entries;
  final Future<List<String>> catalog;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<List<String>>(
      future: catalog,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            '解锁进度暂不可用',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          );
        }
        if (!snapshot.hasData) {
          return const LinearProgressIndicator();
        }
        final available = snapshot.data!
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .toSet();
        final unlocked = entries
            .map((entry) => entry.name.trim())
            .where(available.contains)
            .toSet()
            .length;
        final total = available.length;
        final value = total == 0 ? 0.0 : unlocked / total;
        return Semantics(
          label: '解锁进度',
          value: '$unlocked/$total',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: colors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(child: Text('解锁进度')),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '$unlocked / $total',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(value * 100).round()}%',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: value.clamp(0, 1),
                minHeight: 6,
                borderRadius: BorderRadius.circular(AppRadius.small),
                color: colors.primary,
                backgroundColor: colors.primary.withValues(alpha: 0.14),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UnlockPieChartPage extends StatefulWidget {
  const _UnlockPieChartPage({
    required this.title,
    required this.icon,
    required this.entries,
  });

  final String title;
  final IconData icon;
  final List<DashboardUnlockEntry> entries;

  @override
  State<_UnlockPieChartPage> createState() => _UnlockPieChartPageState();
}

class _UnlockPieChartPageState extends State<_UnlockPieChartPage> {
  int _minPercent = PieChartSettings.defaultMinPercent;

  @override
  void initState() {
    super.initState();
    _loadMinPercent();
  }

  Future<void> _loadMinPercent() async {
    final minPercent = await PieChartSettings.loadMinPercent();
    if (!mounted) return;
    setState(() => _minPercent = minPercent);
  }

  void _setMinPercent(int value) {
    if (value == _minPercent) return;
    setState(() => _minPercent = value);
    PieChartSettings.saveMinPercent(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          PopupMenuButton<int>(
            tooltip: '占比下限：低于该占比的项目合并为「其他」',
            icon: const Icon(Icons.filter_alt_outlined),
            initialValue: _minPercent,
            onSelected: _setMinPercent,
            itemBuilder: (context) => [
              for (final option in PieChartSettings.minPercentOptions)
                CheckedPopupMenuItem<int>(
                  value: option,
                  checked: option == _minPercent,
                  child: Text(option == 0 ? '不合并（0%）' : '低于 $option% 合并'),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.page,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppLayout.dashboardMaxWidth,
              ),
              child: _UnlockPieChart(
                entries: widget.entries,
                icon: widget.icon,
                minPercent: _minPercent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnlockPieChart extends StatefulWidget {
  const _UnlockPieChart({
    required this.entries,
    required this.icon,
    required this.minPercent,
  });

  final List<DashboardUnlockEntry> entries;
  final IconData icon;
  final int minPercent;

  @override
  State<_UnlockPieChart> createState() => _UnlockPieChartState();
}

class _UnlockPieChartState extends State<_UnlockPieChart> {
  int? _selectedIndex;
  int? _hoveredIndex;

  @override
  void didUpdateWidget(covariant _UnlockPieChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.minPercent != widget.minPercent) {
      _selectedIndex = null;
      _hoveredIndex = null;
    }
  }

  /// 点同一项取消选中；传 null（点空白处）也回到总计。
  void _select(int? index) {
    setState(() => _selectedIndex = index == _selectedIndex ? null : index);
  }

  void _hover(int? index) {
    if (index == _hoveredIndex) return;
    setState(() => _hoveredIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final slices = _buildPieSlices(widget.entries, widget.minPercent);
    if (slices.isEmpty) return const _PieEmptyState();

    final total = slices.fold<int>(0, (sum, slice) => sum + slice.count);
    final pieColors = _pieColors(colors, slices);
    final selectedIndex =
        _selectedIndex != null && _selectedIndex! < slices.length
        ? _selectedIndex
        : null;
    final hoveredIndex = _hoveredIndex != null && _hoveredIndex! < slices.length
        ? _hoveredIndex
        : null;
    final activeIndex = selectedIndex ?? hoveredIndex;

    // 提示只在固定/未固定之间切换。悬停时中心已经在变，提示再跟着变会让
    // 鼠标快速划过时两行文字来回跳。
    final hint = selectedIndex == null
        ? '点按扇区或图例查看单项占比'
        : '已固定「${slices[selectedIndex].name}」· 再次点按取消';

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final twoPane = width >= 640;
        final large = width >= 1000;
        final chartHeight = large ? 380.0 : (twoPane ? 300.0 : 256.0);

        final chartCard = AppCard.filled(
          title: '次数占比',
          icon: widget.icon,
          trailing: _PieTotalBadge(total: total),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.lg,
          ),
          child: Column(
            children: [
              SizedBox(
                height: chartHeight,
                child: _Pie(
                  slices: slices,
                  total: total,
                  colors: pieColors,
                  activeIndex: activeIndex,
                  onSelect: _select,
                  onHover: _hover,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              _PieFadeSwitcher(
                child: Text(
                  hint,
                  key: ValueKey(hint),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );

        final legendCard = AppCard.filled(
          title: '各项明细',
          icon: Icons.list_alt_outlined,
          trailing: Text(
            widget.minPercent == 0
                ? '${slices.length} 项 · 不合并'
                : '${slices.length} 项 · 下限 ${widget.minPercent}%',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            0,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: MouseRegion(
            onExit: (_) => _hover(null),
            child: _PieLegend(
              slices: slices,
              total: total,
              colors: pieColors,
              activeIndex: activeIndex,
              onSelect: _select,
              onHover: _hover,
            ),
          ),
        );

        if (!twoPane) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              chartCard,
              const SizedBox(height: AppSpacing.lg),
              legendCard,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: large ? 440 : 340, child: chartCard),
            SizedBox(width: large ? AppSpacing.xxl : AppSpacing.lg),
            Expanded(child: legendCard),
          ],
        );
      },
    );
  }
}

class _PieTotalBadge extends StatelessWidget {
  const _PieTotalBadge({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        '$total 次',
        style: theme.textTheme.labelMedium?.copyWith(
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PieEmptyState extends StatelessWidget {
  const _PieEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return AppCard.filled(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: 48,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.donut_large_outlined,
              size: 28,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('暂无统计数据', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '产生行程次数后，这里会显示各项占比',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pie extends StatelessWidget {
  const _Pie({
    required this.slices,
    required this.total,
    required this.colors,
    required this.activeIndex,
    required this.onSelect,
    required this.onHover,
  });

  final List<_PieSlice> slices;
  final int total;
  final List<Color> colors;
  final int? activeIndex;
  final ValueChanged<int?> onSelect;
  final ValueChanged<int?> onHover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = activeIndex != null && activeIndex! < slices.length
        ? activeIndex
        : null;
    final activeSlice = active == null ? null : slices[active];
    final isSingle = slices.length == 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        final outerRadius = math.max(side / 2 - 10, 0.0);
        final centerSpaceRadius = outerRadius / 2;
        final sectionRadius = outerRadius - centerSpaceRadius;
        final centerWidth = (centerSpaceRadius * 1.85)
            .clamp(96.0, 168.0)
            .toDouble();
        final isLarge = side >= 320;
        final titleStyle = isLarge
            ? theme.textTheme.labelMedium
            : theme.textTheme.labelSmall;

        return Semantics(
          label: slices
              .map(
                (slice) =>
                    '${slice.name} ${_formatPercentage(slice.count, total)}',
              )
              .join('，'),
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  centerSpaceRadius: centerSpaceRadius,
                  sectionsSpace: isSingle ? 0 : 2.5,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(
                    enabled: true,
                    touchCallback: (event, response) {
                      final index =
                          response?.touchedSection?.touchedSectionIndex ?? -1;
                      final valid = index >= 0 && index < slices.length
                          ? index
                          : null;
                      if (event is FlTapUpEvent) {
                        onSelect(valid);
                      } else if (event is FlPointerHoverEvent) {
                        onHover(valid);
                      } else if (event is FlPointerExitEvent ||
                          event is FlTapCancelEvent ||
                          event is FlPanCancelEvent) {
                        onHover(null);
                      }
                    },
                    mouseCursorResolver: (event, response) {
                      final index =
                          response?.touchedSection?.touchedSectionIndex ?? -1;
                      return index >= 0
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.basic;
                    },
                  ),
                  sections: slices.indexed
                      .map((item) {
                        final index = item.$1;
                        final slice = item.$2;
                        final isActive = index == active;
                        final dimmed = active != null && !isActive;
                        final color = colors[index];
                        final showTitle =
                            !dimmed && slice.count * 100 >= total * 5;
                        return PieChartSectionData(
                          value: slice.count.toDouble(),
                          color: dimmed ? color.withValues(alpha: 0.28) : color,
                          radius: isActive
                              ? sectionRadius * 1.08
                              : sectionRadius,
                          cornerRadius: isSingle ? 0 : (side >= 320 ? 6 : 4),
                          title: showTitle
                              ? _formatPercentage(slice.count, total)
                              : '',
                          titleStyle: titleStyle?.copyWith(
                            color:
                                ThemeData.estimateBrightnessForColor(color) ==
                                    Brightness.dark
                                ? Colors.white
                                : Colors.black87,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                          titlePositionPercentageOffset: 0.56,
                        );
                      })
                      .toList(growable: false),
                ),
                duration: m3MotionDuration,
                curve: Easing.standardDecelerate,
              ),
              IgnorePointer(
                child: ExcludeSemantics(
                  child: SizedBox(
                    width: centerWidth,
                    child: _PieFadeSwitcher(
                      child: activeSlice == null
                          ? _PieCenterTotal(
                              key: const ValueKey('total'),
                              total: total,
                              large: isLarge,
                            )
                          : _PieCenterSlice(
                              key: ValueKey(active),
                              slice: activeSlice,
                              total: total,
                              color: colors[active!],
                              large: isLarge,
                              maxNameWidth: math.max(76.0, centerWidth - 36),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 只让当前内容淡入，旧内容立即移除。
///
/// 默认 `AnimatedSwitcher` 会把旧内容与新内容叠在同一个 Stack 里一起淡出；
/// 鼠标快速划过扇区时，中心会同时叠着两三个项目名。
class _PieFadeSwitcher extends StatelessWidget {
  const _PieFadeSwitcher({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 140),
      switchInCurve: Easing.standardDecelerate,
      layoutBuilder: (currentChild, previousChildren) =>
          currentChild ?? const SizedBox.shrink(),
      transitionBuilder: (child, animation) => FadeTransition(
        // 从 35% 起步，快速切换时文字不会整个消失再出现。
        opacity: Tween<double>(begin: 0.35, end: 1).animate(animation),
        child: child,
      ),
      child: child,
    );
  }
}

class _PieCenterTotal extends StatelessWidget {
  const _PieCenterTotal({super.key, required this.total, required this.large});

  final int total;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$total',
          maxLines: 1,
          style:
              (large
                      ? theme.textTheme.headlineLarge
                      : theme.textTheme.headlineMedium)
                  ?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '总次数',
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PieCenterSlice extends StatelessWidget {
  const _PieCenterSlice({
    super.key,
    required this.slice,
    required this.total,
    required this.color,
    required this.large,
    required this.maxNameWidth,
  });

  final _PieSlice slice;
  final int total;
  final Color color;
  final bool large;
  final double maxNameWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatPercentage(slice.count, total),
          maxLines: 1,
          style:
              (large
                      ? theme.textTheme.headlineMedium
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxNameWidth),
              child: Text(
                slice.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '${slice.count} 次',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PieLegend extends StatefulWidget {
  const _PieLegend({
    required this.slices,
    required this.total,
    required this.colors,
    required this.activeIndex,
    required this.onSelect,
    required this.onHover,
  });

  final List<_PieSlice> slices;
  final int total;
  final List<Color> colors;
  final int? activeIndex;
  final ValueChanged<int?> onSelect;
  final ValueChanged<int?> onHover;

  @override
  State<_PieLegend> createState() => _PieLegendState();
}

class _PieLegendState extends State<_PieLegend> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 480 ? 2 : 1;
        final collapsedCount = columns * 6;
        final canExpand = widget.slices.length > collapsedCount;
        final visibleItems = _expanded || !canExpand
            ? widget.slices.indexed.toList(growable: false)
            : _collapsedLegendItems(collapsedCount);
        final itemWidth = columns == 2
            ? (constraints.maxWidth - AppSpacing.sm) / 2
            : constraints.maxWidth;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MouseRegion(
              onExit: (_) => widget.onHover(null),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xxs,
                children: [
                  for (final item in visibleItems)
                    SizedBox(
                      width: itemWidth,
                      child: _PieLegendRow(
                        index: item.$1,
                        slice: item.$2,
                        total: widget.total,
                        color: widget.colors[item.$1],
                        active: widget.activeIndex == item.$1,
                        onSelect: widget.onSelect,
                        onHover: widget.onHover,
                      ),
                    ),
                ],
              ),
            ),
            if (canExpand) ...[
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.center,
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

class _PieLegendRow extends StatelessWidget {
  const _PieLegendRow({
    required this.index,
    required this.slice,
    required this.total,
    required this.color,
    required this.active,
    required this.onSelect,
    required this.onHover,
  });

  final int index;
  final _PieSlice slice;
  final int total;
  final Color color;
  final bool active;
  final ValueChanged<int?> onSelect;
  final ValueChanged<int?> onHover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final percentage = _formatPercentage(slice.count, total);
    final foreground = active ? colors.onSecondaryContainer : colors.onSurface;
    final secondaryForeground = active
        ? colors.onSecondaryContainer.withValues(alpha: 0.75)
        : colors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Semantics(
        button: true,
        selected: active,
        label: '${slice.name}，${slice.count} 次，$percentage',
        onTap: () => onSelect(index),
        excludeSemantics: true,
        child: AnimatedContainer(
          duration: m3MotionDurationShort,
          curve: Easing.standard,
          decoration: BoxDecoration(
            color: active
                ? colors.secondaryContainer
                : colors.secondaryContainer.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(AppRadius.small),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              excludeFromSemantics: true,
              borderRadius: BorderRadius.circular(AppRadius.small),
              onTap: () => onSelect(index),
              onHover: (hovering) {
                if (hovering) onHover(index);
              },
              child: SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: m3MotionDurationShort,
                        curve: Easing.standard,
                        width: active ? 12 : 10,
                        height: active ? 12 : 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          slice.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: foreground,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '${slice.count} 次',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondaryForeground,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      SizedBox(
                        width: 52,
                        child: Text(
                          percentage,
                          textAlign: TextAlign.right,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PieSlice {
  const _PieSlice({required this.name, required this.count});

  final String name;
  final int count;
}

/// 按次数降序切片；占比低于 [minPercent] 的尾部合并为「其他」。
///
/// 前 5 项始终单独成片，避免项目本来就不多时，阈值把整张图画成一块「其他」。
/// [minPercent] 为 0 表示不合并。
List<_PieSlice> _buildPieSlices(
  List<DashboardUnlockEntry> entries,
  int minPercent,
) {
  final sorted = entries.where((entry) => entry.tripCount > 0).toList()
    ..sort((a, b) {
      final byCount = b.tripCount.compareTo(a.tripCount);
      return byCount != 0 ? byCount : a.name.compareTo(b.name);
    });
  if (minPercent <= 0 || sorted.length <= 5) {
    return sorted
        .map((entry) => _PieSlice(name: entry.name, count: entry.tripCount))
        .toList(growable: false);
  }
  final total = sorted.fold<int>(0, (sum, entry) => sum + entry.tripCount);
  var visibleCount = 5;
  while (visibleCount < sorted.length &&
      sorted[visibleCount].tripCount * 100 >= total * minPercent) {
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

/// 前三个扇区直接用主题色，后续色相从种子色散开。
///
/// 色相刻意避开 secondary / tertiary 所在的区间（约 +60°、+120°），
/// 否则动态取色下会和前三个颜色撞在一起；聚合项「其他」固定用中性描边色。
List<Color> _pieColors(ColorScheme colors, List<_PieSlice> slices) {
  final isDark =
      ThemeData.estimateBrightnessForColor(colors.surface) == Brightness.dark;
  final seedHue = HSLColor.fromColor(colors.primary).hue;
  const accentHues = <double>[180, 240, 300, 30, 90, 150, 210, 270, 330];
  var accentIndex = 0;
  final result = <Color>[];
  for (final slice in slices) {
    if (slice.name == '其他') {
      result.add(colors.outline);
    } else if (result.isEmpty) {
      result.add(colors.primary);
    } else if (result.length == 1) {
      result.add(colors.tertiary);
    } else if (result.length == 2) {
      result.add(colors.secondary);
    } else {
      result.add(
        HSLColor.fromAHSL(
          1,
          (seedHue + accentHues[accentIndex++ % accentHues.length]) % 360,
          isDark ? 0.5 : 0.58,
          isDark ? 0.72 : 0.5,
        ).toColor(),
      );
    }
  }
  return result;
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
