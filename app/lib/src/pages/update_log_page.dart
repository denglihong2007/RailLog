import 'package:flutter/material.dart';
import 'package:raillog/src/models/app_update_info.dart';
import 'package:raillog/src/services/update_service.dart';
import 'package:raillog/src/widgets/update_prompt.dart';
import 'package:raillog/src/widgets/update_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateLogPage extends StatefulWidget {
  const UpdateLogPage({super.key});

  @override
  State<UpdateLogPage> createState() => _UpdateLogPageState();
}

class _UpdateLogPageState extends State<UpdateLogPage> {
  late Future<AppUpdateInfo> _release = UpdateService.latest();

  void _retry() => setState(() => _release = UpdateService.latest());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('更新日志')),
      body: FutureBuilder<AppUpdateInfo>(
        future: _release,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final release = snapshot.data;
          if (release == null) {
            return _LoadFailure(onRetry: _retry);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        release.name.trim().isEmpty
                            ? 'RailLog ${release.version}'
                            : release.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '版本 ${release.version} · '
                        '${formatUpdateDate(release.publishedAt)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      UpdateMarkdown(data: updateNotes(release.releaseNotes)),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          if (UpdateService.githubUrlForCurrentPlatform(release)
                              case final githubUrl?)
                            FilledButton.icon(
                              onPressed: () => _open(githubUrl),
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('GitHub'),
                            ),
                          if (UpdateService.domesticUrlForCurrentPlatform(
                                release,
                              )
                              case final domesticUrl?)
                            OutlinedButton.icon(
                              onPressed: () => _open(domesticUrl),
                              icon: const Icon(Icons.cloud_download_outlined),
                              label: Text(release.domesticDownloadName),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _open(String value) async {
    final uri = Uri.tryParse(value.trim());
    final opened =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开下载链接')));
    }
  }
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            const Text('无法读取更新日志'),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
