import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/services/ticket_display_policy.dart';
import 'package:raillog/src/services/ticket_generator_settings.dart';

void main() {
  test('本地行程始终使用 MD3 票面', () {
    final trip = _trip(isLocalOnly: true);

    expect(
      ticketDisplayStyleForTrip(trip, TicketDisplayStyle.red),
      TicketDisplayStyle.md3,
    );
    expect(
      ticketDisplayStyleForTrip(trip, TicketDisplayStyle.blue),
      TicketDisplayStyle.md3,
    );
  });

  test('云端行程沿用全局票面设置', () {
    final trip = _trip();
    expect(
      ticketDisplayStyleForTrip(trip, TicketDisplayStyle.blue),
      TicketDisplayStyle.blue,
    );
  });
}

TripRecord _trip({bool isLocalOnly = false}) => TripRecord(
  id: 1,
  trainNumber: 'G1',
  fromStation: '北京',
  toStation: '上海',
  departureTime: DateTime(2026, 1, 1),
  viaRouteSegments: const [],
  isLocalOnly: isLocalOnly,
);
