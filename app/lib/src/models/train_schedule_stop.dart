import 'package:raillog/src/models/station_pair_distance.dart';

class TrainScheduleStop {
  const TrainScheduleStop({
    required this.stationName,
    required this.stationNo,
    required this.arriveTime,
    required this.startTime,
    required this.runningTime,
    required this.arriveDay,
    required this.arriveDayDifference,
    this.mileage,
    this.arrivalDateTime,
    this.departureDateTime,
  });

  final String stationName;
  final String stationNo;
  final String arriveTime;
  final String startTime;
  final String runningTime;
  final String arriveDay;
  final int arriveDayDifference;
  final double? mileage;
  final DateTime? arrivalDateTime;
  final DateTime? departureDateTime;

  TrainScheduleStop copyWith({
    DateTime? arrivalDateTime,
    DateTime? departureDateTime,
  }) {
    return TrainScheduleStop(
      stationName: stationName,
      stationNo: stationNo,
      arriveTime: arriveTime,
      startTime: startTime,
      runningTime: runningTime,
      arriveDay: arriveDay,
      arriveDayDifference: arriveDayDifference,
      mileage: mileage,
      arrivalDateTime: arrivalDateTime,
      departureDateTime: departureDateTime,
    );
  }

  factory TrainScheduleStop.fromJson(Map<String, dynamic> json) {
    return TrainScheduleStop(
      stationName: (json['station_name']?.toString() ?? '').replaceAll(
        RegExp(r'\s+'),
        '',
      ),
      stationNo: json['station_no'] ?? '',
      arriveTime: json['arrive_time'] ?? '',
      startTime: json['start_time'] ?? '',
      runningTime: json['running_time'] ?? '',
      arriveDay: json['arrive_day_str'] ?? '',
      arriveDayDifference:
          int.tryParse(json['arrive_day_diff']?.toString() ?? '') ?? 0,
      mileage: (json['mileage'] as num?)?.toDouble(),
    );
  }
}

double? historicalJourneyMileage(
  TrainScheduleStop departure,
  TrainScheduleStop arrival,
) {
  final departureMileage = departure.mileage;
  final arrivalMileage = arrival.mileage;
  if (departureMileage == null || arrivalMileage == null) return null;

  final distance = (arrivalMileage - departureMileage).abs();
  return distance > 0 ? distance : null;
}

/// 所选区间里每一对相邻站的里程，全部来自站序自带的累计里程。
///
/// 途经线路推断要的是「这一段大概多远」，而站序里每一站都写着从始发站起算的累计
/// 里程，相邻两站相减就是这一段 —— 不必再对每对相邻站各打一次里程接口。
/// 缺里程或里程差为 0 的段给 null，推断会退回最短路径。
List<StationPairDistance> historicalSectionDistances(
  List<TrainScheduleStop> stops,
  int departureStopIndex,
  int arrivalStopIndex,
) {
  if (stops.isEmpty ||
      departureStopIndex < 0 ||
      arrivalStopIndex >= stops.length ||
      arrivalStopIndex <= departureStopIndex) {
    return const [];
  }

  return List.generate(arrivalStopIndex - departureStopIndex, (offset) {
    final from = stops[departureStopIndex + offset];
    final to = stops[departureStopIndex + offset + 1];
    return StationPairDistance(
      fromStation: from.stationName,
      toStation: to.stationName,
      distanceKm: historicalJourneyMileage(from, to),
    );
  }, growable: false);
}
