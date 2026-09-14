import 'package:flutter/material.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/entity_review_service.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/widgets/cached_avatar.dart';
import 'package:raillog/src/widgets/entity_review_reaction_bar.dart';

class EntityReviewCard extends StatelessWidget {
  const EntityReviewCard({
    super.key,
    required this.review,
    required this.onChanged,
    this.trips = const [],
    this.entityName,
    this.showTarget = false,
    this.showTripLinks = true,
    this.showDivider = false,
    this.contentPadding = const EdgeInsets.fromLTRB(12, 12, 8, 4),
    this.onEdit,
    this.onDelete,
    this.onUserTap,
    this.onTripTap,
    this.onTargetTap,
  });

  final EntityReview review;
  final List<TripRecord> trips;
  final String? entityName;
  final bool showTarget;
  final bool showTripLinks;
  final bool showDivider;
  final EdgeInsetsGeometry contentPadding;
  final VoidCallback onChanged;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onUserTap;
  final void Function(TripRecord trip)? onTripTap;
  final VoidCallback? onTargetTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final primary = review.trip ?? _localTripForTicket(trips, review.tripId);
    final secondary =
        review.secondTrip ?? _localTripForTicket(trips, review.secondTripId);
    final extra = _reviewExtra(review);
    final seat = review.reviewType == 'rollingStock'
        ? [primary?.seatType, secondary?.seatType]
              .where((value) => value?.trim().isNotEmpty == true)
              .map((value) => value!.trim())
              .toSet()
              .join(' / ')
        : '';
    final routeRange = review.reviewType == 'route'
        ? _reviewRouteRange(review, primary, entityName ?? review.entityKey)
        : '';
    final metadata = [
      extra,
      if (seat.isNotEmpty) '席别：$seat',
      if (routeRange.isNotEmpty) '评价区间：$routeRange',
    ].where((value) => value.isNotEmpty).join(' · ');
    final isOwner = review.userId == SessionService.instance.user?.id;

    return Padding(
      padding: EdgeInsets.only(bottom: showDivider ? 8 : 0),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: showDivider
                ? BorderSide(color: colors.outlineVariant)
                : BorderSide.none,
          ),
        ),
        child: Padding(
          padding: contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showTarget) ...[
                _EntityReviewTargetLine(review: review, onTap: onTargetTap),
                const SizedBox(height: 10),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: onUserTap,
                    child: CachedAvatar(
                      name: review.displayName,
                      imageUrl: review.avatarUrl,
                      size: 40,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                review.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (isOwner && (onEdit != null || onDelete != null))
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (onEdit != null)
                                    IconButton(
                                      tooltip: '编辑评价',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: onEdit,
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                      ),
                                    ),
                                  if (onDelete != null)
                                    IconButton(
                                      tooltip: '删除评价',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: onDelete,
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              '★' * review.rating,
                              style: TextStyle(
                                color: colors.primary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            if (metadata.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  metadata,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ] else
                              const Spacer(),
                            Text(
                              _formatReviewDate(review.createdAt),
                              style: textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(review.comment, style: textTheme.bodyMedium),
                        if (showTripLinks && primary != null)
                          _EntityReviewTripLink(
                            roleLabel: review.reviewType == 'transfer'
                                ? '前序行程 · 到站 ${_formatTime(primary.arrivalTime)}'
                                : null,
                            trip: primary,
                            onTap: onTripTap,
                          ),
                        if (showTripLinks && secondary != null)
                          _EntityReviewTripLink(
                            roleLabel:
                                '后续行程 · 发车 ${_formatTime(secondary.departureTime)}',
                            trip: secondary,
                            onTap: onTripTap,
                          ),
                        if (review.reactions.isNotEmpty || !isOwner) ...[
                          const SizedBox(height: 6),
                          EntityReviewReactionBar(
                            reactions: review.reactions,
                            enabled: !isOwner,
                            onToggle: (emoji) =>
                                _toggleReaction(context, emoji),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleReaction(BuildContext context, String emoji) async {
    var currentEmoji = '';
    for (final reaction in review.reactions) {
      if (reaction.reactedByCurrentUser) {
        currentEmoji = reaction.emoji;
        break;
      }
    }
    try {
      if (currentEmoji == emoji) {
        await EntityReviewService.removeReaction(review);
      } else {
        await EntityReviewService.setReaction(review, emoji);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(error))));
      }
      return;
    }
    if (context.mounted) onChanged();
  }
}

class _EntityReviewTargetLine extends StatelessWidget {
  const _EntityReviewTargetLine({required this.review, this.onTap});

  final EntityReview review;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final target = entityReviewTarget(review);
    return Material(
      color: colors.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(target.icon, size: 17, color: colors.primary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${target.category} · ${target.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: '查看${target.name}详情',
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colors.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EntityReviewTripLink extends StatelessWidget {
  const _EntityReviewTripLink({required this.trip, this.roleLabel, this.onTap});

  final TripRecord trip;
  final String? roleLabel;
  final void Function(TripRecord trip)? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final summary = [
      _formatTripDate(trip.departureTime),
      trip.trainNumber,
      '${trip.fromStation} → ${trip.toStation}',
    ].where((part) => part.isNotEmpty).join(' · ');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      leading: const Icon(Icons.confirmation_number_outlined, size: 18),
      title: Text(
        roleLabel ?? summary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: colors.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: roleLabel == null
          ? null
          : Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
      onTap: onTap == null ? null : () => onTap!(trip),
      trailing: onTap == null
          ? null
          : const Icon(Icons.chevron_right_rounded, size: 20),
    );
  }
}

class EntityReviewTarget {
  const EntityReviewTarget(this.icon, this.category, this.name);

  final IconData icon;
  final String category;
  final String name;
}

EntityReviewTarget entityReviewTarget(EntityReview review) {
  final key = review.entityKey.trim();
  final name = key.isEmpty ? '未记录' : key;
  return switch (review.reviewType) {
    'station' => EntityReviewTarget(Icons.train_outlined, '车站服务', name),
    'transfer' => EntityReviewTarget(Icons.swap_horiz, '车站换乘', name),
    'route' => EntityReviewTarget(Icons.route_outlined, '线路', name),
    'company' => EntityReviewTarget(Icons.business_outlined, '承运单位服务', name),
    'meal' => EntityReviewTarget(Icons.restaurant_outlined, '餐饮服务', name),
    'rollingStock' => EntityReviewTarget(
      Icons.directions_railway_outlined,
      '车型体验',
      name,
    ),
    'train' => EntityReviewTarget(
      Icons.confirmation_number_outlined,
      '车次体验',
      name,
    ),
    _ => EntityReviewTarget(
      Icons.rate_review_outlined,
      review.entityType.trim().isEmpty ? '行程评价' : review.entityType,
      name,
    ),
  };
}

String _reviewRouteRange(
  EntityReview review,
  TripRecord? primary,
  String routeName,
) {
  final fromStation = review.routeFromStation?.trim() ?? '';
  final toStation = review.routeToStation?.trim() ?? '';
  if (fromStation.isNotEmpty && toStation.isNotEmpty) {
    return '$fromStation→$toStation';
  }
  return primary == null ? '' : _routeRange(primary, routeName);
}

String _routeRange(TripRecord trip, String route) {
  final segment = trip.viaRouteSegments.where(
    (value) => _normalize(value.routeName) == _normalize(route),
  );
  if (segment.isEmpty) return '${trip.fromStation}→${trip.toStation}';
  final first = segment.first;
  final last = segment.last;
  return '${first.fromStation}→${last.toStation}';
}

String _reviewExtra(EntityReview review) {
  final parts = <String>[];
  if (review.transferMinutes != null) {
    parts.add('换乘 ${review.transferMinutes} 分钟');
  }
  if (review.dish?.trim().isNotEmpty == true) {
    parts.add('菜品：${review.dish!.trim()}');
  }
  if (review.price != null) {
    parts.add('¥${review.price!.toStringAsFixed(2)}');
  }
  return parts.join(' · ');
}

TripRecord? _localTripForTicket(Iterable<TripRecord> trips, int? ticketId) {
  if (ticketId == null) return null;
  for (final trip in trips) {
    if (trip.ticketId == ticketId) return trip;
  }
  return null;
}

String _formatReviewDate(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return value;
  return _formatTripDate(date);
}

String _formatTripDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _formatTime(DateTime? value) => value == null
    ? '未记录'
    : '${value.hour.toString().padLeft(2, '0')}:'
          '${value.minute.toString().padLeft(2, '0')}';

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
