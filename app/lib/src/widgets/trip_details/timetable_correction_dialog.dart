import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:raillog/src/models/trip_schedule_times.dart';

/// 手动矫正历史时刻表的中间站到发时刻。
///
/// 矫正只用于当前这次查看：结果只替换页面里的 [TripScheduleTimes]，既不写回历史
/// 时刻表，也不落到行程记录上。
Future<List<TripScheduleStop>?> showTimetableCorrectionDialog(
  BuildContext context, {
  required TripScheduleTimes times,
}) {
  return showDialog<List<TripScheduleStop>>(
    context: context,
    builder: (_) => _TimetableCorrectionDialog(times: times),
  );
}

class _TimetableCorrectionDialog extends StatefulWidget {
  const _TimetableCorrectionDialog({required this.times});

  final TripScheduleTimes times;

  @override
  State<_TimetableCorrectionDialog> createState() =>
      _TimetableCorrectionDialogState();
}

class _TimetableCorrectionDialogState
    extends State<_TimetableCorrectionDialog> {
  final Map<int, TextEditingController> _arrivalControllers = {};
  final Map<int, TextEditingController> _departureControllers = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    for (
      var index = widget.times.boardingIndex + 1;
      index < widget.times.alightingIndex;
      index++
    ) {
      final stop = widget.times.stops[index];
      _arrivalControllers[index] = TextEditingController(
        text: _formatClock(stop.arrival),
      );
      _departureControllers[index] = TextEditingController(
        text: _formatClock(stop.departure),
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _arrivalControllers.values) {
      controller.dispose();
    }
    for (final controller in _departureControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    _error = null;
    final corrected = List<TripScheduleStop>.of(widget.times.stops);
    for (final entry in _arrivalControllers.entries) {
      final index = entry.key;
      final stop = corrected[index];
      final fallbackDate = _fallbackDate(index);
      final arrivalText = entry.value.text.trim();
      final departureText = _departureControllers[index]!.text.trim();
      final arrival = _parseClock(
        arrivalText,
        original: stop.arrival ?? stop.departure ?? fallbackDate,
      );
      final departSource = stop.departure ?? stop.arrival ?? fallbackDate;
      final departure = _parseClock(departureText, original: departSource);
      if ((arrival == null && arrivalText.isNotEmpty) ||
          (departure == null && departureText.isNotEmpty)) {
        setState(() => _error = '时刻格式应为 HH:mm，例如 08:05');
        return;
      }
      if (arrival != null && departure != null && departure.isBefore(arrival)) {
        setState(() => _error = '发点不能早于到点');
        return;
      }
      corrected[index] = TripScheduleStop(
        stationName: stop.stationName,
        arrival: arrival,
        departure: departure,
        mileage: stop.mileage,
      );
    }
    Navigator.of(context).pop(corrected);
  }

  DateTime _fallbackDate(int index) {
    for (var probe = index; probe >= 0; probe--) {
      final stop = widget.times.stops[probe];
      final value = stop.arrival ?? stop.departure;
      if (value != null) return value;
    }
    return DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = math.min(420.0, MediaQuery.sizeOf(context).width - 96);
    return AlertDialog(
      title: const Text('手动矫正时刻表'),
      content: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '矫正只对本次查看生效，不会改动历史时刻表。留空表示该站通过。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _arrivalControllers.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, offset) => _buildStopRow(offset, theme),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('应用')),
      ],
    );
  }

  Widget _buildStopRow(int offset, ThemeData theme) {
    final index = _arrivalControllers.keys.elementAt(offset);
    final station = widget.times.stops[index].stationName;
    return Row(
      children: [
        Expanded(
          child: Text(
            station,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _buildClockField(_arrivalControllers[index]!, '到'),
        const SizedBox(width: 8),
        _buildClockField(_departureControllers[index]!, '发'),
      ],
    );
  }

  Widget _buildClockField(TextEditingController controller, String label) {
    return SizedBox(
      width: 84,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.datetime,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
          LengthLimitingTextInputFormatter(5),
        ],
        decoration: InputDecoration(
          labelText: label,
          hintText: 'HH:mm',
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

String _formatClock(DateTime? value) {
  if (value == null) return '';
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

/// 把 `HH:mm` 贴回 [original] 的日期；空串表示没有时刻。
DateTime? _parseClock(String text, {required DateTime original}) {
  final value = text.trim();
  if (value.isEmpty) return null;
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return DateTime(original.year, original.month, original.day, hour, minute);
}
