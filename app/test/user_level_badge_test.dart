import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/widgets/user_level_badge.dart';

void main() {
  test('maps achievement experience to the configured user levels', () {
    expect(userLevelForExperience(-1), 0);
    expect(userLevelForExperience(0), 0);
    expect(userLevelForExperience(1), 1);
    expect(userLevelForExperience(49), 1);
    expect(userLevelForExperience(50), 2);
    expect(userLevelForExperience(124), 2);
    expect(userLevelForExperience(125), 3);
    expect(userLevelForExperience(249), 3);
    expect(userLevelForExperience(250), 4);
    expect(userLevelForExperience(449), 4);
    expect(userLevelForExperience(450), 5);
    expect(userLevelForExperience(799), 5);
    expect(userLevelForExperience(800), 6);
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
    expect(levelOneStart.remainingExperience, 49);
    expect(levelOneStart.value, 0);

    final levelOneEnd = userLevelProgressForExperience(49);
    expect(levelOneEnd.value, closeTo(48 / 49, 0.0001));

    final levelTwoStart = userLevelProgressForExperience(50);
    expect(levelTwoStart.level, 2);
    expect(levelTwoStart.value, 0);

    final maxLevel = userLevelProgressForExperience(800);
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
