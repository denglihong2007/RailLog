import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/widgets/trip_details/company_editor.dart';

void main() {
  test('已知客运段可匹配对应路局', () {
    final selection = matchCompanySelection('上局南京段');
    final traditionalVariant = matchCompanySelection('兰州局银川段');

    expect(selection?.bureau, '上海局');
    expect(selection?.segment, '上局南京段');
    expect(traditionalVariant?.bureau, '兰州局');
  });

  testWidgets('网络结果匹配失败时转为其它并保留原值', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));

    controller.text = '网络返回的未知客运段';
    await tester.pump();

    expect(find.text('其它'), findsOneWidget);
    expect(find.text('网络返回的未知客运段'), findsOneWidget);
  });

  testWidgets('网络结果为暂无时留空', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));

    controller.text = '暂无';
    await tester.pump();

    expect(controller.text, isEmpty);
    expect(find.text('其它'), findsNothing);
    expect(find.text('请先选择路局'), findsOneWidget);
  });

  testWidgets('选择路局和客运段后只输出客运段', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('上海局').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('上局杭州段').last);
    await tester.pumpAndSettle();

    expect(controller.text, '上局杭州段');
  });
}

Widget _app(TextEditingController controller) => MaterialApp(
  home: Scaffold(
    body: Form(
      child: SizedBox(width: 360, child: CompanyEditor(controller: controller)),
    ),
  ),
);
