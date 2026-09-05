import 'package:flutter/material.dart';
import 'package:raillog/src/models/achievement_unlock_trip.dart';
import 'package:raillog/src/pages/home_page.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/services/achievement_unlock_service.dart';
import 'package:raillog/src/widgets/cached_avatar.dart';
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
        final trips = snapshot.data!.trips;
        if (trips.isEmpty) {
          return const Center(child: Text('暂无解锁行程'));
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: trips.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _UnlockTripCard(trip: trips[index]),
            ),
          ),
        );
      },
    ),
  );
}

class _UnlockTripCard extends StatelessWidget {
  const _UnlockTripCard({required this.trip});

  final AchievementUnlockTrip trip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: trip.isCurrentUser
          ? colors.primaryContainer
          : colors.surfaceContainerLow,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CachedAvatar(
          name: trip.displayName,
          imageUrl: trip.avatarUrl,
          size: 44,
        ),
        title: Row(
          children: [
            Expanded(child: Text(trip.displayName)),
            if (trip.isCurrentUser)
              Icon(Icons.person, size: 18, color: colors.primary),
          ],
        ),
        subtitle: Text(
          '${_date(trip.occurredAt)} · ${trip.trainNumber.trim().isEmpty ? '未填写车次' : trip.trainNumber}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          m3PageRoute(
            builder: (_) => TripRecordDetailsPage.public(
              ticketId: trip.ticketId,
              onOwnerTap: () => Navigator.of(context).push(
                m3PageRoute(
                  builder: (_) => PublicUserPage(userId: trip.userId),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
