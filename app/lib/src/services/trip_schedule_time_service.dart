import 'package:raillog/src/models/timetable_version.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/trip_schedule_times.dart';
import 'package:raillog/src/services/train_service.dart';

/// 为行程详情读取历史时刻表，并校验它与用户录入的发/到时刻是否一致。
///
/// 读不到版本、查不到同号车次、时刻对不上都返回 null —— 简图本来就不依赖它，
/// 拿不到时刻时静默不显示即可。
class TripScheduleTimeService {
  /// 简图与地图来回切换会重建整个视图，查一次就缓存住，避免重复打两次接口。
  /// 只缓存成功的匹配：网络失败时下次进入还能再试。
  static final Map<String, TripScheduleTimes> _cache = {};

  static Future<TripScheduleTimes?> load(TripRecord trip) async {
    final key = _cacheKey(trip);
    final cached = _cache[key];
    if (cached != null) return cached;
    try {
      final versions = await TrainService.fetchTimetableVersions();
      final version = resolveTimetableVersion(trip.departureTime, versions);
      if (version == null) return null;

      // 只认同号车次：检索是前缀匹配，退而取其次会把别的车的时刻叠到这条行程上。
      final lookup = await TrainService.lookupHistoricalSchedule(
        trainNumber: trip.trainNumber,
        boardingDate: trip.departureTime,
        version: version,
        fallbackToFirst: false,
      );
      if (lookup == null) return null;

      final indexes = findJourneyStopIndexes(
        lookup.stops,
        trip.fromStation,
        trip.toStation,
      );
      if (indexes == null) return null;
      final (boardingIndex, alightingIndex) = indexes;

      final resolved = TrainService.resolveScheduleDateTimes(
        lookup.stops,
        trip.departureTime,
        boardingIndex,
      );
      final times = TripScheduleTimes.match(
        resolvedStops: resolved,
        boardingIndex: boardingIndex,
        alightingIndex: alightingIndex,
        departureTime: trip.departureTime,
        arrivalTime: trip.arrivalTime,
      );
      if (times != null) _cache[key] = times;
      return times;
    } catch (_) {
      return null;
    }
  }

  static String _cacheKey(TripRecord trip) => [
    trip.trainNumber,
    trip.departureTime.toIso8601String(),
    trip.arrivalTime?.toIso8601String() ?? '',
    trip.fromStation,
    trip.toStation,
  ].join('\u0000');
}
