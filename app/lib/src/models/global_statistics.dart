import 'package:raillog/src/models/public_user_dashboard.dart';
import 'package:raillog/src/models/trip_record.dart';

class GlobalStatistics {
  const GlobalStatistics({
    required this.site,
    required this.users,
    required this.trips,
    required this.elements,
  });

  factory GlobalStatistics.fromJson(Map<String, dynamic> json) {
    return GlobalStatistics(
      site: SiteStatistics.fromJson(json['site'] as Map<String, dynamic>),
      users: UserLeaderboards.fromJson(json['users'] as Map<String, dynamic>),
      trips: TripLeaderboards.fromJson(json['trips'] as Map<String, dynamic>),
      elements: ElementLeaderboards.fromJson(
        json['elements'] as Map<String, dynamic>,
      ),
    );
  }

  final SiteStatistics site;
  final UserLeaderboards users;
  final TripLeaderboards trips;
  final ElementLeaderboards elements;
}

class SiteStatistics {
  const SiteStatistics({
    required this.total,
    required this.thisYear,
    required this.thisMonth,
    required this.thisWeek,
    required this.totalMetrics,
    required this.thisYearMetrics,
    required this.thisMonthMetrics,
    required this.thisWeekMetrics,
  });

  factory SiteStatistics.fromJson(Map<String, dynamic> json) {
    SitePeriodStatistics period(String key, String countKey) {
      final value = json[key];
      if (value is Map<String, dynamic>) {
        return SitePeriodStatistics.fromJson(value);
      }
      return SitePeriodStatistics.onlyTrips((json[countKey] as num).toInt());
    }

    return SiteStatistics(
      total: (json['total'] as num).toInt(),
      thisYear: (json['thisYear'] as num).toInt(),
      thisMonth: (json['thisMonth'] as num).toInt(),
      thisWeek: (json['thisWeek'] as num).toInt(),
      totalMetrics: period('totalMetrics', 'total'),
      thisYearMetrics: period('thisYearMetrics', 'thisYear'),
      thisMonthMetrics: period('thisMonthMetrics', 'thisMonth'),
      thisWeekMetrics: period('thisWeekMetrics', 'thisWeek'),
    );
  }

  final int total;
  final int thisYear;
  final int thisMonth;
  final int thisWeek;
  final SitePeriodStatistics totalMetrics;
  final SitePeriodStatistics thisYearMetrics;
  final SitePeriodStatistics thisMonthMetrics;
  final SitePeriodStatistics thisWeekMetrics;
}

class SitePeriodStatistics {
  const SitePeriodStatistics({
    required this.tripCount,
    required this.mileageKm,
    required this.durationSeconds,
    required this.spending,
  });

  const SitePeriodStatistics.onlyTrips(this.tripCount)
    : mileageKm = 0,
      durationSeconds = 0,
      spending = 0;

  factory SitePeriodStatistics.fromJson(Map<String, dynamic> json) =>
      SitePeriodStatistics(
        tripCount: (json['tripCount'] as num).toInt(),
        mileageKm: (json['mileageKm'] as num).toDouble(),
        durationSeconds: (json['durationSeconds'] as num).toDouble(),
        spending: (json['spending'] as num).toDouble(),
      );

  final int tripCount;
  final double mileageKm;
  final double durationSeconds;
  final double spending;
}

class UserRankingEntry {
  const UserRankingEntry({
    required this.rank,
    required this.user,
    required this.value,
  });

  factory UserRankingEntry.fromJson(Map<String, dynamic> json) =>
      UserRankingEntry(
        rank: (json['rank'] as num).toInt(),
        user: PublicUser.fromJson(json['user'] as Map<String, dynamic>),
        value: (json['value'] as num).toDouble(),
      );

  final int rank;
  final PublicUser user;
  final double value;
}

class UserLeaderboards {
  const UserLeaderboards({
    required this.totalSpending,
    required this.tripCount,
    required this.durationSeconds,
    required this.mileageKm,
  });

  factory UserLeaderboards.fromJson(Map<String, dynamic> json) =>
      UserLeaderboards(
        totalSpending: _users(json['totalSpending']),
        tripCount: _users(json['tripCount']),
        durationSeconds: _users(json['durationSeconds']),
        mileageKm: _users(json['mileageKm']),
      );

  final List<UserRankingEntry> totalSpending;
  final List<UserRankingEntry> tripCount;
  final List<UserRankingEntry> durationSeconds;
  final List<UserRankingEntry> mileageKm;
}

class TripRankingEntry {
  const TripRankingEntry({
    required this.rank,
    required this.user,
    required this.trip,
    required this.value,
  });

  factory TripRankingEntry.fromJson(Map<String, dynamic> json) {
    final user = PublicUser.fromJson(json['user'] as Map<String, dynamic>);
    return TripRankingEntry(
      rank: (json['rank'] as num).toInt(),
      user: user,
      trip: publicTripFromJson(json['trip'] as Map<String, dynamic>, user.id),
      value: (json['value'] as num).toDouble(),
    );
  }

  final int rank;
  final PublicUser user;
  final TripRecord trip;
  final double value;
}

class TripLeaderboards {
  const TripLeaderboards({
    required this.singleSpending,
    required this.mileageKm,
    required this.durationSeconds,
    required this.bestValueYuanPerKm,
    required this.luxuryYuanPerKm,
  });

  factory TripLeaderboards.fromJson(Map<String, dynamic> json) =>
      TripLeaderboards(
        singleSpending: _trips(json['singleSpending']),
        mileageKm: _trips(json['mileageKm']),
        durationSeconds: _trips(json['durationSeconds']),
        bestValueYuanPerKm: _trips(json['bestValueYuanPerKm']),
        luxuryYuanPerKm: _trips(json['luxuryYuanPerKm']),
      );

  final List<TripRankingEntry> singleSpending;
  final List<TripRankingEntry> mileageKm;
  final List<TripRankingEntry> durationSeconds;
  final List<TripRankingEntry> bestValueYuanPerKm;
  final List<TripRankingEntry> luxuryYuanPerKm;
}

class ElementRankingEntry {
  const ElementRankingEntry({
    required this.rank,
    required this.name,
    required this.value,
  });

  factory ElementRankingEntry.fromJson(Map<String, dynamic> json) =>
      ElementRankingEntry(
        rank: (json['rank'] as num).toInt(),
        name: json['name'] as String,
        value: (json['value'] as num).toInt(),
      );

  final int rank;
  final String name;
  final int value;
}

class ElementLeaderboards {
  const ElementLeaderboards({
    required this.stations,
    required this.routes,
    required this.trains,
  });

  factory ElementLeaderboards.fromJson(Map<String, dynamic> json) =>
      ElementLeaderboards(
        stations: _elements(json['stations']),
        routes: _elements(json['routes']),
        trains: _elements(json['trains']),
      );

  final List<ElementRankingEntry> stations;
  final List<ElementRankingEntry> routes;
  final List<ElementRankingEntry> trains;
}

List<UserRankingEntry> _users(Object? value) =>
    (value as List<dynamic>? ?? const [])
        .map((row) => UserRankingEntry.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);

List<TripRankingEntry> _trips(Object? value) =>
    (value as List<dynamic>? ?? const [])
        .map((row) => TripRankingEntry.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);

List<ElementRankingEntry> _elements(Object? value) =>
    (value as List<dynamic>? ?? const [])
        .map((row) => ElementRankingEntry.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
