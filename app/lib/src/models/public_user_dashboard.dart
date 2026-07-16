import 'dart:convert';

import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';

class PublicUserDashboard {
  const PublicUserDashboard({required this.user, required this.trips});

  factory PublicUserDashboard.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'] as Map<String, dynamic>;
    return PublicUserDashboard(
      user: PublicUser.fromJson(userJson),
      trips: (json['trips'] as List<dynamic>? ?? const [])
          .map(
            (row) => publicTripFromJson(
              row as Map<String, dynamic>,
              userJson['id'] as String,
            ),
          )
          .toList(growable: false),
    );
  }

  final PublicUser user;
  final List<TripRecord> trips;

  TripRecord? tripByTicketId(int? ticketId) {
    if (ticketId == null) return null;
    for (final trip in trips) {
      if (trip.ticketId == ticketId) return trip;
    }
    return null;
  }
}

class PublicUser {
  const PublicUser({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    this.email,
  });

  factory PublicUser.fromJson(Map<String, dynamic> json) => PublicUser(
    id: json['id'] as String,
    displayName: json['displayName'] as String,
    avatarUrl: json['avatarUrl'] as String?,
    bio: json['bio'] as String?,
    email: json['email'] as String?,
  );

  final String id;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final String? email;
}

TripRecord publicTripFromJson(Map<String, dynamic> json, String userId) {
  final ticketId = (json['ticketId'] as num).toInt();
  return TripRecord(
    id: -ticketId,
    ticketId: ticketId,
    ownerUserId: userId,
    trainNumber: json['trainNumber'] as String,
    createdAt: _date(json['createdAt'])!,
    rollingStock: json['rollingStock'] as String?,
    companyName: json['companyName'] as String?,
    fromStation: json['fromStation'] as String,
    toStation: json['toStation'] as String,
    departureTime: _date(json['departureTime']) ?? _date(json['createdAt'])!,
    arrivalTime: _date(json['arrivalTime']),
    mileageKm: (json['mileageKm'] as num).toDouble(),
    viaRouteSegments: _routeSegments(json['viaRoutes'] as String?),
    seatType: json['seatType'] as String?,
    seatNumber: json['seatNumber'] as String?,
    price: (json['price'] as num).toDouble(),
    notes: json['notes'] as String?,
    isRailTrip: json['isRailTrip'] as bool? ?? true,
  );
}

DateTime? _date(Object? value) {
  if (value is! String) return null;
  return DateTime.parse(value).toLocal();
}

List<ViaRouteSegment> _routeSegments(String? value) {
  if (value == null || value.isEmpty) return const [];
  try {
    return (jsonDecode(value) as List<dynamic>)
        .map((row) => ViaRouteSegment.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}
