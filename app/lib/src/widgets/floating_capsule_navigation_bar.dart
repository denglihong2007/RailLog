import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:material_ui/material_ui.dart';
import 'package:raillog/src/theme/app_theme.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

/// 紧凑布局下的底部导航：悬浮的磨砂胶囊，选中项把图标和文字并排展开。
///
/// `NavigationBar` 的图标/标签是写死的上下结构，没有自定义 destination
/// 布局的接口，所以条目布局由这里排；外壳的投影、形状裁剪、水波纹、工具
/// 提示与 Tab 语义仍用框架组件，不引第三方包。
///
/// 需要页面内容从胶囊后面滚过，使用方要把 [Scaffold.extendBody] 设为 true。
class FloatingCapsuleNavigationBar extends StatelessWidget {
  const FloatingCapsuleNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.maxWidth = 520,
    this.blurSigma = 20,
    this.opacity = 0.72,
  });

  static const double itemMinWidth = 60;
  static const double itemMinHeight = 44;
  static const double iconSize = 24;

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;
  final double maxWidth;
  final double blurSigma;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 与 NavigationBar 内部一致：底栏文字放大封顶，避免窄屏把胶囊撑破。
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Material(
              // Material 自带 shape 裁剪与 elevation 投影；底色在下、
              // 模糊在上，半透明底色与模糊叠加后仍是「磨砂」效果。
              color: colorScheme.surfaceContainerHigh.withValues(
                alpha: opacity,
              ),
              elevation: 3,
              shadowColor: colorScheme.shadow.withValues(alpha: 0.24),
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                // 内层透明 Material 让水波纹画在模糊层之上，而不是被一起糊掉。
                child: Material(
                  type: MaterialType.transparency,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (
                          var index = 0;
                          index < destinations.length;
                          index++
                        )
                          _CapsuleDestination(
                            destination: destinations[index],
                            selected: index == selectedIndex,
                            onTap: () => onDestinationSelected(index),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CapsuleDestination extends StatelessWidget {
  const _CapsuleDestination({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  /// 展开/收起的缓动。对称曲线让宽度变化有可感的起步和收尾。
  static const _expandCurve = Curves.easeInOutCubicEmphasized;

  static const _collapsedPadding =
      (FloatingCapsuleNavigationBar.itemMinWidth -
          FloatingCapsuleNavigationBar.iconSize) /
      2;

  final NavigationDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final icon = selected
        ? (destination.selectedIcon ?? destination.icon)
        : destination.icon;
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      label: destination.label,
      button: true,
      selected: selected,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: destination.label,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          // 宽度、底色、图标颜色与文字显隐全部挂在同一个展开系数上。拆成
          // 几个隐式动画时（AnimatedContainer 的 padding + AnimatedSize 的
          // 文字宽度），切换的第一帧会各自跳到新值，胶囊先缩一下再补回来。
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: selected ? 1 : 0,
              end: selected ? 1 : 0,
            ),
            duration: reduceMotion ? Duration.zero : m3MotionDuration,
            curve: _expandCurve,
            builder: (context, expanded, _) {
              return Container(
                constraints: const BoxConstraints(
                  minWidth: FloatingCapsuleNavigationBar.itemMinWidth,
                  minHeight: FloatingCapsuleNavigationBar.itemMinHeight,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: lerpDouble(
                    // 收起态的内边距要让「图标 + 两侧留白」正好等于
                    // itemMinWidth：否则最小宽度会吃掉展开初期的一截宽度，
                    // 一收一放加起来不再守恒，整条胶囊中途会先缩一下。
                    _collapsedPadding,
                    AppSpacing.lg,
                    expanded,
                  )!,
                ),
                decoration: BoxDecoration(
                  color: Color.lerp(
                    colorScheme.secondaryContainer.withValues(alpha: 0),
                    colorScheme.secondaryContainer,
                    expanded,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconTheme.merge(
                      data: IconThemeData(
                        color: Color.lerp(
                          colorScheme.onSurfaceVariant,
                          colorScheme.onSecondaryContainer,
                          expanded,
                        ),
                        size: FloatingCapsuleNavigationBar.iconSize,
                      ),
                      child: icon,
                    ),
                    ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        // 只按系数裁宽度，文字始终按自然宽度排版：展开途中
                        // 不会被挤压重新断行，也不会突然补上省略号。
                        widthFactor: expanded,
                        heightFactor: 1,
                        child: expanded == 0
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(
                                  left: AppSpacing.xs,
                                ),
                                child: Opacity(
                                  opacity: expanded,
                                  child: Text(
                                    destination.label,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: labelStyle?.copyWith(
                                      color: colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
