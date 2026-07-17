import 'package:flutter/material.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return M3Reveal(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: colors.primary),
                  const SizedBox(width: 8),
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (trailing != null) ...[const Spacer(), trailing!],
                ],
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class ResponsiveFieldWrap extends StatelessWidget {
  const ResponsiveFieldWrap({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final width = constraints.maxWidth >= 620
            ? (constraints.maxWidth - gap) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class FormPageScrollView extends StatelessWidget {
  const FormPageScrollView({
    super.key,
    required this.children,
    required this.padding,
    this.maxWidth = 840,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: padding,
          sliver: SliverList.builder(
            itemCount: children.length,
            itemBuilder: (context, index) => _KeepAliveFormSection(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: SizedBox(
                    width: double.infinity,
                    child: children[index],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _KeepAliveFormSection extends StatefulWidget {
  const _KeepAliveFormSection({required this.child});

  final Widget child;

  @override
  State<_KeepAliveFormSection> createState() => _KeepAliveFormSectionState();
}

class _KeepAliveFormSectionState extends State<_KeepAliveFormSection>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
