import 'package:flutter/material.dart';
import 'package:raillog/src/services/update_service.dart';
import 'package:raillog/src/widgets/update_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showUpdatePrompt(
  BuildContext context,
  UpdateCheckResult result,
) async {
  final selectedUrl = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.system_update_outlined),
      title: const Text('发现新版本'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('RailLog ${result.latest.version} 已发布'),
              const SizedBox(height: 4),
              Text(
                '发布于 ${formatUpdateDate(result.latest.publishedAt)}'
                ' · 当前版本 ${result.currentVersion}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text('更新日志', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              UpdateMarkdown(
                data: updateNotes(result.latest.releaseNotes),
                compact: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('稍后'),
        ),
        if (UpdateService.githubUrlForCurrentPlatform(result.latest)
            case final githubUrl?)
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(githubUrl),
            icon: const Icon(Icons.open_in_new),
            label: const Text('GitHub'),
          ),
        if (UpdateService.domesticUrlForCurrentPlatform(result.latest)
            case final domesticUrl?)
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(domesticUrl),
            icon: const Icon(Icons.cloud_download_outlined),
            label: Text(result.latest.domesticDownloadName),
          ),
      ],
    ),
  );
  if (selectedUrl == null || !context.mounted) return;
  await _openUpdateUrl(context, selectedUrl);
}

Future<void> _openUpdateUrl(BuildContext context, String value) async {
  final uri = Uri.tryParse(value.trim());
  final opened =
      uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法打开下载链接')));
  }
}

String formatUpdateDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

String updateNotes(String? value) {
  final notes = value?.trim() ?? '';
  return notes.isEmpty ? '暂无更新日志' : notes;
}

String _two(int value) => value.toString().padLeft(2, '0');
