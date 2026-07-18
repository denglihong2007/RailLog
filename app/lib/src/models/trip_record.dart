import 'dart:convert';
import 'dart:math';
import 'via_route_segment.dart';

class TripRecord {
  final int id;
  final int? ticketId;
  final String clientId;
  final String? ownerUserId;
  final String trainNumber;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? rollingStock;
  final String? companyName;
  final String fromStation;
  final String toStation;
  final DateTime departureTime;
  final DateTime? arrivalTime;
  final double mileageKm;
  final List<ViaRouteSegment> viaRouteSegments;
  final String? seatType;
  final String? seatNumber;
  final double price;
  final bool isRailTrip;
  final String? notes;

  String get ticketLabel => ticketId == null ? '本地 #$id' : '#$ticketId';

  double? get averageSpeedKmh {
    final arrival = arrivalTime;
    if (arrival == null || mileageKm <= 0) return null;
    final duration = arrival.difference(departureTime);
    if (duration <= Duration.zero) return null;
    return mileageKm / (duration.inMilliseconds / 3600000);
  }

  double? get averagePricePerKm {
    if (mileageKm <= 0) return null;
    return price / mileageKm;
  }

  TripRecord({
    required this.id,
    this.ticketId,
    String? clientId,
    this.ownerUserId,
    required this.trainNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.rollingStock,
    this.companyName,
    required this.fromStation,
    required this.toStation,
    required this.departureTime,
    this.arrivalTime,
    this.mileageKm = 0.0,
    required this.viaRouteSegments,
    this.seatType,
    this.seatNumber,
    this.price = 0.0,
    this.isRailTrip = true,
    this.notes,
  }) : clientId = clientId ?? _newClientId(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ticket_id': ticketId,
      'client_id': clientId,
      'owner_user_id': ownerUserId,
      'train_number': trainNumber,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
      'rolling_stock': rollingStock,
      'company_name': companyName,
      'from_station': fromStation,
      'to_station': toStation,
      'departure_time': departureTime.toIso8601String(),
      'arrival_time': arrivalTime?.toIso8601String(),
      'mileage_km': mileageKm,
      'via_route_segments': jsonEncode(
        viaRouteSegments.map((e) => e.toJson()).toList(),
      ),
      'seat_type': seatType,
      'seat_number': seatNumber,
      'price': price,
      'is_rail_trip': isRailTrip ? 1 : 0,
      'notes': notes,
    };
  }

  factory TripRecord.fromMap(Map<String, dynamic> map) {
    final List<dynamic> segmentsJson = jsonDecode(
      map['via_route_segments'] as String,
    );
    final segments = segmentsJson
        .map((e) => ViaRouteSegment.fromJson(e as Map<String, dynamic>))
        .toList();

    return TripRecord(
      id: map['id'] as int,
      ticketId: (map['ticket_id'] as num?)?.toInt(),
      clientId: map['client_id'] as String?,
      ownerUserId: map['owner_user_id'] as String?,
      trainNumber: map['train_number'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] == null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.parse(map['updated_at'] as String),
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.parse(map['deleted_at'] as String),
      rollingStock: map['rolling_stock'] as String?,
      companyName: map['company_name'] as String?,
      fromStation: map['from_station'] as String,
      toStation: map['to_station'] as String,
      departureTime: DateTime.parse(map['departure_time'] as String),
      arrivalTime: map['arrival_time'] != null
          ? DateTime.parse(map['arrival_time'] as String)
          : null,
      mileageKm: (map['mileage_km'] as num).toDouble(),
      viaRouteSegments: segments,
      seatType: map['seat_type'] as String?,
      seatNumber: map['seat_number'] as String?,
      price: (map['price'] as num).toDouble(),
      isRailTrip: (map['is_rail_trip'] as int) == 1,
      notes: map['notes'] as String?,
    );
  }
}

String _newClientId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}
