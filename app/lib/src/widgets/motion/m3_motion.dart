import 'package:flutter/material.dart';

const m3MotionDuration = Duration(milliseconds: 300);
const m3MotionDurationShort = Duration(milliseconds: 200);

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
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: alignment,
          children: [...previousChildren, ?currentChild],
        );
      },
      transitionBuilder: (child, animation) {
        final fade = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.2, 1, curve: Curves.easeOutCubic),
          reverseCurve: const Interval(0, 0.8, curve: Curves.easeInCubic),
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
    this.duration = m3MotionDuration,
  });

  final Widget child;
  final double distance;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
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

Route<T> m3PageRoute<T>({required WidgetBuilder builder}) {
  return PageRouteBuilder<T>(
    transitionDuration: m3MotionDuration,
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
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
