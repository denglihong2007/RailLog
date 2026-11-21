import 'package:raillog/src/models/train_schedule_stop.dart';

/// 历史时刻表里的一站，时刻已经换算成绝对时间。
class TripScheduleStop {
  const TripScheduleStop({
    required this.stationName,
    required this.arrival,
    required this.departure,
    required this.mileage,
  });

  final String stationName;
  final DateTime? arrival;
  final DateTime? departure;
  final double? mileage;
}

/// 简图上一站要和时刻表叠加显示的时刻。
///
/// 停站给 [arrival]/[departure]，通过站给 [passTime]；[estimated] 表示这个通过
/// 时刻不是时刻表里的原始值，而是按前后停站的里程比例估算出来的。
/// [stopIndex] 只在匹配到历史站序时有值，手动矫正停站时刻时用它定位。
class StationScheduleTime {
  const StationScheduleTime({
    this.arrival,
    this.departure,
    this.passTime,
    this.estimated = false,
    this.stopIndex,
  });

  final DateTime? arrival;
  final DateTime? departure;
  final DateTime? passTime;
  final bool estimated;
  final int? stopIndex;

  bool get isStop => passTime == null;

  int? get dwellMinutes {
    final arrival = this.arrival;
    final departure = this.departure;
    if (arrival == null || departure == null) return null;
    return departure.difference(arrival).inMinutes;
  }
}

/// 一趟行程所选区间的历史时刻表，以及把它叠加到简图站点上的规则。
///
/// 只有当用户录入的发车时刻（以及录入的到站时刻）与历史站序完全相同时才构造成功：
/// 时刻对不上说明录的不是快照里的这一趟车，叠上去只会误导用户。
class TripScheduleTimes {
  TripScheduleTimes({
    required List<TripScheduleStop> stops,
    required this.boardingIndex,
    required this.alightingIndex,
    Map<String, DateTime> passTimeOverrides = const {},
  }) : assert(boardingIndex >= 0),
       assert(alightingIndex > boardingIndex),
       assert(alightingIndex < stops.length),
       stops = List.unmodifiable(stops),
       passTimeOverrides = Map.unmodifiable(passTimeOverrides);

  final List<TripScheduleStop> stops;
  final int boardingIndex;
  final int alightingIndex;

  /// 手动校准过的通过时刻，键见 [stationOccurrenceKeys]。
  ///
  /// 通过时刻本来是匀速模型估出来的，用户可以在简图上按实际观察改掉；
  /// 这类校准只覆盖显示值，不改变前后停站。
  final Map<String, DateTime> passTimeOverrides;

  /// 手动矫正后替换站序；下标、校准值保持不变。
  TripScheduleTimes withStops(List<TripScheduleStop> stops) =>
      TripScheduleTimes(
        stops: stops,
        boardingIndex: boardingIndex,
        alightingIndex: alightingIndex,
        passTimeOverrides: passTimeOverrides,
      );

  TripScheduleTimes withPassTimeOverrides(Map<String, DateTime> overrides) =>
      TripScheduleTimes(
        stops: stops,
        boardingIndex: boardingIndex,
        alightingIndex: alightingIndex,
        passTimeOverrides: overrides,
      );

  /// 用已换算成绝对时间的站序校验时刻是否与行程一致。
  ///
  /// 历史库只精确到分，用户录入的时间可能带秒，比较时只看年月日时分。
  static TripScheduleTimes? match({
    required List<TrainScheduleStop> resolvedStops,
    required int boardingIndex,
    required int alightingIndex,
    required DateTime departureTime,
    required DateTime? arrivalTime,
  }) {
    if (boardingIndex < 0 ||
        alightingIndex <= boardingIndex ||
        alightingIndex >= resolvedStops.length) {
      return null;
    }
    final boardingDeparture = resolvedStops[boardingIndex].departureDateTime;
    if (boardingDeparture == null ||
        !_sameMinute(boardingDeparture, departureTime)) {
      return null;
    }
    if (arrivalTime != null) {
      final alightingArrival = resolvedStops[alightingIndex].arrivalDateTime;
      if (alightingArrival == null ||
          !_sameMinute(alightingArrival, arrivalTime)) {
        return null;
      }
    }
    return TripScheduleTimes(
      stops: [
        for (final stop in resolvedStops)
          TripScheduleStop(
            stationName: stop.stationName,
            arrival: stop.arrivalDateTime,
            departure: stop.departureDateTime,
            mileage: stop.mileage,
          ),
      ],
      boardingIndex: boardingIndex,
      alightingIndex: alightingIndex,
    );
  }

  /// 给简图上的每一站算时刻；首末站显示发车/到达时刻。
  ///
  /// [stationNames] 与 [mileage] 是简图当前的站序和累计里程，两者等长。站名按
  /// 单调游标对齐历史站序：折返车会在简图里第二次经过同一站，查表只能取到其中
  /// 一次，游标才能依次落到去程和回程。
  List<StationScheduleTime?> annotate({
    required List<String> stationNames,
    required List<double> mileage,
  }) {
    final result = List<StationScheduleTime?>.filled(stationNames.length, null);
    if (stationNames.length < 2) return result;

    final matched = List<int?>.filled(stationNames.length, null);
    var cursor = boardingIndex;
    for (var index = 0; index < stationNames.length; index++) {
      final name = normalizeStationName(stationNames[index]);
      if (name.isEmpty) continue;
      for (var stopIndex = cursor; stopIndex <= alightingIndex; stopIndex++) {
        if (normalizeStationName(stops[stopIndex].stationName) != name) {
          continue;
        }
        matched[index] = stopIndex;
        cursor = stopIndex + 1;
        break;
      }
    }

    final keys = stationOccurrenceKeys(stationNames);
    for (var index = 0; index < stationNames.length; index++) {
      final stopIndex = matched[index];
      final isEndpoint = index == 0 || index == stationNames.length - 1;
      if (stopIndex != null) {
        result[index] = isEndpoint
            ? _endpointTime(stopIndex, atStart: index == 0)
            : _timeAtStop(stopIndex);
        continue;
      }
      if (isEndpoint) continue;
      final previous = _previousMatched(matched, index);
      final next = _nextMatched(matched, index);
      if (previous == null || next == null) continue;
      result[index] = _estimateBetweenStations(
        previous: previous,
        next: next,
        station: index,
        mileage: mileage,
        matched: matched,
      );
    }

    for (var index = 0; index < result.length; index++) {
      result[index] = _applyPassOverride(keys[index], result[index]);
    }
    return result;
  }

  /// 始发/终到站只显示本次行程用到的那个时刻。
  StationScheduleTime? _endpointTime(int stopIndex, {required bool atStart}) {
    final stop = stops[stopIndex];
    if (atStart) {
      final departure = stop.departure ?? stop.arrival;
      if (departure == null) return null;
      return StationScheduleTime(departure: departure, stopIndex: stopIndex);
    }
    final arrival = stop.arrival ?? stop.departure;
    if (arrival == null) return null;
    return StationScheduleTime(arrival: arrival, stopIndex: stopIndex);
  }

  StationScheduleTime? _applyPassOverride(
    String key,
    StationScheduleTime? time,
  ) {
    final override = passTimeOverrides[key];
    if (override == null || time == null || time.isStop) return time;
    return StationScheduleTime(passTime: override);
  }

  StationScheduleTime? _timeAtStop(int index) {
    final stop = stops[index];
    final arrival = stop.arrival;
    final departure = stop.departure;
    if (arrival != null && departure != null && departure.isAfter(arrival)) {
      return StationScheduleTime(
        arrival: arrival,
        departure: departure,
        stopIndex: index,
      );
    }
    // 只有单边时刻（快照里个别站只给了到点或发点）时按通过处理，但用原值，
    // 不再套匀速模型。
    final exact = arrival ?? departure;
    if (exact != null) return StationScheduleTime(passTime: exact);
    return _estimatePassAtStop(index);
  }

  /// 时刻表里明明有这一站、却没给到发时刻：夹在前后两个有时刻的停站之间估算。
  StationScheduleTime? _estimatePassAtStop(int index) {
    int? previous;
    for (var probe = index - 1; probe >= boardingIndex; probe--) {
      if (_departureTime(probe) != null) {
        previous = probe;
        break;
      }
    }
    int? next;
    for (var probe = index + 1; probe <= alightingIndex; probe++) {
      if (_arrivalTime(probe) != null) {
        next = probe;
        break;
      }
    }
    if (previous == null || next == null) return null;

    final start = _departureTime(previous);
    final end = _arrivalTime(next);
    if (start == null || end == null || !end.isAfter(start)) return null;

    final ratio = _mileageRatio(
      from: _mileageAt(previous),
      at: _mileageAt(index),
      to: _mileageAt(next),
      fallback: (index - previous) / (next - previous),
    );
    return StationScheduleTime(
      passTime: _interpolate(start, end, ratio),
      estimated: true,
    );
  }

  /// 简图上有、时刻表站序里没有的站：用它两侧最近的时刻表停站做匀速插值。
  StationScheduleTime? _estimateBetweenStations({
    required int previous,
    required int next,
    required int station,
    required List<double> mileage,
    required List<int?> matched,
  }) {
    final previousStop = matched[previous];
    final nextStop = matched[next];
    if (previousStop == null || nextStop == null) return null;

    // 锚点本身也可能是没有到发时刻的通过站，用它自己的估算值当端点。
    final start = _effectiveDeparture(previousStop);
    final end = _effectiveArrival(nextStop);
    if (start == null || end == null || !end.isAfter(start)) return null;

    final ratio = _mileageRatio(
      from: previous < mileage.length ? mileage[previous] : null,
      at: station < mileage.length ? mileage[station] : null,
      to: next < mileage.length ? mileage[next] : null,
      fallback: (station - previous) / (next - previous),
    );
    return StationScheduleTime(
      passTime: _interpolate(start, end, ratio),
      estimated: true,
    );
  }

  DateTime? _departureTime(int index) =>
      stops[index].departure ?? stops[index].arrival;

  DateTime? _arrivalTime(int index) =>
      stops[index].arrival ?? stops[index].departure;

  /// 没有到发时刻的通过站，用匀速模型估出来的时刻作为锚点。
  DateTime? _effectiveDeparture(int index) =>
      _departureTime(index) ?? _estimatePassAtStop(index)?.passTime;

  DateTime? _effectiveArrival(int index) =>
      _arrivalTime(index) ?? _estimatePassAtStop(index)?.passTime;

  /// 站序里的累计里程；非始发站的 0 或负值表示缺失（历史库就是这么落的）。
  double? _mileageAt(int index) {
    final value = stops[index].mileage;
    if (value == null) return null;
    if (index > 0 && value <= 0) return null;
    return value;
  }

  static int? _previousMatched(List<int?> matched, int index) {
    for (var probe = index - 1; probe >= 0; probe--) {
      if (matched[probe] != null) return probe;
    }
    return null;
  }

  static int? _nextMatched(List<int?> matched, int index) {
    for (var probe = index + 1; probe < matched.length; probe++) {
      if (matched[probe] != null) return probe;
    }
    return null;
  }
}

/// 叠在简图上的完整时刻层。
///
/// [times] 是匹配到的历史时刻表，可能为空（没数据、版本对不上、时刻不一致）；
/// [customTimes] 是用户自己补的站时刻，没有历史数据时也能用，键见
/// [stationOccurrenceKeys]。自定义时刻优先于历史数据。
class TripScheduleOverlay {
  const TripScheduleOverlay({this.times, this.customTimes = const {}});

  final TripScheduleTimes? times;
  final Map<String, StationScheduleTime> customTimes;

  bool get hasData => times != null || customTimes.isNotEmpty;

  TripScheduleOverlay withTimes(TripScheduleTimes? times) =>
      TripScheduleOverlay(times: times, customTimes: customTimes);

  TripScheduleOverlay withCustomTimes(
    Map<String, StationScheduleTime> customTimes,
  ) => TripScheduleOverlay(times: times, customTimes: customTimes);

  List<StationScheduleTime?> annotate({
    required List<String> stationNames,
    required List<double> mileage,
  }) {
    final result =
        times?.annotate(stationNames: stationNames, mileage: mileage) ??
        List<StationScheduleTime?>.filled(stationNames.length, null);
    if (customTimes.isEmpty) return result;

    final keys = stationOccurrenceKeys(stationNames);
    for (var index = 0; index < result.length; index++) {
      final custom = customTimes[keys[index]];
      if (custom != null) result[index] = custom;
    }
    return result;
  }
}

/// 简图站序里每站一个稳定键：归一化站名 + 同名站的第几次出现。
///
/// 展开/收起只会在已有站之间插入新站，不会改变同名站的先后次序，所以校准
/// 通过时刻用的键在两种布局下都能落回同一站。
List<String> stationOccurrenceKeys(List<String> stationNames) {
  final counts = <String, int>{};
  final keys = <String>[];
  for (final name in stationNames) {
    final normalized = normalizeStationName(name);
    final occurrence = counts[normalized] ?? 0;
    counts[normalized] = occurrence + 1;
    keys.add('$normalized\u0000$occurrence');
  }
  return keys;
}

/// 在车次站序里找出上车站与下车站的下标。
///
/// 下车站必须在上车站之后；同名站出现两次（折返）时取上车站之后第一次遇到的那个。
(int, int)? findJourneyStopIndexes(
  List<TrainScheduleStop> stops,
  String fromStation,
  String toStation,
) {
  final from = normalizeStationName(fromStation);
  final to = normalizeStationName(toStation);
  if (from.isEmpty || to.isEmpty) return null;

  var boarding = -1;
  for (var index = 0; index < stops.length; index++) {
    if (normalizeStationName(stops[index].stationName) == from) {
      boarding = index;
      break;
    }
  }
  if (boarding < 0) return null;

  for (var index = boarding + 1; index < stops.length; index++) {
    if (normalizeStationName(stops[index].stationName) == to) {
      return (boarding, index);
    }
  }
  return null;
}

double _mileageRatio({
  required double? from,
  required double? at,
  required double? to,
  required double fallback,
}) {
  if (from != null && at != null && to != null && to > from) {
    final ratio = (at - from) / (to - from);
    if (ratio.isFinite) return ratio.clamp(0.0, 1.0);
  }
  return fallback.clamp(0.0, 1.0);
}

DateTime _interpolate(DateTime start, DateTime end, double ratio) {
  final total = end.difference(start).inMicroseconds;
  final value = start.add(Duration(microseconds: (total * ratio).round()));
  return _roundToMinute(value);
}

/// 匀速模型的结果只保留到分，四舍五入。
DateTime _roundToMinute(DateTime value) {
  final minute = DateTime(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
  );
  return value.second >= 30 ? minute.add(const Duration(minutes: 1)) : minute;
}

bool _sameMinute(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day &&
    first.hour == second.hour &&
    first.minute == second.minute;
