import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/achievement_engine.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/models/trip_record.dart';

void main() {
  test('慢慢旅途由第 10 次纯数字车次解锁', () {
    final numericTrips = List.generate(
      10,
      (index) => _trip(id: index + 1, trainNumber: '${1000 + index}'),
    );
    final mixed = _trip(id: 20, trainNumber: 'G123');

    expect(
      _achievement([
        ...numericTrips.take(9),
        mixed,
      ], DashboardAchievementKind.tenNumericTrains).isUnlocked,
      isFalse,
    );
    expect(
      _achievement(
        numericTrips,
        DashboardAchievementKind.tenNumericTrains,
      ).unlockedBy?.id,
      10,
    );
  });

  test('夕发朝至要求夜间发车、早间到达和卧铺', () {
    final wrongSeat = _trip(
      id: 1,
      departureTime: DateTime(2026, 1, 1, 18),
      arrivalTime: DateTime(2026, 1, 2, 5),
      seatType: '硬座',
    );
    final matching = _trip(
      id: 2,
      departureTime: DateTime(2026, 1, 2, 23, 59),
      arrivalTime: DateTime(2026, 1, 3, 11),
      seatType: '软卧下铺',
    );

    expect(
      _achievement([
        wrongSeat,
      ], DashboardAchievementKind.overnightSleeper).isUnlocked,
      isFalse,
    );
    expect(
      _achievement([
        wrongSeat,
        matching,
      ], DashboardAchievementKind.overnightSleeper).unlockedBy?.id,
      matching.id,
    );
  });

  test('辗转挪移要求连续三次同站换乘且每次不超过三小时', () {
    final chain = [
      _trip(
        id: 1,
        fromStation: 'A',
        toStation: 'B',
        departureTime: DateTime(2026, 1, 1, 7),
        arrivalTime: DateTime(2026, 1, 1, 9),
      ),
      _trip(
        id: 2,
        fromStation: 'B站',
        toStation: 'C',
        departureTime: DateTime(2026, 1, 1, 10),
        arrivalTime: DateTime(2026, 1, 1, 12),
      ),
      _trip(
        id: 3,
        fromStation: 'C',
        toStation: 'D站',
        departureTime: DateTime(2026, 1, 1, 14),
        arrivalTime: DateTime(2026, 1, 1, 15),
      ),
      _trip(
        id: 4,
        fromStation: 'D',
        toStation: 'E',
        departureTime: DateTime(2026, 1, 1, 18),
        arrivalTime: DateTime(2026, 1, 1, 19),
      ),
    ];

    expect(
      _achievement(
        chain.take(3).toList(),
        DashboardAchievementKind.tripleTransfer,
      ).isUnlocked,
      isFalse,
    );
    expect(
      _achievement(
        chain,
        DashboardAchievementKind.tripleTransfer,
      ).unlockedBy?.id,
      4,
    );

    final brokenChain = [...chain];
    brokenChain[3] = _trip(
      id: 5,
      fromStation: 'D',
      toStation: 'E',
      departureTime: DateTime(2026, 1, 1, 18, 1),
      arrivalTime: DateTime(2026, 1, 1, 19),
    );
    expect(
      _achievement(
        brokenChain,
        DashboardAchievementKind.tripleTransfer,
      ).isUnlocked,
      isFalse,
    );
  });

  test('天涯海角和四大名北按实际探访解锁', () {
    final famousNorthTrips = [
      _arrivingTrip(id: 1, station: '阳泉北站'),
      _arrivingTrip(id: 2, station: '盘锦北'),
      _arrivingTrip(id: 3, station: '孝感北站'),
      _trip(id: 4, toStation: '邵阳北站'),
    ];

    expect(
      _achievement([
        _trip(id: 10, fromStation: '天涯海角站'),
      ], DashboardAchievementKind.endsOfTheEarth).isUnlocked,
      isTrue,
    );
    expect(
      _achievement(
        famousNorthTrips,
        DashboardAchievementKind.fourFamousNorths,
      ).isUnlocked,
      isFalse,
    );
    final finalVisit = _arrivingTrip(id: 5, station: '邵阳北站');
    expect(
      _achievement([
        ...famousNorthTrips,
        finalVisit,
      ], DashboardAchievementKind.fourFamousNorths).unlockedBy?.id,
      finalVisit.id,
    );
  });

  test('青春没有售价要求硬座实际到达拉萨', () {
    final notArrived = _trip(id: 1, toStation: '拉萨站', seatType: '硬座');
    final wrongSeat = _arrivingTrip(id: 2, station: '拉萨', seatType: '硬卧');
    final matching = _arrivingTrip(id: 3, station: '拉萨站', seatType: '硬座');

    expect(
      _achievement([
        notArrived,
        wrongSeat,
      ], DashboardAchievementKind.youthPriceless).isUnlocked,
      isFalse,
    );
    expect(
      _achievement([
        notArrived,
        wrongSeat,
        matching,
      ], DashboardAchievementKind.youthPriceless).unlockedBy?.id,
      matching.id,
    );
  });

  test('已解锁成就稳定排在未解锁成就之前且删除烂柯之人', () {
    final achievements = buildDashboardAchievements([
      _trip(id: 1, fromStation: '天涯海角'),
      _arrivingTrip(id: 2, station: '拉萨', seatType: '硬座'),
    ]);
    final firstLocked = achievements.indexWhere(
      (achievement) => !achievement.isUnlocked,
    );

    expect(
      achievements.take(firstLocked).every((item) => item.isUnlocked),
      isTrue,
    );
    expect(
      achievements.skip(firstLocked).every((item) => !item.isUnlocked),
      isTrue,
    );
    expect(
      achievements.where((item) => item.isUnlocked).map((item) => item.kind),
      containsAllInOrder([
        DashboardAchievementKind.endsOfTheEarth,
        DashboardAchievementKind.youthPriceless,
      ]),
    );
    expect(achievements.map((item) => item.title), isNot(contains('烂柯之人')));
  });
}

DashboardAchievement _achievement(
  List<TripRecord> trips,
  DashboardAchievementKind kind,
) => buildDashboardAchievements(
  trips,
).singleWhere((achievement) => achievement.kind == kind);

TripRecord _arrivingTrip({
  required int id,
  required String station,
  String? seatType,
}) => _trip(
  id: id,
  toStation: station,
  seatType: seatType,
  arrivalTime: DateTime(2026, 1, 1).add(Duration(days: id, hours: 10)),
);

TripRecord _trip({
  required int id,
  String? trainNumber,
  String fromStation = '北京',
  String toStation = '上海',
  DateTime? departureTime,
  DateTime? arrivalTime,
  String? seatType,
}) => TripRecord(
  id: id,
  trainNumber: trainNumber ?? 'G$id',
  fromStation: fromStation,
  toStation: toStation,
  departureTime:
      departureTime ?? DateTime(2026, 1, 1).add(Duration(days: id, hours: 8)),
  arrivalTime: arrivalTime,
  seatType: seatType,
  viaRouteSegments: const [],
);
