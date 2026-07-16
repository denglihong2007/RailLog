import 'dart:convert';

import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';

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
    required this.bio,
    required this.email,
    required this.occurredAt,
    required this.isStrict,
    required this.trainNumber,
    required this.fromStation,
    required this.toStation,
    required this.departureTime,
    required this.arrivalTime,
    required this.mileageKm,
    required this.viaRouteSegments,
    required this.seatType,
    required this.seatNumber,
    required this.price,
    required this.rollingStock,
    required this.companyName,
  });

  factory IntersectionTrip.fromJson(Map<String, dynamic> json) {
    return IntersectionTrip(
      ticketId: (json['ticketId'] as num).toInt(),
      userId: json['userId'] as String,
      displayName: json['displayName'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      bio: json['bio'] as String?,
      email: json['email'] as String?,
      occurredAt: _date(json['occurredAt'])!,
      isStrict: json['isStrict'] as bool? ?? false,
      trainNumber: json['trainNumber'] as String,
      fromStation: json['fromStation'] as String,
      toStation: json['toStation'] as String,
      departureTime: _date(json['departureTime']),
      arrivalTime: _date(json['arrivalTime']),
      mileageKm: (json['mileageKm'] as num).toDouble(),
      viaRouteSegments: _routeSegments(json['viaRoutes'] as String?),
      seatType: json['seatType'] as String?,
      seatNumber: json['seatNumber'] as String?,
      price: (json['price'] as num).toDouble(),
      rollingStock: json['rollingStock'] as String?,
      companyName: json['companyName'] as String?,
    );
  }

  final int ticketId;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final String? email;
  final DateTime occurredAt;
  final bool isStrict;
  final String trainNumber;
  final String fromStation;
  final String toStation;
  final DateTime? departureTime;
  final DateTime? arrivalTime;
  final double mileageKm;
  final List<ViaRouteSegment> viaRouteSegments;
  final String? seatType;
  final String? seatNumber;
  final double price;
  final String? rollingStock;
  final String? companyName;

  TripRecord toTripRecord() => TripRecord(
    id: 0,
    ticketId: ticketId,
    ownerUserId: userId,
    trainNumber: trainNumber,
    rollingStock: rollingStock,
    companyName: companyName,
    fromStation: fromStation,
    toStation: toStation,
    departureTime: departureTime ?? occurredAt,
    arrivalTime: arrivalTime,
    mileageKm: mileageKm,
    viaRouteSegments: viaRouteSegments,
    seatType: seatType,
    seatNumber: seatNumber,
    price: price,
  );
}

DateTime? _date(Object? value) {
  if (value is! String) return null;
  return DateTime.parse(value).toLocal();
}

List<ViaRouteSegment> _routeSegments(String? value) {
  if (value == null || value.isEmpty) return const [];
  try {
    final rows = jsonDecode(value) as List<dynamic>;
    return rows
        .map((row) => ViaRouteSegment.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}
