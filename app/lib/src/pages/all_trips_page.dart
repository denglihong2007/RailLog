import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/engagement_prompt_service.dart';
import 'package:raillog/src/services/ticket_generator_service.dart';
import 'package:raillog/src/widgets/engagement_prompt.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';
import 'package:url_launcher/url_launcher.dart';

enum _TripSortField { departureTime, mileage, duration, price }

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
    this.enableSelection = false,
  });

  final List<DashboardTripEntry> trips;
  final String title;
  final bool showTripKindFilter;
  final TripEntryOpener? openTrip;
  final bool enableSelection;

  @override
  State<AllTripsPage> createState() => _AllTripsPageState();
}

class _AllTripsPageState extends State<AllTripsPage> {
  final TextEditingController _searchController = TextEditingController();
  _TripSortField _sortField = _TripSortField.departureTime;
  bool _descending = true;
  DateTimeRange? _dateRange;
  _TripKindFilter _kindFilter = _TripKindFilter.all;
  String _searchQuery = '';
  final Set<int> _selectedTripIds = {};
  final Set<int> _removedTripIds = {};
  bool _isSelecting = false;
  String? _busyLabel;
  bool _changed = false;

  bool get _selectionMode => _isSelecting;

  List<DashboardTripEntry> get _selectedTrips =>
      widget.trips.where((trip) => _selectedTripIds.contains(trip.id)).toList();

  bool get _selectedTripsCanGenerate =>
      _selectedTrips.isNotEmpty &&
      _selectedTrips.every((trip) => trip.ticketId != null);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasFilters =>
      _dateRange != null ||
      (widget.showTripKindFilter && _kindFilter != _TripKindFilter.all);

  List<DashboardTripEntry> get _visibleTrips {
    final trips = widget.trips.where((trip) {
      if (_removedTripIds.contains(trip.id)) return false;
      if (!trip.matchesSearch(_searchQuery)) return false;
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

  void _toggleSelection(DashboardTripEntry trip) {
    if (!widget.enableSelection || _busyLabel != null) return;
    setState(() {
      _isSelecting = true;
      if (!_selectedTripIds.add(trip.id)) _selectedTripIds.remove(trip.id);
    });
  }

  void _startSelection() {
    if (!widget.enableSelection || _busyLabel != null) return;
    setState(() => _isSelecting = true);
  }

  void _clearSelection() {
    if (_busyLabel != null) return;
    setState(() {
      _isSelecting = false;
      _selectedTripIds.clear();
    });
  }

  void _returnWithChanges() {
    setState(() => _changed = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  void _toggleSelectAll(List<DashboardTripEntry> visibleTrips) {
    if (_busyLabel != null) return;
    final visibleIds = visibleTrips.map((trip) => trip.id).toSet();
    final allSelected =
        visibleIds.isNotEmpty && visibleIds.every(_selectedTripIds.contains);
    setState(() {
      if (allSelected) {
        _selectedTripIds.removeAll(visibleIds);
      } else {
        _selectedTripIds.addAll(visibleIds);
      }
    });
  }

  Future<void> _deleteSelectedTrips() async {
    final selectedTrips = _selectedTrips;
    if (selectedTrips.isEmpty || _busyLabel != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text('删除 ${selectedTrips.length} 趟行程？'),
        content: const Text('所选行程将被永久删除，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyLabel = '正在删除');
    final deletedIds = <int>[];
    try {
      for (final trip in selectedTrips) {
        if (await DbHelper.instance.deleteTrip(trip.id) > 0) {
          deletedIds.add(trip.id);
        }
      }
      if (!mounted) return;
      setState(() {
        _removedTripIds.addAll(deletedIds);
        _isSelecting = false;
        _selectedTripIds.clear();
        _changed = deletedIds.isNotEmpty || _changed;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已删除 ${deletedIds.length} 趟行程')));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _removedTripIds.addAll(deletedIds);
        _selectedTripIds.removeAll(deletedIds);
        _changed = deletedIds.isNotEmpty || _changed;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 ${deletedIds.length} 趟，随后操作失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _busyLabel = null);
    }
  }

  Future<void> _downloadSelectedImages() async {
    final selectedTrips = _selectedTrips;
    if (!_selectedTripsCanGenerate || _busyLabel != null) return;
    var savedCount = 0;
    try {
      for (var index = 0; index < selectedTrips.length; index++) {
        if (!mounted) return;
        setState(
          () => _busyLabel = '正在下载 ${index + 1}/${selectedTrips.length}',
        );
        final ticketId = selectedTrips[index].ticketId!;
        final bytes = await TicketGeneratorService.generateImage(
          tripId: ticketId,
        );
        await TicketGeneratorService.saveImage(tripId: ticketId, bytes: bytes);
        savedCount++;
      }
      if (!mounted) return;
      setState(() {
        _isSelecting = false;
        _selectedTripIds.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已逐张保存 $savedCount 张车票图片')));
      await maybeShowEngagementPrompt(
        context,
        EngagementPromptEvent.ticketImageSaved,
      );
    } on TicketGeneratorException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存 $savedCount 张，随后下载失败：${error.message}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存 $savedCount 张，随后下载失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _busyLabel = null);
    }
  }

  Future<void> _orderSelectedTickets() async {
    final selectedTrips = _selectedTrips;
    if (!_selectedTripsCanGenerate || _busyLabel != null) return;
    setState(() => _busyLabel = '正在创建 Key');
    try {
      final download = await TicketGeneratorService.createPdfDownloadKey(
        tripIds: selectedTrips.map((trip) => trip.ticketId!),
      );
      if (!mounted) return;
      setState(() => _busyLabel = null);
      await _showOrderKey(download, selectedTrips.length);
      if (mounted) {
        setState(() {
          _isSelecting = false;
          _selectedTripIds.clear();
        });
      }
    } on TicketGeneratorException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('创建下载 Key 失败：$error')));
    } finally {
      if (mounted) setState(() => _busyLabel = null);
    }
  }

  Future<void> _showOrderKey(
    TicketPdfDownloadKey download,
    int ticketCount,
  ) async {
    final openTaobao = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.key_outlined),
        title: const Text('向商家发送下载 Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('此 Key 包含 $ticketCount 趟行程，请发送给淘宝商家客服。'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Theme.of(dialogContext).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                download.key,
                textAlign: TextAlign.center,
                style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Key 有效期至 ${_formatDateTime(download.expiresAt.toLocal())}。',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: download.key));
              if (!mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Key 已复制')));
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('复制 Key'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('前往淘宝'),
          ),
        ],
      ),
    );
    if (!mounted || openTaobao != true) return;
    final opened = await launchUrl(
      Uri.parse('https://m.tb.cn/h.8XSxU6t54xTo7tM'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开购买链接')));
    }
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
    return PopScope<bool>(
      canPop: !_selectionMode && !_changed,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectionMode) {
          _clearSelection();
        } else if (_changed) {
          _returnWithChanges();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _selectionMode
              ? IconButton(
                  tooltip: '退出多选',
                  onPressed: _busyLabel == null ? _clearSelection : null,
                  icon: const Icon(Icons.close),
                )
              : _changed
              ? IconButton(
                  tooltip: '返回',
                  onPressed: _returnWithChanges,
                  icon: const Icon(Icons.arrow_back),
                )
              : null,
          title: Text(
            _selectionMode
                ? (_busyLabel ??
                      '已选择 ${_selectedTripIds.length} 项'
                          '${_selectedTripIds.isNotEmpty && !_selectedTripsCanGenerate ? '（含未同步行程）' : ''}')
                : widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: _selectionMode
              ? [
                  IconButton(
                    tooltip: '全选当前结果',
                    onPressed: _busyLabel == null
                        ? () => _toggleSelectAll(trips)
                        : null,
                    icon: const Icon(Icons.select_all),
                  ),
                ]
              : [
                  if (widget.enableSelection && trips.isNotEmpty)
                    IconButton(
                      tooltip: '多选车票',
                      onPressed: _startSelection,
                      icon: const Icon(Icons.checklist),
                    ),
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
        bottomNavigationBar: _selectionMode
            ? _SelectionActionsBar(
                busy: _busyLabel != null,
                hasSelection: _selectedTripIds.isNotEmpty,
                canGenerate: _selectedTripsCanGenerate,
                onDelete: _deleteSelectedTrips,
                onDownload: _downloadSelectedImages,
                onOrder: _orderSelectedTickets,
              )
            : null,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final status = Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${trips.length} / '
                            '${widget.trips.length - _removedTripIds.length} 趟行程',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          '${_sortFieldLabel(_sortField)} · '
                          '${_descending ? '降序' : '升序'}',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    );
                    final search = SizedBox(
                      height: 44,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                        decoration: InputDecoration(
                          hintText: '搜索',
                          isDense: true,
                          filled: true,
                          fillColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          prefixIcon: const Icon(Icons.search, size: 20),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 44,
                          ),
                          suffixIcon: _searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清除搜索',
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                  icon: const Icon(Icons.close, size: 20),
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    );

                    if (constraints.maxWidth < 720) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [status, const SizedBox(height: 10), search],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: status),
                        const SizedBox(width: 20),
                        SizedBox(width: 360, child: search),
                      ],
                    );
                  },
                ),
              ),
              Expanded(
                child: trips.isEmpty
                    ? const _NoTripsFound()
                    : _ResponsiveTripsList(
                        trips: trips,
                        openTrip: widget.openTrip,
                        selectionMode: _selectionMode,
                        selectedTripIds: _selectedTripIds,
                        onToggleSelection: _toggleSelection,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionActionsBar extends StatelessWidget {
  const _SelectionActionsBar({
    required this.busy,
    required this.hasSelection,
    required this.canGenerate,
    required this.onDelete,
    required this.onDownload,
    required this.onOrder,
  });

  final bool busy;
  final bool hasSelection;
  final bool canGenerate;
  final VoidCallback onDelete;
  final VoidCallback onDownload;
  final VoidCallback onOrder;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: _SelectionAction(
              icon: Icons.delete_outline,
              label: '删除',
              onPressed: busy || !hasSelection ? null : onDelete,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          Expanded(
            child: _SelectionAction(
              icon: Icons.download_outlined,
              label: '下载图片',
              onPressed: busy || !canGenerate ? null : onDownload,
            ),
          ),
          Expanded(
            child: _SelectionAction(
              icon: Icons.shopping_bag_outlined,
              label: '订购车票',
              onPressed: busy || !canGenerate ? null : onOrder,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionAction extends StatelessWidget {
  const _SelectionAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: onPressed == null ? null : color),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: color == null || onPressed == null
            ? null
            : TextStyle(color: color),
      ),
    );
  }
}

class _ResponsiveTripsList extends StatelessWidget {
  const _ResponsiveTripsList({
    required this.trips,
    required this.selectionMode,
    required this.selectedTripIds,
    required this.onToggleSelection,
    this.openTrip,
  });

  final List<DashboardTripEntry> trips;
  final TripEntryOpener? openTrip;
  final bool selectionMode;
  final Set<int> selectedTripIds;
  final ValueChanged<DashboardTripEntry> onToggleSelection;

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
      child: _TripTicketCard(
        trip: trips[index],
        openTrip: openTrip,
        selectionMode: selectionMode,
        selected: selectedTripIds.contains(trips[index].id),
        onToggleSelection: onToggleSelection,
      ),
    );
  }
}

class _TripTicketCard extends StatelessWidget {
  const _TripTicketCard({
    required this.trip,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelection,
    this.openTrip,
  });

  final DashboardTripEntry trip;
  final TripEntryOpener? openTrip;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<DashboardTripEntry> onToggleSelection;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = trip.duration;
    return Material(
      clipBehavior: Clip.antiAlias,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: selectionMode
            ? () => onToggleSelection(trip)
            : () => _openDetails(context),
        onLongPress: () => onToggleSelection(trip),
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
                    selectionMode
                        ? (selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked)
                        : trip.isRailTrip
                        ? Icons.train_outlined
                        : Icons.commute_outlined,
                    size: 20,
                    color: selected ? colors.primary : null,
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

String _formatDateTime(DateTime value) =>
    '${_formatDate(value)} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

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
