import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:raillog/src/models/public_user_dashboard.dart';
import 'package:raillog/src/models/route_station.dart';
import 'package:raillog/src/models/trip_dashboard_stats.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/pages/manual_trip_page.dart';
import 'package:raillog/src/pages/ct_photo_search_page.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/engagement_prompt_service.dart';
import 'package:raillog/src/services/public_trip_service.dart';
import 'package:raillog/src/services/route_service.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/services/ticket_generator_service.dart';
import 'package:raillog/src/services/ticket_generator_settings.dart';
import 'package:raillog/src/services/ticket_display_policy.dart';
import 'package:raillog/src/widgets/cached_avatar.dart';
import 'package:raillog/src/widgets/engagement_prompt.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';
import 'package:url_launcher/url_launcher.dart';

class TripRecordDetailsPage extends StatefulWidget {
  const TripRecordDetailsPage({super.key, required this.tripId})
    : publicTicketId = null,
      onOwnerTap = null;

  const TripRecordDetailsPage.public({
    super.key,
    required int ticketId,
    this.onOwnerTap,
  }) : tripId = null,
       publicTicketId = ticketId;

  final int? tripId;
  final int? publicTicketId;
  final VoidCallback? onOwnerTap;

  bool get isReadOnly => publicTicketId != null;

  @override
  State<TripRecordDetailsPage> createState() => _TripRecordDetailsPageState();
}

class _TripRecordDetailsPageState extends State<TripRecordDetailsPage> {
  late Future<_LoadedTrip?> _tripFuture;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _tripFuture = _loadTrip();
  }

  Future<_LoadedTrip?> _loadTrip() async {
    final publicTicketId = widget.publicTicketId;
    if (publicTicketId != null) {
      final details = await PublicTripService.fetch(publicTicketId);
      return _LoadedTrip.public(details);
    }
    final trip = await DbHelper.instance.getTripById(widget.tripId!);
    return trip == null ? null : _LoadedTrip.local(trip);
  }

  Future<void> _editTrip(TripRecord trip) async {
    final updated = await Navigator.of(context).push<bool>(
      m3PageRoute(builder: (context) => ManualTripPage(initialTrip: trip)),
    );
    if (updated == true && mounted) {
      setState(() {
        _tripFuture = _loadTrip();
      });
    }
  }

  Future<void> _deleteTrip(TripRecord trip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除行程？'),
        content: Text(
          '将永久删除 ${trip.ticketLabel} '
          '${trip.trainNumber.trim().isEmpty ? '这趟行程' : trip.trainNumber}，此操作无法撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      final deleted = await DbHelper.instance.deleteTrip(trip.id);
      if (!mounted) return;
      if (deleted == 0) throw StateError('行程不存在或已被删除');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LoadedTrip?>(
      future: _tripFuture,
      builder: (context, snapshot) {
        final trip = snapshot.data?.trip;
        return Scaffold(
          appBar: AppBar(
            title: const Text('行程详情'),
            actions: [
              if (trip != null && !widget.isReadOnly) ...[
                IconButton(
                  tooltip: '编辑行程',
                  onPressed: _isDeleting ? null : () => _editTrip(trip),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: '删除行程',
                  color: Theme.of(context).colorScheme.error,
                  onPressed: _isDeleting ? null : () => _deleteTrip(trip),
                  icon: _isDeleting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                ),
              ],
            ],
          ),
          body: _buildBody(snapshot),
        );
      },
    );
  }

  Widget _buildBody(AsyncSnapshot<_LoadedTrip?> snapshot) {
    if (snapshot.hasError) {
      return _MessageState(
        icon: Icons.error_outline,
        message: '读取行程失败：${snapshot.error}',
      );
    }
    if (snapshot.connectionState != ConnectionState.done) {
      return const Center(child: CircularProgressIndicator());
    }
    final loaded = snapshot.data;
    if (loaded == null) {
      return const _MessageState(
        icon: Icons.search_off_outlined,
        message: '未找到这条行程记录',
      );
    }
    return _TripDetailsContent(
      trip: loaded.trip,
      ownerName: loaded.ownerName,
      ownerAvatarUrl: loaded.ownerAvatarUrl,
      ownerBio: loaded.ownerBio,
      onOwnerTap: widget.onOwnerTap,
    );
  }
}

class _LoadedTrip {
  const _LoadedTrip.local(this.trip)
    : ownerName = null,
      ownerAvatarUrl = null,
      ownerBio = null;

  _LoadedTrip.public(PublicTripDetails details)
    : trip = details.trip,
      ownerName = details.user.displayName,
      ownerAvatarUrl = details.user.avatarUrl,
      ownerBio = details.user.bio;

  final TripRecord trip;
  final String? ownerName;
  final String? ownerAvatarUrl;
  final String? ownerBio;
}

class _TripDetailsContent extends StatelessWidget {
  const _TripDetailsContent({
    required this.trip,
    this.ownerName,
    this.ownerAvatarUrl,
    this.ownerBio,
    this.onOwnerTap,
  });

  final TripRecord trip;
  final String? ownerName;
  final String? ownerAvatarUrl;
  final String? ownerBio;
  final VoidCallback? onOwnerTap;

  VoidCallback? _photoSearch(
    BuildContext context,
    String label,
    String? value,
  ) {
    final keyword = rollingStockModelCode(value).trim();
    if (keyword.isEmpty) return null;
    return () => Navigator.of(context).push(
      m3PageRoute(
        builder: (_) => CtPhotoSearchPage(keyword: keyword, fieldLabel: label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              if (ownerName != null) ...[
                _PublicOwnerBanner(
                  name: ownerName!,
                  avatarUrl: ownerAvatarUrl,
                  bio: ownerBio,
                  onTap: onOwnerTap,
                ),
                const SizedBox(height: 12),
              ],
              AnimatedBuilder(
                animation: TicketGeneratorSettings.instance,
                builder: (context, _) {
                  final settings = TicketGeneratorSettings.instance;
                  final displayStyle = ticketDisplayStyleForTrip(
                    trip,
                    settings.displayStyle,
                  );
                  if (displayStyle == TicketDisplayStyle.md3) {
                    return M3Reveal(child: _DetailsTicket(trip: trip));
                  }
                  return M3Reveal(
                    child: _GeneratedTicketPanel(
                      key: ValueKey('${trip.ticketId}|${settings.cacheKey}'),
                      trip: trip,
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _DetailsSection(
                icon: Icons.info_outline,
                title: '基础信息',
                child: _InfoGrid(
                  children: [
                    _InfoItem(
                      label: '行程类型',
                      value: trip.isRailTrip ? '铁路行程' : '非铁路行程',
                    ),
                    _InfoItem(
                      label: '车次',
                      value: _optionalText(trip.trainNumber),
                    ),
                    _InfoItem(
                      label: '始发站',
                      value: _optionalText(trip.fromStation),
                    ),
                    _InfoItem(
                      label: '终到站',
                      value: _optionalText(trip.toStation),
                    ),
                    _InfoItem(
                      label: '录入时间',
                      value: _formatDateTime(trip.createdAt),
                    ),
                    _InfoItem(
                      label: '出发时间',
                      value: _formatDateTime(trip.departureTime),
                    ),
                    _InfoItem(
                      label: '到达时间',
                      value: trip.arrivalTime == null
                          ? '未记录'
                          : _formatDateTime(trip.arrivalTime!),
                    ),
                  ],
                ),
              ),
              _DetailsSection(
                icon: Icons.route_outlined,
                title: '运行信息',
                child: _InfoGrid(
                  children: [
                    _InfoItem(
                      label: '车型',
                      value: _optionalText(trip.rollingStock),
                      onTap: _photoSearch(context, '车型', trip.rollingStock),
                    ),
                    _InfoItem(
                      label: '承运单位',
                      value: _optionalText(trip.companyName),
                    ),
                    _InfoItem(
                      label: '里程',
                      value: trip.mileageKm > 0
                          ? '${_number(trip.mileageKm)} km'
                          : '未记录',
                    ),
                    _InfoItem(label: '乘坐时长', value: _tripDuration(trip)),
                    _InfoItem(
                      label: '均速',
                      value: trip.averageSpeedKmh == null
                          ? '未记录'
                          : '${_number(trip.averageSpeedKmh!)} km/h',
                    ),
                  ],
                ),
              ),
              _DetailsSection(
                icon: Icons.event_seat_outlined,
                title: '票务信息',
                child: _InfoGrid(
                  children: [
                    _InfoItem(label: '席别', value: _optionalText(trip.seatType)),
                    _InfoItem(
                      label: '座位号',
                      value: _optionalText(trip.seatNumber),
                    ),
                    _InfoItem(
                      label: '票价',
                      value: '¥${trip.price.toStringAsFixed(2)}',
                    ),
                    _InfoItem(
                      label: '平均价格',
                      value: trip.averagePricePerKm == null
                          ? '未记录'
                          : '${trip.averagePricePerKm!.toStringAsFixed(2)} 元/km',
                    ),
                  ],
                ),
              ),
              _DetailsSection(
                icon: Icons.alt_route,
                title: '经由线路 · ${trip.viaRouteSegments.length} 段',
                child: trip.viaRouteSegments.isEmpty
                    ? const Text('未记录')
                    : _ViaRouteDiagram(trip: trip),
              ),
              _DetailsSection(
                icon: Icons.notes_outlined,
                title: '备注',
                child: Text(_optionalText(trip.notes)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicOwnerBanner extends StatelessWidget {
  const _PublicOwnerBanner({
    required this.name,
    this.avatarUrl,
    this.bio,
    this.onTap,
  });

  final String name;
  final String? avatarUrl;
  final String? bio;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final normalizedBio = bio?.trim() ?? '';
    final displayBio = normalizedBio.isEmpty ? '这个人很懒，还没有个人简介~' : normalizedBio;
    final colors = Theme.of(context).colorScheme;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _OwnerAvatar(name: name, avatarUrl: avatarUrl, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  displayBio,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
          ],
        ],
      ),
    );
    return Card.outlined(
      margin: EdgeInsets.zero,
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

class _OwnerAvatar extends StatelessWidget {
  const _OwnerAvatar({
    required this.name,
    required this.avatarUrl,
    required this.size,
  });

  final String name;
  final String? avatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CachedAvatar(name: name, imageUrl: avatarUrl, size: size);
}

class _GeneratedTicketPanel extends StatefulWidget {
  const _GeneratedTicketPanel({super.key, required this.trip});

  final TripRecord trip;

  @override
  State<_GeneratedTicketPanel> createState() => _GeneratedTicketPanelState();
}

class _GeneratedTicketPanelState extends State<_GeneratedTicketPanel>
    with AutomaticKeepAliveClientMixin<_GeneratedTicketPanel> {
  Uint8List? _imageBytes;
  String? _error;
  bool _loading = false;
  bool _savingImage = false;
  bool _buying = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ticketId = widget.trip.ticketId;
    if (SessionService.instance.token == null) {
      setState(() => _error = '登录后才能生成纪念车票');
      return;
    }
    if (ticketId == null) {
      setState(() => _error = '请先同步这条行程，再生成纪念车票');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await TicketGeneratorService.generateImage(
        tripId: ticketId,
      );
      if (!mounted) return;
      setState(() => _imageBytes = bytes);
    } on TicketGeneratorException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '车票生成失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveImage() async {
    final ticketId = widget.trip.ticketId;
    final bytes = _imageBytes;
    if (ticketId == null || bytes == null || _savingImage) return;
    setState(() => _savingImage = true);
    var saved = false;
    try {
      final path = await TicketGeneratorService.saveImage(
        tripId: ticketId,
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('车票图片已保存\n保存位置：$path')));
      saved = true;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
    } finally {
      if (mounted) setState(() => _savingImage = false);
    }
    if (saved && mounted) {
      await maybeShowEngagementPrompt(
        context,
        EngagementPromptEvent.ticketImageSaved,
      );
    }
  }

  Future<void> _buy() async {
    final ticketId = widget.trip.ticketId;
    if (ticketId == null || _buying) return;
    setState(() => _buying = true);
    try {
      final download = await TicketGeneratorService.createPdfDownloadKey(
        tripIds: [ticketId],
      );
      if (!mounted) return;
      final openTaobao = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.key_outlined),
          title: const Text('向商家发送下载 Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('请将以下 Key 发送给淘宝商家客服，用于获取本次车票排版文件。'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(dialogContext).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  download.key,
                  textAlign: TextAlign.center,
                  style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Key 有效期至 ${_formatDateTime(download.expiresAt.toLocal())}。',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: download.key));
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Key 已复制')));
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('复制 Key'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('前往淘宝'),
            ),
          ],
        ),
      );
      if (!mounted || openTaobao != true) return;
      final opened = await launchUrl(
        Uri.parse('https://m.tb.cn/h.8XSxU6t54xTo7tM'),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开购买链接')));
      }
    } on TicketGeneratorException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('创建下载 Key 失败：$error')));
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = Theme.of(context).colorScheme;
    final bytes = _imageBytes;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 1800 / 1120,
        child: bytes == null
            ? _buildState(colors)
            : Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: colors.surface,
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Material(
                      elevation: 3,
                      color: colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '下载车票图片',
                            onPressed: _savingImage ? null : _saveImage,
                            icon: _savingImage
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.download_outlined),
                          ),
                          IconButton(
                            tooltip: '购买实体纪念票',
                            onPressed: _buying ? null : _buy,
                            icon: _buying
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.shopping_bag_outlined),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildState(ColorScheme colors) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.confirmation_number_outlined,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(_error ?? '暂时无法生成车票', textAlign: TextAlign.center),
            if (widget.trip.ticketId != null &&
                SessionService.instance.token != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailsTicket extends StatelessWidget {
  const _DetailsTicket({required this.trip});

  final TripRecord trip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = _duration(trip);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            color: trip.isRailTrip
                ? colors.primaryContainer
                : colors.secondaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  trip.isRailTrip
                      ? Icons.train_outlined
                      : Icons.commute_outlined,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _optionalText(trip.trainNumber),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      trip.ticketLabel,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Text(_formatDate(trip.departureTime)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _TicketStation(
                    station: trip.fromStation,
                    dateTime: trip.departureTime,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      const Icon(Icons.arrow_forward),
                      if (duration != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _formatDuration(duration),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: _TicketStation(
                    station: trip.toStation,
                    dateTime: trip.arrivalTime,
                    alignEnd: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketStation extends StatelessWidget {
  const _TicketStation({
    required this.station,
    required this.dateTime,
    this.alignEnd = false,
  });

  final String station;
  final DateTime? dateTime;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          station,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(dateTime == null ? '--:--' : _formatMonthDayTime(dateTime!)),
      ],
    );
  }
}

class _DetailsSection extends StatelessWidget {
  const _DetailsSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: M3Reveal(
        distance: 6,
        child: Material(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: colors.primary),
                    const SizedBox(width: 8),
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0;
        final itemWidth = constraints.maxWidth >= 620
            ? (constraints.maxWidth - gap) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: gap,
          runSpacing: 16,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SelectableText(
                value,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            if (onTap != null && value != '未记录') ...[
              const SizedBox(width: 2),
              IconButton(
                tooltip: '搜索车型照片',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                onPressed: onTap,
                icon: Icon(
                  Icons.photo_library_outlined,
                  size: 16,
                  color: colors.primary,
                ),
              ),
            ],
          ],
        ),
      ],
    );
    return content;
  }
}

class _ViaRouteDiagram extends StatefulWidget {
  const _ViaRouteDiagram({required this.trip});

  final TripRecord trip;

  @override
  State<_ViaRouteDiagram> createState() => _ViaRouteDiagramState();
}

class _ViaRouteDiagramState extends State<_ViaRouteDiagram>
    with AutomaticKeepAliveClientMixin<_ViaRouteDiagram> {
  static const _rowHeight = 88.0;
  Map<int, List<RouteStation>> _routeStations = const {};
  final Set<int> _expandedRouteSections = {};
  bool _isLoading = true;
  int _stationRequestId = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadRouteStations();
  }

  @override
  void didUpdateWidget(covariant _ViaRouteDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trip.clientId != widget.trip.clientId ||
        oldWidget.trip.updatedAt != widget.trip.updatedAt) {
      _loadRouteStations();
    }
  }

  Future<void> _loadRouteStations() async {
    final requestId = ++_stationRequestId;
    if (mounted && !_isLoading) {
      setState(() {
        _isLoading = true;
        _routeStations = const {};
        _expandedRouteSections.clear();
      });
    }
    final results = <int, List<RouteStation>>{};
    await Future.wait([
      for (var index = 0; index < widget.trip.viaRouteSegments.length; index++)
        _loadRouteSection(index, results),
    ]);
    if (!mounted || requestId != _stationRequestId) return;
    setState(() {
      _routeStations = results;
      _isLoading = false;
    });
  }

  Future<void> _loadRouteSection(
    int index,
    Map<int, List<RouteStation>> results,
  ) async {
    final segment = widget.trip.viaRouteSegments[index];
    if (segment.routeName.trim().isEmpty) return;
    try {
      final stations = await RouteService.getStationsBetweenRoute(
        segment.routeName,
        segment.fromStation,
        segment.toStation,
      );
      if (stations.length >= 2) results[index] = stations;
    } catch (_) {
      // 手动线路或数据库读取失败时保留区间端点。
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = Theme.of(context).colorScheme;
    if (_isLoading) {
      return const SizedBox(
        height: 112,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(height: 12),
              Text('正在读取经由线路'),
            ],
          ),
        ),
      );
    }
    final segments = widget.trip.viaRouteSegments;
    final routeColors = <String, Color>{};
    const routeColorSeeds = [
      Color(0xFF005AC1),
      Color(0xFFC43E00),
      Color(0xFF006B5E),
      Color(0xFF8E24AA),
      Color(0xFF7A5900),
      Color(0xFFB0005A),
    ];
    final palette = [
      for (final seed in routeColorSeeds)
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: colors.brightness,
        ).primary,
    ];
    for (final segment in segments) {
      final route = _routeLabel(segment.routeName);
      routeColors.putIfAbsent(
        route,
        () => palette[routeColors.length % palette.length],
      );
    }
    final segmentColors = <Color>[];
    final routeNames = <String>[];
    final routeSectionIds = <int>[];
    final expandableRouteSectionIds = <int>{};
    final stations = <String>[widget.trip.fromStation];
    final cumulativeMileage = <double>[0];
    String? previousRoute;
    var routeSectionId = 0;
    var collapsedMileage = 0.0;
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final route = _routeLabel(segment.routeName);
      if (index == 0 || route != previousRoute) {
        routeSectionId = index;
        collapsedMileage = 0;
      }
      previousRoute = route;
      final color = routeColors[route]!;
      final routeStations = _routeStations[index];
      if ((routeStations?.length ?? 0) > 2) {
        expandableRouteSectionIds.add(routeSectionId);
      }
      if (!_expandedRouteSections.contains(routeSectionId)) {
        collapsedMileage += segment.mileageKm;
        final nextRoute = index + 1 < segments.length
            ? _routeLabel(segments[index + 1].routeName)
            : null;
        if (nextRoute == route) continue;
        _appendStation(
          stations,
          cumulativeMileage,
          segment.toStation,
          collapsedMileage,
          segmentColors,
          routeNames,
          routeSectionIds,
          color,
          route,
          routeSectionId,
        );
        continue;
      }
      if (routeStations == null) {
        _appendStation(
          stations,
          cumulativeMileage,
          segment.toStation,
          segment.mileageKm,
          segmentColors,
          routeNames,
          routeSectionIds,
          color,
          route,
          routeSectionId,
        );
        continue;
      }
      var expandedMileage = 0.0;
      for (
        var stationIndex = 1;
        stationIndex < routeStations.length;
        stationIndex++
      ) {
        expandedMileage +=
            (routeStations[stationIndex].mileage -
                    routeStations[stationIndex - 1].mileage)
                .abs();
      }
      final mileageScale = segment.mileageKm > 0 && expandedMileage > 0
          ? segment.mileageKm / expandedMileage
          : 1.0;
      var previousMileage = routeStations.first.mileage;
      for (final station in routeStations.skip(1)) {
        final stationMileage = station.mileage;
        _appendStation(
          stations,
          cumulativeMileage,
          station.name,
          (stationMileage - previousMileage).abs() * mileageScale,
          segmentColors,
          routeNames,
          routeSectionIds,
          color,
          route,
          routeSectionId,
        );
        previousMileage = stationMileage;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = stations.length == 1
            ? 1
            : math.max(2, math.min(8, (constraints.maxWidth / 80).floor()));
        final rowCount = (stations.length + columns - 1) ~/ columns;
        final height = rowCount * _rowHeight;
        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ViaRoutePainter(
                    segmentColors: segmentColors,
                    routeSectionIds: routeSectionIds,
                    rowHeight: _rowHeight,
                    stationCount: stations.length,
                    columns: columns,
                    trackUnderlayColor: colors.surfaceContainerHighest,
                  ),
                ),
              ),
              for (var index = 0; index < stations.length; index++)
                _buildStation(
                  context,
                  index: index,
                  station: stations[index],
                  mileage: cumulativeMileage[index],
                  leftColor: _stationSideColor(
                    index,
                    left: true,
                    segmentColors: segmentColors,
                    fallback: colors.primary,
                    columns: columns,
                  ),
                  rightColor: _stationSideColor(
                    index,
                    left: false,
                    segmentColors: segmentColors,
                    fallback: colors.primary,
                    columns: columns,
                  ),
                  width: constraints.maxWidth,
                  columns: columns,
                ),
              ..._buildRouteLabels(
                context,
                routeNames: routeNames,
                routeSectionIds: routeSectionIds,
                expandableRouteSectionIds: expandableRouteSectionIds,
                segmentColors: segmentColors,
                width: constraints.maxWidth,
                columns: columns,
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildRouteLabels(
    BuildContext context, {
    required List<String> routeNames,
    required List<int> routeSectionIds,
    required Set<int> expandableRouteSectionIds,
    required List<Color> segmentColors,
    required double width,
    required int columns,
  }) {
    final labels = <Widget>[];
    var firstSegment = 0;
    while (firstSegment < routeSectionIds.length) {
      final sectionId = routeSectionIds[firstSegment];
      final canExpand = expandableRouteSectionIds.contains(sectionId);
      var lastSegment = firstSegment;
      while (lastSegment + 1 < routeSectionIds.length &&
          routeSectionIds[lastSegment + 1] == sectionId) {
        lastSegment++;
      }
      final center = _routeLabelCenter(
        firstSegment,
        lastSegment,
        width,
        columns,
      );
      final labelWidth = math.min(112.0, width);
      labels.add(
        Positioned(
          left: math.max(
            0,
            math.min(width - labelWidth, center.dx - labelWidth / 2),
          ),
          top: math.max(0, center.dy - 34),
          width: labelWidth,
          height: 25,
          child: Center(
            child: _ViaRouteLabel(
              key: ValueKey(sectionId),
              route: routeNames[firstSegment],
              color: segmentColors[firstSegment],
              expanded: canExpand && _expandedRouteSections.contains(sectionId),
              onTap: canExpand
                  ? () {
                      setState(() {
                        if (!_expandedRouteSections.add(sectionId)) {
                          _expandedRouteSections.remove(sectionId);
                        }
                      });
                    }
                  : null,
            ),
          ),
        ),
      );
      firstSegment = lastSegment + 1;
    }
    return labels;
  }

  Offset _routeLabelCenter(
    int firstSegment,
    int lastSegment,
    double width,
    int columns,
  ) {
    final startsAtTurn = firstSegment % columns == columns - 1;
    final start = _viaStationOffset(firstSegment, width, columns, _rowHeight);
    if (startsAtTurn && lastSegment == firstSegment) return start;

    final firstRowSegment = startsAtTurn ? firstSegment + 1 : firstSegment;
    final firstRow = firstRowSegment ~/ columns;
    final rowStart = _viaStationOffset(
      firstRowSegment,
      width,
      columns,
      _rowHeight,
    );
    var endX = rowStart.dx;
    for (var index = firstRowSegment; index <= lastSegment; index++) {
      if (index ~/ columns != firstRow) break;
      final end = _viaStationOffset(index + 1, width, columns, _rowHeight);
      if (index ~/ columns == (index + 1) ~/ columns) {
        endX = end.dx;
      } else {
        endX = _viaStationOffset(index, width, columns, _rowHeight).dx;
        break;
      }
    }
    return Offset((rowStart.dx + endX) / 2, rowStart.dy);
  }

  Color _stationSideColor(
    int index, {
    required bool left,
    required List<Color> segmentColors,
    required Color fallback,
    required int columns,
  }) {
    if (segmentColors.isEmpty) return fallback;
    final incoming = index > 0 ? segmentColors[index - 1] : segmentColors.first;
    final outgoing = index < segmentColors.length
        ? segmentColors[index]
        : segmentColors.last;
    final incomingIsLeft = (index ~/ columns).isEven;
    return left == incomingIsLeft ? incoming : outgoing;
  }

  void _appendStation(
    List<String> stations,
    List<double> cumulativeMileage,
    String station,
    double mileage,
    List<Color> segmentColors,
    List<String> routeNames,
    List<int> routeSectionIds,
    Color color,
    String route,
    int routeSectionId,
  ) {
    final normalized = station.trim();
    if (normalized.isEmpty || _sameStation(stations.last, normalized)) return;
    stations.add(normalized);
    cumulativeMileage.add(cumulativeMileage.last + (mileage > 0 ? mileage : 0));
    segmentColors.add(color);
    routeNames.add(route);
    routeSectionIds.add(routeSectionId);
  }

  bool _sameStation(String first, String second) {
    final normalizedFirst = first.trim();
    final normalizedSecond = second.trim();
    if (normalizedFirst == normalizedSecond) return true;
    return normalizedFirst.replaceFirst(RegExp(r'站$'), '') ==
        normalizedSecond.replaceFirst(RegExp(r'站$'), '');
  }

  Widget _buildStation(
    BuildContext context, {
    required int index,
    required String station,
    required double mileage,
    required Color leftColor,
    required Color rightColor,
    required double width,
    required int columns,
  }) {
    final row = index ~/ columns;
    final x = _viaStationX(index, width, columns);
    final labelWidth = math.min(104.0, width / columns);
    return Positioned(
      top: row * _rowHeight + 25,
      left: 0,
      width: width,
      height: _rowHeight - 25,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: x - _ViaStationDot.size / 2,
            child: _ViaStationDot(leftColor: leftColor, rightColor: rightColor),
          ),
          Positioned(
            top: _ViaStationDot.size + 2,
            left: math.max(0, math.min(width - labelWidth, x - labelWidth / 2)),
            width: labelWidth,
            child: _ViaStationLabel(
              station: station,
              mileage: mileage,
              alignEnd: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _ViaRouteLabel extends StatelessWidget {
  const _ViaRouteLabel({
    super.key,
    required this.route,
    required this.color,
    required this.expanded,
    this.onTap,
  });

  final String route;
  final Color color;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              route,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 14,
              color: colors.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
    final label = Material(
      color: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              child: content,
            ),
    );
    return onTap == null
        ? label
        : Tooltip(message: expanded ? '收起$route' : '展开$route', child: label);
  }
}

class _ViaRoutePainter extends CustomPainter {
  const _ViaRoutePainter({
    required this.segmentColors,
    required this.routeSectionIds,
    required this.rowHeight,
    required this.stationCount,
    required this.columns,
    required this.trackUnderlayColor,
  });

  final List<Color> segmentColors;
  final List<int> routeSectionIds;
  final double rowHeight;
  final int stationCount;
  final int columns;
  final Color trackUnderlayColor;

  @override
  void paint(Canvas canvas, Size size) {
    final underlayPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = trackUnderlayColor;
    final routePaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    var firstSegment = 0;
    while (firstSegment < stationCount - 1) {
      var lastSegment = firstSegment;
      while (lastSegment + 1 < stationCount - 1 &&
          routeSectionIds[lastSegment + 1] == routeSectionIds[firstSegment]) {
        lastSegment++;
      }
      final points = [
        for (var index = firstSegment; index <= lastSegment + 1; index++)
          _viaStationOffset(index, size.width, columns, rowHeight),
      ];
      final path = _roundedRoutePath(_addTurnaroundPoints(points, size.width));
      canvas.drawPath(path, underlayPaint);
      routePaint.color = segmentColors[firstSegment];
      canvas.drawPath(path, routePaint);
      firstSegment = lastSegment + 1;
    }
  }

  List<Offset> _addTurnaroundPoints(List<Offset> stations, double width) {
    const turnPadding = 12.0;
    final points = <Offset>[stations.first];
    for (var index = 1; index < stations.length; index++) {
      final start = stations[index - 1];
      final end = stations[index];
      if ((start.dy - end.dy).abs() >= 1) {
        final turnX = start.dx < width / 2 ? turnPadding : width - turnPadding;
        points
          ..add(Offset(turnX, start.dy))
          ..add(Offset(turnX, end.dy));
      }
      points.add(end);
    }
    return points;
  }

  Path _roundedRoutePath(List<Offset> points) {
    const radius = 14.0;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length - 1; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final next = points[index + 1];
      final incoming = current - previous;
      final outgoing = next - current;
      final incomingLength = incoming.distance;
      final outgoingLength = outgoing.distance;
      if (incomingLength == 0 || outgoingLength == 0) continue;
      final cornerRadius = math.min(
        radius,
        math.min(incomingLength, outgoingLength) / 2,
      );
      final before = current - incoming / incomingLength * cornerRadius;
      final after = current + outgoing / outgoingLength * cornerRadius;
      path
        ..lineTo(before.dx, before.dy)
        ..quadraticBezierTo(current.dx, current.dy, after.dx, after.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  @override
  bool shouldRepaint(covariant _ViaRoutePainter oldDelegate) =>
      oldDelegate.rowHeight != rowHeight ||
      oldDelegate.stationCount != stationCount ||
      oldDelegate.columns != columns ||
      oldDelegate.trackUnderlayColor != trackUnderlayColor ||
      !_sameInts(oldDelegate.routeSectionIds, routeSectionIds) ||
      !_sameColors(oldDelegate.segmentColors, segmentColors);

  bool _sameInts(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  bool _sameColors(List<Color> first, List<Color> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}

Offset _viaStationOffset(
  int index,
  double width,
  int columns,
  double rowHeight,
) {
  return Offset(
    _viaStationX(index, width, columns),
    index ~/ columns * rowHeight + 34,
  );
}

double _viaStationX(int index, double width, int columns) {
  final horizontalPadding = math.min(44.0, width / 4);
  final step = columns == 1
      ? 0.0
      : (width - horizontalPadding * 2) / (columns - 1);
  final slot = index % columns;
  final row = index ~/ columns;
  final actualSlot = row.isEven ? slot : columns - 1 - slot;
  return horizontalPadding + actualSlot * step;
}

class _ViaStationLabel extends StatelessWidget {
  const _ViaStationLabel({
    required this.station,
    required this.mileage,
    required this.alignEnd,
  });

  final String station;
  final double mileage;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.center,
      children: [
        Text(
          station,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          '${_number(mileage)} km',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
    return content;
  }
}

class _ViaStationDot extends StatelessWidget {
  const _ViaStationDot({required this.leftColor, required this.rightColor});

  static const size = 18.0;

  final Color leftColor;
  final Color rightColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.16),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _ViaStationDotPainter(
          leftColor: leftColor,
          rightColor: rightColor,
        ),
      ),
    );
  }
}

class _ViaStationDotPainter extends CustomPainter {
  const _ViaStationDotPainter({
    required this.leftColor,
    required this.rightColor,
  });

  final Color leftColor;
  final Color rightColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 4.0;
    final rect =
        Offset(strokeWidth / 2, strokeWidth / 2) &
        Size(size.width - strokeWidth, size.height - strokeWidth);
    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;
    if (leftColor == rightColor) {
      canvas.drawOval(rect, paint..color = leftColor);
      return;
    }
    canvas.drawArc(rect, math.pi / 2, math.pi, false, paint..color = leftColor);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi,
      false,
      paint..color = rightColor,
    );
  }

  @override
  bool shouldRepaint(covariant _ViaStationDotPainter oldDelegate) =>
      oldDelegate.leftColor != leftColor ||
      oldDelegate.rightColor != rightColor;
}

String _routeLabel(String routeName) {
  final value = routeName.trim();
  return value.isEmpty ? '手动线路' : value;
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

String _optionalText(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? '未记录' : text;
}

Duration? _duration(TripRecord trip) {
  final arrivalTime = trip.arrivalTime;
  if (arrivalTime == null || arrivalTime.isBefore(trip.departureTime)) {
    return null;
  }
  return arrivalTime.difference(trip.departureTime);
}

String _tripDuration(TripRecord trip) {
  final duration = _duration(trip);
  return duration == null ? '未记录' : _formatDuration(duration);
}

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _formatDateTime(DateTime value) =>
    '${_formatDate(value)} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}:'
    '${value.second.toString().padLeft(2, '0')}';

String _formatMonthDayTime(DateTime value) =>
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _formatDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  if (hours == 0) return '$minutes分';
  return minutes == 0 ? '$hours时' : '$hours时$minutes分';
}

String _number(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}
