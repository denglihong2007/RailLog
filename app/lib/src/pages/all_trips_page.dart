import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/trip_group_summary.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/engagement_prompt_service.dart';
import 'package:raillog/src/services/journal_export_service.dart';
import 'package:raillog/src/services/journal_settings.dart';
import 'package:raillog/src/services/ticket_generator_service.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/engagement_prompt.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';
import 'package:raillog/src/widgets/selection_actions_bar.dart';
import 'package:url_launcher/url_launcher.dart';

enum _TripSortField { departureTime, mileage, duration, price }

enum _TripKindFilter { all, rail, nonRail }

enum _GroupAction { apply, clear }

typedef TripEntryOpener =
    Future<bool?> Function(BuildContext context, DashboardTripEntry trip);

/// 列表里的一行：单趟行程，或合并后的分组。
sealed class _TripListEntry {
  const _TripListEntry();

  DateTime get departureTime;
  Duration? get duration;
  double get mileageKm;
  double get price;
}

class _SingleTripEntry extends _TripListEntry {
  const _SingleTripEntry(this.trip);

  final DashboardTripEntry trip;

  @override
  DateTime get departureTime => trip.departureTime;

  @override
  Duration? get duration => trip.duration;

  @override
  double get mileageKm => trip.mileageKm;

  @override
  double get price => trip.price;
}

class _GroupTripEntry extends _TripListEntry {
  const _GroupTripEntry(this.group);

  final TripGroupSummary group;

  @override
  DateTime get departureTime => group.earliestDeparture;

  @override
  Duration? get duration => group.totalDuration;

  @override
  double get mileageKm => group.totalMileageKm;

  @override
  double get price => group.totalPrice;
}

class AllTripsPage extends StatefulWidget {
  const AllTripsPage({
    super.key,
    required this.trips,
    this.title = '全部行程',
    this.showTripKindFilter = true,
    this.openTrip,
    this.enableSelection = false,
    this.enableGrouping = false,
    this.headerBuilder,
    this.selectionBarBuilder,
  });

  final List<DashboardTripEntry> trips;
  final String title;
  final bool showTripKindFilter;
  final TripEntryOpener? openTrip;
  final bool enableSelection;

  /// 只对「完整行程列表」开启：按 `groupName` 合并成卡片。
  /// 已按条件筛过的子集（实体详情、图表、成就解锁）保持关闭。
  final bool enableGrouping;

  /// 列表上方（搜索框之上）的额外控件，供复用本页的批量操作放自己的筛选条。
  final WidgetBuilder? headerBuilder;

  /// 多选时替换默认的 [SelectionActionsBar]。
  ///
  /// 复用它做别的批量操作（如按历史时刻表重建）时，不需要另写一套列表/多选界面。
  final Widget Function(BuildContext context, TripsSelection selection)?
  selectionBarBuilder;

  @override
  State<AllTripsPage> createState() => _AllTripsPageState();
}

/// 复用「全部行程」的多选界面时，交给外部批量操作的状态与入口。
class TripsSelection {
  const TripsSelection({
    required this.visibleTrips,
    required this.selectedTrips,
    required this.busyLabel,
    required this.setBusyLabel,
    required this.exitSelection,
  });

  /// 当前搜索/筛选下可见的行程（不合并分组）。
  final List<DashboardTripEntry> visibleTrips;

  /// 已选中的行程。
  final List<DashboardTripEntry> selectedTrips;

  /// 非空时页面标题显示它，并禁止继续改选。
  final String? busyLabel;

  /// 设置 [busyLabel]。
  final ValueChanged<String?> setBusyLabel;

  /// 退出多选并清空选择。
  final VoidCallback exitSelection;
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
  final Set<String> _expandedGroupNames = {};

  /// `containsKey` 用来区分「没改过」与「取消分组（值为 null）」。
  final Map<int, String?> _groupNameOverrides = {};
  bool _isSelecting = false;
  String? _busyLabel;
  bool _changed = false;

  bool get _selectionMode => _isSelecting;

  DashboardTripEntry _withOverride(DashboardTripEntry trip) =>
      _groupNameOverrides.containsKey(trip.id)
      ? trip.withGroupName(_groupNameOverrides[trip.id])
      : trip;

  List<DashboardTripEntry> get _selectedTrips => widget.trips
      .where((trip) => _selectedTripIds.contains(trip.id))
      .map(_withOverride)
      .toList();

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

  /// 过滤后的单条行程，未排序。多选与「全选」都以它为准。
  List<DashboardTripEntry> get _visibleTrips {
    return widget.trips.map(_withOverride).where((trip) {
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
  }

  /// 列表实际渲染的条目：多选或未启用分组时逐条，否则同名行程合并成组。
  ///
  /// 归并对象是过滤后的可见成员，所以搜索/筛选生效时卡片聚合值只反映
  /// 命中成员；即使某组只剩一条可见成员也仍按分组卡片渲染。
  List<_TripListEntry> get _displayEntries {
    final visible = _visibleTrips;
    if (_selectionMode || !widget.enableGrouping) {
      return [for (final trip in visible) _SingleTripEntry(trip)];
    }

    final grouped = <String, List<DashboardTripEntry>>{};
    final entries = <_TripListEntry>[];
    for (final trip in visible) {
      final name = trip.groupName?.trim();
      if (name == null || name.isEmpty) {
        entries.add(_SingleTripEntry(trip));
      } else {
        (grouped[name] ??= []).add(trip);
      }
    }
    for (final group in grouped.entries) {
      entries.add(
        _GroupTripEntry(TripGroupSummary.fromTrips(group.key, group.value)),
      );
    }
    entries.sort(_compareEntries);
    return entries;
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

  void _setBusyLabel(String? label) {
    if (!mounted || _busyLabel == label) return;
    setState(() => _busyLabel = label);
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

  void _selectGroupMembers(List<DashboardTripEntry> members) {
    if (!widget.enableSelection || _busyLabel != null) return;
    setState(() {
      _isSelecting = true;
      _selectedTripIds.addAll(members.map((trip) => trip.id));
    });
  }

  void _toggleGroup(String name) {
    setState(() {
      if (!_expandedGroupNames.add(name)) {
        _expandedGroupNames.remove(name);
      }
    });
  }

  Future<void> _groupSelectedTrips() async {
    final selected = _selectedTrips;
    if (selected.isEmpty || _busyLabel != null) return;

    final existingNames = selected
        .map((trip) => trip.groupName?.trim())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toSet();
    final commonName = existingNames.length == 1 ? existingNames.first : null;
    var input = commonName ?? '';
    final formKey = GlobalKey<FormState>();
    final action = await showDialog<_GroupAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.workspaces_outline),
        title: const Text('设置分组'),
        content: Form(
          key: formKey,
          child: TextFormField(
            initialValue: input,
            autofocus: true,
            maxLength: 30,
            onChanged: (value) => input = value,
            decoration: const InputDecoration(
              labelText: '分组名称',
              hintText: '例如：京沪往返',
            ),
            validator: (value) =>
                (value ?? '').trim().isEmpty ? '请输入分组名称' : null,
            onFieldSubmitted: (_) {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(_GroupAction.apply);
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          if (existingNames.isNotEmpty)
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_GroupAction.clear),
              child: const Text('取消分组'),
            ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(_GroupAction.apply);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;

    final groupName = action == _GroupAction.clear ? null : input.trim();
    if (groupName != null && groupName.isEmpty) return;
    final ids = selected.map((trip) => trip.id).toList();
    setState(() => _busyLabel = '正在保存分组');
    try {
      final affected = await DbHelper.instance.updateTripGroups(ids, groupName);
      if (!mounted) return;
      setState(() {
        for (final id in ids) {
          _groupNameOverrides[id] = groupName;
        }
        _expandedGroupNames.removeAll(existingNames);
        _isSelecting = false;
        _selectedTripIds.clear();
        _busyLabel = null;
        _changed = affected > 0 || _changed;
      });
      final message = groupName == null
          ? '已取消分组'
          : '已将 ${ids.length} 趟行程归入「$groupName」';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyLabel = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('设置分组失败：$error')));
    }
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

  /// 把手账 PDF 存到系统下载目录。
  ///
  /// 启用条件只要求「选了东西」，绝不能用 [_selectedTripsCanGenerate]——
  /// 那个条件要求有 ticketId，而本地未同步的行程恰恰没有 ticketId，
  /// 它们正是选客户端本地生成要照顾到的人群。
  Future<void> _exportSelectedJournal() async {
    if (_selectedTripIds.isEmpty || _busyLabel != null) return;
    setState(() => _busyLabel = '正在读取行程');
    try {
      // 多选持有的是 DashboardTripEntry，只有字段子集：缺 notes /
      // companyName / viaRouteSegments / createdAt。按 id 回查完整 TripRecord。
      // getTripById 对「已删除 / 归属不符」返回 null，直接跳过。
      final trips = <TripRecord>[];
      for (final id in _selectedTripIds) {
        final trip = await DbHelper.instance.getTripById(id);
        if (trip != null) trips.add(trip);
      }
      if (trips.isEmpty) {
        throw const JournalExportException('所选行程已不存在，无法导出手账');
      }
      // 手账是从头往后翻的，与列表的倒序相反。
      trips.sort((a, b) => a.departureTime.compareTo(b.departureTime));

      if (!mounted) return;
      setState(() => _busyLabel = '正在生成手账');
      final result = await JournalExportService.exportTrips(
        trips: trips,
        style: JournalSettings.instance.style,
      );
      if (!mounted) return;

      // 成功即退出多选；失败留在原地，用户可以换风格或去掉几趟再试。
      setState(() {
        _isSelecting = false;
        _selectedTripIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已导出手账 ${result.tripCount} 趟行程（${result.pageCount} 页）\n'
            '保存位置：${result.savedPath}',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
      await maybeShowEngagementPrompt(
        context,
        EngagementPromptEvent.journalExported,
      );
    } on JournalExportException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出手账失败：$error')));
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
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: SelectableText(
                download.key,
                textAlign: TextAlign.center,
                style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
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
    final webUri = Uri.parse('https://m.tb.cn/h.8XSxU6t54xTo7tM');
    final appUri = Uri.parse(
      'taobao://shop.m.taobao.com/shop/shop_index.htm?shop_id=587947567',
    );
    var opened = false;
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        opened = await launchUrl(appUri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened) {
      try {
        opened = await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开购买链接')));
    }
  }

  int _compareEntries(_TripListEntry a, _TripListEntry b) {
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
    final entries = _displayEntries;
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
            ? (widget.selectionBarBuilder?.call(
                    context,
                    TripsSelection(
                      visibleTrips: trips,
                      selectedTrips: _selectedTrips,
                      busyLabel: _busyLabel,
                      setBusyLabel: _setBusyLabel,
                      exitSelection: _clearSelection,
                    ),
                  ) ??
                  SelectionActionsBar(
                    busy: _busyLabel != null,
                    hasSelection: _selectedTripIds.isNotEmpty,
                    canGenerate: _selectedTripsCanGenerate,
                    onGroup: _groupSelectedTrips,
                    onDelete: _deleteSelectedTrips,
                    onDownload: _downloadSelectedImages,
                    onExportJournal: _exportSelectedJournal,
                    onOrder: _orderSelectedTickets,
                  ))
            : null,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppLayout.dashboardMaxWidth,
              ),
              child: Column(
                children: [
                  if (widget.headerBuilder != null)
                    // Column 默认按内容居中放子项；不撑满宽度的话，复用方传进来的
                    // 一行筛选控件会缩成一小块悬在页面中间。
                    SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: widget.headerBuilder!(context),
                      ),
                    ),
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
                                borderRadius: BorderRadius.circular(
                                  AppRadius.extraSmall,
                                ),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        );

                        if (constraints.maxWidth < 720) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              status,
                              const SizedBox(height: AppSpacing.md),
                              search,
                            ],
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
                    child: entries.isEmpty
                        ? const _NoTripsFound()
                        : _ResponsiveTripsList(
                            entries: entries,
                            openTrip: widget.openTrip,
                            selectionMode: _selectionMode,
                            selectedTripIds: _selectedTripIds,
                            onToggleSelection: _toggleSelection,
                            enableSelection: widget.enableSelection,
                            expandedGroupNames: _expandedGroupNames,
                            onToggleGroup: _toggleGroup,
                            onSelectGroupMembers: _selectGroupMembers,
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

class _ResponsiveTripsList extends StatelessWidget {
  const _ResponsiveTripsList({
    required this.entries,
    required this.selectionMode,
    required this.selectedTripIds,
    required this.onToggleSelection,
    required this.enableSelection,
    required this.expandedGroupNames,
    required this.onToggleGroup,
    required this.onSelectGroupMembers,
    this.openTrip,
  });

  final List<_TripListEntry> entries;
  final TripEntryOpener? openTrip;
  final bool selectionMode;
  final Set<int> selectedTripIds;
  final ValueChanged<DashboardTripEntry> onToggleSelection;
  final bool enableSelection;
  final Set<String> expandedGroupNames;
  final ValueChanged<String> onToggleGroup;
  final ValueChanged<List<DashboardTripEntry>> onSelectGroupMembers;

  @override
  Widget build(BuildContext context) {
    const horizontalPadding = 16.0;
    const gap = 12.0;
    const minCardWidth = 300.0;
    final colors = Theme.of(context).colorScheme;
    final cards = _flattenEntries(colors);
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - horizontalPadding * 2;
        final calculatedColumns =
            ((availableWidth + gap) / (minCardWidth + gap)).floor();
        final columns = cards.isEmpty
            ? 1
            : calculatedColumns.clamp(1, cards.length).toInt();
        final rowCount = (cards.length + columns - 1) ~/ columns;

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
                  Expanded(
                    child: _buildCard(cards, rowIndex * columns + columnIndex),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  /// 展开的分组把成员卡片按原样紧跟在分组卡片后面，参与正常的网格排布。
  List<Widget> _flattenEntries(ColorScheme colors) {
    final cards = <Widget>[];
    for (final entry in entries) {
      switch (entry) {
        case _SingleTripEntry(:final trip):
          cards.add(_tripCard(trip, colors));
        case _GroupTripEntry(:final group):
          cards.add(_groupCard(group, colors));
          if (expandedGroupNames.contains(group.name)) {
            for (final trip in group.trips) {
              cards.add(_tripCard(trip, colors));
            }
          }
      }
    }
    return cards;
  }

  Widget _buildCard(List<Widget> cards, int index) {
    if (index >= cards.length) return const SizedBox.shrink();
    return M3Reveal(
      delay: m3RevealDelay(index),
      distance: 6,
      child: cards[index],
    );
  }

  Widget _tripCard(DashboardTripEntry trip, ColorScheme colors) {
    final groupName = trip.groupName?.trim() ?? '';
    return TripTicketCard(
      key: ValueKey('trip:${trip.id}'),
      trip: trip,
      openTrip: openTrip,
      selectionMode: selectionMode,
      selected: selectedTripIds.contains(trip.id),
      onToggleSelection: onToggleSelection,
      headerColor: groupName.isEmpty
          ? null
          : _groupHeaderColor(colors, groupName),
    );
  }

  Widget _groupCard(TripGroupSummary group, ColorScheme colors) =>
      _TripGroupCard(
        key: ValueKey('group:${group.name}'),
        group: group,
        headerColor: _groupHeaderColor(colors, group.name),
        expanded: expandedGroupNames.contains(group.name),
        onToggle: () => onToggleGroup(group.name),
        enableSelection: enableSelection,
        onSelectMembers: () => onSelectGroupMembers(group.trips),
      );
}

/// 分组标题底色按分组名稳定轮换：同一分组始终同色，不同分组尽量错开。
Color _groupHeaderColor(ColorScheme colors, String name) {
  final base = HSLColor.fromColor(colors.tertiaryContainer);
  final hue = (base.hue + _groupColorIndex(name) * 55) % 360;
  final tint = base.withHue(hue).toColor();
  // 与 surface 混合，保持浅色/深色主题下文字都有足够对比度。
  return Color.alphaBlend(tint.withValues(alpha: 0.72), colors.surface);
}

const _groupColorCount = 6;

int _groupColorIndex(String name) {
  var hash = 0;
  for (final codeUnit in name.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return hash % _groupColorCount;
}

class TripTicketCard extends StatelessWidget {
  const TripTicketCard({
    super.key,
    required this.trip,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelection,
    this.openTrip,
    this.headerColor,
  });

  final DashboardTripEntry trip;
  final TripEntryOpener? openTrip;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<DashboardTripEntry> onToggleSelection;

  /// 属于某个分组时传入该分组的标题底色，与独立行程区分。
  final Color? headerColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = trip.duration;
    return AppCard.outlined(
      color: colors.surface,
      borderColor: selected ? colors.primary : colors.outlineVariant,
      borderWidth: selected ? 2 : 1,
      onTap: selectionMode
          ? () => onToggleSelection(trip)
          : () => _openDetails(context),
      onLongPress: () => onToggleSelection(trip),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            color:
                headerColor ??
                (trip.isRailTrip
                    ? colors.primaryContainer
                    : colors.secondaryContainer),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
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
                    style: Theme.of(context).textTheme.titleMedium,
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
            padding: const EdgeInsets.all(AppSpacing.lg),
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
                            const SizedBox(height: AppSpacing.xs),
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
                const SizedBox(height: AppSpacing.md),
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
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: colors.primary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDetails(BuildContext context) =>
      _openTripDetails(context, trip, openTrip);
}

/// 打开行程详情；详情里改过数据时把「全部行程」也标记为需要刷新。
Future<void> _openTripDetails(
  BuildContext context,
  DashboardTripEntry trip,
  TripEntryOpener? openTrip,
) async {
  final changed = openTrip == null
      ? await Navigator.of(context).push<bool>(
          m3PageRoute(
            builder: (context) => TripRecordDetailsPage(tripId: trip.id),
          ),
        )
      : await openTrip(context, trip);
  if (changed == true && context.mounted) {
    Navigator.of(context).pop(true);
  }
}

class _TripGroupCard extends StatelessWidget {
  const _TripGroupCard({
    super.key,
    required this.group,
    required this.headerColor,
    required this.expanded,
    required this.onToggle,
    required this.enableSelection,
    required this.onSelectMembers,
  });

  final TripGroupSummary group;
  final Color headerColor;
  final bool expanded;
  final VoidCallback onToggle;
  final bool enableSelection;
  final VoidCallback onSelectMembers;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = group.totalDuration;
    return Semantics(
      button: true,
      expanded: expanded,
      label: '分组 ${group.name}，共 ${group.count} 趟',
      child: AppCard.outlined(
        color: colors.surface,
        borderColor: colors.outlineVariant,
        onTap: onToggle,
        onLongPress: enableSelection ? onSelectMembers : null,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            Container(
              color: headerColor,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  const Icon(Icons.workspaces_outline, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${group.count} 趟',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(_formatDate(group.earliestDeparture)),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StationTime(
                          station: group.fromStation,
                          dateTime: group.earliestDeparture,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          children: [
                            Icon(
                              group.isRoundTrip
                                  ? Icons.swap_horiz
                                  : Icons.arrow_forward,
                              size: 20,
                            ),
                            if (duration != null) ...[
                              const SizedBox(height: AppSpacing.xs),
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
                          station: group.toStation,
                          dateTime: group.latestArrival,
                          alignEnd: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: colors.outlineVariant),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 14,
                          runSpacing: 4,
                          children: [
                            if (group.seatSummary != null)
                              _TicketDetail(
                                icon: Icons.event_seat_outlined,
                                text: group.seatSummary!,
                              ),
                            if (group.totalMileageKm > 0)
                              _TicketDetail(
                                icon: Icons.straighten_outlined,
                                text: '${group.totalMileageKm.round()} km',
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '¥${group.totalPrice.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: colors.primary),
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
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
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
