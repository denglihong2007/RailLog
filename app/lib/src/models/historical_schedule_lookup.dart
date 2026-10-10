import 'package:raillog/src/models/train_schedule_stop.dart';

/// 按乘车日期从历史时刻表查到的整趟站序。
class HistoricalScheduleLookup {
  const HistoricalScheduleLookup({
    required this.version,
    required this.trainNumber,
    required this.stops,
  });

  /// 命中的历史版本（`yyyy.MM.dd`）。
  final String version;

  /// 命中车次的车次号。
  final String trainNumber;

  final List<TrainScheduleStop> stops;
}
