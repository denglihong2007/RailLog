import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/services/train_service.dart';

void main() {
  test('ticket prices always query tomorrow then the day after in China', () {
    final dates = TrainService.ticketPriceLookupDates(
      DateTime.utc(2026, 12, 31, 16),
    );

    expect(dates, [DateTime(2027, 1, 2), DateTime(2027, 1, 3)]);
  });
}
