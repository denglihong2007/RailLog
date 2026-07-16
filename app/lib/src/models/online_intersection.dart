enum OnlineIntersectionKind { station, train }

class OnlineIntersection {
  const OnlineIntersection({
    required this.kind,
    required this.location,
    required this.intersectionCount,
    required this.trips,
  });

  factory OnlineIntersection.fromJson(Map<String, dynamic> json) {
    return OnlineIntersection(
      kind: json['kind'] == 'train'
          ? OnlineIntersectionKind.train
          : OnlineIntersectionKind.station,
      location: json['location'] as String,
      intersectionCount: (json['intersectionCount'] as num).toInt(),
      trips: (json['trips'] as List<dynamic>? ?? const [])
          .map(
            (item) => IntersectionTrip.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }

  final OnlineIntersectionKind kind;
  final String location;
  final int intersectionCount;
  final List<IntersectionTrip> trips;
}

class IntersectionTrip {
  const IntersectionTrip({
    required this.ticketId,
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
    required this.occurredAt,
    required this.isStrict,
    required this.trainNumber,
  });

  factory IntersectionTrip.fromJson(Map<String, dynamic> json) {
    return IntersectionTrip(
      ticketId: (json['ticketId'] as num).toInt(),
      userId: json['userId'] as String,
      displayName: json['displayName'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      occurredAt: _date(json['occurredAt'])!,
      isStrict: json['isStrict'] as bool? ?? false,
      trainNumber: json['trainNumber'] as String,
    );
  }

  final int ticketId;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final DateTime occurredAt;
  final bool isStrict;
  final String trainNumber;
}

DateTime? _date(Object? value) {
  if (value is! String) return null;
  return DateTime.parse(value).toLocal();
}
