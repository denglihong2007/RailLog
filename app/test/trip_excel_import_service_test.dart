import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';
import 'package:raillog/src/services/trip_excel_export_service.dart';
import 'package:raillog/src/services/trip_excel_import_service.dart';

void main() {
  group('TripExcelImportService', () {
    test('parses a workbook produced by the export service', () {
      final source = TripRecord(
        id: 42,
        trainNumber: 'G1',
        createdAt: DateTime(2026, 8, 1, 9, 30),
        rollingStock: '复兴号 CR400AF',
        companyName: '中国铁路北京局集团有限公司',
        fromStation: '北京南',
        toStation: '上海虹桥',
        departureTime: DateTime(2026, 8, 2, 7),
        arrivalTime: DateTime(2026, 8, 2, 11, 36),
        mileageKm: 1318,
        viaRouteSegments: const [
          ViaRouteSegment(
            routeName: '京沪高速铁路',
            fromStation: '北京南',
            toStation: '上海虹桥',
            mileageKm: 1318,
          ),
        ],
        seatType: '二等座',
        seatNumber: '01车 01A',
        price: 662,
        notes: '测试记录',
      );

      final bytes = TripExcelExportService.buildWorkbook([source]);
      final trips = TripExcelImportService.parseWorkbook(bytes);

      expect(trips, hasLength(1));
      final imported = trips.single;
      expect(imported.trainNumber, 'G1');
      expect(imported.fromStation, '北京南');
      expect(imported.toStation, '上海虹桥');
      expect(imported.departureTime, DateTime(2026, 8, 2, 7));
      expect(imported.arrivalTime, DateTime(2026, 8, 2, 11, 36));
      expect(imported.mileageKm, 1318);
      expect(imported.price, 662);
      expect(imported.viaRouteSegments.single.routeName, '京沪高速铁路');
      expect(imported.notes, '测试记录');
    });

    test('accepts reordered required columns and Excel date cells', () {
      final workbook = Excel.createExcel();
      final sheet = workbook['行程'];
      sheet.appendRow([
        TextCellValue('出发时间'),
        TextCellValue('到达站'),
        TextCellValue('车次/班次'),
        TextCellValue('出发站'),
      ]);
      sheet.appendRow([
        DateTimeCellValue.fromDateTime(DateTime(2025, 1, 2, 8, 15)),
        TextCellValue('南京南'),
        TextCellValue('G101'),
        TextCellValue('北京南'),
      ]);

      final trips = TripExcelImportService.parseWorkbook(_save(workbook));

      expect(trips.single.trainNumber, 'G101');
      expect(trips.single.departureTime, DateTime(2025, 1, 2, 8, 15));
    });

    test('reports missing required columns', () {
      final workbook = Excel.createExcel();
      workbook['行程'].appendRow([TextCellValue('车次/班次')]);

      expect(
        () => TripExcelImportService.parseWorkbook(_save(workbook)),
        throwsA(
          isA<TripExcelImportException>().having(
            (error) => error.message,
            'message',
            contains('缺少必填列'),
          ),
        ),
      );
    });

    test('reports the row number for invalid dates', () {
      final workbook = Excel.createExcel();
      final sheet = workbook['行程'];
      sheet.appendRow(
        TripExcelImportService.requiredHeaders.map(TextCellValue.new).toList(),
      );
      sheet.appendRow([
        TextCellValue('G1'),
        TextCellValue('北京南'),
        TextCellValue('上海虹桥'),
        TextCellValue('2026-02-30 08:00:00'),
      ]);

      expect(
        () => TripExcelImportService.parseWorkbook(_save(workbook)),
        throwsA(
          isA<TripExcelImportException>().having(
            (error) => error.message,
            'message',
            contains('第2行：出发时间不是有效日期'),
          ),
        ),
      );
    });
  });
}

Uint8List _save(Excel workbook) => Uint8List.fromList(workbook.save()!);
