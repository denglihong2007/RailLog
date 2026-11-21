import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/widgets/user_level_badge.dart';

void main() {
  test('maps achievement experience to the configured user levels', () {
    expect(userLevelForExperience(-1), 0);
    expect(userLevelForExperience(0), 0);
    expect(userLevelForExperience(1), 1);
    expect(userLevelForExperience(99), 1);
    expect(userLevelForExperience(100), 2);
    expect(userLevelForExperience(249), 2);
    expect(userLevelForExperience(250), 3);
    expect(userLevelForExperience(499), 3);
    expect(userLevelForExperience(500), 4);
    expect(userLevelForExperience(799), 4);
    expect(userLevelForExperience(800), 5);
    expect(userLevelForExperience(1099), 5);
    expect(userLevelForExperience(1100), 6);
    expect(userLevelForExperience(5000), 6);
  });

  test('calculates progress within the current level range', () {
    final levelZero = userLevelProgressForExperience(0);
    expect(levelZero.level, 0);
    expect(levelZero.nextLevelExperience, 1);
    expect(levelZero.remainingExperience, 1);
    expect(levelZero.value, 0);

    final levelOneStart = userLevelProgressForExperience(1);
    expect(levelOneStart.level, 1);
    expect(levelOneStart.remainingExperience, 99);
    expect(levelOneStart.value, 0);

    final levelOneEnd = userLevelProgressForExperience(99);
    expect(levelOneEnd.value, closeTo(98 / 99, 0.0001));

    final levelTwoStart = userLevelProgressForExperience(100);
    expect(levelTwoStart.level, 2);
    expect(levelTwoStart.value, 0);

    final maxLevel = userLevelProgressForExperience(1100);
    expect(maxLevel.level, 6);
    expect(maxLevel.isMaxLevel, isTrue);
    expect(maxLevel.value, 1);
  });

  testWidgets('renders the matching level asset', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: UserLevelBadge(experience: 125))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UserLevelBadge), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
