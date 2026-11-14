import 'package:flutter/material.dart';
import 'package:raillog/src/widgets/app_card.dart';

/// 排行榜通用行：名次、头像、标题/副标题与右侧数值。
///
/// [rank] 为空时不画名次，只保留排行榜的版式。
class LeaderboardRow extends StatelessWidget {
  const LeaderboardRow({
    super.key,
    required this.title,
    this.rank,
    this.avatar,
    this.subtitle,
    this.value,
    this.valueDetail,
    this.onTap,
    this.color,
  });

  final int? rank;
  final Widget? avatar;
  final String title;
  final String? subtitle;
  final String? value;

  /// 数值下方的补充说明（要素排行榜用来看平均评分）。
  final String? valueDetail;
  final VoidCallback? onTap;

  /// 覆盖默认的行底色（实体详情页用它标出严格匹配的行程）。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rank = this.rank;
    final emphasized = rank != null && rank <= 3;
    final rankColors = rank == null ? null : _rankColors(context, rank);
    // 四位以上位次放不进圆标，统一显示为省略号。
    final rankLabel = rank == null ? null : (rank > 999 ? '...' : '$rank');
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          if (rankColors != null) ...[
            CircleAvatar(
              radius: 17,
              backgroundColor: emphasized
                  ? rankColors.$1
                  : colors.surfaceContainerHighest,
              foregroundColor: emphasized
                  ? rankColors.$2
                  : colors.onSurfaceVariant,
              child: Text(
                rankLabel!,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (avatar != null) ...[
            avatar!,
            const SizedBox(width: 12),
          ] else if (rankColors != null)
            const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 12),
            _LeaderboardValue(
              value: value!,
              detail: valueDetail,
              emphasized: emphasized,
            ),
          ],
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 20, color: colors.onSurfaceVariant),
          ],
        ],
      ),
    );
    return AppCard(
      variant: emphasized ? AppCardVariant.outlined : AppCardVariant.filled,
      color: color ?? colors.surfaceContainerLow,
      borderColor: emphasized ? rankColors!.$3 : null,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: content,
    );
  }
}

class _LeaderboardValue extends StatelessWidget {
  const _LeaderboardValue({
    required this.value,
    required this.detail,
    required this.emphasized,
  });

  final String value;
  final String? detail;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final valueText = Text(
      value,
      style: textTheme.titleSmall?.copyWith(
        color: emphasized ? colors.onSurface : colors.primary,
        fontWeight: FontWeight.w700,
      ),
    );
    final secondary = detail;
    if (secondary == null) return valueText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        valueText,
        const SizedBox(height: 2),
        Text(
          secondary,
          style: textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

(Color, Color, Color) _rankColors(BuildContext context, int rank) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch ((dark, rank)) {
    (true, 1) => (
      const Color(0xFF5B4712),
      const Color(0xFFFFE08A),
      const Color(0xFFB89232),
    ),
    (true, 2) => (
      const Color(0xFF45484C),
      const Color(0xFFE3E5E8),
      const Color(0xFF8D939A),
    ),
    (true, 3) => (
      const Color(0xFF563727),
      const Color(0xFFF6C0A0),
      const Color(0xFFB77A56),
    ),
    (false, 1) => (
      const Color(0xFFFFE8A3),
      const Color(0xFF4C3900),
      const Color(0xFFC49A24),
    ),
    (false, 2) => (
      const Color(0xFFE4E7EB),
      const Color(0xFF30343A),
      const Color(0xFF9298A0),
    ),
    (false, 3) => (
      const Color(0xFFF4D0BB),
      const Color(0xFF4E2C1B),
      const Color(0xFFB97954),
    ),
    _ => (
      Theme.of(context).colorScheme.surfaceContainerHighest,
      Theme.of(context).colorScheme.onSurfaceVariant,
      Colors.transparent,
    ),
  };
}
