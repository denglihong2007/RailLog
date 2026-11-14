import 'package:flutter/material.dart';
import 'package:raillog/src/models/achievement_unlock_trip.dart';
import 'package:raillog/src/pages/home_page.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/services/achievement_unlock_service.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/cached_avatar.dart';
import 'package:raillog/src/widgets/leaderboard_row.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

class AchievementUnlockTripsPage extends StatefulWidget {
  const AchievementUnlockTripsPage({
    super.key,
    required this.achievementId,
    required this.title,
  });

  final String achievementId;
  final String title;

  @override
  State<AchievementUnlockTripsPage> createState() =>
      _AchievementUnlockTripsPageState();
}

class _AchievementUnlockTripsPageState
    extends State<AchievementUnlockTripsPage> {
  late Future<AchievementUnlockTrips> _future;

  @override
  void initState() {
    super.initState();
    _future = AchievementUnlockService.fetch(widget.achievementId);
  }

  Future<void> _retry() async {
    final future = AchievementUnlockService.fetch(widget.achievementId);
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.title} · 解锁行程')),
    body: FutureBuilder<AchievementUnlockTrips>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: FilledButton.tonalIcon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
              label: const Text('加载失败，重试'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final ranking = snapshot.data!.ranking;
        if (ranking.isEmpty) {
          return const Center(child: Text('暂无解锁行程'));
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.contentMaxWidth,
            ),
            child: ListView.separated(
              padding: AppSpacing.page,
              itemCount: ranking.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = ranking[index];
                return AchievementTripRow(trip: entry.trip, rank: entry.rank);
              },
            ),
          ),
        );
      },
    ),
  );
}

class AchievementTripRow extends StatelessWidget {
  const AchievementTripRow({
    super.key,
    required this.trip,
    this.rank,
    this.highlight = false,
  });

  final AchievementUnlockTrip trip;

  /// 经验随进度变化的成就才有名次；其余只沿用排行榜版式。
  final int? rank;

  /// 实体详情页用它标出严格匹配的行程。
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LeaderboardRow(
      rank: rank,
      avatar: _AchievementTripAvatar(trip: trip),
      title: trip.displayName,
      subtitle: _subtitle(trip),
      value: rank == null ? null : '${trip.experience} XP',
      color: highlight ? colors.primaryContainer : null,
      onTap: () => _openTrip(context),
    );
  }

  /// 自己的行程走本地详情（可编辑、删除）；别人的只读。
  Future<void> _openTrip(BuildContext context) async {
    final navigator = Navigator.of(context);
    if (trip.isCurrentUser) {
      final local = await DbHelper.instance.getTripByTicketId(trip.ticketId);
      if (local != null) {
        navigator.push(
          m3PageRoute(builder: (_) => TripRecordDetailsPage(tripId: local.id)),
        );
        return;
      }
    }
    navigator.push(
      m3PageRoute(
        builder: (_) => TripRecordDetailsPage.public(
          ticketId: trip.ticketId,
          onOwnerTap: () => navigator.push(
            m3PageRoute(builder: (_) => PublicUserPage(userId: trip.userId)),
          ),
        ),
      ),
    );
  }
}

class _AchievementTripAvatar extends StatelessWidget {
  const _AchievementTripAvatar({required this.trip});

  final AchievementUnlockTrip trip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CachedAvatar(
      name: trip.displayName,
      imageUrl: trip.avatarUrl,
      size: 40,
      backgroundColor: colors.secondaryContainer,
    );
  }
}

String _subtitle(AchievementUnlockTrip trip) {
  final head = '${_date(trip.occurredAt)} · ${_trainLabel(trip.trainNumber)}';
  final route = _routeLabel(trip);
  return route.isEmpty ? head : '$head · $route';
}

String _routeLabel(AchievementUnlockTrip trip) {
  final from = trip.fromStation.trim();
  final to = trip.toStation.trim();
  if (from.isEmpty && to.isEmpty) return '';
  if (from.isEmpty) return '→ $to';
  if (to.isEmpty) return '$from →';
  return '$from → $to';
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _trainLabel(String value) {
  final trainNumber = value.trim();
  return trainNumber.isEmpty ? '未填写车次' : trainNumber;
}
