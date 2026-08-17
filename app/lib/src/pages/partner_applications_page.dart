import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:raillog/src/models/partner_application.dart';
import 'package:raillog/src/services/partner_application_service.dart';
import 'package:url_launcher/url_launcher.dart';

class PartnerApplicationsPage extends StatefulWidget {
  const PartnerApplicationsPage({super.key});

  @override
  State<PartnerApplicationsPage> createState() =>
      _PartnerApplicationsPageState();
}

class _PartnerApplicationsPageState extends State<PartnerApplicationsPage> {
  late Future<List<PartnerApplication>> _future =
      PartnerApplicationService.fetch();

  Future<void> _retry() async {
    final future = PartnerApplicationService.fetch();
    setState(() => _future = future);
    await future;
  }

  Future<void> _openWebsite(String value) async {
    final uri = Uri.tryParse(value);
    final opened =
        uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开合作应用官网')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('合作应用')),
      body: FutureBuilder<List<PartnerApplication>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _PartnerState(
              icon: Icons.cloud_off_outlined,
              message: '合作应用加载失败',
              onRetry: _retry,
            );
          }
          final partners = snapshot.data ?? const [];
          if (partners.isEmpty) {
            return const _PartnerState(
              icon: Icons.apps_outlined,
              message: '暂无合作应用',
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: RefreshIndicator(
                onRefresh: _retry,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  itemCount: partners.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _PartnerCard(
                    partner: partners[index],
                    onOpen: () => _openWebsite(partners[index].websiteUrl),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PartnerCard extends StatelessWidget {
  const _PartnerCard({required this.partner, required this.onOpen});

  final PartnerApplication partner;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CachedNetworkImage(
              imageUrl: partner.posterUrl,
              width: double.infinity,
              fit: BoxFit.contain,
              placeholder: (_, _) => AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(
                  color: colors.surfaceContainerHighest,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
              errorWidget: (_, _, _) => AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(
                  color: colors.surfaceContainerHighest,
                  child: const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: partner.iconUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain,
                      errorWidget: (_, _, _) => ColoredBox(
                        color: colors.surfaceContainerHighest,
                        child: const Icon(Icons.apps_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          partner.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          partner.description,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: '访问官网',
                    child: Icon(
                      Icons.open_in_new,
                      size: 20,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartnerState extends StatelessWidget {
  const _PartnerState({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 42,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Text(message),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ],
    ),
  );
}
