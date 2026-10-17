import 'package:flutter/material.dart';

/// 多选状态下贴着底部的一条动作栏。
///
/// 多选期间的操作都集中在这里（分组、下载、手账、订票、删除）：
/// 图标在上、两字标签在下，单个动作只占标签宽度，360dp 屏分出 5 份也很宽裕；
/// 「删除」放在最右并用错误色，与其他动作拉开距离。
///
/// 屏宽窄到每个动作不足 [_labelledMinWidth] 时退化成纯图标，
/// 完整语义交给 [Tooltip]。
class SelectionActionsBar extends StatelessWidget {
  const SelectionActionsBar({
    super.key,
    required this.busy,
    required this.hasSelection,
    required this.canGenerate,
    required this.onGroup,
    required this.onDelete,
    required this.onDownload,
    required this.onExportJournal,
    required this.onOrder,
  });

  /// 有动作在跑：所有按钮置灰，避免并发。
  final bool busy;

  /// 至少选了一项。删除、分组与导出手账只要求这个。
  final bool hasSelection;

  /// 选中的行程都有 ticketId。下载车票图片与订购车票要求这个——
  /// 未同步的本地行程没有 ticketId，但**手账不在此列**，
  /// 它正是为这些行程准备的。
  final bool canGenerate;

  final VoidCallback onGroup;
  final VoidCallback onDelete;
  final VoidCallback onDownload;
  final VoidCallback onExportJournal;
  final VoidCallback onOrder;

  /// 标签能放下就带文字的分界宽度。低于它退化成纯图标。
  static const double _labelledMinWidth = 52;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = <_SelectionActionSpec>[
            _SelectionActionSpec(
              icon: Icons.workspaces_outline,
              label: '分组',
              tooltip: '设置分组',
              onPressed: busy || !hasSelection ? null : onGroup,
            ),
            _SelectionActionSpec(
              icon: Icons.download_outlined,
              label: '下载',
              tooltip: '下载车票图片',
              onPressed: busy || !canGenerate ? null : onDownload,
            ),
            _SelectionActionSpec(
              icon: Icons.menu_book_outlined,
              label: '手账',
              tooltip: '导出手账 PDF',
              onPressed: busy || !hasSelection ? null : onExportJournal,
            ),
            _SelectionActionSpec(
              icon: Icons.shopping_bag_outlined,
              label: '订票',
              tooltip: '订购车票',
              onPressed: busy || !canGenerate ? null : onOrder,
            ),
            _SelectionActionSpec(
              icon: Icons.delete_outline,
              label: '删除',
              tooltip: '删除所选行程',
              onPressed: busy || !hasSelection ? null : onDelete,
              color: Theme.of(context).colorScheme.error,
            ),
          ];

          final perAction = constraints.maxWidth / actions.length;
          final labelled = perAction >= _labelledMinWidth;
          return Row(
            children: [
              for (final action in actions)
                Expanded(
                  child: labelled
                      ? _LabelledAction(action: action)
                      : _IconAction(action: action),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SelectionActionSpec {
  const _SelectionActionSpec({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
}

/// 图标在上、标签在下，单个动作的宽度只要放得下两字标签。
class _LabelledAction extends StatelessWidget {
  const _LabelledAction({required this.action});

  final _SelectionActionSpec action;

  @override
  Widget build(BuildContext context) {
    final enabled = action.onPressed != null;
    final color = enabled ? action.color : null;
    return Tooltip(
      message: action.tooltip,
      child: TextButton(
        onPressed: action.onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          minimumSize: const Size(0, 56),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(action.icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.action});

  final _SelectionActionSpec action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: IconButton(
        tooltip: action.tooltip,
        onPressed: action.onPressed,
        icon: Icon(action.icon),
        color: action.color,
      ),
    );
  }
}
