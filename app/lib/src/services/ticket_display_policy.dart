import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/services/ticket_generator_settings.dart';

TicketDisplayStyle ticketDisplayStyleForTrip(
  TripRecord trip,
  TicketDisplayStyle configuredStyle,
) => trip.isLocalOnly ? TicketDisplayStyle.md3 : configuredStyle;
