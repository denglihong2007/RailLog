import 'dart:math' as math;

import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/trip_schedule_times.dart';
import 'package:raillog/src/services/rail_track_service.dart';
import 'package:raillog/src/services/trip_map_service.dart';

/// 把「简图模式的站序 + 线路 + 时刻表」合成地图动画用的时间轴。
///
/// 简图模式已经把历史时刻表按里程比例铺到了站序上（[TripScheduleOverlay]），
/// 地图模式要做的是把同一份数据换成「什么时刻走到哪里」：每个站点一个到发
/// 时刻，每个站间区间一段带几何的移动。没有时刻表时退回行程自己的到发时刻；
/// 连到达时刻都没有时才按里程和最高速度估一个，并在播放条上标出来。
abstract final class TripAnimationService {
  /// 行程记录缺到达时刻时的兜底速度。取 200km/h 是因为高铁区间均速大致落在
  /// 这个量级，估出来的进度条至少不会明显跑偏。
  static const double _fallbackSpeedKmh = 200;

  static const String _manualLineLabel = '手动线路';

  static const Duration _minimumMove = Duration(seconds: 1);

  /// [stationNames]/[legRouteNames] 与地图构建共用同一份站序；
  /// [lineColors] 用来给每一段运行上色，缺省颜色走 [fallbackColor]。
  ///
  /// 返回 null 表示这趟行程凑不出可播放的轴（站点不足、坐标缺失或全部重合），
  /// 此时地图照常画折线，不显示播放条。
  static TripAnimationPlan? build({
    required TripRecord trip,
    required List<String> stationNames,
    required List<String> legRouteNames,
    required StationCoordinateIndex coordinates,
    required RailTrackIndex? tracks,
    required TripScheduleOverlay overlay,
    required Map<String, String> lineColors,
    required String fallbackColor,
  }) {
    final names = <String>[];
    final located = <StationCoordinate>[];
    final originalIndexes = <int>[];
    for (var index = 0; index < stationNames.length; index++) {
      final coordinate = coordinates.find(stationNames[index]);
      if (coordinate == null) continue;
      // 同名站、换乘站可能落到同一个坐标；保留两个会让时间轴凭空多出一次
      // 零距离移动，进度条也会在原地停一下。
      if (located.isNotEmpty && _sameCoordinate(located.last, coordinate)) {
        continue;
      }
      names.add(stationNames[index]);
      located.add(coordinate);
      originalIndexes.add(index);
    }
    if (names.length < 2) return null;

    final cumulativeMileage = List<double>.filled(names.length, 0);
    for (var index = 1; index < names.length; index++) {
      cumulativeMileage[index] = cumulativeMileage[index - 1] +
          _distanceKm(located[index - 1], located[index]);
    }
    if (cumulativeMileage.last <= 0) return null;

    final annotations = overlay.annotate(
      stationNames: names,
      mileage: cumulativeMileage,
    );

    // 简图模式已经按同一套站序和里程算过一遍；这里只看各站的到达（或通过）
    // 时刻，所以拿到后统一取一个时刻，不再区分停站与通过。
    final arrivals = <DateTime?>[];
    final departures = <DateTime?>[];
    final estimatedStops = <bool>[];
    var usedSchedule = false;
    for (final annotation in annotations) {
      if (annotation == null) {
        arrivals.add(null);
        departures.add(null);
        estimatedStops.add(false);
        continue;
      }
      usedSchedule = true;
      estimatedStops.add(annotation.estimated);
      if (annotation.isStop) {
        arrivals.add(annotation.arrival);
        departures.add(annotation.departure);
      } else {
        // 通过站没有停站时间，到达和出发都锚在同一个通过时刻上。
        arrivals.add(annotation.passTime);
        departures.add(annotation.passTime);
      }
    }

    final anchors = List<DateTime?>.filled(names.length, null);
    for (var index = 0; index < names.length; index++) {
      final arrival = arrivals[index];
      final departure = departures[index];
      // 始发站时刻表只给发车，终到站只给到达，中间站两者都有。
      anchors[index] = index == 0 ? (departure ?? arrival) : arrival;
    }
    anchors[0] ??= trip.departureTime;
    final arrivalTime = trip.arrivalTime;
    if (anchors[anchors.length - 1] == null && arrivalTime != null) {
      anchors[anchors.length - 1] = arrivalTime;
    }
    var estimatedDuration = false;
    if (anchors[anchors.length - 1] == null) {
      // 行程没填到达时刻：按里程估一个终点，好让进度条有终点可走。
      final hours = cumulativeMileage.last / _fallbackSpeedKmh;
      final seconds = math.max(60, (hours * 3600).round());
      anchors[anchors.length - 1] =
          anchors[0]!.add(Duration(seconds: seconds));
      estimatedDuration = true;
    }

    _interpolateAnchors(
      anchors: anchors,
      mileage: cumulativeMileage,
      estimated: estimatedStops,
    );
    _enforceMonotonic(anchors);

    final departure = anchors[0]!;
    var arrival = anchors[anchors.length - 1]!;
    if (!arrival.isAfter(departure)) {
      arrival = departure.add(_minimumMove);
    }

    final stops = <TripAnimationStop>[];
    for (var index = 0; index < names.length; index++) {
      final isFirst = index == 0;
      final isLast = index == names.length - 1;
      // 时间轴已经被压成单调递增，站点自己的到发时刻也要跟着抬，否则会出现
      // 「10:00 到达、10:05 发车」但时间轴锚点被前站推到 11:00 的矛盾。
      final anchor = anchors[index]!;
      DateTime? arrivalAtStop;
      if (!isFirst) {
        final raw = arrivals[index] ?? anchor;
        arrivalAtStop = raw.isAfter(anchor) ? raw : anchor;
      }
      DateTime? departureAtStop;
      if (!isLast) {
        var raw = departures[index] ?? anchor;
        if (!raw.isAfter(anchor)) raw = anchor;
        if (arrivalAtStop != null && raw.isBefore(arrivalAtStop)) {
          raw = arrivalAtStop;
        }
        departureAtStop = raw;
      }
      final isPass =
          annotations[index] != null && !annotations[index]!.isStop;
      final lineName = isLast
          ? _lineNameAt(legRouteNames, originalIndexes[index - 1])
          : _lineNameAt(legRouteNames, originalIndexes[index]);
      stops.add(
        TripAnimationStop(
          name: names[index],
          coordinate: located[index],
          time: isFirst
              ? departureAtStop!
              : (isLast ? arrivalAtStop! : anchor),
          arrival: arrivalAtStop,
          departure: departureAtStop,
          kind: isPass
              ? TripAnimationStopKind.pass
              : TripAnimationStopKind.stop,
          estimated: estimatedStops[index],
          lineName: lineName,
        ),
      );
    }

    final moves = <TripAnimationMove>[];
    for (var index = 0; index < names.length - 1; index++) {
      final lineName = _lineNameAt(legRouteNames, originalIndexes[index]);
      final color =
          lineColors[lineName] ?? lineColors[_manualLineLabel] ?? fallbackColor;
      final points = buildTrackPoints(
        tracks?.findOriented(lineName, names[index], names[index + 1]),
        located[index],
        located[index + 1],
      );
      var start = stops[index].departure ?? stops[index].time;
      if (moves.isNotEmpty && start.isBefore(moves.last.end)) {
        // 前一站停站跨过了这一段的发车时刻时，宁可让这一段短一点，也不能让
        // 时间轴倒流——播放器按顺序找移动区间，倒流会跳段。
        start = moves.last.end;
      }
      var end = stops[index + 1].arrival ?? stops[index + 1].time;
      if (!end.isAfter(start)) end = start.add(_minimumMove);
      moves.add(
        TripAnimationMove(
          fromIndex: index,
          toIndex: index + 1,
          start: start,
          end: end,
          color: color,
          lineName: lineName,
          points: points,
        ),
      );
    }

    return TripAnimationPlan(
      departure: departure,
      arrival: arrival,
      utcOffsetMinutes: trip.departureTime.timeZoneOffset.inMinutes,
      sourceLabel: usedSchedule
          ? '历史时刻表'
          : (estimatedDuration ? '按里程估算' : '行程时刻'),
      stops: stops,
      moves: moves,
    );
  }

  static String _lineNameAt(List<String> legRouteNames, int index) {
    if (index < 0 || index >= legRouteNames.length) return '';
    return legRouteNames[index];
  }

  /// 把没有时刻的中间站按里程比例插到左右两个已知锚点之间。
  ///
  /// 时刻表只覆盖部分车站时这是常态；用里程而不是站数，长区间和短区间才能
  /// 按实际走行时间分配。
  static void _interpolateAnchors({
    required List<DateTime?> anchors,
    required List<double> mileage,
    required List<bool> estimated,
  }) {
    var previous = 0;
    while (previous < anchors.length - 1 && anchors[previous] == null) {
      previous++;
    }
    for (var index = previous + 1; index < anchors.length; index++) {
      if (anchors[index] == null) continue;
      if (index > previous + 1) {
        final from = anchors[previous]!;
        final to = anchors[index]!;
        final span = mileage[index] - mileage[previous];
        for (var cursor = previous + 1; cursor < index; cursor++) {
          final ratio = span > 0
              ? (mileage[cursor] - mileage[previous]) / span
              : (cursor - previous) / (index - previous);
          anchors[cursor] = from.add(
            Duration(
              seconds: ((to.difference(from).inSeconds) * ratio).round(),
            ),
          );
          estimated[cursor] = true;
        }
      }
      previous = index;
    }
  }

  static void _enforceMonotonic(List<DateTime?> anchors) {
    for (var index = 1; index < anchors.length; index++) {
      final previous = anchors[index - 1];
      final current = anchors[index];
      if (previous == null || current == null) continue;
      if (!current.isAfter(previous)) {
        anchors[index] = previous.add(_minimumMove);
      }
    }
  }

  static double _distanceKm(StationCoordinate from, StationCoordinate to) {
    const earthRadiusKm = 6371.0088;
    final fromLat = _toRadians(from.latitude);
    final toLat = _toRadians(to.latitude);
    final deltaLat = _toRadians(to.latitude - from.latitude);
    final deltaLng = _toRadians(to.longitude - from.longitude);
    final value = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(fromLat) *
            math.cos(toLat) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    return 2 * earthRadiusKm * math.asin(math.min(1, math.sqrt(value)));
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  static bool _sameCoordinate(StationCoordinate a, StationCoordinate b) =>
      (a.latitude - b.latitude).abs() < 1e-9 &&
      (a.longitude - b.longitude).abs() < 1e-9;
}
