import 'package:flutter/material.dart';

const m3MotionDuration = Duration(milliseconds: 300);
const m3MotionDurationShort = Duration(milliseconds: 200);

/// 列表/网格入场时，相邻两项之间的错开步长。
const m3RevealStaggerStep = Duration(milliseconds: 40);

/// stagger 的索引封顶。超过它的项与它同时开始，
/// 以免长列表把最后一项的入场推得过晚。
const m3RevealStaggerMaxIndex = 8;

/// 返回列表中第 [index] 项应当使用的错开延迟。
Duration m3RevealDelay(int index) {
  final capped = index.clamp(0, m3RevealStaggerMaxIndex);
  return m3RevealStaggerStep * capped;
}

class M3FadeThroughSwitcher extends StatelessWidget {
  const M3FadeThroughSwitcher({
    super.key,
    required this.child,
    this.duration = m3MotionDuration,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final Duration duration;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Easing.emphasizedDecelerate,
      switchOutCurve: Easing.emphasizedAccelerate,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: alignment,
          children: [...previousChildren, ?currentChild],
        );
      },
      transitionBuilder: (child, animation) {
        final fade = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.2, 1, curve: Easing.standardDecelerate),
          reverseCurve: const Interval(
            0,
            0.8,
            curve: Easing.standardAccelerate,
          ),
        );
        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(fade),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class M3Reveal extends StatelessWidget {
  const M3Reveal({
    super.key,
    required this.child,
    this.distance = 12,
    this.duration = m3MotionDurationShort,
    this.delay = Duration.zero,
  });

  final Widget child;
  final double distance;
  final Duration duration;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) return child;
    final total = delay + duration;
    final delayFraction = total.inMicroseconds == 0
        ? 0.0
        : delay.inMicroseconds / total.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(delayFraction, 1, curve: Easing.standardDecelerate),
      child: child,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, distance * (1 - value)),
            child: child,
          ),
        );
      },
    );
  }
}

Route<T> m3PageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: m3MotionDuration,
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Easing.emphasizedDecelerate,
        reverseCurve: Easing.emphasizedAccelerate,
      );
      return FadeTransition(
        opacity: curvedAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}

class M3AnimatedVisibility extends StatelessWidget {
  const M3AnimatedVisibility({
    super.key,
    required this.visible,
    required this.child,
    this.alignment = Alignment.topCenter,
    this.duration = m3MotionDurationShort,
  });

  final bool visible;
  final Widget child;
  final AlignmentGeometry alignment;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) {
      return visible ? child : const SizedBox.shrink();
    }
    return AnimatedSize(
      duration: duration,
      curve: Easing.standard,
      alignment: alignment,
      child: M3FadeThroughSwitcher(
        duration: duration,
        alignment: alignment,
        child: visible
            ? KeyedSubtree(key: const ValueKey(true), child: child)
            : const SizedBox.shrink(key: ValueKey(false)),
      ),
    );
  }
}
