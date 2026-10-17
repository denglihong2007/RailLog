import 'package:flutter/material.dart';

/// 多选状态下贴着底部的一条动作栏。
///
/// 四个动作要挤进 360dp 屏（BottomAppBar 左右各留 12，可分量 336）：
/// 均分后每个 84dp。带图标的 M3 TextButton 在 2 字标签下约 68dp，
/// 4 字标签（原来的「下载图片」「订购车票」）约 116dp——三个就已经贴着临界，
/// 所以标签一律压到 2 字，完整语义交给 [Tooltip]。
///
/// 再窄就整体退化成纯图标：图标有 [Tooltip] 兜着，缩到两个字也读不出来时
/// 就没必要硬留文字。
class SelectionActionsBar extends StatelessWidget {
  const SelectionActionsBar({
    super.key,
    required this.busy,
    required this.hasSelection,
    required this.canGenerate,
    required this.onDelete,
    required this.onDownload,
    required this.onExportJournal,
    required this.onOrder,
  });

  /// 有动作在跑：所有按钮置灰，避免并发。
  final bool busy;

  /// 至少选了一项。删除与导出手账只要求这个。
  final bool hasSelection;

  /// 选中的行程都有 ticketId。下载车票图片与订购车票要求这个——
  /// 未同步的本地行程没有 ticketId，但**手账不在此列**，
  /// 它正是为这些行程准备的。
  final bool canGenerate;

  final VoidCallback onDelete;
  final VoidCallback onDownload;
  final VoidCallback onExportJournal;
  final VoidCallback onOrder;

  /// 标签能放下就带文字的分界宽度。低于它退化成纯图标。
  static const double _labelledMinWidth = 76;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = <_SelectionActionSpec>[
            _SelectionActionSpec(
              icon: Icons.delete_outline,
              label: '删除',
              tooltip: '删除所选行程',
              onPressed: busy || !hasSelection ? null : onDelete,
              color: Theme.of(context).colorScheme.error,
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

class _LabelledAction extends StatelessWidget {
  const _LabelledAction({required this.action});

  final _SelectionActionSpec action;

  @override
  Widget build(BuildContext context) {
    final enabled = action.onPressed != null;
    final color = enabled ? action.color : null;
    return Tooltip(
      message: action.tooltip,
      child: TextButton.icon(
        onPressed: action.onPressed,
        // 不压内边距的话 M3 默认会在两侧各吃掉 16dp，文字就被挤成省略号了。
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: const Size(0, 48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(action.icon, color: color),
        label: Text(
          action.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: color == null ? null : TextStyle(color: color),
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
