import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/theme/app_theme.dart';
import 'package:raillog/src/widgets/app_card.dart';

void main() {
  test('theme uses pill action and selection controls', () {
    final theme = AppTheme.build(
      ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
    );

    final chipShape = theme.chipTheme.shape!;
    final segmentedShape = theme.segmentedButtonTheme.style!.shape!.resolve(
      {},
    )!;
    final filledButtonShape = theme.filledButtonTheme.style!.shape!.resolve(
      {},
    )!;
    final outlinedButtonShape = theme.outlinedButtonTheme.style!.shape!.resolve(
      {},
    )!;
    final textButtonShape = theme.textButtonTheme.style!.shape!.resolve({})!;

    expect(chipShape, isA<StadiumBorder>());
    expect(segmentedShape, isA<StadiumBorder>());
    expect(filledButtonShape, isA<StadiumBorder>());
    expect(outlinedButtonShape, isA<StadiumBorder>());
    expect(textButtonShape, isA<StadiumBorder>());
    expect(AppLayout.contentMaxWidth, AppLayout.detailMaxWidth);
    expect(theme.textTheme.headlineMedium!.fontSize, 28);
  });

  testWidgets('AppCard preserves bounded grid layout and card radius', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        ),
        home: Scaffold(
          body: GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 1.4,
            children: const [
              AppCard(
                child: Column(
                  children: [
                    Text('Metric'),
                    Expanded(child: Center(child: Text('42'))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    final card = tester.widget<Card>(find.byType(Card));
    final shape = card.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(AppRadius.card));
  });
}
