class TrainSearchResult {
  const TrainSearchResult({
    required this.trainNumber,
    required this.departureStation,
    required this.arrivalStation,
    required this.trainNo,
    this.lookupDate,
  });

  final String trainNumber;
  final String departureStation;
  final String arrivalStation;
  final String trainNo;
  final DateTime? lookupDate;

  String get summary => '$departureStation → $arrivalStation $trainNo';

  factory TrainSearchResult.fromJson(
    Map<String, dynamic> json, {
    DateTime? lookupDate,
  }) {
    return TrainSearchResult(
      trainNumber: json['station_train_code'] ?? '',
      departureStation: json['from_station'] ?? '',
      arrivalStation: json['to_station'] ?? '',
      trainNo: json['train_no'] ?? '',
      lookupDate: lookupDate,
    );
  }
}
