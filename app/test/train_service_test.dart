import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/services/train_service.dart';

void main() {
  group('TrainService.trainQueryDates', () {
    final now = DateTime.utc(2026, 7, 31, 4);

    test('keeps a selected date inside the online window', () {
      final selected = DateTime(2026, 8, 5);

      expect(
        TrainService.trainQueryDates(selected, trainNumber: 'G1234', now: now),
        [selected],
      );
    });

    test('probes the full window for an old complete train number', () {
      final selected = DateTime(2025, 3, 3);
      final dates = TrainService.trainQueryDates(
        selected,
        trainNumber: 'G1234',
        now: now,
      );

      expect(dates, hasLength(24));
      expect(dates.first.weekday, selected.weekday);
      expect(dates.toSet(), hasLength(24));
      expect(dates, contains(DateTime(2026, 7, 29)));
      expect(dates, contains(DateTime(2026, 8, 21)));
    });

    test('uses one representative day for an incomplete train number', () {
      expect(
        TrainService.trainQueryDates(
          DateTime(2020),
          trainNumber: 'G',
          now: now,
        ),
        [DateTime(2026, 7, 31)],
      );
    });
  });

  test('trainQueryDate retains its single-date clamping behavior', () {
    final now = DateTime.utc(2026, 7, 31, 4);

    expect(
      TrainService.trainQueryDate(DateTime(2020), now: now),
      DateTime(2026, 7, 29),
    );
    expect(
      TrainService.trainQueryDate(DateTime(2030), now: now),
      DateTime(2026, 8, 21),
    );
  });
}
