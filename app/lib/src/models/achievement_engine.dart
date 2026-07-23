import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/railway_bureau.dart';
import 'package:raillog/src/models/trip_record.dart';

const _regular25Models = {'25B', '25Z', '25G', '25K', '25T', '25DT'};
const _emuModels = {
  'CRH1',
  'CRH2',
  'CRH3',
  'CRH5',
  'CRH6',
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
};
const _regularSeatTypes = {
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
};
const _airportStationsWithoutAirportSuffix = {'美兰', '龙洞堡'};

List<DashboardAchievement> buildDashboardAchievements(
  Iterable<TripRecord> trips,
) {
  final railTrips = trips.where((trip) => trip.isRailTrip).toList()
    ..sort((a, b) {
      final byTime = a.departureTime.compareTo(b.departureTime);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });

  final achievements = [
    _achievement(
      DashboardAchievementKind.freeMeal,
      '蹭吃蹭喝',
      '在用餐时段乘坐里程不超过 50 公里的商务座',
      _firstWhere(railTrips, _unlocksFreeMeal),
    ),
    _achievement(
      DashboardAchievementKind.overnightSeat,
      '铁腚行',
      '乘坐硬座或二等座，完整度过 00:00 至 06:00',
      _firstWhere(railTrips, _unlocksOvernightSeat),
    ),
    _achievement(
      DashboardAchievementKind.tightTransfer,
      '极限换乘',
      '完成同站换乘，换乘时间少于 10 分钟',
      _firstTightTransfer(railTrips),
    ),
    _achievement(
      DashboardAchievementKind.wellPreparedTransfer,
      '充分打算',
      '完成同站换乘，等待至少 6 小时但少于 12 小时',
      _firstWellPreparedTransfer(railTrips),
    ),
    _achievement(
      DashboardAchievementKind.sevenDayStreak,
      '马不停蹄',
      '连续 7 天乘坐列车',
      _firstStreakCompletion(railTrips, 7),
    ),
    _achievement(
      DashboardAchievementKind.thirtyDayStreak,
      '漂泊不定',
      '连续 30 天乘坐列车',
      _firstStreakCompletion(railTrips, 30),
    ),
    _achievement(
      DashboardAchievementKind.duration24Hours,
      '恍如昨日',
      '乘坐单程时长至少 24 小时的列车',
      _firstDurationAtLeast(railTrips, const Duration(hours: 24)),
    ),
    _achievement(
      DashboardAchievementKind.duration48Hours,
      '旦复旦兮',
      '乘坐单程时长至少 48 小时的列车',
      _firstDurationAtLeast(railTrips, const Duration(hours: 48)),
    ),
    _achievement(
      DashboardAchievementKind.duration72Hours,
      '舟车劳顿',
      '乘坐单程时长至少 72 小时的列车',
      _firstDurationAtLeast(railTrips, const Duration(hours: 72)),
    ),
    _achievement(
      DashboardAchievementKind.all25Series,
      '五彩斑斓',
      '分别乘坐全部常规 25 系列客车型号',
      _firstCollectionCompletion(
        railTrips,
        _regular25Models,
        (trip) => _rollingStockMatches(trip.rollingStock, _regular25Models),
      ),
    ),
    _achievement(
      DashboardAchievementKind.allEmuSeries,
      '琳琅满目',
      '分别乘坐全部常规和谐号、复兴号子型号',
      _firstCollectionCompletion(
        railTrips,
        _emuModels,
        (trip) => _emuMatches(trip.rollingStock),
      ),
    ),
    _achievement(
      DashboardAchievementKind.allSeatTypes,
      '我全都要',
      '分别乘坐全部常规席别',
      _firstCollectionCompletion(
        railTrips,
        _regularSeatTypes,
        (trip) => _seatTypeMatches(trip.seatType),
      ),
    ),
    _achievement(
      DashboardAchievementKind.noSeat12Hours,
      '体力非凡',
      '持无座车票乘坐至少 12 小时',
      _firstWhere(
        railTrips,
        (trip) =>
            _normalizedSeatType(trip.seatType) == '无座' &&
            _validDuration(trip) >= const Duration(hours: 12),
      ),
    ),
    _achievement(
      DashboardAchievementKind.hundredTickets,
      '日积月累',
      '累计留存至少 100 张本人车票',
      railTrips.length >= 100 ? railTrips[99] : null,
    ),
    _achievement(
      DashboardAchievementKind.midnightBoarding,
      '夜半钟声',
      '在 00:00 至 05:00 乘车或下车',
      _firstMidnightBoarding(railTrips),
    ),
    _achievement(
      DashboardAchievementKind.wallFacingSeat,
      '面壁者',
      '乘坐车厢第 1 排或第 18 排的二等座',
      _firstWhere(railTrips, _unlocksWallFacingSeat),
    ),
    _achievement(
      DashboardAchievementKind.hundredStations,
      '百站印记',
      '累计到访至少 100 座不同的客运车站',
      _firstStationCompletion(railTrips, 100),
    ),
    _achievement(
      DashboardAchievementKind.thousandKilometers,
      '千里足迹',
      '完成单程至少 1,000 公里的行程',
      _firstMileageCompletion(railTrips, 1000),
    ),
    _achievement(
      DashboardAchievementKind.airRail,
      '空铁联运',
      '累计到访至少 3 座不同的国内机场铁路站',
      _firstAirportStationCompletion(railTrips, 3),
    ),
    _achievement(
      DashboardAchievementKind.railFerry,
      '铁水联运',
      '乘坐经由粤海轮渡线的列车，或在大连与烟台间完成 24 小时内的跨海接续',
      _firstRailFerryCompletion(railTrips),
    ),
    _achievement(
      DashboardAchievementKind.railwayWorkerPassenger,
      '待旅客如职工',
      '乘坐一次路用列车',
      _firstWhere(
        railTrips,
        (trip) => RegExp(r'^57\d{3}$').hasMatch(trip.trainNumber.trim()),
      ),
    ),
    _achievement(
      DashboardAchievementKind.verticalChina,
      '纵贯中国',
      '在 14 天内到访漠河站和三亚站',
      _firstStationPairWithin(railTrips, '漠河', '三亚', const Duration(days: 14)),
    ),
    _achievement(
      DashboardAchievementKind.horizontalChina,
      '横贯中国',
      '在 14 天内到访阿克陶站和抚远站',
      _firstStationPairWithin(railTrips, '阿克陶', '抚远', const Duration(days: 14)),
    ),
    _achievement(
      DashboardAchievementKind.highSpeedExperiment,
      '冲高实验',
      '完成时长超过 1 小时且均速超过 300 公里/小时的行程',
      _firstWhere(
        railTrips,
        (trip) =>
            _validDuration(trip) > const Duration(hours: 1) &&
            (trip.averageSpeedKmh ?? 0) > 300,
      ),
    ),
    _achievement(
      DashboardAchievementKind.slowCrawl,
      '龟速爬行',
      '完成时长超过 1 小时且均速不超过 50 公里/小时的行程',
      _firstWhere(
        railTrips,
        (trip) =>
            _validDuration(trip) > const Duration(hours: 1) &&
            trip.averageSpeedKmh != null &&
            trip.averageSpeedKmh! <= 50,
      ),
    ),
    _achievement(
      DashboardAchievementKind.slowerThanCycling,
      '不如骑车',
      '完成时长超过 1 小时且均速低于 30 公里/小时的行程',
      _firstWhere(
        railTrips,
        (trip) =>
            _validDuration(trip) > const Duration(hours: 1) &&
            trip.averageSpeedKmh != null &&
            trip.averageSpeedKmh! < 30,
      ),
    ),
    _achievement(
      DashboardAchievementKind.fleetingMoment,
      '转瞬即逝',
      '乘坐福田或深圳北与香港西九龙间的一等座、商务座或特等座',
      _firstWhere(railTrips, _unlocksFleetingMoment),
    ),
    _achievement(
      DashboardAchievementKind.borderPorts,
      '异域风情',
      '到访阿拉山口、二连、满洲里、绥芬河、丹东、崇左或磨憨站',
      _firstStationVisit(railTrips, const {
        '阿拉山口',
        '二连',
        '满洲里',
        '绥芬河',
        '丹东',
        '崇左',
        '磨憨',
      }),
    ),
    _achievement(
      DashboardAchievementKind.lonelyPlanet,
      '孤独星球',
      '分别乘坐经由和若线与格库线的列车',
      _firstRouteCollectionCompletion(railTrips, const {'和若线', '格库线'}),
    ),
    _achievement(
      DashboardAchievementKind.hundredThousandKilometers,
      '我就是GPS',
      '累计乘车里程至少 100,000 公里',
      _firstCumulativeMileageCompletion(railTrips, 100000),
    ),
    _achievement(
      DashboardAchievementKind.fTrain,
      '中途遣返',
      '乘坐一次 F 字头列车',
      _firstWhere(
        railTrips,
        (trip) => RegExp(
          r'^F\s*\d',
          caseSensitive: false,
        ).hasMatch(trip.trainNumber.trim()),
      ),
    ),
    _achievement(
      DashboardAchievementKind.axleOverheat,
      '轴温过高',
      '乘坐一次 CR400BF-5033 型列车',
      _firstWhere(
        railTrips,
        (trip) => _rollingStockMatches(trip.rollingStock, const {
          'CR400BF-5033',
        }).isNotEmpty,
      ),
    ),
    _achievement(
      DashboardAchievementKind.permanentMagnetPower,
      '永磁动力',
      '乘坐一次 CRH380AN 型列车',
      _firstWhere(
        railTrips,
        (trip) => _rollingStockMatches(trip.rollingStock, const {
          'CRH380AN',
        }).isNotEmpty,
      ),
    ),
    _achievement(
      DashboardAchievementKind.advantageIsMine,
      '优势在我',
      '到访徐州站或徐州东站',
      _firstStationVisit(railTrips, const {'徐州', '徐州东'}),
    ),
    _achievement(
      DashboardAchievementKind.platformSubsidence,
      '站台沉降',
      '到访杭州东站',
      _firstStationVisit(railTrips, const {'杭州东'}),
    ),
    _achievement(
      DashboardAchievementKind.archaeologyTeam,
      '考古队',
      '录入至少 15 年前的行程',
      _firstWhere(
        railTrips,
        (trip) => trip.departureTime.isBefore(
          DateTime(
            DateTime.now().year - 15,
            DateTime.now().month,
            DateTime.now().day,
          ),
        ),
      ),
    ),
    _achievement(
      DashboardAchievementKind.strategist,
      '战略家',
      '乘坐定西北站至镇江南站的列车',
      _firstWhere(
        railTrips,
        (trip) =>
            _normalizedStation(trip.fromStation) == '定西北' &&
            _normalizedStation(trip.toStation) == '镇江南'
      ),
    ),
    _achievement(
      DashboardAchievementKind.eveOfTheStorm,
      '风雨前夜',
      '在 2019-12-01 至 2020-01-23 到访武汉站、汉口站或武昌站',
      _firstStationVisitDuring(
        railTrips,
        const {'武汉', '汉口', '武昌'},
        DateTime(2019, 12, 1),
        DateTime(2020, 1, 24),
      ),
    ),
    _achievement(
      DashboardAchievementKind.tenNumericTrains,
      '慢慢旅途',
      '累计乘坐至少 10 次纯数字车次',
      _firstCountCompletion(
        railTrips,
        10,
        (trip) => RegExp(r'^\d+$').hasMatch(trip.trainNumber.trim()),
      ),
    ),
    _achievement(
      DashboardAchievementKind.overnightSleeper,
      '夕发朝至',
      '乘坐 18:00 至 00:00 发车且 05:00 至 11:00 到达的卧铺列车',
      _firstWhere(railTrips, _unlocksOvernightSleeper),
    ),
    _achievement(
      DashboardAchievementKind.tripleTransfer,
      '辗转挪移',
      '连续换乘至少 3 次，每次换乘间隔不超过 3 小时',
      _firstTransferChainCompletion(railTrips, 3),
    ),
    _achievement(
      DashboardAchievementKind.endsOfTheEarth,
      '天涯海角',
      '到访天涯海角站',
      _firstStationVisit(railTrips, const {'天涯海角'}),
    ),
    _achievement(
      DashboardAchievementKind.fourFamousNorths,
      '四大名北',
      '分别到访阳泉北站、盘锦北站、孝感北站和邵阳北站',
      _firstTargetStationCompletion(railTrips, const {
        '阳泉北',
        '盘锦北',
        '孝感北',
        '邵阳北',
      }),
    ),
    _achievement(
      DashboardAchievementKind.youthPriceless,
      '青春没有售价',
      '乘坐全程硬座列车到达拉萨站',
      _firstWhere(
        railTrips,
        (trip) =>
            _normalizedStation(trip.toStation) == '拉萨' &&
            _normalizedSeatType(trip.seatType) == '硬座',
      ),
    ),
    _achievement(
      DashboardAchievementKind.zeroDisplacement,
      '位移为零',
      '乘坐始发站与终到站相同的环线列车全程',
      _firstWhere(
        railTrips,
        (trip) =>
            _normalizedStation(trip.fromStation) ==
                _normalizedStation(trip.toStation),
      ),
    ),
    _achievement(
      DashboardAchievementKind.dreamPath,
      '逐梦之路',
      '乘坐一次 25DT 型列车',
      _firstWhere(
        railTrips,
        (trip) => _rollingStockMatches(trip.rollingStock, const {
          '25DT',
        }).contains('25DT'),
      ),
    ),
    _achievement(
      DashboardAchievementKind.commuterSpecial,
      '牛马专列',
      '乘坐北京站或北京南站与上海虹桥站或上海站间全程经由京沪高铁的优选一等座、商务座、一等座或特等座',
      _firstWhere(railTrips, _unlocksCommuterSpecial),
    ),
    _achievement(
      DashboardAchievementKind.grandSlam,
      '大满贯',
      '分别乘坐全部铁路局担当的列车',
      _firstRailwayBureauCompletion(railTrips),
    ),
    _achievement(
      DashboardAchievementKind.storedUpReward,
      '厚积薄发',
      '使用积分兑换里程超过 50 公里的商务座或特等座车票',
      _firstWhere(railTrips, _unlocksStoredUpReward),
    ),
    _achievement(
      DashboardAchievementKind.spontaneousTrip,
      '说走就走',
      '乘坐一次 Y 字头旅游列车',
      _firstWhere(
        railTrips,
        (trip) => RegExp(
          r'^Y\s*\d',
          caseSensitive: false,
        ).hasMatch(trip.trainNumber.trim()),
      ),
    ),
    _achievement(
      DashboardAchievementKind.redFootprints,
      '红色足迹',
      '乘坐韶山南站至延安站的列车',
      _firstWhere(railTrips, _unlocksRedFootprints),
    ),
    _achievement(
      DashboardAchievementKind.greatWallWatch,
      '长城守望',
      '到访八达岭站或八达岭长城站',
      _firstStationVisit(railTrips, const {'八达岭', '八达岭长城'}),
    ),
    _achievement(
      DashboardAchievementKind.icyWorld,
      '冰天雪地',
      '在 12 月、1 月或 2 月到访根河站',
      _firstWhere(railTrips, _unlocksIcyWorld),
    ),
    _achievement(
      DashboardAchievementKind.unnecessaryExtra,
      '多此一举',
      '分 3 张车票接续乘坐同一列车',
      _firstThreeTicketSameTrainCompletion(railTrips),
    ),
    _achievement(
      DashboardAchievementKind.blessChina,
      '祝福祖国',
      '在 10 月 1 日乘坐列车',
      _firstWhere(railTrips, _unlocksBlessChina),
    ),
  ];
  return List.unmodifiable([
    ...achievements.where((achievement) => achievement.isUnlocked),
    ...achievements.where((achievement) => !achievement.isUnlocked),
  ]);
}

DashboardAchievement _achievement(
  DashboardAchievementKind kind,
  String title,
  String requirement,
  TripRecord? trip,
) => DashboardAchievement(
  kind: kind,
  title: title,
  requirement: requirement,
  unlockedBy: trip == null ? null : DashboardTripEntry.fromTrip(trip),
);

TripRecord? _firstWhere(
  List<TripRecord> trips,
  bool Function(TripRecord trip) predicate,
) {
  for (final trip in trips) {
    if (predicate(trip)) return trip;
  }
  return null;
}

TripRecord? _firstCountCompletion(
  List<TripRecord> trips,
  int target,
  bool Function(TripRecord trip) predicate,
) {
  var count = 0;
  for (final trip in trips) {
    if (!predicate(trip)) continue;
    count++;
    if (count >= target) return trip;
  }
  return null;
}

TripRecord? _firstStreakCompletion(List<TripRecord> trips, int targetDays) {
  final firstTripByDay = <DateTime, TripRecord>{};
  for (final trip in trips) {
    firstTripByDay.putIfAbsent(_dateOnly(trip.departureTime), () => trip);
  }
  final days = firstTripByDay.keys.toList()..sort();
  var streak = 0;
  DateTime? previous;
  for (final day in days) {
    streak = previous != null && day.difference(previous).inDays == 1
        ? streak + 1
        : 1;
    if (streak >= targetDays) return firstTripByDay[day];
    previous = day;
  }
  return null;
}

TripRecord? _firstDurationAtLeast(List<TripRecord> trips, Duration threshold) =>
    _firstWhere(trips, (trip) => _validDuration(trip) >= threshold);

TripRecord? _firstCollectionCompletion(
  List<TripRecord> trips,
  Set<String> required,
  Set<String> Function(TripRecord trip) valuesForTrip,
) {
  final collected = <String>{};
  for (final trip in trips) {
    collected.addAll(valuesForTrip(trip));
    if (collected.containsAll(required)) return trip;
  }
  return null;
}

Set<String> _rollingStockMatches(String? value, Set<String> models) {
  final normalized = value?.trim().toUpperCase() ?? '';
  return models
      .where(
        (model) =>
            RegExp('${RegExp.escape(model)}(?![A-Z0-9])').hasMatch(normalized),
      )
      .toSet();
}

Set<String> _emuMatches(String? value) {
  final normalized = value?.trim().toUpperCase() ?? '';
  final result = <String>{};
  for (final model in _emuModels) {
    final pattern = switch (model) {
      'CRH1' ||
      'CRH2' ||
      'CRH3' ||
      'CRH5' ||
      'CRH6' => '(^|[^A-Z0-9])$model(?![0-9])',
      _ => '(^|[^A-Z0-9])$model',
    };
    if (RegExp(pattern).hasMatch(normalized)) result.add(model);
  }
  return result;
}

Set<String> _seatTypeMatches(String? value) {
  final normalized = _normalizedSeatType(value);
  return _regularSeatTypes.where((seat) => seat == normalized).toSet();
}

String _normalizedSeatType(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.replaceFirst(RegExp(r'[上中下]铺$'), '');
}

TripRecord? _firstMidnightBoarding(List<TripRecord> trips) {
  TripRecord? result;
  DateTime? eventTime;
  for (final trip in trips) {
    for (final event in [trip.departureTime, trip.arrivalTime]) {
      if (event == null || !_isMidnightTime(event)) continue;
      if (eventTime == null || event.isBefore(eventTime)) {
        eventTime = event;
        result = trip;
      }
    }
  }
  return result;
}

bool _isMidnightTime(DateTime value) =>
    value.hour < 5 || (value.hour == 5 && value.minute == 0);

bool _unlocksWallFacingSeat(TripRecord trip) {
  if (_normalizedSeatType(trip.seatType) != '二等座') return false;
  final seat = trip.seatNumber?.replaceAll(' ', '').toUpperCase() ?? '';
  return RegExp(r'车(?:1|18)[A-Z]?号').hasMatch(seat);
}

TripRecord? _firstStationCompletion(List<TripRecord> trips, int target) {
  final stations = <String>{};
  for (final trip in trips) {
    _addStation(stations, trip.fromStation);
    _addStation(stations, trip.toStation);
    if (stations.length >= target) return trip;
  }
  return null;
}

TripRecord? _firstStationVisit(
  List<TripRecord> trips,
  Set<String> targetStations,
) => _firstWhere(trips, (trip) {
  if (targetStations.contains(_normalizedStation(trip.fromStation))) {
    return true;
  }
  return targetStations.contains(_normalizedStation(trip.toStation));
});

TripRecord? _firstTargetStationCompletion(
  List<TripRecord> trips,
  Set<String> targetStations,
) {
  final visited = <String>{};
  for (final trip in trips) {
    final departure = _normalizedStation(trip.fromStation);
    if (targetStations.contains(departure)) visited.add(departure);
    final arrival = _normalizedStation(trip.toStation);
    if (targetStations.contains(arrival)) visited.add(arrival);
    if (visited.containsAll(targetStations)) return trip;
  }
  return null;
}

TripRecord? _firstStationPairWithin(
  List<TripRecord> trips,
  String firstStation,
  String secondStation,
  Duration maxWindow,
) {
  final targets = {
    _normalizedStation(firstStation),
    _normalizedStation(secondStation),
  };
  final latestVisit = <String, _StationVisit>{};
  for (final visit in _stationVisits(trips)) {
    if (!targets.contains(visit.station)) continue;
    latestVisit[visit.station] = visit;
    final otherStation = targets.firstWhere(
      (station) => station != visit.station,
    );
    final otherVisit = latestVisit[otherStation];
    if (otherVisit != null &&
        visit.time.difference(otherVisit.time) <= maxWindow) {
      return visit.trip;
    }
  }
  return null;
}

List<_StationVisit> _stationVisits(List<TripRecord> trips) {
  final visits = <_StationVisit>[];
  for (final trip in trips) {
    visits.add(
      _StationVisit(
        station: _normalizedStation(trip.fromStation),
        time: trip.departureTime,
        trip: trip,
      ),
    );
    final arrival = trip.arrivalTime;
    if (arrival != null) {
      visits.add(
        _StationVisit(
          station: _normalizedStation(trip.toStation),
          time: arrival,
          trip: trip,
        ),
      );
    }
  }
  visits.sort((a, b) {
    final byTime = a.time.compareTo(b.time);
    return byTime != 0 ? byTime : a.trip.id.compareTo(b.trip.id);
  });
  return visits;
}

TripRecord? _firstStationVisitDuring(
  List<TripRecord> trips,
  Set<String> targetStations,
  DateTime startInclusive,
  DateTime endExclusive,
) => _firstWhere(trips, (trip) {
  if (_isWithin(trip.departureTime, startInclusive, endExclusive) &&
      targetStations.contains(_normalizedStation(trip.fromStation))) {
    return true;
  }
  final arrival = trip.arrivalTime;
  return arrival != null &&
      _isWithin(arrival, startInclusive, endExclusive) &&
      targetStations.contains(_normalizedStation(trip.toStation));
});

bool _isWithin(
  DateTime value,
  DateTime startInclusive,
  DateTime endExclusive,
) => !value.isBefore(startInclusive) && value.isBefore(endExclusive);

TripRecord? _firstMileageCompletion(List<TripRecord> trips, double target) {
  for (final trip in trips) {
    if (trip.mileageKm >= target) return trip;
  }
  return null;
}

TripRecord? _firstCumulativeMileageCompletion(
  List<TripRecord> trips,
  double target,
) {
  var mileage = 0.0;
  for (final trip in trips) {
    if (trip.mileageKm > 0) mileage += trip.mileageKm;
    if (mileage >= target) return trip;
  }
  return null;
}

TripRecord? _firstRouteCollectionCompletion(
  List<TripRecord> trips,
  Set<String> requiredRoutes,
) => _firstCollectionCompletion(
  trips,
  requiredRoutes,
  (trip) => requiredRoutes
      .where(
        (route) => trip.viaRouteSegments.any(
          (segment) => segment.routeName.trim().contains(route),
        ),
      )
      .toSet(),
);

TripRecord? _firstRailFerryCompletion(List<TripRecord> trips) {
  for (var currentIndex = 0; currentIndex < trips.length; currentIndex++) {
    final current = trips[currentIndex];
    if (current.viaRouteSegments.any(
      (segment) => segment.routeName.trim().contains('粤海轮渡线'),
    )) {
      return current;
    }
    final departureStation = _normalizedStation(current.fromStation);
    if (!departureStation.contains('大连') && !departureStation.contains('烟台')) {
      continue;
    }
    final requiredArrivalStation = departureStation.contains('大连')
        ? '烟台'
        : '大连';
    for (var previousIndex = 0; previousIndex < currentIndex; previousIndex++) {
      final previous = trips[previousIndex];
      final arrival = previous.arrivalTime;
      if (arrival == null ||
          !_normalizedStation(
            previous.toStation,
          ).contains(requiredArrivalStation)) {
        continue;
      }
      final connectionTime = current.departureTime.difference(arrival);
      if (!connectionTime.isNegative &&
          connectionTime <= const Duration(hours: 24)) {
        return current;
      }
    }
  }
  return null;
}

TripRecord? _firstAirportStationCompletion(List<TripRecord> trips, int target) {
  final stations = <String>{};
  for (final trip in trips) {
    for (final station in [
      trip.fromStation,
      trip.toStation,
    ]) {
      final normalized = station.trim().replaceFirst(RegExp(r'站$'), '');
      if (normalized.contains('机场') ||
          _airportStationsWithoutAirportSuffix.contains(normalized)) {
        stations.add(normalized);
      }
    }
    if (stations.length >= target) return trip;
  }
  return null;
}

void _addStation(Set<String> stations, String value) {
  final station = value.trim();
  if (station.isNotEmpty) stations.add(station);
}

String _normalizedStation(String value) =>
    value.trim().replaceFirst(RegExp(r'站$'), '');

Duration _validDuration(TripRecord trip) {
  final arrival = trip.arrivalTime;
  if (arrival == null || arrival.isBefore(trip.departureTime)) {
    return Duration.zero;
  }
  return arrival.difference(trip.departureTime);
}

bool _unlocksFreeMeal(TripRecord trip) {
  if (_normalizedSeatType(trip.seatType) != '商务座' ||
      trip.mileageKm <= 0 ||
      trip.mileageKm > 50) {
    return false;
  }
  final minutes = trip.departureTime.hour * 60 + trip.departureTime.minute;
  return (minutes >= 11 * 60 && minutes < 13 * 60) ||
      (minutes >= 17 * 60 && minutes < 19 * 60);
}

bool _unlocksOvernightSeat(TripRecord trip) {
  final seatType = _normalizedSeatType(trip.seatType);
  if (seatType != '硬座' && seatType != '二等座') return false;
  final arrival = trip.arrivalTime;
  if (arrival == null || arrival.isBefore(trip.departureTime)) return false;

  var day = _dateOnly(trip.departureTime);
  final lastDay = _dateOnly(arrival);
  while (!day.isAfter(lastDay)) {
    final windowEnd = day.add(const Duration(hours: 6));
    if (!trip.departureTime.isAfter(day) && !arrival.isBefore(windowEnd)) {
      return true;
    }
    day = day.add(const Duration(days: 1));
  }
  return false;
}

bool _unlocksOvernightSleeper(TripRecord trip) {
  final arrival = trip.arrivalTime;
  if (arrival == null || arrival.isBefore(trip.departureTime)) return false;
  if (!_normalizedSeatType(trip.seatType).contains('卧')) return false;
  final departureMinutes =
      trip.departureTime.hour * 60 + trip.departureTime.minute;
  final arrivalMinutes = arrival.hour * 60 + arrival.minute;
  return departureMinutes >= 18 * 60 &&
      arrivalMinutes >= 5 * 60 &&
      arrivalMinutes <= 11 * 60;
}

bool _unlocksFleetingMoment(TripRecord trip) {
  const premiumSeats = {'一等座', '商务座', '特等座'};
  if (!premiumSeats.contains(_normalizedSeatType(trip.seatType))) {
    return false;
  }
  final from = _normalizedStation(trip.fromStation);
  final to = _normalizedStation(trip.toStation);
  const mainlandStations = {'福田', '深圳北'};
  return (mainlandStations.contains(from) && to == '香港西九龙') ||
      (from == '香港西九龙' && mainlandStations.contains(to));
}

bool _unlocksCommuterSpecial(TripRecord trip) {
  const premiumSeats = {'优选一等座', '一等座', '商务座', '特等座'};
  if (!premiumSeats.contains(_normalizedSeatType(trip.seatType))) {
    return false;
  }
  const beijingStations = {'北京', '北京南'};
  const shanghaiStations = {'上海虹桥', '上海'};
  final from = _normalizedStation(trip.fromStation);
  final to = _normalizedStation(trip.toStation);
  final coversFullRoute =
      (beijingStations.contains(from) && shanghaiStations.contains(to)) ||
      (shanghaiStations.contains(from) && beijingStations.contains(to));
  return coversFullRoute;
}

TripRecord? _firstRailwayBureauCompletion(List<TripRecord> trips) =>
    _firstCollectionCompletion(trips, railwayBureauSegments.keys.toSet(), (
      trip,
    ) {
      final bureau = railwayBureauForCompany(trip.companyName);
      return bureau == null ? const <String>{} : {bureau};
    });

bool _unlocksStoredUpReward(TripRecord trip) =>
    trip.price == 0 &&
    trip.mileageKm > 50 &&
    const {'商务座', '特等座'}.contains(_normalizedSeatType(trip.seatType));

bool _unlocksRedFootprints(TripRecord trip) =>
    _normalizedStation(trip.fromStation) == '韶山南' &&
    _normalizedStation(trip.toStation) == '延安';

bool _unlocksIcyWorld(TripRecord trip) {
  const winterMonths = {12, 1, 2};
  if (_normalizedStation(trip.fromStation) == '根河' &&
      winterMonths.contains(trip.departureTime.month)) {
    return true;
  }
  final arrival = trip.arrivalTime;
  return arrival != null &&
      _normalizedStation(trip.toStation) == '根河' &&
      winterMonths.contains(arrival.month);
}

TripRecord? _firstThreeTicketSameTrainCompletion(List<TripRecord> trips) {
  final chainLengths = List<int>.filled(trips.length, 1);
  for (var currentIndex = 0; currentIndex < trips.length; currentIndex++) {
    final current = trips[currentIndex];
    final trainNumber = current.trainNumber.trim().toUpperCase();
    final fromStation = _normalizedStation(current.fromStation);
    if (trainNumber.isEmpty || fromStation.isEmpty) continue;
    for (var previousIndex = 0; previousIndex < currentIndex; previousIndex++) {
      final previous = trips[previousIndex];
      final arrival = previous.arrivalTime;
      if (arrival == null ||
          previous.trainNumber.trim().toUpperCase() != trainNumber ||
          _normalizedStation(previous.toStation) != fromStation ||
          current.departureTime.isBefore(arrival)) {
        continue;
      }
      chainLengths[currentIndex] = _max(
        chainLengths[currentIndex],
        chainLengths[previousIndex] + 1,
      );
    }
    if (chainLengths[currentIndex] >= 3) return current;
  }
  return null;
}

bool _unlocksBlessChina(TripRecord trip) {
  if (trip.departureTime.month == 10 && trip.departureTime.day == 1) {
    return true;
  }
  return false;
}

int _max(int first, int second) => first > second ? first : second;

TripRecord? _firstTightTransfer(List<TripRecord> trips) {
  for (var outgoingIndex = 0; outgoingIndex < trips.length; outgoingIndex++) {
    final outgoing = trips[outgoingIndex];
    final station = outgoing.fromStation.trim();
    if (station.isEmpty) continue;
    for (
      var incomingIndex = 0;
      incomingIndex < outgoingIndex;
      incomingIndex++
    ) {
      final incoming = trips[incomingIndex];
      final arrival = incoming.arrivalTime;
      if (arrival == null || incoming.toStation.trim() != station) continue;
      final transferTime = outgoing.departureTime.difference(arrival);
      if (!transferTime.isNegative &&
          transferTime < const Duration(minutes: 10)) {
        return outgoing;
      }
    }
  }
  return null;
}

TripRecord? _firstWellPreparedTransfer(List<TripRecord> trips) {
  for (var outgoingIndex = 0; outgoingIndex < trips.length; outgoingIndex++) {
    final outgoing = trips[outgoingIndex];
    final transferStation = _normalizedStation(outgoing.fromStation);
    final outgoingDestination = _normalizedStation(outgoing.toStation);
    if (transferStation.isEmpty || outgoingDestination.isEmpty) continue;
    for (
      var incomingIndex = 0;
      incomingIndex < outgoingIndex;
      incomingIndex++
    ) {
      final incoming = trips[incomingIndex];
      final arrival = incoming.arrivalTime;
      if (arrival == null ||
          _normalizedStation(incoming.toStation) != transferStation ||
          _normalizedStation(incoming.fromStation) == outgoingDestination) {
        continue;
      }
      final transferTime = outgoing.departureTime.difference(arrival);
      if (transferTime >= const Duration(hours: 6) &&
          transferTime < const Duration(hours: 12)) {
        return outgoing;
      }
    }
  }
  return null;
}

TripRecord? _firstTransferChainCompletion(
  List<TripRecord> trips,
  int targetTransfers,
) {
  final transferCounts = List<int>.filled(trips.length, 0);
  for (var outgoingIndex = 0; outgoingIndex < trips.length; outgoingIndex++) {
    final outgoing = trips[outgoingIndex];
    final station = _normalizedStation(outgoing.fromStation);
    if (station.isEmpty) continue;
    for (
      var incomingIndex = 0;
      incomingIndex < outgoingIndex;
      incomingIndex++
    ) {
      final incoming = trips[incomingIndex];
      final arrival = incoming.arrivalTime;
      if (arrival == null ||
          _normalizedStation(incoming.toStation) != station) {
        continue;
      }
      final transferTime = outgoing.departureTime.difference(arrival);
      if (transferTime.isNegative || transferTime > const Duration(hours: 3)) {
        continue;
      }
      final count = transferCounts[incomingIndex] + 1;
      if (count > transferCounts[outgoingIndex]) {
        transferCounts[outgoingIndex] = count;
      }
    }
    if (transferCounts[outgoingIndex] >= targetTransfers) return outgoing;
  }
  return null;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

class _StationVisit {
  const _StationVisit({
    required this.station,
    required this.time,
    required this.trip,
  });

  final String station;
  final DateTime time;
  final TripRecord trip;
}
