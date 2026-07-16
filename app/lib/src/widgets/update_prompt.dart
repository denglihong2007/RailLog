import 'package:flutter/material.dart';
import 'package:raillog/src/services/update_service.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showUpdatePrompt(
  BuildContext context,
  UpdateCheckResult result,
) async {
  final shouldOpen = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.system_update_outlined),
      title: const Text('发现新版本'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RailLog ${result.latest.version} 已发布'),
          const SizedBox(height: 8),
          Text(
            '当前版本 ${result.currentVersion}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('稍后'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.open_in_new),
          label: const Text('前往下载'),
        ),
      ],
    ),
  );
  if (shouldOpen != true || !context.mounted) return;
  final uri = Uri.tryParse(result.latest.downloadPageUrl);
  final opened =
      uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法打开下载页面')));
  }
}
