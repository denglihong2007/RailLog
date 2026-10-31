import 'package:flutter/material.dart';
import 'package:raillog/src/models/ticket_12306_order.dart';
import 'package:raillog/src/widgets/app_card.dart';

/// 三个导入页共用的步骤标题：圆形图标 + 「步骤 N」 + 标题 + 右侧操作。
class TicketImportStepHeader extends StatelessWidget {
  const TicketImportStepHeader({
    super.key,
    required this.icon,
    required this.title,
    this.step,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final int? step;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox.square(
          dimension: 40,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: colors.onSecondaryContainer, size: 21),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (step != null)
                Text(
                  '步骤 $step',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: colors.primary),
                ),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// 三个导入页共用的空状态：图标 + 标题 + 说明 + 可选操作。
class TicketImportEmptyState extends StatelessWidget {
  const TicketImportEmptyState({
    super.key,
    required this.title,
    required this.hint,
    this.icon = Icons.confirmation_number_outlined,
    this.actionLabel,
    this.actionIcon = Icons.refresh,
    this.onAction,
  });

  final String title;
  final String hint;
  final IconData icon;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(icon, size: 48, color: colors.outline),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: Icon(actionIcon),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// 12306 / 邮箱 / 电子发票三个导入页共用的车票勾选卡片。
class TicketOrderSelectionTile extends StatelessWidget {
  const TicketOrderSelectionTile({
    super.key,
    required this.order,
    required this.selected,
    required this.imported,
    required this.enabled,
    required this.onChanged,
    this.hideStatusWhenImportable = false,
  });

  final Ticket12306Order order;
  final bool selected;
  final bool imported;
  final bool enabled;
  final ValueChanged<bool?>? onChanged;

  /// 「邮件导入」「电子发票」这类来源说明不必每张卡片都重复，
  /// 只显示退票、改签、红字发票等异常状态。
  final bool hideStatusWhenImportable;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = imported
        ? '已导入'
        : hideStatusWhenImportable && order.canImport
        ? ''
        : order.statusText;
    final canToggle = enabled && !imported && onChanged != null;
    return AppCard.filled(
      color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
      padding: EdgeInsets.zero,
      onTap: canToggle ? () => onChanged!(!selected) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: selected, onChanged: canToggle ? onChanged : null),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        order.trainCode,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${order.fromStation} → ${order.toStation}',
                          style: Theme.of(context).textTheme.bodyLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      _TicketOrderFact(
                        icon: Icons.schedule,
                        label: _formatDateTime(order.startTime),
                      ),
                      if (order.passengerName.isNotEmpty)
                        _TicketOrderFact(
                          icon: Icons.person_outline,
                          label: order.passengerName,
                        ),
                      if (order.seatDisplay.isNotEmpty)
                        _TicketOrderFact(
                          icon: Icons.event_seat_outlined,
                          label: order.seatDisplay,
                        ),
                      if (order.price > 0)
                        _TicketOrderFact(
                          icon: Icons.payments_outlined,
                          label: '¥${_formatNumber(order.price)}',
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (status.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                status,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: order.canImport ? colors.primary : colors.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 全选行：与 [TicketOrderSelectionTile] 配套使用。
class TicketOrderSelectionToolbar extends StatelessWidget {
  const TicketOrderSelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.selectableCount,
    required this.allSelected,
    required this.enabled,
    required this.onToggleAll,
  });

  final int selectedCount;
  final int selectableCount;
  final bool allSelected;
  final bool enabled;
  final ValueChanged<bool?> onToggleAll;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Checkbox(
          value: allSelected,
          tristate: selectedCount > 0 && !allSelected,
          onChanged: enabled ? onToggleAll : null,
        ),
        TextButton(
          onPressed: enabled ? () => onToggleAll(!allSelected) : null,
          child: const Text('全选'),
        ),
        const Spacer(),
        Text(
          '已选择 $selectedCount / $selectableCount',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 底部「开始确认」操作栏。
class TicketImportActionBar extends StatelessWidget {
  const TicketImportActionBar({
    super.key,
    required this.selectedCount,
    required this.preparingPosition,
    required this.isImporting,
    required this.onStart,
    required this.horizontalPadding,
  });

  final int selectedCount;
  final int? preparingPosition;
  final bool isImporting;
  final VoidCallback onStart;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      child: SafeArea(
        minimum: EdgeInsets.fromLTRB(
          horizontalPadding,
          12,
          horizontalPadding,
          12,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preparingPosition == null
                        ? '逐条确认后写入'
                        : '正在准备第 $preparingPosition/$selectedCount 条',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    '共 $selectedCount 条待确认',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: isImporting ? null : onStart,
              icon: isImporting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward),
              label: const Text('开始确认'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 导入页顶部的结果/错误提示条。
class TicketImportMessageBanner extends StatelessWidget {
  const TicketImportMessageBanner({
    super.key,
    required this.message,
    required this.isError,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: isError ? colors.errorContainer : colors.secondaryContainer,
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              color: isError
                  ? colors.onErrorContainer
                  : colors.onSecondaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isError
                      ? colors.onErrorContainer
                      : colors.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketOrderFact extends StatelessWidget {
  const _TicketOrderFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}

String _formatDateTime(DateTime value) =>
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _formatNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);
