import 'package:flutter/material.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

enum _TripSortField { departureTime, duration, price, mileage }

enum _TripKindFilter { all, rail, nonRail }

typedef TripEntryOpener =
    Future<bool?> Function(BuildContext context, DashboardTripEntry trip);

class AllTripsPage extends StatefulWidget {
  const AllTripsPage({
    super.key,
    required this.trips,
    this.title = '全部行程',
    this.showTripKindFilter = true,
    this.openTrip,
  });

  final List<DashboardTripEntry> trips;
  final String title;
  final bool showTripKindFilter;
  final TripEntryOpener? openTrip;

  @override
  State<AllTripsPage> createState() => _AllTripsPageState();
}

class _AllTripsPageState extends State<AllTripsPage> {
  _TripSortField _sortField = _TripSortField.departureTime;
  bool _descending = true;
  DateTimeRange? _dateRange;
  _TripKindFilter _kindFilter = _TripKindFilter.all;

  bool get _hasFilters =>
      _dateRange != null ||
      (widget.showTripKindFilter && _kindFilter != _TripKindFilter.all);

  List<DashboardTripEntry> get _visibleTrips {
    final trips = widget.trips.where((trip) {
      if (_kindFilter == _TripKindFilter.rail && !trip.isRailTrip) {
        return false;
      }
      if (_kindFilter == _TripKindFilter.nonRail && trip.isRailTrip) {
        return false;
      }
      final range = _dateRange;
      if (range == null) return true;
      final departureDate = DateUtils.dateOnly(trip.departureTime);
      return !departureDate.isBefore(range.start) &&
          !departureDate.isAfter(range.end);
    }).toList();
    trips.sort(_compareTrips);
    return trips;
  }

  int _compareTrips(DashboardTripEntry a, DashboardTripEntry b) {
    if (_sortField == _TripSortField.duration) {
      final aDuration = a.duration;
      final bDuration = b.duration;
      if (aDuration == null && bDuration != null) return 1;
      if (aDuration != null && bDuration == null) return -1;
    }

    final comparison = switch (_sortField) {
      _TripSortField.departureTime => a.departureTime.compareTo(
        b.departureTime,
      ),
      _TripSortField.duration => a.duration?.compareTo(b.duration!) ?? 0,
      _TripSortField.price => a.price.compareTo(b.price),
      _TripSortField.mileage => a.mileageKm.compareTo(b.mileageKm),
    };
    if (comparison != 0) return _descending ? -comparison : comparison;
    return b.departureTime.compareTo(a.departureTime);
  }

  Future<void> _showFilters() async {
    var sortField = _sortField;
    var descending = _descending;
    var dateRange = _dateRange;
    var kindFilter = _kindFilter;

    final settings = await showModalBottomSheet<_TripListSettings>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickDateRange() async {
              final selected = await showDateRangePicker(
                context: context,
                firstDate: DateTime(1900),
                lastDate: DateTime(2200),
                initialDateRange: dateRange,
              );
              if (selected != null) {
                setSheetState(() => dateRange = selected);
              }
            }

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '排序与筛选',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<_TripSortField>(
                      initialValue: sortField,
                      decoration: const InputDecoration(
                        labelText: '排序依据',
                        prefixIcon: Icon(Icons.sort),
                        border: OutlineInputBorder(),
                      ),
                      items: _TripSortField.values
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
                    if (widget.showTripKindFilter) ...[
                      Text(
                        '行程类型',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<_TripKindFilter>(
                        segments: const [
                          ButtonSegment(
                            value: _TripKindFilter.all,
                            label: Text('全部'),
                          ),
                          ButtonSegment(
                            value: _TripKindFilter.rail,
                            label: Text('铁路'),
                          ),
                          ButtonSegment(
                            value: _TripKindFilter.nonRail,
                            label: Text('非铁路'),
                          ),
                        ],
                        selected: {kindFilter},
                        onSelectionChanged: (selection) {
                          setSheetState(() => kindFilter = selection.first);
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pickDateRange,
                            icon: const Icon(Icons.date_range_outlined),
                            label: Text(
                              dateRange == null
                                  ? '选择日期范围'
                                  : '${_formatDate(dateRange!.start)} 至 '
                                        '${_formatDate(dateRange!.end)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (dateRange != null) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: '清除日期范围',
                            onPressed: () {
                              setSheetState(() => dateRange = null);
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              sortField = _TripSortField.departureTime;
                              descending = true;
                              dateRange = null;
                              kindFilter = _TripKindFilter.all;
                            });
                          },
                          child: const Text('重置'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.of(sheetContext).pop(
                            _TripListSettings(
                              sortField: sortField,
                              descending: descending,
                              dateRange: dateRange,
                              kindFilter: kindFilter,
                            ),
                          ),
                          child: const Text('应用'),
                        ),
                      ],
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
      _dateRange = settings.dateRange;
      _kindFilter = settings.kindFilter;
    });
  }

  @override
  Widget build(BuildContext context) {
    final trips = _visibleTrips;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '排序与筛选',
            onPressed: _showFilters,
            icon: Badge(
              isLabelVisible: _hasFilters,
              child: const Icon(Icons.filter_list),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${trips.length} / ${widget.trips.length} 趟行程',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '${_sortFieldLabel(_sortField)} · '
                    '${_descending ? '降序' : '升序'}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: trips.isEmpty
                  ? const _NoTripsFound()
                  : _ResponsiveTripsList(
                      trips: trips,
                      openTrip: widget.openTrip,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResponsiveTripsList extends StatelessWidget {
  const _ResponsiveTripsList({required this.trips, this.openTrip});

  final List<DashboardTripEntry> trips;
  final TripEntryOpener? openTrip;

  @override
  Widget build(BuildContext context) {
    const horizontalPadding = 16.0;
    const gap = 12.0;
    const minCardWidth = 300.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - horizontalPadding * 2;
        final calculatedColumns =
            ((availableWidth + gap) / (minCardWidth + gap)).floor();
        final columns = calculatedColumns.clamp(1, trips.length).toInt();
        final rowCount = (trips.length + columns - 1) ~/ columns;

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            0,
            horizontalPadding,
            24,
          ),
          itemCount: rowCount,
          separatorBuilder: (context, index) => const SizedBox(height: gap),
          itemBuilder: (context, rowIndex) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (
                  var columnIndex = 0;
                  columnIndex < columns;
                  columnIndex++
                ) ...[
                  if (columnIndex > 0) const SizedBox(width: gap),
                  Expanded(child: _buildCard(rowIndex * columns + columnIndex)),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCard(int index) {
    if (index >= trips.length) return const SizedBox.shrink();
    final animationStep = index > 8 ? 8 : index;
    return M3Reveal(
      duration: Duration(milliseconds: 220 + animationStep * 30),
      distance: 6,
      child: _TripTicketCard(trip: trips[index], openTrip: openTrip),
    );
  }
}

class _TripTicketCard extends StatelessWidget {
  const _TripTicketCard({required this.trip, this.openTrip});

  final DashboardTripEntry trip;
  final TripEntryOpener? openTrip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = trip.duration;
    return Material(
      clipBehavior: Clip.antiAlias,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () => _openDetails(context),
        child: Column(
          children: [
            Container(
              color: trip.isRailTrip
                  ? colors.primaryContainer
                  : colors.secondaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    trip.isRailTrip
                        ? Icons.train_outlined
                        : Icons.commute_outlined,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _trainLabel(trip.trainNumber),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        trip.ticketLabel,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(_formatDate(trip.departureTime)),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StationTime(
                          station: trip.fromStation,
                          dateTime: trip.departureTime,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          children: [
                            const Icon(Icons.arrow_forward, size: 20),
                            if (duration != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                _formatDuration(duration),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Expanded(
                        child: _StationTime(
                          station: trip.toStation,
                          dateTime: trip.arrivalTime,
                          alignEnd: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: colors.outlineVariant),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 14,
                          runSpacing: 4,
                          children: [
                            _TicketDetail(
                              icon: Icons.event_seat_outlined,
                              text: _seatLabel(trip),
                            ),
                            if (trip.mileageKm > 0)
                              _TicketDetail(
                                icon: Icons.straighten_outlined,
                                text: '${trip.mileageKm.round()} km',
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '¥${trip.price.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDetails(BuildContext context) async {
    final changed = openTrip == null
        ? await Navigator.of(context).push<bool>(
            m3PageRoute(
              builder: (context) => TripRecordDetailsPage(tripId: trip.id),
            ),
          )
        : await openTrip!(context, trip);
    if (changed == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }
}

class _StationTime extends StatelessWidget {
  const _StationTime({
    required this.station,
    required this.dateTime,
    this.alignEnd = false,
  });

  final String station;
  final DateTime? dateTime;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          station,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(dateTime == null ? '--:--' : _formatMonthDayTime(dateTime!)),
      ],
    );
  }
}

class _TicketDetail extends StatelessWidget {
  const _TicketDetail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: color)),
      ],
    );
  }
}

class _NoTripsFound extends StatelessWidget {
  const _NoTripsFound();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            const Text('没有符合当前筛选条件的行程'),
          ],
        ),
      ),
    );
  }
}

class _TripListSettings {
  const _TripListSettings({
    required this.sortField,
    required this.descending,
    required this.dateRange,
    required this.kindFilter,
  });

  final _TripSortField sortField;
  final bool descending;
  final DateTimeRange? dateRange;
  final _TripKindFilter kindFilter;
}

String _sortFieldLabel(_TripSortField field) => switch (field) {
  _TripSortField.departureTime => '出发时间',
  _TripSortField.duration => '乘坐时长',
  _TripSortField.price => '票价',
  _TripSortField.mileage => '里程',
};

String _trainLabel(String value) {
  final trainNumber = value.trim();
  return trainNumber.isEmpty ? '未填写车次' : trainNumber;
}

String _seatLabel(DashboardTripEntry trip) {
  final seatType = trip.seatType?.trim() ?? '';
  final seatNumber = trip.seatNumber?.trim() ?? '';
  if (seatType.isEmpty && seatNumber.isEmpty) return '坐席未记录';
  if (seatType.isEmpty) return seatNumber;
  if (seatNumber.isEmpty) return seatType;
  return '$seatType/$seatNumber';
}

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _formatMonthDayTime(DateTime value) =>
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _formatDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  if (hours == 0) return '$minutes分';
  return minutes == 0 ? '$hours时' : '$hours时$minutes分';
}
