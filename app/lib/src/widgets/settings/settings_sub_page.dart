import 'package:flutter/material.dart';
import 'package:raillog/src/widgets/app_card.dart';

/// 设置子页面的统一骨架：AppBar + 居中限宽的可滚动正文。
///
/// 背景色交给主题的 scaffoldBackgroundColor，不再逐页覆写。
class SettingsSubPage extends StatelessWidget {
  const SettingsSubPage({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.maxWidth = AppLayout.contentMaxWidth,
  });

  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: ListView(
      padding: AppSpacing.page,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    ),
  );
}
