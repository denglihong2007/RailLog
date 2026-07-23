import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/achievement_engine.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';

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
      ).unlockedBy?.id,
      4,
    );
  });

  test('青春没有售价不要求填写到达时间', () {
    final matching = _trip(id: 1, toStation: '拉萨站', seatType: '硬座');
    final wrongSeat = _arrivingTrip(id: 2, station: '拉萨', seatType: '硬卧');

    expect(
      _achievement([
        matching,
        wrongSeat,
      ], DashboardAchievementKind.youthPriceless).unlockedBy?.id,
      matching.id,
    );
  });

  test('永磁动力要求乘坐 CRH380AN 车型', () {
    expect(
      _achievement([
        _trip(id: 1, rollingStock: 'CRH380AN'),
      ], DashboardAchievementKind.permanentMagnetPower).isUnlocked,
      isTrue,
    );
    expect(
      _achievement([
        _trip(id: 2, rollingStock: 'CRH380AN-0206'),
      ], DashboardAchievementKind.permanentMagnetPower).unlockedBy?.id,
      2,
    );
    for (final model in ['CRH380A', 'CRH380ANX']) {
      expect(
        _achievement([
          _trip(id: 3, rollingStock: model),
        ], DashboardAchievementKind.permanentMagnetPower).isUnlocked,
        isFalse,
        reason: model,
      );
    }
  });

  test('充分打算要求 A-B-C 同站换乘且间隔为六至十二小时', () {
    final incoming = _trip(
      id: 1,
      fromStation: 'A',
      toStation: 'B站',
      departureTime: DateTime(2026, 1, 1, 6),
      arrivalTime: DateTime(2026, 1, 1, 8),
    );
    final matching = _trip(
      id: 2,
      fromStation: 'B',
      toStation: 'C',
      departureTime: DateTime(2026, 1, 1, 14),
    );
    expect(
      _achievement([
        incoming,
        matching,
      ], DashboardAchievementKind.wellPreparedTransfer).unlockedBy?.id,
      matching.id,
    );

    for (final outgoing in [
      _trip(
        id: 3,
        fromStation: 'B',
        toStation: 'A',
        departureTime: DateTime(2026, 1, 1, 14),
      ),
      _trip(
        id: 4,
        fromStation: 'B',
        toStation: 'C',
        departureTime: DateTime(2026, 1, 1, 20),
      ),
    ]) {
      expect(
        _achievement([
          incoming,
          outgoing,
        ], DashboardAchievementKind.wellPreparedTransfer).isUnlocked,
        isFalse,
      );
    }
  });

  test('待旅客如职工只匹配完整的 57XXX 车次', () {
    expect(
      _achievement([
        _trip(id: 1, trainNumber: '57001'),
      ], DashboardAchievementKind.railwayWorkerPassenger).isUnlocked,
      isTrue,
    );
    for (final trainNumber in ['5700', '570001', 'G57001']) {
      expect(
        _achievement([
          _trip(id: 2, trainNumber: trainNumber),
        ], DashboardAchievementKind.railwayWorkerPassenger).isUnlocked,
        isFalse,
      );
    }
  });

  test('纵贯中国和横贯中国按实际到访时间计算十四天窗口', () {
    final mohe = _trip(
      id: 1,
      fromStation: '漠河站',
      departureTime: DateTime(2026, 1, 1, 8),
    );
    final sanyaAtBoundary = _trip(
      id: 2,
      fromStation: '三亚',
      departureTime: DateTime(2026, 1, 15, 8),
    );
    expect(
      _achievement([
        mohe,
        sanyaAtBoundary,
      ], DashboardAchievementKind.verticalChina).unlockedBy?.id,
      sanyaAtBoundary.id,
    );
    expect(
      _achievement([
        mohe,
        _trip(
          id: 3,
          fromStation: '三亚',
          departureTime: DateTime(2026, 1, 15, 8, 1),
        ),
      ], DashboardAchievementKind.verticalChina).isUnlocked,
      isFalse,
    );

    expect(
      _achievement([
        _trip(
          id: 4,
          toStation: '阿克陶站',
          departureTime: DateTime(2026, 2, 1, 6),
        ),
        _trip(
          id: 5,
          fromStation: '抚远站',
          departureTime: DateTime(2026, 2, 10, 8),
        ),
      ], DashboardAchievementKind.horizontalChina).isUnlocked,
      isTrue,
    );
  });

  test('指定日期内探访终点站不要求填写到达时间', () {
    expect(
      _achievement([
        _trip(
          id: 1,
          toStation: '武汉站',
          departureTime: DateTime(2019, 12, 20, 8),
        ),
      ], DashboardAchievementKind.eveOfTheStorm).isUnlocked,
      isTrue,
    );
  });

  test('速度成就遵循时长和速度边界', () {
    final departure = DateTime(2026, 1, 1, 8);
    final fast = _trip(
      id: 1,
      departureTime: departure,
      arrivalTime: departure.add(const Duration(hours: 2)),
      mileageKm: 601,
    );
    final slow = _trip(
      id: 2,
      departureTime: departure.add(const Duration(days: 1)),
      arrivalTime: departure.add(const Duration(days: 1, hours: 2)),
      mileageKm: 100,
    );
    expect(
      _achievement([
        fast,
      ], DashboardAchievementKind.highSpeedExperiment).isUnlocked,
      isTrue,
    );
    expect(
      _achievement([slow], DashboardAchievementKind.slowCrawl).isUnlocked,
      isTrue,
    );
    expect(
      _achievement([
        _trip(
          id: 3,
          departureTime: departure,
          arrivalTime: departure.add(const Duration(hours: 1)),
          mileageKm: 301,
        ),
      ], DashboardAchievementKind.highSpeedExperiment).isUnlocked,
      isFalse,
    );
  });

  test('不如骑车要求单程超过一小时且均速低于 30 km/h', () {
    final shortSlowTrips = List.generate(2, (index) {
      final departure = DateTime(2026, 1, index + 1, 8);
      return _trip(
        id: index + 1,
        departureTime: departure,
        arrivalTime: departure.add(const Duration(minutes: 40)),
        mileageKm: 10,
      );
    });
    expect(
      _achievement(
        shortSlowTrips,
        DashboardAchievementKind.slowerThanCycling,
      ).isUnlocked,
      isFalse,
    );
    final departure = DateTime(2026, 1, 3, 8);
    final matching = _trip(
      id: 3,
      departureTime: departure,
      arrivalTime: departure.add(const Duration(minutes: 61)),
      mileageKm: 20,
    );
    expect(
      _achievement([
        ...shortSlowTrips,
        matching,
      ], DashboardAchievementKind.slowerThanCycling).unlockedBy?.id,
      matching.id,
    );
  });

  test('转瞬即逝要求指定跨境区间和高等级席别', () {
    final matching = _trip(
      id: 1,
      fromStation: '香港西九龙站',
      toStation: '福田站',
      arrivalTime: DateTime(2026, 1, 2, 10),
      seatType: '商务座',
    );
    expect(
      _achievement([
        matching,
      ], DashboardAchievementKind.fleetingMoment).isUnlocked,
      isTrue,
    );
    expect(
      _achievement([
        _trip(
          id: 2,
          fromStation: '深圳北',
          toStation: '香港西九龙',
          arrivalTime: DateTime(2026, 1, 3, 10),
          seatType: '二等座',
        ),
      ], DashboardAchievementKind.fleetingMoment).isUnlocked,
      isFalse,
    );
  });

  test('异域风情探访任一指定口岸车站即可解锁', () {
    expect(
      _achievement([
        _arrivingTrip(id: 1, station: '满洲里站'),
      ], DashboardAchievementKind.borderPorts).isUnlocked,
      isTrue,
    );
  });

  test('孤独星球累计覆盖和若线及格库线', () {
    final heRuo = _trip(id: 1, routeNames: const ['和若线']);
    final geKu = _trip(id: 2, routeNames: const ['格库线']);
    expect(
      _achievement([heRuo], DashboardAchievementKind.lonelyPlanet).isUnlocked,
      isFalse,
    );
    expect(
      _achievement([
        heRuo,
        geKu,
      ], DashboardAchievementKind.lonelyPlanet).unlockedBy?.id,
      geKu.id,
    );
  });

  test('铁水联运支持粤海轮渡线和大连烟台二十四小时接续', () {
    expect(
      _achievement([
        _trip(id: 1, routeNames: const ['粤海轮渡线']),
      ], DashboardAchievementKind.railFerry).isUnlocked,
      isTrue,
    );
    final arrivingDalian = _trip(
      id: 2,
      toStation: '大连站',
      departureTime: DateTime(2026, 1, 1, 6),
      arrivalTime: DateTime(2026, 1, 1, 8),
    );
    final leavingYantai = _trip(
      id: 3,
      fromStation: '烟台站',
      departureTime: DateTime(2026, 1, 2, 8),
    );
    expect(
      _achievement([
        arrivingDalian,
        leavingYantai,
      ], DashboardAchievementKind.railFerry).unlockedBy?.id,
      leavingYantai.id,
    );
    expect(
      _achievement([
        arrivingDalian,
        _trip(
          id: 4,
          fromStation: '烟台',
          departureTime: DateTime(2026, 1, 2, 8, 1),
        ),
      ], DashboardAchievementKind.railFerry).isUnlocked,
      isFalse,
    );
  });

  test('我就是GPS按累计里程首次达到十万公里解锁', () {
    final trips = [
      _trip(id: 1, mileageKm: 60000),
      _trip(id: 2, mileageKm: 40000),
    ];
    expect(
      _achievement([
        trips.first,
      ], DashboardAchievementKind.hundredThousandKilometers).isUnlocked,
      isFalse,
    );
    expect(
      _achievement(
        trips,
        DashboardAchievementKind.hundredThousandKilometers,
      ).unlockedBy?.id,
      trips.last.id,
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
  _registerNewAchievementTests();
}

void _registerNewAchievementTests() {
  test('位移为零要求环线列车已完成全程且始发终到站相同', () {
    final matching = _trip(
      id: 1,
      fromStation: '上海站',
      toStation: '上海',
      arrivalTime: DateTime(2026, 1, 2),
    );
    expect(
      _achievement([
        matching,
      ], DashboardAchievementKind.zeroDisplacement).unlockedBy?.id,
      matching.id,
    );
    expect(
      _achievement([
        _trip(id: 2, fromStation: '上海', toStation: '上海'),
      ], DashboardAchievementKind.zeroDisplacement).isUnlocked,
      isFalse,
    );
    expect(
      _achievement([
        _trip(
          id: 3,
          fromStation: '上海',
          toStation: '北京',
          arrivalTime: DateTime(2026, 1, 2),
        ),
      ], DashboardAchievementKind.zeroDisplacement).isUnlocked,
      isFalse,
    );
  });

  test('逐梦之路匹配完整的 25DT 型号', () {
    expect(
      _achievement([
        _trip(id: 1, rollingStock: '25DT-1234'),
      ], DashboardAchievementKind.dreamPath).isUnlocked,
      isTrue,
    );
    for (final model in ['25D', '25DTX']) {
      expect(
        _achievement([
          _trip(id: 2, rollingStock: model),
        ], DashboardAchievementKind.dreamPath).isUnlocked,
        isFalse,
        reason: model,
      );
    }
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
  String? rollingStock,
  double mileageKm = 0,
  List<String> routeNames = const [],
}) => TripRecord(
  id: id,
  trainNumber: trainNumber ?? 'G$id',
  fromStation: fromStation,
  toStation: toStation,
  departureTime:
      departureTime ?? DateTime(2026, 1, 1).add(Duration(days: id, hours: 8)),
  arrivalTime: arrivalTime,
  seatType: seatType,
  rollingStock: rollingStock,
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
);
