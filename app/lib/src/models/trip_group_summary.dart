import 'package:raillog/src/models/dashboard_trip_entry.dart';

/// 同名行程的聚合视图，供「全部行程」里的分组卡片使用。
///
/// 只在展示层聚合，不落库：分组关系就是每条行程上的 `groupName`。
class TripGroupSummary {
  TripGroupSummary._({
    required this.name,
    required this.trips,
    required this.earliestTrip,
    required this.latestArrivalTrip,
    required this.roundTripStation,
    required this.dominantSeatType,
    required this.hasMixedSeatTypes,
    required this.totalDuration,
    required this.totalMileageKm,
    required this.totalPrice,
  });

  factory TripGroupSummary.fromTrips(
    String name,
    List<DashboardTripEntry> trips,
  ) {
    if (trips.isEmpty) {
      throw ArgumentError.value(trips, 'trips', '分组至少需要一条行程');
    }

    final members = [...trips]
      ..sort((a, b) {
        final byDeparture = a.departureTime.compareTo(b.departureTime);
        return byDeparture != 0 ? byDeparture : a.id.compareTo(b.id);
      });

    final earliestTrip = members.first;
    var latestArrivalTrip = members.first;
    for (final trip in members.skip(1)) {
      final comparison = _effectiveArrival(
        trip,
      ).compareTo(_effectiveArrival(latestArrivalTrip));
      if (comparison > 0 ||
          (comparison == 0 && trip.id > latestArrivalTrip.id)) {
        latestArrivalTrip = trip;
      }
    }

    Duration? totalDuration;
    var totalMileageKm = 0.0;
    var totalPrice = 0.0;
    final seatCounts = <String, int>{};
    for (final trip in members) {
      final duration = trip.duration;
      if (duration != null) {
        totalDuration = (totalDuration ?? Duration.zero) + duration;
      }
      totalMileageKm += trip.mileageKm;
      totalPrice += trip.price;
      final seatType = trip.seatType?.trim() ?? '';
      if (seatType.isNotEmpty) {
        seatCounts.update(seatType, (count) => count + 1, ifAbsent: () => 1);
      }
    }

    String? dominantSeatType;
    var dominantSeatCount = 0;
    for (final entry in seatCounts.entries) {
      // 并列时取先出现的（成员已按出发时间排序），结果稳定。
      if (entry.value > dominantSeatCount) {
        dominantSeatCount = entry.value;
        dominantSeatType = entry.key;
      }
    }

    return TripGroupSummary._(
      name: name,
      trips: List.unmodifiable(members),
      earliestTrip: earliestTrip,
      latestArrivalTrip: latestArrivalTrip,
      roundTripStation: earliestTrip.fromStation == latestArrivalTrip.toStation
          ? _lastTurnaroundStation(members)
          : null,
      dominantSeatType: dominantSeatType,
      hasMixedSeatTypes: seatCounts.length > 1,
      totalDuration: totalDuration,
      totalMileageKm: totalMileageKm,
      totalPrice: totalPrice,
    );
  }

  final String name;

  /// 按出发时间升序（同一时刻按 id 升序）。
  final List<DashboardTripEntry> trips;

  /// 最早出发的那条，出发站与日期取自它。
  final DashboardTripEntry earliestTrip;

  /// 最晚到达的那条，到站取自它。
  final DashboardTripEntry latestArrivalTrip;

  /// 起终点相同时取代终到站的折返站；没有折返站时为 null。
  final String? roundTripStation;

  /// 组内出现次数最多的席别；一条都没填席别时为 null。
  final String? dominantSeatType;

  /// 组内是否出现了多种席别。
  final bool hasMixedSeatTypes;

  /// 所有成员时长之和；成员全部缺到达时间时为 null。
  final Duration? totalDuration;
  final double totalMileageKm;
  final double totalPrice;

  int get count => trips.length;

  String get fromStation => earliestTrip.fromStation;

  /// 起终点相同（往返）时用最后一个折返站，否则用最晚到达的站。
  String get toStation => roundTripStation ?? latestArrivalTrip.toStation;

  /// 出发站与最终到站相同，即一趟往返行程。
  bool get isRoundTrip =>
      earliestTrip.fromStation == latestArrivalTrip.toStation;

  /// 席别摘要：最多的席别，存在多种席别时追加「等」。
  String? get seatSummary {
    final seatType = dominantSeatType;
    if (seatType == null) return null;
    return hasMixedSeatTypes ? '$seatType等' : seatType;
  }

  DateTime get earliestDeparture => earliestTrip.departureTime;

  /// 最晚到达那趟的到达时间；那趟没填到达时间时返回 null。
  DateTime? get latestArrival => latestArrivalTrip.arrivalTime;

  /// 排序用：没有到达时间的成员按出发时间排，避免整组都缺到达时间时失序。
  static DateTime _effectiveArrival(DashboardTripEntry trip) =>
      trip.arrivalTime ?? trip.departureTime;

  /// 按出发顺序找到最后一次「折返」的站：后一趟直接回到前一趟的始发站。
  static String? _lastTurnaroundStation(List<DashboardTripEntry> members) {
    String? station;
    for (var index = 0; index + 1 < members.length; index++) {
      final current = members[index];
      final next = members[index + 1];
      if (next.toStation == current.fromStation &&
          current.toStation != current.fromStation) {
        station = current.toStation;
      }
    }
    return station;
  }
}
