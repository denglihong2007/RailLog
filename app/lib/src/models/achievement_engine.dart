import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
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
      '饭点乘坐 50 km 以内的商务座',
      _firstWhere(railTrips, _unlocksFreeMeal),
    ),
    _achievement(
      DashboardAchievementKind.overnightSeat,
      '铁腚行',
      '乘坐硬座或二等座完整度过 00:00-06:00',
      _firstWhere(railTrips, _unlocksOvernightSeat),
    ),
    _achievement(
      DashboardAchievementKind.tightTransfer,
      '极限换乘',
      '同站换乘时间小于 10 分钟',
      _firstTightTransfer(railTrips),
    ),
    _achievement(
      DashboardAchievementKind.sevenDayStreak,
      '马不停蹄',
      '连续 7 天每天乘坐火车',
      _firstStreakCompletion(railTrips, 7),
    ),
    _achievement(
      DashboardAchievementKind.thirtyDayStreak,
      '漂泊不定',
      '连续 30 天每天乘坐火车',
      _firstStreakCompletion(railTrips, 30),
    ),
    _achievement(
      DashboardAchievementKind.duration24Hours,
      '恍如昨日',
      '单程列车乘坐时长至少 24 小时',
      _firstDurationAtLeast(railTrips, const Duration(hours: 24)),
    ),
    _achievement(
      DashboardAchievementKind.duration48Hours,
      '旦复旦兮',
      '单程列车乘坐时长至少 48 小时',
      _firstDurationAtLeast(railTrips, const Duration(hours: 48)),
    ),
    _achievement(
      DashboardAchievementKind.duration72Hours,
      '舟车劳顿',
      '单程列车乘坐时长至少 72 小时',
      _firstDurationAtLeast(railTrips, const Duration(hours: 72)),
    ),
    _achievement(
      DashboardAchievementKind.all25Series,
      '五彩斑斓',
      '运转过 25 系列客车的所有常规车型',
      _firstCollectionCompletion(
        railTrips,
        _regular25Models,
        (trip) => _rollingStockMatches(trip.rollingStock, _regular25Models),
      ),
    ),
    _achievement(
      DashboardAchievementKind.allEmuSeries,
      '琳琅满目',
      '运转过和谐号、复兴号系列所有常规子型号',
      _firstCollectionCompletion(
        railTrips,
        _emuModels,
        (trip) => _emuMatches(trip.rollingStock),
      ),
    ),
    _achievement(
      DashboardAchievementKind.allSeatTypes,
      '我全都要',
      '运转过所有常规席别',
      _firstCollectionCompletion(
        railTrips,
        _regularSeatTypes,
        (trip) => _seatTypeMatches(trip.seatType),
      ),
    ),
    _achievement(
      DashboardAchievementKind.noSeat12Hours,
      '体力非凡',
      '持无座车票乘车至少 12 小时',
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
      '留存至少 100 张本人车票',
      railTrips.length >= 100 ? railTrips[99] : null,
    ),
    _achievement(
      DashboardAchievementKind.midnightBoarding,
      '夜半钟声',
      '在 00:00-05:00 之间乘车或下车',
      _firstMidnightBoarding(railTrips),
    ),
    _achievement(
      DashboardAchievementKind.wallFacingSeat,
      '面壁者',
      '二等座坐席位于车厢第 1 排或第 18 排',
      _firstWhere(railTrips, _unlocksWallFacingSeat),
    ),
    _achievement(
      DashboardAchievementKind.hundredStations,
      '百站印记',
      '累计去重到访客运车站不少于 100 座',
      _firstStationCompletion(railTrips, 100),
    ),
    _achievement(
      DashboardAchievementKind.thousandKilometers,
      '千里足迹',
      '单次运转里程不少于 1000 km',
      _firstMileageCompletion(railTrips, 1000),
    ),
    _achievement(
      DashboardAchievementKind.airRail,
      '空铁联运',
      '从三处不同的国内机场铁路站出发或到达',
      _firstAirportStationCompletion(railTrips, 3),
    ),
    _achievement(
      DashboardAchievementKind.railFerry,
      '铁水联运',
      '乘坐列车经由粤海轮渡线',
      _firstWhere(
        railTrips,
        (trip) => trip.viaRouteSegments.any(
          (segment) => segment.routeName.trim().contains('粤海轮渡线'),
        ),
      ),
    ),
    _achievement(
      DashboardAchievementKind.hundredThousandKilometers,
      '我就是GPS',
      '累计运转总里程达到 100000 km',
      _firstMileageCompletion(railTrips, 100000),
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
      '搭乘 CR400BF-5033 车型',
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
      '乘坐 CRH380AN 车型',
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
      '探访徐州站或徐州东站',
      _firstStationVisit(railTrips, const {'徐州', '徐州东'}),
    ),
    _achievement(
      DashboardAchievementKind.platformSubsidence,
      '站台沉降',
      '探访杭州东站',
      _firstStationVisit(railTrips, const {'杭州东'}),
    ),
    _achievement(
      DashboardAchievementKind.archaeologyTeam,
      '考古队',
      '录入 15 年之前的行程',
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
      '从定西北站乘坐到镇江南站',
      _firstWhere(
        railTrips,
        (trip) =>
            _normalizedStation(trip.fromStation) == '定西北' &&
            _normalizedStation(trip.toStation) == '镇江南' &&
            trip.arrivalTime != null,
      ),
    ),
    _achievement(
      DashboardAchievementKind.eveOfTheStorm,
      '风雨前夜',
      '在 2019.12.01-2020.01.23 探访武汉、汉口或武昌站',
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
      '乘坐过 10 次纯数字车次',
      _firstCountCompletion(
        railTrips,
        10,
        (trip) => RegExp(r'^\d+$').hasMatch(trip.trainNumber.trim()),
      ),
    ),
    _achievement(
      DashboardAchievementKind.overnightSleeper,
      '夕发朝至',
      '18:00-00:00 发车，05:00-11:00 到达的卧铺行程',
      _firstWhere(railTrips, _unlocksOvernightSleeper),
    ),
    _achievement(
      DashboardAchievementKind.tripleTransfer,
      '辗转挪移',
      '连续换乘至少 3 次，每次间隔不超过 3 小时',
      _firstTransferChainCompletion(railTrips, 3),
    ),
    _achievement(
      DashboardAchievementKind.endsOfTheEarth,
      '天涯海角',
      '探访天涯海角站',
      _firstStationVisit(railTrips, const {'天涯海角'}),
    ),
    _achievement(
      DashboardAchievementKind.fourFamousNorths,
      '四大名北',
      '探访阳泉北、盘锦北、孝感北和邵阳北站',
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
      '乘坐火车前往拉萨，并且全程硬座',
      _firstWhere(
        railTrips,
        (trip) =>
            _normalizedStation(trip.toStation) == '拉萨' &&
            trip.arrivalTime != null &&
            _normalizedSeatType(trip.seatType) == '硬座',
      ),
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
        (model) => RegExp(
          '(^|[^A-Z0-9])${RegExp.escape(model)}(?![A-Z0-9])',
        ).hasMatch(normalized),
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
    if (trip.arrivalTime != null) _addStation(stations, trip.toStation);
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
  return trip.arrivalTime != null &&
      targetStations.contains(_normalizedStation(trip.toStation));
});

TripRecord? _firstTargetStationCompletion(
  List<TripRecord> trips,
  Set<String> targetStations,
) {
  final visited = <String>{};
  for (final trip in trips) {
    final departure = _normalizedStation(trip.fromStation);
    if (targetStations.contains(departure)) visited.add(departure);
    if (trip.arrivalTime != null) {
      final arrival = _normalizedStation(trip.toStation);
      if (targetStations.contains(arrival)) visited.add(arrival);
    }
    if (visited.containsAll(targetStations)) return trip;
  }
  return null;
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

TripRecord? _firstAirportStationCompletion(List<TripRecord> trips, int target) {
  final stations = <String>{};
  for (final trip in trips) {
    for (final station in [
      trip.fromStation,
      if (trip.arrivalTime != null) trip.toStation,
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
