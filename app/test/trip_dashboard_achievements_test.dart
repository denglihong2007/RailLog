import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/models/trip_dashboard_stats.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';

void main() {
  test('unlocks free meal with the earliest qualifying business-seat trip', () {
    final stats = TripDashboardStats.fromTrips([
      _trip(
        id: 2,
        trainNumber: 'G2',
        departure: DateTime(2026, 1, 2, 17),
        arrival: DateTime(2026, 1, 2, 18),
        mileage: 50,
        seatType: '商务座',
      ),
      _trip(
        id: 1,
        trainNumber: 'G1',
        departure: DateTime(2026, 1, 1, 11),
        arrival: DateTime(2026, 1, 1, 12),
        mileage: 30,
        seatType: '商务座',
      ),
    ]);

    final achievement = _achievement(stats, DashboardAchievementKind.freeMeal);
    expect(achievement.unlockedBy?.id, 1);
  });

  test('unlocks overnight seat only when the trip covers 00:00-06:00', () {
    final stats = TripDashboardStats.fromTrips([
      _trip(
        id: 1,
        trainNumber: 'K1',
        departure: DateTime(2026, 1, 1, 23),
        arrival: DateTime(2026, 1, 2, 6),
        seatType: '硬座',
      ),
    ]);

    expect(
      _achievement(
        stats,
        DashboardAchievementKind.overnightSeat,
      ).unlockedBy?.id,
      1,
    );
  });

  test('unlocks tight transfer on the outgoing trip under ten minutes', () {
    final stats = TripDashboardStats.fromTrips([
      _trip(
        id: 1,
        trainNumber: 'G1',
        from: '甲站',
        to: '中转站',
        departure: DateTime(2026, 1, 1, 8),
        arrival: DateTime(2026, 1, 1, 9),
      ),
      _trip(
        id: 2,
        trainNumber: 'G2',
        from: '中转站',
        to: '乙站',
        departure: DateTime(2026, 1, 1, 9, 9),
        arrival: DateTime(2026, 1, 1, 10),
      ),
    ]);

    expect(
      _achievement(
        stats,
        DashboardAchievementKind.tightTransfer,
      ).unlockedBy?.id,
      2,
    );
  });

  test('includes all achievements and unlocks consecutive travel streaks', () {
    final trips = List.generate(7, (index) {
      final departure = DateTime(2026, 2, index + 1, 8);
      return _trip(
        id: index + 1,
        trainNumber: 'G${index + 1}',
        departure: departure,
        arrival: departure.add(const Duration(hours: 1)),
      );
    });
    final stats = TripDashboardStats.fromTrips(trips);

    expect(stats.achievements, hasLength(22));
    expect(
      _achievement(
        stats,
        DashboardAchievementKind.sevenDayStreak,
      ).unlockedBy?.id,
      7,
    );
    expect(
      _achievement(stats, DashboardAchievementKind.thirtyDayStreak).isUnlocked,
      isFalse,
    );
  });

  test('unlocks all long single-trip duration achievements', () {
    final stats = TripDashboardStats.fromTrips([
      _trip(
        id: 1,
        trainNumber: 'K1',
        departure: DateTime(2026, 1, 1),
        arrival: DateTime(2026, 1, 4),
      ),
    ]);

    expect(
      _achievement(stats, DashboardAchievementKind.duration24Hours).isUnlocked,
      isTrue,
    );
    expect(
      _achievement(stats, DashboardAchievementKind.duration48Hours).isUnlocked,
      isTrue,
    );
    expect(
      _achievement(stats, DashboardAchievementKind.duration72Hours).isUnlocked,
      isTrue,
    );
  });

  test('unlocks rolling-stock and seat collection achievements', () {
    const stocks = [
      '25B',
      '25Z',
      '25G',
      '25K',
      '25T',
      '25DT',
      'CRH1A',
      'CRH2A',
      'CRH3C',
      'CRH5A',
      'CRH6A',
      'CR200J',
      'CR300AF',
      'CR300BF',
      'CR400AF',
      'CR400BF',
      'CJ6',
      'CRH380A',
      'CRH380B',
      'CRH380C',
      'CRH380D',
    ];
    const seats = [
      '无座',
      '硬座',
      '软座',
      '一等座',
      '商务座',
      '硬卧',
      '软卧',
      '高级软卧',
      '动卧',
      '二等卧',
      '一等卧',
      '高级动卧',
    ];
    final count = stocks.length > seats.length ? stocks.length : seats.length;
    final stats = TripDashboardStats.fromTrips(
      List.generate(count, (index) {
        final departure = DateTime(2026, 3, 1).add(Duration(days: index));
        return _trip(
          id: index + 1,
          trainNumber: 'D${index + 1}',
          departure: departure,
          arrival: departure.add(const Duration(hours: 1)),
          rollingStock: stocks[index],
          seatType: seats[index % seats.length],
        );
      }),
    );

    expect(
      _achievement(stats, DashboardAchievementKind.all25Series).isUnlocked,
      isTrue,
    );
    expect(
      _achievement(stats, DashboardAchievementKind.allEmuSeries).isUnlocked,
      isTrue,
    );
    expect(
      _achievement(stats, DashboardAchievementKind.allSeatTypes).isUnlocked,
      isTrue,
    );
  });

  test('unlocks ticket, station and mileage accumulation achievements', () {
    final stats = TripDashboardStats.fromTrips(
      List.generate(100, (index) {
        final departure = DateTime(2025, 1, 1).add(Duration(days: index));
        return _trip(
          id: index + 1,
          trainNumber: 'K${index + 1}',
          from: '甲$index',
          to: '乙$index',
          departure: departure,
          arrival: departure.add(const Duration(hours: 1)),
          mileage: 1000,
        );
      }),
    );

    expect(
      _achievement(
        stats,
        DashboardAchievementKind.hundredTickets,
      ).unlockedBy?.id,
      100,
    );
    expect(
      _achievement(
        stats,
        DashboardAchievementKind.hundredStations,
      ).unlockedBy?.id,
      50,
    );
    expect(
      _achievement(
        stats,
        DashboardAchievementKind.hundredThousandKilometers,
      ).unlockedBy?.id,
      100,
    );
  });

  test(
    'unlocks special seat, time, airport, ferry and F-train achievements',
    () {
      final stats = TripDashboardStats.fromTrips([
        _trip(
          id: 1,
          trainNumber: 'K1',
          from: '美兰',
          to: '正定机场',
          departure: DateTime(2026, 1, 1, 2),
          arrival: DateTime(2026, 1, 1, 15),
          seatType: '无座',
        ),
        _trip(
          id: 2,
          trainNumber: 'G2',
          from: '正定机场',
          to: '大兴机场',
          departure: DateTime(2026, 1, 2, 8),
          arrival: DateTime(2026, 1, 2, 9),
          seatNumber: '3车18F号',
        ),
        _trip(
          id: 3,
          trainNumber: 'F1',
          departure: DateTime(2026, 1, 3, 8),
          arrival: DateTime(2026, 1, 3, 9),
          viaRouteSegments: const [
            ViaRouteSegment(
              routeName: '粤海轮渡线',
              fromStation: '海安南',
              toStation: '海口',
            ),
          ],
        ),
      ]);

      for (final kind in [
        DashboardAchievementKind.noSeat12Hours,
        DashboardAchievementKind.midnightBoarding,
        DashboardAchievementKind.wallFacingSeat,
        DashboardAchievementKind.airRail,
        DashboardAchievementKind.railFerry,
        DashboardAchievementKind.fTrain,
      ]) {
        expect(_achievement(stats, kind).isUnlocked, isTrue, reason: '$kind');
      }
    },
  );
}

DashboardAchievement _achievement(
  TripDashboardStats stats,
  DashboardAchievementKind kind,
) => stats.achievements.singleWhere((item) => item.kind == kind);

TripRecord _trip({
  required int id,
  required String trainNumber,
  String from = '甲站',
  String to = '乙站',
  required DateTime departure,
  required DateTime arrival,
  double mileage = 100,
  String seatType = '二等座',
  String? seatNumber,
  String? rollingStock,
  List<ViaRouteSegment> viaRouteSegments = const [],
}) {
  return TripRecord(
    id: id,
    trainNumber: trainNumber,
    fromStation: from,
    toStation: to,
    departureTime: departure,
    arrivalTime: arrival,
    mileageKm: mileage,
    viaRouteSegments: viaRouteSegments,
    seatType: seatType,
    seatNumber: seatNumber,
    rollingStock: rollingStock,
  );
}
