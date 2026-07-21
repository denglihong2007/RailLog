class TrainScheduleStop {
  const TrainScheduleStop({
    required this.stationName,
    required this.stationNo,
    required this.arriveTime,
    required this.startTime,
    required this.runningTime,
    required this.arriveDay,
    required this.arriveDayDifference,
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
    );
  }
}
