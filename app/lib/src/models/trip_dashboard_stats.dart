import 'package:raillog/src/models/dashboard_unlock_entry.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/services/train_service.dart';

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
    required this.firstRecordAt,
    required this.lastRecordAt,
    required this.routePairUnlocks,
    required this.cityUnlocks,
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
    firstRecordAt: null,
    lastRecordAt: null,
    routePairUnlocks: const [],
    cityUnlocks: const [],
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
    final routePairUnlocks = <String, DashboardUnlockEntry>{};
    final cityUnlocks = <String, DashboardUnlockEntry>{};
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
      for (final model in rollingStockModelCodes(trip.rollingStock)) {
        _recordUnlock(rollingStockUnlocks, model, trip);
      }
      _recordUnlock(companyUnlocks, trip.companyName, trip);
      _recordUnlock(
        stationUnlocks,
        trip.fromStation,
        trip,
        action: DashboardUnlockAction.departStation,
      );
      final from = trip.fromStation.trim();
      final to = trip.toStation.trim();
      if (from.isNotEmpty && to.isNotEmpty && from != to) {
        final pair = [from, to]..sort();
        _recordUnlock(routePairUnlocks, '${pair[0]} <-> ${pair[1]}', trip);
      }
      final cityMap = TrainService.stationCities;
      final fromCity = _cityForStation(cityMap, from);
      final toCity = _cityForStation(cityMap, to);
      if (fromCity != null && fromCity.isNotEmpty) {
        _recordUnlock(cityUnlocks, fromCity, trip);
      }
      if (toCity != null && toCity.isNotEmpty) {
        _recordUnlock(cityUnlocks, toCity, trip);
      }
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
      firstRecordAt: railTrips.first.departureTime,
      lastRecordAt: railTrips.last.departureTime,
      routePairUnlocks: _newestFirst(routePairUnlocks.values),
      cityUnlocks: _newestFirst(cityUnlocks.values),
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
  final DateTime? firstRecordAt;
  final DateTime? lastRecordAt;
  final List<DashboardUnlockEntry> routePairUnlocks;
  final List<DashboardUnlockEntry> cityUnlocks;

  int get routeCount => routeUnlocks.length;
  int get trainCount => trainUnlocks.length;
  int get rollingStockCount => rollingStockUnlocks.length;
  int get companyCount => companyUnlocks.length;
  int get stationCount => stationUnlocks.length;
  int get routePairCount => routePairUnlocks.length;
  int get cityCount => cityUnlocks.length;
}

String? _cityForStation(Map<String, String> cities, String station) {
  final direct = cities[station];
  if (direct != null) return direct;
  if (station.endsWith('站')) {
    return cities[station.substring(0, station.length - 1)];
  }
  return cities['$station站'];
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

String rollingStockModelCode(String? rawValue) {
  final models = rollingStockModelCodes(rawValue);
  return models.isEmpty ? '' : models.first;
}

List<String> rollingStockModelCodes(String? rawValue) {
  final value = rawValue?.trim() ?? '';
  if (value.isEmpty) return const [];

  return value
      .split('+')
      .map(_rollingStockModelCode)
      .where((model) => model.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

String _rollingStockModelCode(String component) {
  final value = component.trim();
  if (value.isEmpty) return '';

  // EMU notation: CR400BF-5033&5034. The four-digit numbers belong to the
  // model's vehicle numbers and are excluded from the statistics key.
  final emuMatch = RegExp(
    r'^(.+?)-\d{4}(?:&\d{4})*$',
    caseSensitive: false,
  ).firstMatch(value);
  if (emuMatch != null) return emuMatch.group(1)!.trim();

  // Conventional notation: HXD1D 0001&0002. A missing vehicle number is
  // valid, so a component without whitespace is already a model name.
  return value.split(RegExp(r'\s+')).first.trim();
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
