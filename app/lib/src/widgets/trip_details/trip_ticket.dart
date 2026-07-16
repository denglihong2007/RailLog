import 'package:flutter/material.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';

class TripTicket extends StatelessWidget {
  const TripTicket({
    super.key,
    required this.trainNumber,
    required this.departureStop,
    required this.arrivalStop,
  });

  final String trainNumber;
  final TrainScheduleStop departureStop;
  final TrainScheduleStop arrivalStop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final departureTime = departureStop.departureDateTime!;
    final arrivalTime = arrivalStop.arrivalDateTime!;
    final duration = arrivalTime.difference(departureTime);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.primary, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: colors.primaryContainer,
            child: Row(
              children: [
                Icon(
                  Icons.confirmation_number_outlined,
                  color: colors.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  trainNumber,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(_formatDate(departureTime)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _TicketStation(
                    station: departureStop.stationName,
                    dateTime: departureTime,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      const Icon(Icons.arrow_forward),
                      const SizedBox(height: 4),
                      Text(
                        _formatDuration(duration),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _TicketStation(
                    station: arrivalStop.stationName,
                    dateTime: arrivalTime,
                    alignEnd: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketStation extends StatelessWidget {
  const _TicketStation({
    required this.station,
    required this.dateTime,
    this.alignEnd = false,
  });

  final String station;
  final DateTime dateTime;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          station,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(_formatDateTime(dateTime)),
      ],
    );
  }
}

String _formatDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _formatDateTime(DateTime value) =>
    '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _formatDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  return '$hours时${minutes.toString().padLeft(2, '0')}分';
}
