class TrainDistanceInfo {
  const TrainDistanceInfo({required this.distance, required this.companyName});

  final double distance;
  final String companyName;

  factory TrainDistanceInfo.fromJson(Map<String, dynamic> json) {
    return TrainDistanceInfo(
      distance: (json['distance'] as num).toDouble(),
      companyName: json['companyName']?.toString() ?? '',
    );
  }
}
