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
        final sourceTrips = snapshot.data!.trips;
        final trips = [
          ...sourceTrips.where((trip) => trip.isCurrentUser),
          ...sourceTrips.where((trip) => !trip.isCurrentUser),
        ];
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
                  _AchievementTripRow(trip: trips[index]),
            ),
          ),
        );
      },
    ),
  );
}

class _AchievementTripRow extends StatelessWidget {
  const _AchievementTripRow({required this.trip});

  final AchievementUnlockTrip trip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: trip.isCurrentUser
          ? colors.primaryContainer
          : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: _AchievementTripAvatar(trip: trip),
        title: Text(trip.displayName),
        subtitle: Text(
          '${_date(trip.occurredAt)} · ${_trainLabel(trip.trainNumber)}',
        ),
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

class _AchievementTripAvatar extends StatelessWidget {
  const _AchievementTripAvatar({required this.trip});

  final AchievementUnlockTrip trip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final avatarPadding = trip.isCurrentUser ? 2.0 : 4.0;
    return Container(
      width: 48,
      height: 48,
      padding: EdgeInsets.all(avatarPadding),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: trip.isCurrentUser ? colors.primary : colors.outlineVariant,
          width: trip.isCurrentUser ? 3 : 1,
        ),
      ),
      child: CachedAvatar(
        name: trip.displayName,
        imageUrl: trip.avatarUrl,
        size: 48 - avatarPadding * 2,
        backgroundColor: colors.secondaryContainer,
      ),
    );
  }
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _trainLabel(String value) {
  final trainNumber = value.trim();
  return trainNumber.isEmpty ? '未填写车次' : trainNumber;
}
