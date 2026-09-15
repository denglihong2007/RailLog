import 'package:flutter/material.dart';
import 'package:raillog/src/theme/app_theme.dart';

export 'package:raillog/src/theme/app_theme.dart'
    show AppLayout, AppRadius, AppSpacing;

enum AppCardVariant { filled, outlined }

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.variant = AppCardVariant.filled,
    this.title,
    this.icon,
    this.leading,
    this.trailing,
    this.padding = AppSpacing.card,
    this.headerPadding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.md,
    ),
    this.margin = EdgeInsets.zero,
    this.color,
    this.borderColor,
    this.borderWidth = 1,
    this.onTap,
    this.onLongPress,
  });

  const AppCard.filled({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.leading,
    this.trailing,
    this.padding = AppSpacing.card,
    this.headerPadding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.md,
    ),
    this.margin = EdgeInsets.zero,
    this.color,
    this.onTap,
    this.onLongPress,
  }) : variant = AppCardVariant.filled,
       borderColor = null,
       borderWidth = 0;

  const AppCard.outlined({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.leading,
    this.trailing,
    this.padding = AppSpacing.card,
    this.headerPadding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.md,
    ),
    this.margin = EdgeInsets.zero,
    this.color,
    this.borderColor,
    this.borderWidth = 1,
    this.onTap,
    this.onLongPress,
  }) : variant = AppCardVariant.outlined;

  final Widget child;
  final AppCardVariant variant;
  final String? title;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry headerPadding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final Color? borderColor;
  final double borderWidth;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final effectiveColor =
        color ??
        (variant == AppCardVariant.filled
            ? colors.surfaceContainerLow
            : colors.surface);
    final side = variant == AppCardVariant.outlined
        ? BorderSide(
            color: borderColor ?? colors.outlineVariant,
            width: borderWidth,
          )
        : BorderSide.none;
    final hasHeader = title != null || leading != null || trailing != null;
    final resolvedPadding = padding.resolve(Directionality.of(context));
    final resolvedHeaderPadding = headerPadding.resolve(
      Directionality.of(context),
    );
    final Widget body;
    if (hasHeader) {
      final contentPadding = EdgeInsets.fromLTRB(
        resolvedPadding.left,
        0,
        resolvedPadding.right,
        resolvedPadding.bottom,
      );
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: resolvedHeaderPadding,
            child: Row(
              children: [
                if (leading != null)
                  leading!
                else if (icon != null)
                  Icon(icon, size: 20, color: colors.primary),
                if (leading != null || icon != null)
                  const SizedBox(width: AppSpacing.sm),
                if (title != null)
                  Expanded(
                    child: Text(title!, style: theme.textTheme.titleMedium),
                  )
                else
                  const Spacer(),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  trailing!,
                ],
              ],
            ),
          ),
          Padding(padding: contentPadding, child: child),
        ],
      );
    } else {
      body = Padding(padding: resolvedPadding, child: child);
    }

    return Card(
      margin: margin,
      color: effectiveColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: side,
      ),
      child: onTap == null && onLongPress == null
          ? body
          : InkWell(onTap: onTap, onLongPress: onLongPress, child: body),
    );
  }
}
