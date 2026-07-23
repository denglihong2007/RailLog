import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/models/achievement_engine.dart';
import 'package:raillog/src/models/dashboard_unlock_entry.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/trip_record.dart';

class TripDashboardStats {
  const TripDashboardStats({
    required this.tripCount,
    required this.totalMileage,
    required this.totalCost,
    required this.maxMileage,
    required this.maxCost,
    required this.totalDuration,
    required this.maxDuration,
    required this.allTrips,
    required this.routeUnlocks,
    required this.trainUnlocks,
    required this.rollingStockUnlocks,
    required this.companyUnlocks,
    required this.stationUnlocks,
    required this.achievements,
    required this.firstRecordAt,
    required this.lastRecordAt,
  });

  factory TripDashboardStats.empty({
    List<DashboardTripEntry> allTrips = const [],
  }) => TripDashboardStats(
    tripCount: 0,
    totalMileage: 0,
    totalCost: 0,
    maxMileage: 0,
    maxCost: 0,
    totalDuration: Duration.zero,
    maxDuration: Duration.zero,
    allTrips: allTrips,
    routeUnlocks: [],
    trainUnlocks: [],
    rollingStockUnlocks: [],
    companyUnlocks: [],
    stationUnlocks: [],
    achievements: buildDashboardAchievements(const []),
    firstRecordAt: null,
    lastRecordAt: null,
  );

  factory TripDashboardStats.fromTrips(Iterable<TripRecord> trips) {
    final allRecords = trips.toList()
      ..sort((a, b) {
        final byDeparture = a.departureTime.compareTo(b.departureTime);
        return byDeparture != 0 ? byDeparture : a.id.compareTo(b.id);
      });
    final allTrips = List<DashboardTripEntry>.unmodifiable(
      allRecords.reversed.map(DashboardTripEntry.fromTrip),
    );
    final railTrips = allRecords.where((trip) => trip.isRailTrip).toList();
    if (railTrips.isEmpty) return TripDashboardStats.empty(allTrips: allTrips);

    final routeUnlocks = <String, DashboardUnlockEntry>{};
    final trainUnlocks = <String, DashboardUnlockEntry>{};
    final rollingStockUnlocks = <String, DashboardUnlockEntry>{};
    final companyUnlocks = <String, DashboardUnlockEntry>{};
    final stationUnlocks = <String, DashboardUnlockEntry>{};
    var totalMileage = 0.0;
    var totalCost = 0.0;
    var maxMileage = 0.0;
    var maxCost = 0.0;
    var totalDuration = Duration.zero;
    var maxDuration = Duration.zero;

    for (final trip in railTrips) {
      totalMileage += trip.mileageKm;
      totalCost += trip.price;
      if (trip.mileageKm > maxMileage) maxMileage = trip.mileageKm;
      if (trip.price > maxCost) maxCost = trip.price;

      _recordUnlock(trainUnlocks, trip.trainNumber, trip);
      _recordUnlock(
        rollingStockUnlocks,
        _rollingStockModel(trip.rollingStock),
        trip,
      );
      _recordUnlock(companyUnlocks, trip.companyName, trip);
      _recordUnlock(
        stationUnlocks,
        trip.fromStation,
        trip,
        action: DashboardUnlockAction.departStation,
      );
      _recordUnlock(
        stationUnlocks,
        trip.toStation,
        trip,
        unlockTime: trip.arrivalTime ?? trip.departureTime,
        action: DashboardUnlockAction.arriveStation,
      );
      for (final routeName in {
        ...trip.viaRouteSegments.map((segment) => segment.routeName.trim()),
      }) {
        _recordUnlock(routeUnlocks, routeName, trip);
      }

      final arrivalTime = trip.arrivalTime;
      if (arrivalTime != null && !arrivalTime.isBefore(trip.departureTime)) {
        final duration = arrivalTime.difference(trip.departureTime);
        totalDuration += duration;
        if (duration > maxDuration) maxDuration = duration;
      }
    }

    return TripDashboardStats(
      tripCount: railTrips.length,
      totalMileage: totalMileage,
      totalCost: totalCost,
      maxMileage: maxMileage,
      maxCost: maxCost,
      totalDuration: totalDuration,
      maxDuration: maxDuration,
      allTrips: allTrips,
      routeUnlocks: _newestFirst(routeUnlocks.values),
      trainUnlocks: _newestFirst(trainUnlocks.values),
      rollingStockUnlocks: _newestFirst(rollingStockUnlocks.values),
      companyUnlocks: _newestFirst(companyUnlocks.values),
      stationUnlocks: _newestFirst(stationUnlocks.values),
      achievements: buildDashboardAchievements(railTrips),
      firstRecordAt: railTrips.first.departureTime,
      lastRecordAt: railTrips.last.departureTime,
    );
  }

  final int tripCount;
  final double totalMileage;
  final double totalCost;
  final double maxMileage;
  final double maxCost;
  final Duration totalDuration;
  final Duration maxDuration;
  final List<DashboardTripEntry> allTrips;
  final List<DashboardUnlockEntry> routeUnlocks;
  final List<DashboardUnlockEntry> trainUnlocks;
  final List<DashboardUnlockEntry> rollingStockUnlocks;
  final List<DashboardUnlockEntry> companyUnlocks;
  final List<DashboardUnlockEntry> stationUnlocks;
  final List<DashboardAchievement> achievements;
  final DateTime? firstRecordAt;
  final DateTime? lastRecordAt;

  int get routeCount => routeUnlocks.length;
  int get trainCount => trainUnlocks.length;
  int get rollingStockCount => rollingStockUnlocks.length;
  int get companyCount => companyUnlocks.length;
  int get stationCount => stationUnlocks.length;
}

List<DashboardUnlockEntry> _newestFirst(
  Iterable<DashboardUnlockEntry> entries,
) {
  final result = entries.toList()
    ..sort((a, b) {
      final byUnlockTime = b.unlockTime.compareTo(a.unlockTime);
      return byUnlockTime != 0 ? byUnlockTime : a.name.compareTo(b.name);
    });
  return List.unmodifiable(result);
}

String _rollingStockModel(String? rawValue) {
  final value = rawValue?.trim() ?? '';
  final emuMatch = RegExp(
    r'^([A-Z][A-Z0-9-]*)-\d{4}(?:&\d{4})*$',
    caseSensitive: false,
  ).firstMatch(value);
  if (emuMatch != null) return emuMatch.group(1)!.trim();

  final conventionalMatch = RegExp(
    r'^([A-Z][A-Z0-9-]*)\s+\d{6}$',
    caseSensitive: false,
  ).firstMatch(value);
  if (conventionalMatch != null) {
    return conventionalMatch.group(1)!.trim();
  }
  return value;
}

void _recordUnlock(
  Map<String, DashboardUnlockEntry> unlocks,
  String? rawName,
  TripRecord trip, {
  DateTime? unlockTime,
  DashboardUnlockAction action = DashboardUnlockAction.ride,
}) {
  final name = rawName?.trim() ?? '';
  if (name.isEmpty) return;
  final existing = unlocks[name];
  unlocks[name] = existing == null
      ? DashboardUnlockEntry.fromTrip(
          name: name,
          trip: trip,
          unlockTime: unlockTime,
          action: action,
        )
      : existing.registerTrip(trip, unlockTime: unlockTime, action: action);
}
