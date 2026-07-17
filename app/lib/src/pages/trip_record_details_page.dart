import 'package:flutter/material.dart';
import 'package:raillog/src/models/public_user_dashboard.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';
import 'package:raillog/src/pages/manual_trip_page.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/public_trip_service.dart';
import 'package:raillog/src/widgets/cached_avatar.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

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
              M3Reveal(child: _DetailsTicket(trip: trip)),
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
                  ],
                ),
              ),
              _DetailsSection(
                icon: Icons.alt_route,
                title: '经由线路 · ${trip.viaRouteSegments.length} 段',
                child: trip.viaRouteSegments.isEmpty
                    ? const Text('未记录')
                    : ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(top: 4),
                        title: const Text('展开查看完整经由'),
                        children: [
                          for (
                            var index = 0;
                            index < trip.viaRouteSegments.length;
                            index++
                          ) ...[
                            _RouteSegmentRow(
                              index: index + 1,
                              segment: trip.viaRouteSegments[index],
                            ),
                            if (index < trip.viaRouteSegments.length - 1)
                              const Divider(height: 20, indent: 40),
                          ],
                        ],
                      ),
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
  const _InfoItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 3),
        SelectableText(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

class _RouteSegmentRow extends StatelessWidget {
  const _RouteSegmentRow({required this.index, required this.segment});

  final int index;
  final ViaRouteSegment segment;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 32,
          child: Text(
            index.toString(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                segment.routeName,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),
              Text('${segment.fromStation} → ${segment.toStation}'),
            ],
          ),
        ),
        if (segment.mileageKm > 0) ...[
          const SizedBox(width: 12),
          Text('${_number(segment.mileageKm)} km'),
        ],
      ],
    );
  }
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
