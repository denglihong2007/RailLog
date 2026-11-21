import 'package:material_ui/material_ui.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';
import 'package:raillog/src/models/trip_schedule_times.dart';

/// 编辑简图中间站的时刻。
///
/// 打开底部时间线：点时刻胶囊打开系统时间选择器；停站/通过用行尾菜单切换；
/// 没有历史数据的站也可以手动补。编辑只用于当前这次查看，不写回历史时刻表，
/// 也不落到行程记录上。
Future<TripScheduleOverlay?> showTimetableCorrectionDialog(
  BuildContext context, {
  required TripScheduleOverlay overlay,
  required List<String> stationNames,
  required List<StationScheduleTime?> scheduleTimes,
  required DateTime baseDate,
}) {
  return showModalBottomSheet<TripScheduleOverlay>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => _TimetableCorrectionSheet(
      overlay: overlay,
      stationNames: stationNames,
      scheduleTimes: scheduleTimes,
      baseDate: baseDate,
    ),
  );
}

enum _EditKind { stop, pass }

class _EditRow {
  _EditRow({
    required this.label,
    required this.key,
    required this.kind,
    this.historicalStopIndex,
    this.arrival,
    this.departure,
    this.passTime,
    this.originalPassTime,
    this.passWasOverridden = false,
  });

  final String label;
  final String key;
  final int? historicalStopIndex;
  _EditKind kind;
  DateTime? arrival;
  DateTime? departure;
  DateTime? passTime;
  DateTime? originalPassTime;
  bool passWasOverridden;
}

class _TimetableCorrectionSheet extends StatefulWidget {
  const _TimetableCorrectionSheet({
    required this.overlay,
    required this.stationNames,
    required this.scheduleTimes,
    required this.baseDate,
  });

  final TripScheduleOverlay overlay;
  final List<String> stationNames;
  final List<StationScheduleTime?> scheduleTimes;
  final DateTime baseDate;

  @override
  State<_TimetableCorrectionSheet> createState() =>
      _TimetableCorrectionSheetState();
}

class _TimetableCorrectionSheetState extends State<_TimetableCorrectionSheet> {
  late List<TripScheduleStop> _stops;
  late Map<String, DateTime> _passOverrides;
  late Map<String, StationScheduleTime> _customTimes;
  late List<_EditRow> _rows;

  @override
  void initState() {
    super.initState();
    _loadFromOverlay();
  }

  void _loadFromOverlay() {
    final times = widget.overlay.times;
    _stops = List<TripScheduleStop>.of(
      times?.stops ?? const <TripScheduleStop>[],
    );
    _passOverrides = Map<String, DateTime>.of(
      times?.passTimeOverrides ?? const <String, DateTime>{},
    );
    _customTimes = Map<String, StationScheduleTime>.of(
      widget.overlay.customTimes,
    );
    _rows = _buildRows();
  }

  List<_EditRow> _buildRows() {
    final keys = stationOccurrenceKeys(widget.stationNames);
    final labels = _stationLabels(widget.stationNames);
    final rows = <_EditRow>[];
    for (var index = 1; index < widget.stationNames.length - 1; index++) {
      final key = keys[index];
      final custom = _customTimes[key];
      final annotation = widget.scheduleTimes[index];
      if (custom != null) {
        rows.add(
          _EditRow(
            label: labels[index],
            key: key,
            kind: _EditKind.stop,
            arrival: custom.arrival,
            departure: custom.departure,
          ),
        );
      } else if (annotation != null &&
          annotation.isStop &&
          annotation.stopIndex != null) {
        final stop = _stops[annotation.stopIndex!];
        rows.add(
          _EditRow(
            label: labels[index],
            key: key,
            kind: _EditKind.stop,
            historicalStopIndex: annotation.stopIndex,
            arrival: stop.arrival,
            departure: stop.departure,
          ),
        );
      } else if (annotation?.passTime != null) {
        rows.add(
          _EditRow(
            label: labels[index],
            key: key,
            kind: _EditKind.pass,
            passTime: annotation!.passTime,
            originalPassTime: annotation.passTime,
            passWasOverridden: _passOverrides.containsKey(key),
          ),
        );
      } else {
        rows.add(
          _EditRow(label: labels[index], key: key, kind: _EditKind.stop),
        );
      }
    }
    return rows;
  }

  DateTime _rowBaseDate(int rowIndex) {
    for (var index = rowIndex - 1; index >= 0; index--) {
      final row = _rows[index];
      final value = row.departure ?? row.arrival ?? row.passTime;
      if (value != null) return value;
    }
    return widget.baseDate;
  }

  Future<DateTime?> _pickTime(DateTime? current, DateTime fallback) async {
    final initial = current ?? fallback;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: '选择时刻',
    );
    if (picked == null) return null;
    return DateTime(
      initial.year,
      initial.month,
      initial.day,
      picked.hour,
      picked.minute,
    );
  }

  Future<void> _editArrival(_EditRow row, int index) async {
    final picked = await _pickTime(
      row.arrival,
      row.departure ?? _rowBaseDate(index),
    );
    if (picked == null) return;
    setState(() {
      row.arrival = picked;
      final departure = row.departure;
      if (departure != null &&
          departure.isBefore(picked) &&
          _sameDay(departure, picked)) {
        row.departure = departure.add(const Duration(days: 1));
      }
    });
  }

  Future<void> _editDeparture(_EditRow row, int index) async {
    var picked = await _pickTime(
      row.departure,
      row.arrival ?? _rowBaseDate(index),
    );
    if (picked == null) return;
    final arrival = row.arrival;
    if (arrival != null &&
        picked.isBefore(arrival) &&
        _sameDay(picked, arrival)) {
      picked = picked.add(const Duration(days: 1));
    }
    setState(() => row.departure = picked);
  }

  Future<void> _editPass(_EditRow row, int index) async {
    final picked = await _pickTime(row.passTime, _rowBaseDate(index));
    if (picked == null) return;
    setState(() => row.passTime = picked);
  }

  /// 点圆点直接在停站/通过之间切换。
  void _toggleKind(_EditRow row) {
    setState(() {
      if (row.kind == _EditKind.stop) {
        row.kind = _EditKind.pass;
        row.passTime = row.departure ?? row.arrival;
        row.originalPassTime = null;
        row.passWasOverridden = row.passTime != null;
      } else {
        row.kind = _EditKind.stop;
        row.arrival ??= row.passTime;
      }
    });
  }

  void _reset() => setState(_loadFromOverlay);

  void _apply() {
    final correctedStops = List<TripScheduleStop>.of(_stops);
    final overrides = Map<String, DateTime>.of(_passOverrides);
    final custom = Map<String, StationScheduleTime>.of(_customTimes);

    for (final row in _rows) {
      if (row.kind == _EditKind.pass) {
        custom.remove(row.key);
        final stopIndex = row.historicalStopIndex;
        if (stopIndex != null) {
          final stop = correctedStops[stopIndex];
          correctedStops[stopIndex] = TripScheduleStop(
            stationName: stop.stationName,
            arrival: null,
            departure: null,
            mileage: stop.mileage,
          );
        }
        if (row.passTime == row.originalPassTime) {
          // 没动过：保留原有的校准（或保持「按均速估算」）。
        } else if (row.passTime == null) {
          overrides.remove(row.key);
        } else {
          overrides[row.key] = row.passTime!;
        }
      } else {
        overrides.remove(row.key);
        final stopIndex = row.historicalStopIndex;
        if (stopIndex != null) {
          final stop = correctedStops[stopIndex];
          correctedStops[stopIndex] = TripScheduleStop(
            stationName: stop.stationName,
            arrival: row.arrival,
            departure: row.departure,
            mileage: stop.mileage,
          );
          custom.remove(row.key);
        } else if (row.arrival == null && row.departure == null) {
          custom.remove(row.key);
        } else {
          custom[row.key] = StationScheduleTime(
            arrival: row.arrival,
            departure: row.departure,
          );
        }
      }
    }

    final times = widget.overlay.times;
    final correctedTimes = times
        ?.withStops(correctedStops)
        .withPassTimeOverrides(overrides);
    Navigator.of(context)
        .pop(TripScheduleOverlay(times: correctedTimes, customTimes: custom));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('编辑中间站时刻', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        '点时刻即可修改；没有数据的站可以手动补。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: '关闭',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: _rows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('本段没有可编辑的中间站'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 48),
                    itemBuilder: (context, index) =>
                        _buildRow(context, _rows[index], index),
                  ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('撤销修改'),
                  ),
                  const Spacer(),
                  FilledButton(onPressed: _apply, child: const Text('完成')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, _EditRow row, int index) {
    final theme = Theme.of(context);
    final chips = row.kind == _EditKind.pass
        ? <Widget>[_passChip(row, index)]
        : <Widget>[
            _timeChip(
              '到',
              row.arrival,
              () => _editArrival(row, index),
              () => setState(() => row.arrival = null),
            ),
            _timeChip(
              '发',
              row.departure,
              () => _editDeparture(row, index),
              () => setState(() => row.departure = null),
            ),
          ];
    final name = Text(
      row.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );
    final marker = Tooltip(
      message: row.kind == _EditKind.stop ? '点击改为通过站' : '点击改为停靠站',
      child: InkWell(
        onTap: () => _toggleKind(row),
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(child: _marker(theme, row.kind)),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 280) {
            return Row(
              children: [
                marker,
                const SizedBox(width: 4),
                Expanded(child: name),
                const SizedBox(width: 8),
                ..._spacedChips(chips),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              marker,
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    name,
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: chips),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _spacedChips(List<Widget> chips) => [
    for (var index = 0; index < chips.length; index++) ...[
      if (index > 0) const SizedBox(width: 6),
      chips[index],
    ],
  ];

  Widget _marker(ThemeData theme, _EditKind kind) {
    final colors = theme.colorScheme;
    final isPass = kind == _EditKind.pass;
    return Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isPass ? colors.surfaceContainerLowest : colors.primary,
        border: Border.all(color: colors.primary, width: 2),
      ),
    );
  }

  Widget _timeChip(
    String label,
    DateTime? value,
    VoidCallback onTap,
    VoidCallback onClear,
  ) {
    final colors = Theme.of(context).colorScheme;
    if (value == null) {
      return ActionChip(
        avatar: Icon(Icons.add, size: 16, color: colors.onSurfaceVariant),
        label: Text('$label 时刻'),
        onPressed: onTap,
        backgroundColor: colors.surfaceContainerHigh,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: TextStyle(color: colors.onSurfaceVariant),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelPadding: const EdgeInsets.symmetric(horizontal: 3),
      );
    }
    return InputChip(
      label: Text('$label ${_clock(value)}'),
      onPressed: onTap,
      onDeleted: onClear,
      deleteIcon: const Icon(Icons.close, size: 16),
      backgroundColor: colors.secondaryContainer,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        color: colors.onSecondaryContainer,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 3),
    );
  }

  Widget _passChip(_EditRow row, int index) {
    final colors = Theme.of(context).colorScheme;
    final value = row.passTime;
    final canClear = row.passWasOverridden || row.historicalStopIndex != null;
    if (value == null) {
      return ActionChip(
        avatar: Icon(Icons.add, size: 16, color: colors.onSurfaceVariant),
        label: const Text('通过时刻'),
        onPressed: () => _editPass(row, index),
        backgroundColor: colors.surfaceContainerHigh,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: TextStyle(color: colors.onSurfaceVariant),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelPadding: const EdgeInsets.symmetric(horizontal: 3),
      );
    }
    return InputChip(
      label: Text('通过 ${_clock(value)}'),
      onPressed: () => _editPass(row, index),
      onDeleted: canClear ? () => setState(() => row.passTime = null) : null,
      deleteIcon: canClear ? const Icon(Icons.close, size: 16) : null,
      backgroundColor: colors.surfaceContainerHigh,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        color: colors.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 3),
    );
  }
}

/// 同名站出现多次（折返）时标出第几次，避免编辑到错误的那个。
List<String> _stationLabels(List<String> stationNames) {
  final totals = <String, int>{};
  for (final name in stationNames) {
    final normalized = normalizeStationName(name);
    totals[normalized] = (totals[normalized] ?? 0) + 1;
  }
  final seen = <String, int>{};
  final labels = <String>[];
  for (final name in stationNames) {
    final normalized = normalizeStationName(name);
    final occurrence = (seen[normalized] ?? 0) + 1;
    seen[normalized] = occurrence;
    final total = totals[normalized] ?? 1;
    labels.add(total > 1 ? '$name（第$occurrence次）' : name);
  }
  return labels;
}

String _clock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

bool _sameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;
