import 'package:raillog/src/models/trip_record.dart';

enum DashboardUnlockAction { ride, departStation, arriveStation }

class DashboardUnlockEntry {
  const DashboardUnlockEntry({
    required this.name,
    required this.trainNumber,
    required this.unlockTime,
    required this.action,
    required this.fromStation,
    required this.toStation,
    required this.tripIds,
  });

  factory DashboardUnlockEntry.fromTrip({
    required String name,
    required TripRecord trip,
    DateTime? unlockTime,
    DashboardUnlockAction action = DashboardUnlockAction.ride,
  }) {
    return DashboardUnlockEntry(
      name: name,
      trainNumber: trip.trainNumber,
      unlockTime: unlockTime ?? trip.departureTime,
      action: action,
      fromStation: trip.fromStation,
      toStation: trip.toStation,
      tripIds: List<int>.unmodifiable([trip.id]),
    );
  }

  final String name;
  final String trainNumber;
  final DateTime unlockTime;
  final DashboardUnlockAction action;
  final String fromStation;
  final String toStation;
  final List<int> tripIds;

  int get tripCount => tripIds.length;

  DashboardUnlockEntry registerTrip(
    TripRecord trip, {
    DateTime? unlockTime,
    DashboardUnlockAction action = DashboardUnlockAction.ride,
  }) {
    final eventTime = unlockTime ?? trip.departureTime;
    final updatedTripIds = List<int>.unmodifiable([...tripIds, trip.id]);
    if (eventTime.isBefore(this.unlockTime)) {
      return DashboardUnlockEntry(
        name: name,
        trainNumber: trip.trainNumber,
        unlockTime: eventTime,
        action: action,
        fromStation: trip.fromStation,
        toStation: trip.toStation,
        tripIds: updatedTripIds,
      );
    }
    return DashboardUnlockEntry(
      name: name,
      trainNumber: trainNumber,
      unlockTime: this.unlockTime,
      action: this.action,
      fromStation: fromStation,
      toStation: toStation,
      tripIds: updatedTripIds,
    );
  }
}
