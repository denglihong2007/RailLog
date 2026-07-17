import 'dart:convert';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';
import 'package:raillog/src/pages/settings_page.dart';
import 'package:raillog/src/services/trip_excel_export_service.dart';

void main() {
  test('Excel export matches trip details and keeps route data as JSON', () {
    final segment = const ViaRouteSegment(
      routeName: '京沪高速线',
      fromStation: '北京南',
      toStation: '上海虹桥',
      mileageKm: 1318,
    );
    final trip = TripRecord(
      id: 7,
      trainNumber: 'G1',
      createdAt: DateTime(2026, 7, 18, 12, 30, 45),
      rollingStock: 'CR400AF-B',
      companyName: '京局北京客运段',
      fromStation: '北京南',
      toStation: '上海虹桥',
      departureTime: DateTime(2026, 7, 18, 7),
      arrivalTime: DateTime(2026, 7, 18, 11, 29),
      mileageKm: 1318,
      viaRouteSegments: [segment],
      seatType: '商务座',
      seatNumber: '01车01A',
      price: 1748,
      notes: '测试备注',
    );

    final bytes = TripExcelExportService.buildWorkbook([trip]);
    final workbook = Excel.decodeBytes(bytes);
    final sheet = workbook.tables['行程'];

    expect(sheet, isNotNull);
    expect(sheet!.rows, hasLength(2));
    expect(_text(sheet.rows[0][0]), '行程编号');
    expect(_text(sheet.rows[0][15]), '经由线路(JSON)');
    expect(_text(sheet.rows[1][0]), '本地 #7');
    expect(_text(sheet.rows[1][2]), 'G1');
    expect(_text(sheet.rows[1][5]), '2026-07-18 12:30:45');
    expect(_text(sheet.rows[1][11]), '4时29分');
    expect(sheet.rows[1][10]!.value, isA<IntCellValue>());
    expect(sheet.rows[1][10]!.value.toString(), '1318');
    expect(sheet.rows[1][14]!.value, isA<IntCellValue>());
    expect(sheet.rows[1][14]!.value.toString(), '1748');
    expect(_text(sheet.rows[1][15]), jsonEncode([segment.toJson()]));
    expect(_text(sheet.rows[1][16]), '测试备注');
  });

  testWidgets('settings exposes Excel export in local mode', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SettingsPage())),
    );
    await tester.pump();

    expect(find.text('导出行程到 Excel'), findsOneWidget);
    expect(find.byIcon(Icons.table_view_outlined), findsOneWidget);
  });
}

String? _text(Data? cell) {
  final value = cell?.value;
  return value is TextCellValue ? value.value.text : null;
}
