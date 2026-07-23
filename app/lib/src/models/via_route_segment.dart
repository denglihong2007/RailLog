class ViaRouteSegment {
  final String routeName;
  final String fromStation;
  final String toStation;
  final double mileageKm;

  const ViaRouteSegment({
    required this.routeName,
    required this.fromStation,
    required this.toStation,
    this.mileageKm = 0.0,
  });

  // 转为纯 Map 结构（供父表做 jsonEncode 序列化）
  Map<String, dynamic> toJson() => {
    'routeName': routeName,
    'fromStation': fromStation,
    'toStation': toStation,
    'mileageKm': mileageKm,
  };

  // 从 Map 结构解析（供父表做 jsonDecode 反序列化）
  factory ViaRouteSegment.fromJson(Map<String, dynamic> json) =>
      ViaRouteSegment(
        routeName: json['routeName'] as String,
        fromStation: json['fromStation'] as String,
        toStation: json['toStation'] as String,
        mileageKm: (json['mileageKm'] as num).toDouble(),
      );
}

List<ViaRouteSegment> normalizeViaRouteSegments(
  List<ViaRouteSegment> source, {
  required String startStation,
  required String endStation,
}) {
  final result = <ViaRouteSegment>[];
  for (var index = 0; index < source.length; index++) {
    final segment = source[index];
    result.add(
      ViaRouteSegment(
        routeName: segment.routeName,
        fromStation: index == 0 ? startStation.trim() : result.last.toStation,
        toStation: index == source.length - 1
            ? endStation.trim()
            : segment.toStation.trim(),
        mileageKm: segment.mileageKm,
      ),
    );
  }
  return result;
}

bool hasValidRouteContinuity(
  List<ViaRouteSegment> segments, {
  required String startStation,
  required String endStation,
}) {
  if (segments.isEmpty) return true;
  if (segments.first.fromStation != startStation.trim() ||
      segments.last.toStation != endStation.trim()) {
    return false;
  }
  for (var index = 1; index < segments.length; index++) {
    if (segments[index - 1].toStation != segments[index].fromStation) {
      return false;
    }
  }
  return true;
}

String? validateViaRouteSegments(
  List<ViaRouteSegment> segments, {
  required String startStation,
  required String endStation,
}) {
  for (var index = 0; index < segments.length; index++) {
    final segment = segments[index];
    final fromStation = segment.fromStation.trim();
    final toStation = segment.toStation.trim();
    if (fromStation.isNotEmpty &&
        toStation.isNotEmpty &&
        fromStation == toStation) {
      return '第${index + 1}段经由的始发站和终到站不能相同';
    }

    if (index > 0 &&
        segment.routeName.trim().isNotEmpty &&
        segment.routeName.trim() == segments[index - 1].routeName.trim()) {
      return '第$index段和第${index + 1}段经由的线路不能相同';
    }
  }

  if (!hasValidRouteContinuity(
    segments,
    startStation: startStation,
    endStation: endStation,
  )) {
    return '经由线路必须首尾相接并覆盖乘车区间';
  }
  return null;
}
