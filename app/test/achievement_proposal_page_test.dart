import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/pages/achievement_proposal_page.dart';
import 'package:raillog/src/theme/app_theme.dart';

void main() {
  test('Issue 地址带上标题与四段正文，未填的技术性说明占位', () {
    final uri = achievementProposalIssueUri(
      name: '星罗棋布',
      requirement: ' 到访过全部铁路局 ',
      narrative: '你的足迹遍布全国',
      technicalNote: '   ',
    );

    expect(uri.host, 'github.com');
    expect(uri.path, '/denglihong2007/RailLog/issues/new');
    final query = uri.queryParameters;
    expect(query['title'], '[成就创意] 星罗棋布');
    final body = query['body']!;
    expect(body, contains('### 成就名称\n\n星罗棋布'));
    expect(body, contains('### 达成条件\n\n到访过全部铁路局'));
    expect(body, contains('### 注释\n\n你的足迹遍布全国'));
    expect(body, contains('### 技术性说明\n\n（未填写）'));
    // 空格编码成 %20 而不是 `+`：GitHub 的预填正文只认前者。
    expect(uri.toString(), contains('%20'));
    expect(uri.toString(), isNot(contains('+')));
  });

  test('填了技术性说明就原样带进正文', () {
    final uri = achievementProposalIssueUri(
      name: '星罗棋布',
      requirement: '到访过全部铁路局',
      narrative: '你的足迹遍布全国',
      technicalNote: ' 按乘车记录里的车站所属铁路局统计。 ',
    );

    expect(uri.queryParameters['body'], contains('按乘车记录里的车站所属铁路局统计。'));
    expect(uri.queryParameters['body'], isNot(contains('（未填写）')));
  });

  testWidgets('空表单提交时提示每一段的必填项', (tester) async {
    await _pumpPage(tester);

    await tester.tap(find.text('提交到 GitHub'));
    await tester.pumpAndSettle();

    expect(find.text('请填写成就名称'), findsOneWidget);
    expect(find.text('请填写达成条件'), findsOneWidget);
    expect(find.text('请填写注释'), findsOneWidget);
  });

  testWidgets('成就名称不是四个汉字时给出提示', (tester) async {
    await _pumpPage(tester);

    await tester.enterText(find.widgetWithText(TextFormField, '成就名称'), 'abc');
    await tester.enterText(
      find.widgetWithText(TextFormField, '达成条件'),
      '到访过全部铁路局',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '注释'),
      '你的足迹遍布全国',
    );
    await tester.tap(find.text('提交到 GitHub'));
    await tester.pumpAndSettle();

    expect(find.text('成就名称需为四个汉字'), findsOneWidget);
  });

  testWidgets('输入法组词时不会被字数上限截断', (tester) async {
    await _pumpPage(tester);

    final nameField = find.widgetWithText(TextFormField, '成就名称');
    await tester.enterText(nameField, '一二三四');
    // 四个字已满，用户继续打第五个字的拼音：拼音串落在组合区里，此时不能
    // 按「最多四个字」把它砍掉，否则输入法选不了字。
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '一二三四w',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 4, end: 5),
      ),
    );
    await tester.pump();

    final editable = tester.widget<EditableText>(
      find.descendant(of: nameField, matching: find.byType(EditableText)),
    );
    expect(editable.controller.text, '一二三四w');
  });
}

Future<void> _pumpPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(
        ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
      ),
      home: const AchievementProposalPage(),
    ),
  );
  await tester.pumpAndSettle();
}
