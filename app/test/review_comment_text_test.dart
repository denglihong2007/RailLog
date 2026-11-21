import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:raillog/src/services/entity_review_service.dart';
import 'package:raillog/src/widgets/review_comment_text.dart';

const _mention = EntityReviewMention(
  userId: 'user-2',
  displayName: '新名字',
  mentionedName: '旧名字',
);

void main() {
  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('tapping a mention still opens the user page ($kind)', (
      tester,
    ) async {
      String? pushed;
      await tester.pumpWidget(
        MaterialApp(
          home: const Scaffold(
            body: Center(
              child: ReviewCommentText(
                comment: '@旧名字 打卡',
                mentions: [_mention],
              ),
            ),
          ),
          onGenerateRoute: (settings) {
            pushed = settings.name;
            return MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('user page')),
            );
          },
        ),
      );

      final rect = tester.getRect(find.byType(RichText));
      final gesture = await tester.startGesture(
        rect.topLeft + const Offset(4, 4),
        kind: kind,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(pushed, '/users/user-2');
    });
  }

  testWidgets('long press selects and copies the comment', (tester) async {
    final clipboard = <String, Object?>{};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.addAll((call.arguments as Map).cast<String, Object?>());
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: ReviewCommentText(comment: '北京南的换乘很顺利', mentions: []),
          ),
        ),
      ),
    );

    await tester.longPressAt(
      tester.getRect(find.byType(RichText)).topLeft + const Offset(4, 4),
    );
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(clipboard['text'], isNotEmpty);
  });
}
