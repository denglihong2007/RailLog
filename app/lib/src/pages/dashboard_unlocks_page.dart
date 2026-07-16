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
  _UnlockSortField _sortField = _UnlockSortField.unlockTime;
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

                final entry = entries[index - 1];
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
