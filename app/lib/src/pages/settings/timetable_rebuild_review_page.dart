import 'package:flutter/material.dart';
import 'package:raillog/src/models/via_route_segment.dart';
import 'package:raillog/src/services/timetable_rebuild_service.dart';
import 'package:raillog/src/theme/app_theme.dart';

/// 批量重建的确认页。
///
/// 计划阶段只算出新旧值，不写库；这里逐条摆出差异，用户点「采纳」的才会在底部
/// 一键写入。默认全部未决定，避免「没看清就整批提交」。
class TimetableRebuildReviewPage extends StatefulWidget {
  const TimetableRebuildReviewPage({super.key, required this.plan});

  final TimetableRebuildPlan plan;

  @override
  State<TimetableRebuildReviewPage> createState() =>
      _TimetableRebuildReviewPageState();
}

class _TimetableRebuildReviewPageState
    extends State<TimetableRebuildReviewPage> {
  /// 车票 id → 是否采纳；没有条目表示还没决定。
  final Map<int, bool> _decisions = {};

  bool _applying = false;
  int _written = 0;

  List<TimetableRebuildProposal> get _accepted => [
    for (final proposal in widget.plan.proposals)
      if (_decisions[proposal.trip.id] == true) proposal,
  ];

  void _decide(int tripId, bool? decision) {
    if (_applying) return;
    setState(() {
      if (decision == null) {
        _decisions.remove(tripId);
      } else {
        _decisions[tripId] = decision;
      }
    });
  }

  void _decideAll(bool decision) {
    if (_applying) return;
    setState(() {
      for (final proposal in widget.plan.proposals) {
        _decisions[proposal.trip.id] = decision;
      }
    });
  }

  Future<void> _apply() async {
    final accepted = _accepted;
    if (accepted.isEmpty || _applying) return;
    setState(() {
      _applying = true;
      _written = 0;
    });
    try {
      final result = await TimetableRebuildService.apply(
        accepted,
        onProgress: (completed, total) {
          if (!mounted) return;
          setState(() => _written = completed);
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _applying = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('写入失败：$error')));
    }
  }

  Future<void> _showIssues() async {
    final issues = widget.plan.issues;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${issues.length} 张车票无法重建'),
        content: SizedBox(
          width: 480,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: issues.length,
            separatorBuilder: (_, _) => const Divider(height: AppSpacing.lg),
            itemBuilder: (context, index) {
              final issue = issues[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(issue.label),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    issue.reason,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            },
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

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return PopScope(
      canPop: !_applying,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('确认修改'),
          actions: [
            IconButton(
              tooltip: '全部采纳',
              onPressed: _applying ? null : () => _decideAll(true),
              icon: const Icon(Icons.done_all),
            ),
            IconButton(
              tooltip: '全部拒绝',
              onPressed: _applying ? null : () => _decideAll(false),
              icon: const Icon(Icons.remove_done),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
        bottomNavigationBar: _buildApplyBar(context),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppLayout.wideContentMaxWidth,
              ),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                itemCount: plan.proposals.length + 1,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) {
                  if (index == 0) return _buildSummary(context);
                  final proposal = plan.proposals[index - 1];
                  return _ProposalCard(
                    key: ValueKey(proposal.trip.id),
                    proposal: proposal,
                    decision: _decisions[proposal.trip.id],
                    enabled: !_applying,
                    onDecide: (decision) => _decide(proposal.trip.id, decision),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final plan = widget.plan;
    final unchanged = plan.unchanged > 0
        ? '另有 ${plan.unchanged} 张票算出的结果与原值一致，未列出。'
        : '';
    final skipped = plan.issues.isEmpty ? '' : '${plan.issues.length} 张票无法重建。';
    final stopped = plan.cancelled ? '查询已中途停止，下面是停止前算出的部分。' : '';
    return Container(
      padding: AppSpacing.card,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.fact_check_outlined, color: scheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '共 ${plan.proposals.length} 条修改待确认',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '默认都不写入。逐条点「采纳」后，再点底部的按钮保存。'
                  '$stopped$unchanged$skipped',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (plan.issues.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: _applying ? null : _showIssues,
              child: const Text('查看原因'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildApplyBar(BuildContext context) {
    final theme = Theme.of(context);
    final accepted = _accepted.length;
    final total = widget.plan.proposals.length;
    return BottomAppBar(
      height: 76,
      padding: EdgeInsets.zero,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.contentMaxWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: _applying
                ? Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '正在写入 $_written/$accepted',
                              style: theme.textTheme.labelLarge,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            LinearProgressIndicator(
                              value: accepted == 0 ? null : _written / accepted,
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          '已采纳 $accepted / $total',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      FilledButton.icon(
                        onPressed: accepted == 0 ? null : _apply,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          accepted == 0 ? '应用修改' : '应用 $accepted 项修改',
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    super.key,
    required this.proposal,
    required this.decision,
    required this.enabled,
    required this.onDecide,
  });

  final TimetableRebuildProposal proposal;

  /// null = 还没决定。
  final bool? decision;
  final bool enabled;
  final ValueChanged<bool?> onDecide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rejected = decision == false;
    final trip = proposal.trip;
    return Opacity(
      opacity: rejected ? 0.6 : 1,
      child: Container(
        padding: AppSpacing.card,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: decision == true ? scheme.primary : scheme.outlineVariant,
            width: decision == true ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.train_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${trip.trainNumber}  ${trip.fromStation} → ${trip.toStation}',
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  trip.ticketLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${_formatDateTime(trip.departureTime)} 出发',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (proposal.mode == TimetableRebuildMode.arrivalTime)
              _buildArrivalDiff(context)
            else
              _buildViaDiff(context),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.check, size: 18),
                    label: Text('采纳'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.close, size: 18),
                    label: Text('拒绝'),
                  ),
                ],
                selected: decision == null ? const {} : {decision!},
                onSelectionChanged: enabled
                    ? (selection) =>
                          onDecide(selection.isEmpty ? null : selection.first)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArrivalDiff(BuildContext context) {
    final arrowColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Expanded(
          child: _ValueBlock(
            label: '原到点',
            value: proposal.previousArrivalTime == null
                ? '未填写'
                : _formatDateTime(proposal.previousArrivalTime!),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Icon(Icons.arrow_forward, size: 18, color: arrowColor),
        ),
        Expanded(
          child: _ValueBlock(
            label: '新到点',
            value: _formatDateTime(proposal.arrivalTime!),
            highlight: true,
          ),
        ),
      ],
    );
  }

  Widget _buildViaDiff(BuildContext context) {
    return Column(
      children: [
        _SegmentsBlock(
          label: '原经由',
          segments: proposal.previousViaRouteSegments,
        ),
        const SizedBox(height: AppSpacing.sm),
        _SegmentsBlock(
          label: '新经由',
          segments: proposal.viaRouteSegments,
          highlight: true,
        ),
      ],
    );
  }
}

class _ValueBlock extends StatelessWidget {
  const _ValueBlock({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              color: highlight ? scheme.primary : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentsBlock extends StatelessWidget {
  const _SegmentsBlock({
    required this.label,
    required this.segments,
    this.highlight = false,
  });

  final String label;
  final List<ViaRouteSegment> segments;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textColor = highlight ? scheme.primary : scheme.onSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                segments.isEmpty ? '无' : '${segments.length} 段',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (segments.isEmpty)
            Text(
              '尚未填写',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            // 经由要完整摆出来：只列前几段的话，用户没法确认后面到底改成了什么。
            for (final segment in segments)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Text(
                  _segmentLine(segment),
                  style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
                ),
              ),
        ],
      ),
    );
  }

  static String _segmentLine(ViaRouteSegment segment) {
    final mileage = segment.mileageKm > 0
        ? '（${segment.mileageKm.toStringAsFixed(1)} km）'
        : '';
    return '${segment.routeName} · ${segment.fromStation} → '
        '${segment.toStation}$mileage';
  }
}

String _formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
