import 'package:flutter/material.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/pages/all_trips_page.dart';
import 'package:raillog/src/pages/settings/timetable_rebuild_review_page.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/route_service.dart';
import 'package:raillog/src/services/timetable_rebuild_service.dart';
import 'package:raillog/src/theme/app_theme.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';
import 'package:raillog/src/widgets/selection_actions_bar.dart';

/// 从设置进入的批量维护页。
///
/// 列表直接复用「全部行程」的多选界面（同一套车票卡片与响应式网格），这里只补
/// 批量重建需要的筛选条和底部动作栏。计划阶段不写库：先算出修改清单，用户在确认页
/// 逐条采纳后才落库。除按历史时刻表重建外，这里也承担两项数据清理：删除重复行程、
/// 更正算出不可能均速的里程。
class TimetableRebuildPage extends StatefulWidget {
  const TimetableRebuildPage({super.key, this.tripsLoader});

  /// 测试注入用：widget 测试里碰 sqflite 会静默挂死。
  final Future<List<TripRecord>> Function()? tripsLoader;

  @override
  State<TimetableRebuildPage> createState() => _TimetableRebuildPageState();
}

enum _RebuildFilter { all, missingArrival, brokenVia, duplicates, speedAnomaly }

/// 铁路旅行不可能超过这个均速；超过通常意味着里程或到点填错了。
const double _abnormalSpeedKmh = 360;

class _TimetableRebuildPageState extends State<TimetableRebuildPage> {
  bool _loading = true;
  String? _loadError;
  List<TripRecord> _trips = const [];
  Map<int, TripRecord> _tripsById = const {};

  _RebuildFilter _filter = _RebuildFilter.all;
  Set<int>? _undrawableIds;
  Set<int> _duplicateIds = const {};
  bool _filterLoading = false;

  String? _planningLabel;
  int _completed = 0;
  int _total = 0;
  bool _cancelRequested = false;
  bool _deleting = false;

  /// 每次要重置列表状态（筛选变化、应用完成）时递增，作为 AllTripsPage 的 key。
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    // 计划循环每处理一张票检查一次；页面没了就别再查接口了。
    _cancelRequested = true;
    super.dispose();
  }

  Future<void> _reload({bool resetList = false}) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final loader =
          widget.tripsLoader ?? () => DbHelper.instance.getAllTrips();
      final trips = (await loader())
          .where((trip) => trip.isRailTrip)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _tripsById = {for (final trip in trips) trip.id: trip};
        _duplicateIds = {
          for (final trip in TimetableRebuildService.findDuplicateCopies(trips))
            trip.id,
        };
        _undrawableIds = null;
        _loading = false;
        if (resetList) _revision++;
      });
      // 重建之后原来「经由损坏」的行程可能已经修好，筛选还在就重新判定一遍。
      if (_filter == _RebuildFilter.brokenVia) {
        await _loadUndrawable();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _loadUndrawable() async {
    if (_undrawableIds != null) return;
    setState(() => _filterLoading = true);
    try {
      final ids = await RouteService.findUndrawableTripIds(_trips);
      if (!mounted) return;
      setState(() {
        _undrawableIds = ids;
        _filterLoading = false;
        _revision++;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _filterLoading = false;
        _filter = _RebuildFilter.all;
        _revision++;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('读取线路数据库失败：$error')));
    }
  }

  void _selectFilter(_RebuildFilter filter) {
    if (filter == _filter) return;
    setState(() {
      _filter = filter;
      _revision++;
    });
    if (filter == _RebuildFilter.brokenVia) {
      _loadUndrawable();
    }
  }

  List<TripRecord> get _visibleTrips {
    switch (_filter) {
      case _RebuildFilter.all:
        return _trips;
      case _RebuildFilter.missingArrival:
        return _trips
            .where((trip) => trip.arrivalTime == null)
            .toList(growable: false);
      case _RebuildFilter.brokenVia:
        final ids = _undrawableIds;
        if (ids == null) return const [];
        return _trips
            .where((trip) => ids.contains(trip.id))
            .toList(growable: false);
      case _RebuildFilter.duplicates:
        return _trips
            .where((trip) => _duplicateIds.contains(trip.id))
            .toList(growable: false);
      case _RebuildFilter.speedAnomaly:
        return _speedAnomalyTrips();
    }
  }

  List<TripRecord> _speedAnomalyTrips() => _trips
      .where((trip) => (trip.averageSpeedKmh ?? 0) > _abnormalSpeedKmh)
      .toList(growable: false);

  Future<void> _startPlan(
    TimetableRebuildMode mode,
    TripsSelection selection,
  ) async {
    if (_planningLabel != null) return;
    final trips = <TripRecord>[
      for (final entry in selection.selectedTrips) ?_tripsById[entry.id],
    ];
    if (trips.isEmpty) return;

    setState(() {
      _cancelRequested = false;
      _completed = 0;
      _total = trips.length;
      _planningLabel = '正在查阅历史时刻表 0/${trips.length}';
    });
    selection.setBusyLabel(_planningLabel);

    TimetableRebuildPlan? plan;
    try {
      plan = await TimetableRebuildService.plan(
        trips: trips,
        mode: mode,
        onProgress: (completed, total) {
          if (!mounted) return;
          setState(() {
            _completed = completed;
            _total = total;
            _planningLabel = '正在查阅历史时刻表 $completed/$total';
          });
          selection.setBusyLabel(_planningLabel);
        },
        isCancelled: () => _cancelRequested,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('查询历史时刻表失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _planningLabel = null);
        selection.setBusyLabel(null);
      }
    }

    if (!mounted || plan == null) return;
    if (plan.proposals.isEmpty) {
      await _showEmptyPlan(plan);
      return;
    }

    final result = await Navigator.of(context)
        .push<TimetableRebuildApplyResult>(
          m3PageRoute(builder: (_) => TimetableRebuildReviewPage(plan: plan!)),
        );
    if (!mounted || result == null) return;

    await _reload(resetList: true);
    if (!mounted) return;
    final failed = result.failed > 0 ? '，${result.failed} 项写入失败' : '';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已应用 ${result.applied} 项修改$failed')));
  }

  Future<void> _showEmptyPlan(TimetableRebuildPlan plan) async {
    final target = switch (plan.mode) {
      TimetableRebuildMode.arrivalTime => '到点',
      TimetableRebuildMode.viaRoute => '经由线路',
      TimetableRebuildMode.mileage => '里程',
    };
    final issues = plan.issues;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(plan.cancelled ? '已停止' : '没有需要修改的$target'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '本次查询 ${plan.processed} 张车票：无需修改 ${plan.unchanged} 张，'
                '无法重建 ${issues.length} 张。',
              ),
              if (issues.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                for (final issue in issues.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Text('· ${issue.label}：${issue.reason}'),
                  ),
                if (issues.length > 8) Text('…等 ${issues.length} 张'),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _requestStop() {
    setState(() => _cancelRequested = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('历史时刻表重建')),
        body: Center(
          child: _loadError == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: AppSpacing.page,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('无法读取车票：$_loadError', textAlign: TextAlign.center),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton(
                        onPressed: () => _reload(),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }

    final visible = _visibleTrips;
    // 「全部」只用来浏览：没有筛选目标时不给多选和操作面板，避免对着几千张票
    // 误勾一堆；选定顶部某个筛选之后才开放批量处理。
    final filtered = _filter != _RebuildFilter.all;
    return AllTripsPage(
      key: ValueKey('timetable-rebuild:$_revision'),
      title: '历史时刻表重建',
      trips: [for (final trip in visible) DashboardTripEntry.fromTrip(trip)],
      showTripKindFilter: false,
      enableSelection: filtered,
      enableGrouping: false,
      // 不传的话点车票会进详情页（读库、改动后还会把本页一起弹掉）；
      // 这里的车票只用来看和选。
      openTrip: (context, trip) async {
        _showBatchHint(context, filtered: filtered);
        return null;
      },
      // 长按会尝试进入多选；「全部」下多选被禁用，也要给同一句提示。
      onSelectionBlocked: () => _showBatchHint(context, filtered: false),
      headerBuilder: _buildFilterHeader,
      selectionBarBuilder: filtered ? _buildSelectionBar : null,
    );
  }

  void _showBatchHint(BuildContext context, {required bool filtered}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            filtered ? '点右上角的「多选车票」勾选要处理的行程' : '先在顶部按条件筛选，再点右上角的「多选车票」批量处理',
          ),
        ),
      );
  }

  Widget _buildFilterHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final missingCount = _trips
        .where((trip) => trip.arrivalTime == null)
        .length;
    final brokenCount = _undrawableIds?.length;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '筛选',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant),
        ),
        ChoiceChip(
          label: Text('全部 ${_trips.length}'),
          selected: _filter == _RebuildFilter.all,
          onSelected: (_) => _selectFilter(_RebuildFilter.all),
        ),
        ChoiceChip(
          label: Text('缺到点 $missingCount'),
          tooltip: '到点为空的行程',
          selected: _filter == _RebuildFilter.missingArrival,
          onSelected: (_) => _selectFilter(_RebuildFilter.missingArrival),
        ),
        ChoiceChip(
          label: Text(
            brokenCount == null && _filterLoading
                ? '经由损坏…'
                : '经由损坏 ${brokenCount ?? ''}'.trim(),
          ),
          tooltip: '已存的经由线路在当前线路数据库里找不到对应区间，地图只能画成直线',
          selected: _filter == _RebuildFilter.brokenVia,
          onSelected: (_) => _selectFilter(_RebuildFilter.brokenVia),
        ),
        ChoiceChip(
          label: Text('重复行程 ${_duplicateIds.length}'),
          tooltip:
              '同一车次、同一天、同一区间出现多条时，每组只保留一条'
              '（优先云端副本，其次最早录入）；这里只列出多余的副本，可全选删除',
          selected: _filter == _RebuildFilter.duplicates,
          onSelected: (_) => _selectFilter(_RebuildFilter.duplicates),
        ),
        ChoiceChip(
          label: Text('均速异常 ${_speedAnomalyTrips().length}'),
          tooltip: '到点与里程算出的平均速度超过 360 km/h，通常是里程或到点填错了',
          selected: _filter == _RebuildFilter.speedAnomaly,
          onSelected: (_) => _selectFilter(_RebuildFilter.speedAnomaly),
        ),
        if (_filterLoading) ...[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          Text(
            '正在核对线路数据库',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _buildSelectionBar(BuildContext context, TripsSelection selection) {
    final busy = _planningLabel != null;
    final count = selection.selectedTrips.length;
    return BottomAppBar(
      // 与「全部行程」的多选动作栏同高、同样只留横向内边距，按钮高度才放得下。
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.contentMaxWidth,
          ),
          child: busy
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: _progressRow(context),
                )
              : _buildIdleAction(context, selection, count),
        ),
      ),
    );
  }

  /// 每个筛选只摆对应的那一个操作。
  Widget _buildIdleAction(
    BuildContext context,
    TripsSelection selection,
    int count,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final SelectionActionSpec? action = switch (_filter) {
      _RebuildFilter.missingArrival => SelectionActionSpec(
        icon: Icons.schedule_outlined,
        label: '重建到点',
        tooltip: '按历史时刻表重建所选行程的到点',
        onPressed: count == 0
            ? null
            : () => _startPlan(TimetableRebuildMode.arrivalTime, selection),
      ),
      _RebuildFilter.brokenVia => SelectionActionSpec(
        icon: Icons.alt_route_outlined,
        label: '重建经由',
        tooltip: '按历史时刻表重建所选行程的经由线路',
        onPressed: count == 0
            ? null
            : () => _startPlan(TimetableRebuildMode.viaRoute, selection),
      ),
      _RebuildFilter.speedAnomaly => SelectionActionSpec(
        icon: Icons.straighten_outlined,
        label: '更正里程',
        tooltip: '按历史时刻表更正所选行程的里程',
        onPressed: count == 0
            ? null
            : () => _startPlan(TimetableRebuildMode.mileage, selection),
      ),
      _RebuildFilter.duplicates => SelectionActionSpec(
        icon: Icons.delete_outline,
        label: '删除',
        tooltip: '删除所选行程',
        onPressed: count == 0 ? null : () => _deleteSelectedTrips(selection),
        color: scheme.error,
      ),
      // 「全部」不会进入多选，兜底保持空白。
      _RebuildFilter.all => null,
    };
    if (action == null) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 固定宽度：桌面上不会被拉成横贯整栏的长条，样式与「全部行程」的
        // 多选动作栏一致。
        SizedBox(width: 112, child: SelectionActionButton(action: action)),
      ],
    );
  }

  /// 删除前必须让用户看清会删掉哪些：这是本页唯一不可撤销的动作。
  Future<void> _deleteSelectedTrips(TripsSelection selection) async {
    if (_planningLabel != null) return;
    final trips = <TripRecord>[
      for (final entry in selection.selectedTrips) ?_tripsById[entry.id],
    ];
    if (trips.isEmpty) return;

    final duplicateCount = trips
        .where((trip) => _duplicateIds.contains(trip.id))
        .length;
    final duplicateHint = duplicateCount == 0
        ? ''
        : '其中 $duplicateCount 条是重复副本。';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text('删除 ${trips.length} 趟行程？'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('所选行程将被永久删除，此操作无法撤销。$duplicateHint'),
              const SizedBox(height: AppSpacing.md),
              for (final trip in trips.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text('· ${_tripSummary(trip)}'),
                ),
              if (trips.length > 6) Text('…等 ${trips.length} 条'),
            ],
          ),
        ),
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

    setState(() {
      _deleting = true;
      _cancelRequested = false;
      _completed = 0;
      _total = trips.length;
      _planningLabel = '正在删除 0/${trips.length}';
    });
    selection.setBusyLabel(_planningLabel);

    var deleted = 0;
    Object? failure;
    for (final trip in trips) {
      try {
        if (await DbHelper.instance.deleteTrip(trip.id) > 0) deleted++;
      } catch (error) {
        failure = error;
      }
      _completed++;
      // 删除不可中途停止：页面已经关掉也要把这一批删完，不能留下删一半的状态。
      if (!mounted) continue;
      setState(() => _planningLabel = '正在删除 $_completed/${trips.length}');
      selection.setBusyLabel(_planningLabel);
    }

    if (!mounted) return;
    setState(() {
      _deleting = false;
      _planningLabel = null;
    });
    selection.setBusyLabel(null);
    await _reload(resetList: true);
    if (!mounted) return;
    final suffix = failure == null ? '' : '，部分删除失败：$failure';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已删除 $deleted 趟行程$suffix')));
  }

  Widget _progressRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _cancelRequested
                    ? '正在停止…（$_completed / $_total）'
                    : _planningLabel ?? '正在查阅历史时刻表',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              LinearProgressIndicator(
                value: _total == 0 ? null : _completed / _total,
              ),
            ],
          ),
        ),
        // 删除逐条写库，中途停下只会留下删了一半的状态，所以不给停止。
        if (!_deleting) ...[
          const SizedBox(width: AppSpacing.md),
          TextButton.icon(
            onPressed: _cancelRequested ? null : _requestStop,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('停止'),
          ),
        ],
      ],
    );
  }

  static String _tripSummary(TripRecord trip) {
    final departure = trip.departureTime;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${trip.trainNumber} '
        '${departure.year}-${two(departure.month)}-${two(departure.day)} '
        '${two(departure.hour)}:${two(departure.minute)} '
        '${trip.fromStation}→${trip.toStation}';
  }
}
