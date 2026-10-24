import 'package:raillog/src/models/timetable_version.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';
import 'package:raillog/src/models/train_search_result.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/route_service.dart';
import 'package:raillog/src/services/train_service.dart';

/// 批量重建的目标字段。
enum TimetableRebuildMode {
  /// 按历史时刻表重算到点。
  arrivalTime,

  /// 按历史时刻表重算经由线路。
  viaRoute,
}

/// 一张没处理成功的车票，以及原因。
class TimetableRebuildIssue {
  const TimetableRebuildIssue({required this.label, required this.reason});

  final String label;
  final String reason;
}

/// 一条待用户确认的修改。
///
/// 计划阶段只算不写：批量操作没人逐张复核，写错比没写更糟，所以把新旧值都摆出来，
/// 由用户逐条采纳后再落库。
class TimetableRebuildProposal {
  const TimetableRebuildProposal({
    required this.trip,
    required this.mode,
    this.previousArrivalTime,
    this.arrivalTime,
    this.previousViaRouteSegments = const [],
    this.viaRouteSegments = const [],
  });

  factory TimetableRebuildProposal.arrivalTime({
    required TripRecord trip,
    required DateTime arrivalTime,
  }) => TimetableRebuildProposal(
    trip: trip,
    mode: TimetableRebuildMode.arrivalTime,
    previousArrivalTime: trip.arrivalTime,
    arrivalTime: arrivalTime,
  );

  factory TimetableRebuildProposal.viaRoute({
    required TripRecord trip,
    required List<ViaRouteSegment> viaRouteSegments,
  }) => TimetableRebuildProposal(
    trip: trip,
    mode: TimetableRebuildMode.viaRoute,
    previousArrivalTime: trip.arrivalTime,
    arrivalTime: trip.arrivalTime,
    previousViaRouteSegments: trip.viaRouteSegments,
    viaRouteSegments: viaRouteSegments,
  );

  final TripRecord trip;
  final TimetableRebuildMode mode;
  final DateTime? previousArrivalTime;
  final DateTime? arrivalTime;
  final List<ViaRouteSegment> previousViaRouteSegments;
  final List<ViaRouteSegment> viaRouteSegments;

  /// 采纳后的车票记录（尚未落库）。
  TripRecord appliedTrip() => switch (mode) {
    TimetableRebuildMode.arrivalTime => trip.copyWith(arrivalTime: arrivalTime),
    TimetableRebuildMode.viaRoute => trip.copyWith(
      viaRouteSegments: viaRouteSegments,
    ),
  };
}

/// 计划阶段的结果：待确认的修改 + 无需修改/无法重建的部分。
class TimetableRebuildPlan {
  const TimetableRebuildPlan({
    required this.mode,
    required this.proposals,
    required this.issues,
    required this.unchanged,
    required this.cancelled,
  });

  final TimetableRebuildMode mode;
  final List<TimetableRebuildProposal> proposals;
  final List<TimetableRebuildIssue> issues;

  /// 历史库算出来与原值一致、没有修改可审的车票数。
  final int unchanged;

  /// 是否在计划阶段被调用方中途停止；已算出的部分仍然可以审阅。
  final bool cancelled;

  int get processed => proposals.length + issues.length + unchanged;

  bool get isEmpty => proposals.isEmpty;
}

class TimetableRebuildApplyResult {
  const TimetableRebuildApplyResult({
    required this.applied,
    required this.failed,
  });

  final int applied;
  final int failed;
}

/// 按历史时刻表批量重建车票的到点或经由线路。
///
/// 分成两步：[plan] 只查历史库、算出新旧值；用户逐条确认后 [apply] 才写库。
/// 车票本身仍是本地库的唯一数据源：查不到的一律跳过，绝不拿别的车次或
/// 「最短路径」硬凑。
class TimetableRebuildService {
  TimetableRebuildService._();

  /// 查询历史时刻表，给出待确认的修改清单。
  static Future<TimetableRebuildPlan> plan({
    required Iterable<TripRecord> trips,
    required TimetableRebuildMode mode,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final selected = trips.toList(growable: false);
    final issues = <TimetableRebuildIssue>[];
    final proposals = <TimetableRebuildProposal>[];
    var unchanged = 0;
    var cancelled = false;

    final versions = await TrainService.fetchTimetableVersions();
    if (versions.isEmpty) {
      return TimetableRebuildPlan(
        mode: mode,
        proposals: const [],
        issues: const [
          TimetableRebuildIssue(label: '全部车票', reason: '没有可用的历史时刻表版本'),
        ],
        unchanged: 0,
        cancelled: false,
      );
    }

    // 同一趟车、同一个区间在一个批次里可能被选了很多次，站序只查一遍。
    final scheduleCache = <String, List<TrainScheduleStop>?>{};

    for (var index = 0; index < selected.length; index++) {
      if (isCancelled?.call() ?? false) {
        cancelled = true;
        break;
      }
      final trip = selected[index];
      try {
        final result = await _planTrip(trip, mode, versions, scheduleCache);
        switch (result.outcome) {
          case _TripOutcome.changed:
            proposals.add(result.proposal!);
          case _TripOutcome.unchanged:
            unchanged++;
          case _TripOutcome.skipped:
            issues.add(
              TimetableRebuildIssue(
                label: _tripLabel(trip),
                reason: result.reason ?? '已跳过',
              ),
            );
        }
      } catch (error) {
        issues.add(
          TimetableRebuildIssue(label: _tripLabel(trip), reason: '处理失败：$error'),
        );
      }
      onProgress?.call(index + 1, selected.length);
    }

    return TimetableRebuildPlan(
      mode: mode,
      proposals: proposals,
      issues: issues,
      unchanged: unchanged,
      cancelled: cancelled,
    );
  }

  /// 把用户采纳的修改写回本地库。逐条写入，单条失败不影响其余条目。
  static Future<TimetableRebuildApplyResult> apply(
    Iterable<TimetableRebuildProposal> proposals, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final list = proposals.toList(growable: false);
    var applied = 0;
    var failed = 0;
    for (var index = 0; index < list.length; index++) {
      try {
        await DbHelper.instance.updateTrip(list[index].appliedTrip());
        applied++;
      } catch (_) {
        failed++;
      }
      onProgress?.call(index + 1, list.length);
    }
    return TimetableRebuildApplyResult(applied: applied, failed: failed);
  }

  static Future<_TripResult> _planTrip(
    TripRecord trip,
    TimetableRebuildMode mode,
    List<String> versions,
    Map<String, List<TrainScheduleStop>?> scheduleCache,
  ) async {
    if (!trip.isRailTrip) {
      return const _TripResult(_TripOutcome.skipped, '非铁路行程');
    }
    final version = resolveTimetableVersion(trip.departureTime, versions);
    if (version == null) {
      return const _TripResult(_TripOutcome.skipped, '没有可用的历史时刻表版本');
    }

    final scheduleKey =
        '${_trainCodesKey(trip.trainNumber)}|$version|'
        '${normalizeStationName(trip.fromStation)}|'
        '${normalizeStationName(trip.toStation)}';
    List<TrainScheduleStop>? stops;
    if (scheduleCache.containsKey(scheduleKey)) {
      stops = scheduleCache[scheduleKey];
    } else {
      stops = await _findHistoricalSchedule(trip, version);
      scheduleCache[scheduleKey] = stops;
    }
    if (stops == null || stops.isEmpty) {
      return _TripResult(_TripOutcome.skipped, '历史时刻表 $version 中没有该车次');
    }

    final match = matchHistoricalSegment(
      stops: stops,
      fromStation: trip.fromStation,
      toStation: trip.toStation,
      departureTime: trip.departureTime,
    );
    if (match == null) {
      return _TripResult(
        _TripOutcome.skipped,
        '历史时刻表中没有 ${trip.fromStation} → ${trip.toStation} 的停站区间',
      );
    }

    if (mode == TimetableRebuildMode.arrivalTime) {
      final arrival = match.arrivalTime;
      if (arrival == null) {
        return const _TripResult(_TripOutcome.skipped, '历史时刻表中该区间没有到点');
      }
      if (!arrival.isAfter(trip.departureTime)) {
        return const _TripResult(_TripOutcome.skipped, '历史时刻表的到点不晚于出发时间');
      }
      if (_sameMinute(arrival, trip.arrivalTime)) {
        return const _TripResult(_TripOutcome.unchanged);
      }
      return _TripResult(
        _TripOutcome.changed,
        null,
        TimetableRebuildProposal.arrivalTime(trip: trip, arrivalTime: arrival),
      );
    }

    final sections = historicalSectionDistances(
      stops,
      match.departureIndex,
      match.arrivalIndex,
    );
    if (sections.isEmpty) {
      return const _TripResult(_TripOutcome.skipped, '历史时刻表中该区间没有相邻停站');
    }
    if (sections.every((section) => section.distanceKm == null)) {
      return const _TripResult(_TripOutcome.skipped, '历史时刻表所选区间没有有效里程数据');
    }
    final resolution = await RouteService.resolveJourney(sections);
    if (resolution.unresolvedSections.isNotEmpty) {
      return _TripResult(
        _TripOutcome.skipped,
        '无法推断区间：${resolution.unresolvedSections.join('、')}',
      );
    }
    final segments = normalizeViaRouteSegments(
      resolution.segments,
      startStation: trip.fromStation,
      endStation: trip.toStation,
    );
    if (segments.isEmpty) {
      return const _TripResult(_TripOutcome.skipped, '无法推断经由线路');
    }
    final routeError = validateViaRouteSegments(
      segments,
      startStation: trip.fromStation,
      endStation: trip.toStation,
    );
    if (routeError != null) {
      return _TripResult(_TripOutcome.skipped, routeError);
    }
    if (_sameSegments(segments, trip.viaRouteSegments)) {
      return const _TripResult(_TripOutcome.unchanged);
    }
    return _TripResult(
      _TripOutcome.changed,
      null,
      TimetableRebuildProposal.viaRoute(trip: trip, viaRouteSegments: segments),
    );
  }

  /// 按车次号 + 版本找整趟站序。
  ///
  /// 车次可能记成号对（`D111/D114`），检索接口按**单个号**前缀匹配，所以拆开逐个
  /// 查。同一个单号可能挂在多个号对下（是两趟不同的车），这时逐个拉站序、用
  /// [matchHistoricalSegment] 验证车票区间确实落在这一趟上，再采用。
  static Future<List<TrainScheduleStop>?> _findHistoricalSchedule(
    TripRecord trip,
    String version,
  ) async {
    final tripCodes = _trainCodes(trip.trainNumber);
    if (tripCodes.isEmpty) return null;

    final candidates = <String, _ScheduleCandidate>{};
    for (final code in tripCodes) {
      // 放宽到 200 条：短号（G1）的前缀结果很容易被 G10/G100… 挤满，
      // 号对车次（G1/G2）反而会落在默认的 20 条之外。
      final results = await TrainService.searchHistoricalTrains(
        code,
        version,
        limit: 200,
      );
      for (final result in results) {
        // 用规范号对去重：按命中号 "D114" 查站序时，服务端会在同号的多个号对里
        // 按固定优先级挑一个，未必是这一行对应的那趟车。
        final codes = _trainCodes(result.lookupTrainNumber);
        if (codes.isEmpty) continue;
        final key = (codes.toList()..sort()).join('/');
        candidates.putIfAbsent(key, () => _ScheduleCandidate(result, codes));
      }
    }
    if (candidates.isEmpty) return null;

    final ranked = candidates.values.toList()
      ..sort(
        (first, second) =>
            _candidateRank(first.codes, tripCodes) -
            _candidateRank(second.codes, tripCodes),
      );

    List<TrainScheduleStop>? fallback;
    // 通常第一条就命中；留几条给同号多号对的情况，别为一趟车无限重查。
    for (final candidate in ranked.take(4)) {
      final stops = await TrainService.fetchTrainSchedule(
        candidate.train.lookupTrainNumber,
        trip.departureTime,
        historicalVersion: version,
      );
      if (stops.isEmpty) continue;
      fallback ??= stops;
      final match = matchHistoricalSegment(
        stops: stops,
        fromStation: trip.fromStation,
        toStation: trip.toStation,
        departureTime: trip.departureTime,
      );
      if (match != null) return stops;
    }
    return fallback;
  }

  /// 把车票的上下车站对到历史站序上。
  ///
  /// 折返车会在同一条线上两次经过同一个站（西安换向的 灞桥→西安→灞桥），
  /// 站名本身分不清去程还是回程。这里按**发车时刻最接近**的那次停站来选，
  /// 到站取它后面的第一次停靠；这样两张方向相反的车票不会都套去程那一段。
  static HistoricalSegmentMatch? matchHistoricalSegment({
    required List<TrainScheduleStop> stops,
    required String fromStation,
    required String toStation,
    required DateTime departureTime,
  }) {
    final from = normalizeStationName(fromStation);
    final to = normalizeStationName(toStation);
    if (from.isEmpty || to.isEmpty || stops.length < 2) return null;

    HistoricalSegmentMatch? best;
    var bestDifference = Duration.zero;
    for (
      var departureIndex = 0;
      departureIndex < stops.length;
      departureIndex++
    ) {
      if (normalizeStationName(stops[departureIndex].stationName) != from) {
        continue;
      }
      // 每个候选发站都要按它自己的日序算出日期，折返车的两次停靠可能不在同一天。
      final resolved = TrainService.resolveScheduleDateTimes(
        stops,
        departureTime,
        departureIndex,
      );
      final resolvedDeparture =
          resolved[departureIndex].departureDateTime ??
          resolved[departureIndex].arrivalDateTime;
      if (resolvedDeparture == null) continue;

      for (
        var arrivalIndex = departureIndex + 1;
        arrivalIndex < resolved.length;
        arrivalIndex++
      ) {
        if (normalizeStationName(stops[arrivalIndex].stationName) != to) {
          continue;
        }
        final resolvedArrival =
            resolved[arrivalIndex].arrivalDateTime ??
            resolved[arrivalIndex].departureDateTime;
        if (resolvedArrival == null) continue;
        final difference = resolvedDeparture.difference(departureTime).abs();
        if (best == null || difference < bestDifference) {
          best = HistoricalSegmentMatch(
            resolvedStops: resolved,
            departureIndex: departureIndex,
            arrivalIndex: arrivalIndex,
          );
          bestDifference = difference;
        }
        // 同一发站之后的第一处终到站就是这张票要的区间，后面的同名停靠是折返。
        break;
      }
    }
    return best;
  }

  static String _trainCodesKey(String value) {
    final codes = _trainCodes(value).toList()..sort();
    return codes.join('/');
  }

  static Set<String> _trainCodes(String value) {
    return value
        .toUpperCase()
        .replaceAll('次', '')
        .split('/')
        .map((code) => code.replaceAll(RegExp(r'\s+'), '').trim())
        .where((code) => code.isNotEmpty)
        .toSet();
  }

  /// 号对越贴近车票记的车次越优先：完全一致 > 车票只记了其中一个号 > 其余。
  static int _candidateRank(Set<String> candidate, Set<String> tripCodes) {
    if (!candidate.containsAll(tripCodes)) return 2;
    return candidate.length == tripCodes.length ? 0 : 1;
  }

  static bool _sameMinute(DateTime first, DateTime? second) {
    if (second == null) return false;
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day &&
        first.hour == second.hour &&
        first.minute == second.minute;
  }

  static bool _sameSegments(
    List<ViaRouteSegment> first,
    List<ViaRouteSegment> second,
  ) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      final left = first[index];
      final right = second[index];
      if (left.routeName != right.routeName ||
          left.fromStation != right.fromStation ||
          left.toStation != right.toStation ||
          (left.mileageKm - right.mileageKm).abs() > 0.05) {
        return false;
      }
    }
    return true;
  }

  static String _tripLabel(TripRecord trip) =>
      '${trip.trainNumber} ${trip.fromStation}→${trip.toStation}'
      '（${trip.ticketLabel}）';
}

/// 历史站序里与车票区间对应的一段。
class HistoricalSegmentMatch {
  const HistoricalSegmentMatch({
    required this.resolvedStops,
    required this.departureIndex,
    required this.arrivalIndex,
  });

  /// 已按乘车日期补好日期时间的整趟站序。
  final List<TrainScheduleStop> resolvedStops;
  final int departureIndex;
  final int arrivalIndex;

  DateTime? get arrivalTime =>
      resolvedStops[arrivalIndex].arrivalDateTime ??
      resolvedStops[arrivalIndex].departureDateTime;
}

enum _TripOutcome { changed, unchanged, skipped }

class _TripResult {
  const _TripResult(this.outcome, [this.reason, this.proposal]);

  final _TripOutcome outcome;
  final String? reason;
  final TimetableRebuildProposal? proposal;
}

class _ScheduleCandidate {
  const _ScheduleCandidate(this.train, this.codes);

  final TrainSearchResult train;
  final Set<String> codes;
}
