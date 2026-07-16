import 'package:raillog/src/models/trip_record.dart';

class DashboardTripEntry {
  const DashboardTripEntry({
    required this.id,
    this.ticketId,
    required this.trainNumber,
    required this.fromStation,
    required this.toStation,
    required this.departureTime,
    required this.arrivalTime,
    required this.mileageKm,
    required this.seatType,
    required this.seatNumber,
    required this.price,
    required this.isRailTrip,
  });

  factory DashboardTripEntry.fromTrip(TripRecord trip) {
    return DashboardTripEntry(
      id: trip.id,
      ticketId: trip.ticketId,
      trainNumber: trip.trainNumber,
      fromStation: trip.fromStation,
      toStation: trip.toStation,
      departureTime: trip.departureTime,
      arrivalTime: trip.arrivalTime,
      mileageKm: trip.mileageKm,
      seatType: trip.seatType,
      seatNumber: trip.seatNumber,
      price: trip.price,
      isRailTrip: trip.isRailTrip,
    );
  }

  final int id;
  final int? ticketId;
  final String trainNumber;
  final String fromStation;
  final String toStation;
  final DateTime departureTime;
  final DateTime? arrivalTime;
  final double mileageKm;
  final String? seatType;
  final String? seatNumber;
  final double price;
  final bool isRailTrip;

  String get ticketLabel => ticketId == null ? '本地 #$id' : '#$ticketId';

  Duration? get duration {
    final arrival = arrivalTime;
    if (arrival == null || arrival.isBefore(departureTime)) return null;
    return arrival.difference(departureTime);
  }
}
