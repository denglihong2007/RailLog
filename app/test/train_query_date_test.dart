import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/services/train_service.dart';

void main() {
  final now = DateTime.utc(2026, 7, 15, 4);

  test('dates three or more days ago use two days ago', () {
    expect(
      TrainService.trainQueryDate(DateTime(2026, 7, 12), now: now),
      DateTime(2026, 7, 13),
    );
    expect(
      TrainService.trainQueryDate(DateTime(2020), now: now),
      DateTime(2026, 7, 13),
    );
  });

  test('dates 22 or more days ahead use 21 days ahead', () {
    expect(
      TrainService.trainQueryDate(DateTime(2026, 8, 6), now: now),
      DateTime(2026, 8, 5),
    );
    expect(
      TrainService.trainQueryDate(DateTime(2030), now: now),
      DateTime(2026, 8, 5),
    );
  });

  test('dates inside the supported window remain unchanged', () {
    expect(
      TrainService.trainQueryDate(DateTime(2026, 7, 13), now: now),
      DateTime(2026, 7, 13),
    );
    expect(
      TrainService.trainQueryDate(DateTime(2026, 8, 5), now: now),
      DateTime(2026, 8, 5),
    );
  });
}
