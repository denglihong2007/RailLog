import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/download_file_service.dart';

class TripExcelExportResult {
  const TripExcelExportResult({
    required this.tripCount,
    required this.fileName,
    required this.savedPath,
  });

  final int tripCount;
  final String fileName;
  final String savedPath;
}

class TripExcelExportException implements Exception {
  const TripExcelExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract final class TripExcelExportService {
  static const headers = [
    '行程编号',
    '行程类型',
    '车次/班次',
    '出发站',
    '到达站',
    '录入时间',
    '出发时间',
    '到达时间',
    '车型',
    '承运单位',
    '里程(km)',
    '乘坐时长',
    '席别',
    '座位号',
    '票价(元)',
    '经由线路(JSON)',
    '备注',
  ];

  static Future<TripExcelExportResult> exportVisibleTrips() async {
    final trips = await DbHelper.instance.getAllTrips();
    if (trips.isEmpty) {
      throw const TripExcelExportException('暂无可导出的行程');
    }
    final bytes = buildWorkbook(trips);
    final timestamp = _fileTimestamp(DateTime.now());
    final name = 'RailLog_行程_$timestamp';
    final savedPath = await DownloadFileService.save(
      name: name,
      bytes: bytes,
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
      androidMimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    return TripExcelExportResult(
      tripCount: trips.length,
      fileName: '$name.xlsx',
      savedPath: savedPath,
    );
  }

  static Uint8List buildWorkbook(List<TripRecord> trips) {
    final workbook = Excel.createExcel();
    final defaultSheet = workbook.getDefaultSheet();
    final sheet = workbook['行程'];
    if (defaultSheet != null && defaultSheet != '行程') {
      workbook.delete(defaultSheet);
    }

    sheet.appendRow(headers.map(TextCellValue.new).toList(growable: false));
    for (final trip in trips) {
      sheet.appendRow(_rowForTrip(trip));
    }

    final headerStyle = CellStyle(bold: true);
    for (var column = 0; column < headers.length; column++) {
      sheet
              .cell(
                CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0),
              )
              .cellStyle =
          headerStyle;
      sheet.setColumnWidth(column, _columnWidths[column]);
    }
    sheet.setRowHeight(0, 24);

    final encoded = workbook.save();
    if (encoded == null) {
      throw const TripExcelExportException('生成 Excel 文件失败');
    }
    return Uint8List.fromList(encoded);
  }

  static List<CellValue> _rowForTrip(TripRecord trip) => [
    TextCellValue(trip.ticketLabel),
    TextCellValue(trip.isRailTrip ? '铁路行程' : '非铁路行程'),
    TextCellValue(trip.trainNumber),
    TextCellValue(trip.fromStation),
    TextCellValue(trip.toStation),
    TextCellValue(_formatDateTime(trip.createdAt)),
    TextCellValue(_formatDateTime(trip.departureTime)),
    TextCellValue(
      trip.arrivalTime == null ? '' : _formatDateTime(trip.arrivalTime!),
    ),
    TextCellValue(trip.rollingStock ?? ''),
    TextCellValue(trip.companyName ?? ''),
    DoubleCellValue(trip.mileageKm),
    TextCellValue(_durationText(trip)),
    TextCellValue(trip.seatType ?? ''),
    TextCellValue(trip.seatNumber ?? ''),
    DoubleCellValue(trip.price),
    TextCellValue(
      jsonEncode(
        trip.viaRouteSegments.map((segment) => segment.toJson()).toList(),
      ),
    ),
    TextCellValue(trip.notes ?? ''),
  ];

  static const _columnWidths = <double>[
    14,
    12,
    14,
    14,
    14,
    21,
    21,
    21,
    18,
    20,
    12,
    14,
    14,
    16,
    12,
    50,
    28,
  ];
}

String _formatDateTime(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}:'
    '${value.second.toString().padLeft(2, '0')}';

String _durationText(TripRecord trip) {
  final arrival = trip.arrivalTime;
  if (arrival == null || arrival.isBefore(trip.departureTime)) return '';
  final duration = arrival.difference(trip.departureTime);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '$minutes分';
  return minutes == 0 ? '$hours时' : '$hours时$minutes分';
}

String _fileTimestamp(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}'
    '${value.month.toString().padLeft(2, '0')}'
    '${value.day.toString().padLeft(2, '0')}_'
    '${value.hour.toString().padLeft(2, '0')}'
    '${value.minute.toString().padLeft(2, '0')}'
    '${value.second.toString().padLeft(2, '0')}';
