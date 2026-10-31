import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/pages/import_invoice_page.dart';

void main() {
  testWidgets('shows the file picker entry points and empty state', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ImportInvoicePage()));

    expect(find.text('从电子发票导入'), findsOneWidget);
    expect(find.text('选择待导入车票'), findsOneWidget);
    expect(find.text('选择文件'), findsOneWidget);
    expect(find.text('暂无可导入车票'), findsOneWidget);
    expect(find.textContaining('同一张发票的 PDF 与 OFD 只会导入一次'), findsOneWidget);
  });
}
