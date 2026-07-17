import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateMarkdown extends StatelessWidget {
  const UpdateMarkdown({super.key, required this.data, this.compact = false});

  final String data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MarkdownBody(
      data: data,
      selectable: true,
      shrinkWrap: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: (compact ? theme.textTheme.bodyMedium : theme.textTheme.bodyLarge)
            ?.copyWith(height: 1.6),
        h1: compact
            ? theme.textTheme.titleLarge
            : theme.textTheme.headlineSmall,
        h2: compact ? theme.textTheme.titleMedium : theme.textTheme.titleLarge,
        h3: theme.textTheme.titleMedium,
        blockSpacing: compact ? 8 : 12,
      ),
      onTapLink: (_, href, _) {
        if (href != null) _openLink(context, href);
      },
    );
  }

  Future<void> _openLink(BuildContext context, String value) async {
    final uri = Uri.tryParse(value.trim());
    final opened =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开日志链接')));
    }
  }
}
