import 'package:flutter/material.dart';
import 'package:raillog/src/widgets/app_card.dart';
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
    return M3Reveal(
      child: AppCard.filled(
        title: title,
        icon: icon,
        trailing: trailing,
        child: child,
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
    this.maxWidth = AppLayout.formMaxWidth,
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
