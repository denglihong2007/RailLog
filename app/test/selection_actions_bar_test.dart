import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/widgets/selection_actions_bar.dart';

/// 纯布局测试：这个 widget 不碰任何 I/O，可以放心泵。
Future<void> _pump(
  WidgetTester tester, {
  required double width,
  bool busy = false,
  bool hasSelection = true,
  bool canGenerate = true,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        bottomNavigationBar: SelectionActionsBar(
          busy: busy,
          hasSelection: hasSelection,
          canGenerate: canGenerate,
          onDelete: () {},
          onDownload: () {},
          onExportJournal: () {},
          onOrder: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('360dp 下四个动作都带标签且不溢出', (tester) async {
    await _pump(tester, width: 360);

    expect(tester.takeException(), isNull);
    for (final label in ['删除', '下载', '手账', '订票']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('280dp 下退化成纯图标，不抛异常', (tester) async {
    await _pump(tester, width: 280);

    expect(tester.takeException(), isNull);
    // 退化后文字不再渲染，四个动作只剩图标。
    for (final label in ['删除', '下载', '手账', '订票']) {
      expect(find.text(label), findsNothing);
    }
    for (final icon in [
      Icons.delete_outline,
      Icons.download_outlined,
      Icons.menu_book_outlined,
      Icons.shopping_bag_outlined,
    ]) {
      expect(find.byIcon(icon), findsOneWidget);
    }
  });

  testWidgets('文字放大到 1.3 倍时仍不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
          ),
          child: child!,
        ),
        home: Scaffold(
          bottomNavigationBar: SelectionActionsBar(
            busy: false,
            hasSelection: true,
            canGenerate: true,
            onDelete: () {},
            onDownload: () {},
            onExportJournal: () {},
            onOrder: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('手账只要求「选了东西」，不要求能生成车票', (tester) async {
    // 本地未同步的行程没有 ticketId，canGenerate 为 false，
    // 而它们恰恰是手账要照顾的人群——手账必须仍然可点。
    await _pump(tester, width: 360, canGenerate: false);

    final journal = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('手账'),
        matching: find.byType(TextButton),
      ),
    );
    expect(journal.onPressed, isNotNull);

    final download = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('下载'),
        matching: find.byType(TextButton),
      ),
    );
    expect(download.onPressed, isNull);
  });

  testWidgets('一个都没选时手账与删除都不可点', (tester) async {
    await _pump(tester, width: 360, hasSelection: false);

    for (final label in ['删除', '手账']) {
      final button = tester.widget<TextButton>(
        find.ancestor(of: find.text(label), matching: find.byType(TextButton)),
      );
      expect(button.onPressed, isNull, reason: label);
    }
  });

  testWidgets('busy 时四个动作全部置灰', (tester) async {
    await _pump(tester, width: 360, busy: true);

    for (final label in ['删除', '下载', '手账', '订票']) {
      final button = tester.widget<TextButton>(
        find.ancestor(of: find.text(label), matching: find.byType(TextButton)),
      );
      expect(button.onPressed, isNull, reason: label);
    }
  });
}
