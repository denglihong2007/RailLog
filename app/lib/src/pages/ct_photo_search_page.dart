import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:raillog/src/services/ct_photo_service.dart';
import 'package:url_launcher/url_launcher.dart';

class CtPhotoSearchPage extends StatefulWidget {
  const CtPhotoSearchPage({
    super.key,
    required this.keyword,
    required this.fieldLabel,
    this.filter = CtPhotoSearchFilter.model,
  });

  final String keyword;
  final String fieldLabel;
  final CtPhotoSearchFilter filter;

  @override
  State<CtPhotoSearchPage> createState() => _CtPhotoSearchPageState();
}

class _CtPhotoSearchPageState extends State<CtPhotoSearchPage> {
  final _photos = <CtPhoto>[];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _page = 0;
  int _pages = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (more) {
      if (_loadingMore || _page >= _pages) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await CtPhotoService.search(
        widget.keyword,
        filter: widget.filter,
        page: more ? _page + 1 : 1,
      );
      if (!mounted) return;
      setState(() {
        if (!more) _photos.clear();
        _photos.addAll(result.photos);
        _page = result.page;
        _pages = result.pages;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = '照片搜索失败：$error';
      });
    }
  }

  Future<void> _openPhoto(CtPhoto photo) async {
    final uri = Uri.parse('https://train.idcmoss.cn/photo.php?id=${photo.id}');
    if (!await launchUrl(uri, mode: LaunchMode.inAppBrowserView) && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开照片页面')));
    }
  }

  Future<void> _openPartnerSite() async {
    final opened = await launchUrl(
      Uri.parse('https://train.idcmoss.cn/'),
      mode: LaunchMode.inAppBrowserView,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开 CT Photos 官网')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.fieldLabel}照片')),
      body: Column(
        children: [
          _PartnerBanner(onTap: _openPartnerSite),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _PhotoMessage(
                    icon: Icons.error_outline,
                    message: _error!,
                    onRetry: _load,
                  )
                : _photos.isEmpty
                ? const _PhotoMessage(
                    icon: Icons.photo_library_outlined,
                    message: '没有找到相关照片',
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.all(12),
                          sliver: SliverLayoutBuilder(
                            builder: (context, constraints) {
                              const spacing = 12.0;
                              final columns =
                                  ((constraints.crossAxisExtent + spacing) /
                                          (150 + spacing))
                                      .floor()
                                      .clamp(1, 100);
                              final tileWidth =
                                  (constraints.crossAxisExtent -
                                      spacing * (columns - 1)) /
                                  columns;
                              final tileHeight = tileWidth * 3 / 4 + 53;
                              return SliverGrid(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => _PhotoTile(
                                    photo: _photos[index],
                                    onTap: () => _openPhoto(_photos[index]),
                                  ),
                                  childCount: _photos.length,
                                ),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      mainAxisSpacing: spacing,
                                      crossAxisSpacing: spacing,
                                      mainAxisExtent: tileHeight,
                                    ),
                              );
                            },
                          ),
                        ),
                        if (_page < _pages)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                              child: OutlinedButton.icon(
                                onPressed: _loadingMore
                                    ? null
                                    : () => _load(more: true),
                                icon: _loadingMore
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.expand_more),
                                label: const Text('加载更多'),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo, required this.onTap});
  final CtPhoto photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: photo.thumbnailUrl.isEmpty
                  ? ColoredBox(
                      color: colors.surfaceContainerHighest,
                      child: const Center(
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: photo.thumbnailUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (_, _, _) => const Center(
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          photo.title.isEmpty ? '照片 #${photo.id}' : photo.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      if (photo.shootDate.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        const Tooltip(
                          message: '拍摄日期',
                          child: Icon(Icons.calendar_today_outlined, size: 13),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          photo.shootDate,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Tooltip(
                        message: '摄影师',
                        child: Icon(Icons.person_outline, size: 14),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          photo.author.isEmpty ? '未署名' : photo.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _PhotoMetric(
                        tooltip: '查看数',
                        icon: Icons.visibility_outlined,
                        value: photo.viewsCount,
                      ),
                      const SizedBox(width: 6),
                      _PhotoMetric(
                        tooltip: '点赞数',
                        icon: Icons.favorite_border,
                        value: photo.likesCount,
                      ),
                    ],
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

class _PhotoMetric extends StatelessWidget {
  const _PhotoMetric({
    required this.tooltip,
    required this.icon,
    required this.value,
  });

  final String tooltip;
  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14),
        const SizedBox(width: 2),
        Text('$value', style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _PartnerBanner extends StatelessWidget {
  const _PartnerBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 20,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '图库合作方: CT Photos',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const Spacer(),
              Icon(Icons.open_in_new, size: 16, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoMessage extends StatelessWidget {
  const _PhotoMessage({
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
        Text(message, textAlign: TextAlign.center),
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
