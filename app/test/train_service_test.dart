import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/train_search_result.dart';
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

  group('TrainService.parseTicketSeatPrices', () {
    test('treats a single second-class seat price as the no-seat price', () {
      final availability = TrainService.parseTicketSeatPrices('O000300000', '');

      expect(availability.seatOptions, hasLength(1));
      expect(availability.seatOptions.single.seatType, '二等座');
      expect(availability.seatOptions.single.price, 3);
      expect(availability.noSeatOption?.seatType, '二等座');
      expect(availability.noSeatOption?.price, 3);
      expect(availability.noSeatOption?.isNoSeat, isTrue);
    });

    test('uses a repeated second-class entry as the no-seat price', () {
      final availability = TrainService.parseTicketSeatPrices(
        'O003000000O002000000',
        '',
      );

      expect(availability.seatOptions.single.price, 30);
      expect(availability.noSeatOption?.price, 20);
    });

    test('prefers any repeated seat code over a single second-class code', () {
      final availability = TrainService.parseTicketSeatPrices(
        'O003000000M005000000M004000000',
        '',
      );

      expect(availability.seatOptions, hasLength(2));
      expect(availability.noSeatOption?.seatType, '一等座');
      expect(availability.noSeatOption?.price, 40);
    });
  });

  group('TrainService.normalizeTrainSuggestions', () {
    TrainSearchResult train(String number, {DateTime? lookupDate}) =>
        TrainSearchResult(
          trainNumber: number,
          departureStation: '始发站',
          arrivalStation: '终到站',
          trainNo: number,
          lookupDate: lookupDate,
        );

    test('keeps prefix matches and places the exact train first', () {
      final suggestions = TrainService.normalizeTrainSuggestions(' s55 ', [
        train('S551'),
        train('S55 次'),
        train('S550'),
        train('S54'),
      ]);

      expect(suggestions.map((result) => result.trainNumber), [
        'S55 次',
        'S550',
        'S551',
      ]);
    });

    test('deduplicates results, sorts naturally, and limits the list', () {
      final suggestions = TrainService.normalizeTrainSuggestions('S', [
        train('S500'),
        train('S50'),
        train('S5'),
        train('S50'),
      ], limit: 2);

      expect(suggestions.map((result) => result.trainNumber), ['S5', 'S50']);
    });

    test('does not treat slash-separated train numbers as aliases', () {
      final suggestions = TrainService.normalizeTrainSuggestions('G2', [
        train('G1/G2'),
        train('G20'),
        train('G3'),
      ]);

      expect(suggestions.map((result) => result.trainNumber), ['G20']);
    });
  });
}
