import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/achievement_engine.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/models/railway_bureau.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';

void main() {
  test('新增成就沿用简洁的乘车条件描述', () {
    final achievements = buildDashboardAchievements(const []);
    final descriptions = {
      for (final achievement in achievements)
        achievement.kind: (achievement.title, achievement.requirement),
    };

    expect(descriptions[DashboardAchievementKind.commuterSpecial], (
      '牛马专列',
      '乘坐北京站或北京南站与上海虹桥站或上海站间全程经由京沪高铁的优选一等座、商务座、一等座或特等座',
    ));
    expect(descriptions[DashboardAchievementKind.grandSlam], (
      '大满贯',
      '分别乘坐全部铁路局担当的列车',
    ));
    expect(descriptions[DashboardAchievementKind.storedUpReward], (
      '厚积薄发',
      '使用积分兑换里程超过 50 公里的商务座或特等座车票',
    ));
    expect(descriptions[DashboardAchievementKind.spontaneousTrip], (
      '说走就走',
      '乘坐一次 Y 字头旅游列车',
    ));
    expect(descriptions[DashboardAchievementKind.redFootprints], (
      '红色足迹',
      '乘坐韶山南站至延安站的列车',
    ));
    expect(descriptions[DashboardAchievementKind.greatWallWatch], (
      '长城守望',
      '到访八达岭站或八达岭长城站',
    ));
    expect(descriptions[DashboardAchievementKind.icyWorld], (
      '冰天雪地',
      '在 12 月、1 月或 2 月到访根河站',
    ));
    expect(descriptions[DashboardAchievementKind.unnecessaryExtra], (
      '多此一举',
      '分 3 张车票接续乘坐同一列车',
    ));
    expect(descriptions[DashboardAchievementKind.blessChina], (
      '祝福祖国',
      '在 10 月 1 日乘坐列车',
    ));
  });

  test('牛马专列只按京沪全程站点、高等级席别和实际到达判断', () {
    final matching = _trip(
      id: 1,
      fromStation: '北京南站',
      toStation: '上海虹桥站',
      arrivalTime: DateTime(2026, 1, 1, 13),
      seatType: '优选一等座',
    );
    expect(
      _achievement([
        matching,
      ], DashboardAchievementKind.commuterSpecial).unlockedBy?.id,
      matching.id,
    );
    for (final trip in [
      _trip(
        id: 2,
        fromStation: '北京',
        toStation: '上海',
        arrivalTime: DateTime(2026, 1, 2, 13),
        seatType: '二等座',
      ),
      _trip(id: 3, fromStation: '北京', toStation: '上海', seatType: '商务座'),
    ]) {
      expect(
        _achievement([
          trip,
        ], DashboardAchievementKind.commuterSpecial).isUnlocked,
        isFalse,
      );
    }
  });

  test('大满贯按客运段所属路局累计并由最后一个路局解锁', () {
    final trips = <TripRecord>[];
    var id = 1;
    for (final entry in railwayBureauSegments.entries) {
      trips.add(_trip(id: id++, companyName: entry.value.first));
    }

    expect(
      _achievement(
        trips.take(trips.length - 1).toList(),
        DashboardAchievementKind.grandSlam,
      ).isUnlocked,
      isFalse,
    );
    expect(
      _achievement(trips, DashboardAchievementKind.grandSlam).unlockedBy?.id,
      trips.last.id,
    );
  });

  test('厚积薄发要求零票价、超过五十公里和指定席别', () {
    final matching = _trip(id: 1, mileageKm: 50.1, price: 0, seatType: '商务座');
    expect(
      _achievement([
        matching,
      ], DashboardAchievementKind.storedUpReward).isUnlocked,
      isTrue,
    );
    for (final trip in [
      _trip(id: 2, mileageKm: 50, price: 0, seatType: '特等座'),
      _trip(id: 3, mileageKm: 100, price: 1, seatType: '特等座'),
      _trip(id: 4, mileageKm: 100, price: 0, seatType: '一等座'),
    ]) {
      expect(
        _achievement([
          trip,
        ], DashboardAchievementKind.storedUpReward).isUnlocked,
        isFalse,
      );
    }
  });

  test('说走就走和红色足迹按完整车次与指定方向解锁', () {
    expect(
      _achievement([
        _trip(id: 1, trainNumber: 'y123'),
      ], DashboardAchievementKind.spontaneousTrip).isUnlocked,
      isTrue,
    );
    expect(
      _achievement([
        _trip(id: 2, trainNumber: 'GY123'),
      ], DashboardAchievementKind.spontaneousTrip).isUnlocked,
      isFalse,
    );

    final matching = _trip(
      id: 3,
      fromStation: '韶山南站',
      toStation: '延安站',
      arrivalTime: DateTime(2026, 1, 3, 18),
    );
    expect(
      _achievement([
        matching,
      ], DashboardAchievementKind.redFootprints).isUnlocked,
      isTrue,
    );
    expect(
      _achievement([
        _trip(
          id: 4,
          fromStation: '延安',
          toStation: '韶山南',
          arrivalTime: DateTime(2026, 1, 4, 18),
        ),
      ], DashboardAchievementKind.redFootprints).isUnlocked,
      isFalse,
    );
  });

  test('长城守望和冰天雪地按实际探访车站的日期解锁', () {
    expect(
      _achievement([
        _trip(id: 1, fromStation: '八达岭长城站'),
      ], DashboardAchievementKind.greatWallWatch).isUnlocked,
      isTrue,
    );
    expect(
      _achievement([
        _trip(
          id: 2,
          toStation: '根河站',
          departureTime: DateTime(2026, 1, 1, 20),
          arrivalTime: DateTime(2026, 1, 2, 8),
        ),
      ], DashboardAchievementKind.icyWorld).isUnlocked,
      isTrue,
    );
    expect(
      _achievement([
        _trip(
          id: 3,
          toStation: '根河',
          departureTime: DateTime(2026, 6, 1, 20),
          arrivalTime: DateTime(2026, 6, 2, 8),
        ),
      ], DashboardAchievementKind.icyWorld).isUnlocked,
      isFalse,
    );
  });

  test('多此一举要求三张票按站点和时间接续同一车次', () {
    final chain = [
      _trip(
        id: 1,
        trainNumber: 'G100',
        fromStation: 'A',
        toStation: 'B',
        departureTime: DateTime(2026, 1, 1, 8),
        arrivalTime: DateTime(2026, 1, 1, 9),
      ),
      _trip(
        id: 2,
        trainNumber: 'g100',
        fromStation: 'B站',
        toStation: 'C',
        departureTime: DateTime(2026, 1, 1, 9, 5),
        arrivalTime: DateTime(2026, 1, 1, 10),
      ),
      _trip(
        id: 3,
        trainNumber: 'G100',
        fromStation: 'C',
        toStation: 'D',
        departureTime: DateTime(2026, 1, 1, 10, 5),
        arrivalTime: DateTime(2026, 1, 1, 11),
      ),
    ];
    expect(
      _achievement(
        chain.take(2).toList(),
        DashboardAchievementKind.unnecessaryExtra,
      ).isUnlocked,
      isFalse,
    );
    expect(
      _achievement(
        chain,
        DashboardAchievementKind.unnecessaryExtra,
      ).unlockedBy?.id,
      chain.last.id,
    );

    final broken = [...chain];
    broken[2] = _trip(
      id: 4,
      trainNumber: 'G101',
      fromStation: 'C',
      toStation: 'D',
      departureTime: DateTime(2026, 1, 1, 10, 5),
    );
    expect(
      _achievement(
        broken,
        DashboardAchievementKind.unnecessaryExtra,
      ).isUnlocked,
      isFalse,
    );
  });

  test('祝福祖国覆盖十月一日出发或仍在途的列车', () {
    expect(
      _achievement([
        _trip(id: 1, departureTime: DateTime(2026, 10, 1, 8)),
      ], DashboardAchievementKind.blessChina).isUnlocked,
      isTrue,
    );
    expect(
      _achievement([
        _trip(
          id: 2,
          departureTime: DateTime(2026, 9, 30, 23),
          arrivalTime: DateTime(2026, 10, 1, 2),
        ),
      ], DashboardAchievementKind.blessChina).isUnlocked,
      isTrue,
    );
    expect(
      _achievement([
        _trip(id: 3, departureTime: DateTime(2026, 10, 2, 8)),
      ], DashboardAchievementKind.blessChina).isUnlocked,
      isFalse,
    );
  });
}

DashboardAchievement _achievement(
  List<TripRecord> trips,
  DashboardAchievementKind kind,
) => buildDashboardAchievements(
  trips,
).singleWhere((achievement) => achievement.kind == kind);

TripRecord _trip({
  required int id,
  String? trainNumber,
  String fromStation = '北京',
  String toStation = '上海',
  DateTime? departureTime,
  DateTime? arrivalTime,
  String? seatType,
  String? companyName,
  double mileageKm = 0,
  double price = 0,
  List<String> routeNames = const [],
}) => TripRecord(
  id: id,
  trainNumber: trainNumber ?? 'G$id',
  companyName: companyName,
  fromStation: fromStation,
  toStation: toStation,
  departureTime:
      departureTime ?? DateTime(2026, 1, 1).add(Duration(days: id, hours: 8)),
  arrivalTime: arrivalTime,
  mileageKm: mileageKm,
  viaRouteSegments: routeNames
      .map(
        (routeName) => ViaRouteSegment(
          routeName: routeName,
          fromStation: fromStation,
          toStation: toStation,
        ),
      )
      .toList(),
  seatType: seatType,
  price: price,
);
