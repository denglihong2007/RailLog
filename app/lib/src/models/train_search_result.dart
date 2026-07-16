class TrainSearchResult {
  const TrainSearchResult({
    required this.trainNumber,
    required this.departureStation,
    required this.arrivalStation,
    required this.trainNo,
  });

  final String trainNumber;
  final String departureStation;
  final String arrivalStation;
  final String trainNo;

  String get summary => '$departureStation → $arrivalStation $trainNo';

  factory TrainSearchResult.fromJson(Map<String, dynamic> json) {
    return TrainSearchResult(
      trainNumber: json['station_train_code'] ?? '',
      departureStation: json['from_station'] ?? '',
      arrivalStation: json['to_station'] ?? '',
      trainNo: json['train_no'] ?? '',
    );
  }
}