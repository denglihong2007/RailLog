import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/trip_excel_export_service.dart';

class TripExcelImportResult {
  const TripExcelImportResult({required this.imported, required this.skipped});

  final int imported;
  final int skipped;
}

class TripExcelImportException implements Exception {
  const TripExcelImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract final class TripExcelImportService {
  static const requiredHeaders = ['本地记录号', '车次/班次', '出发站', '到达站', '出发时间'];
  static const supportedHeaders = TripExcelExportService.headers;

  static Future<TripExcelImportResult> importBytes(Uint8List bytes) async {
    final parsed = parseWorkbook(bytes);
    final existing = await DbHelper.instance.getAllTrips();
    final existingById = {for (final trip in existing) trip.id: trip};
    var imported = 0;
    for (final trip in parsed) {
      final current = trip.id > 0 ? existingById[trip.id] : null;
      if (current == null) {
        await DbHelper.instance.insertTrip(trip);
      } else {
        await DbHelper.instance.updateTrip(
          TripRecord(
            id: current.id,
            ticketId: current.ticketId,
            clientId: current.clientId,
            ownerUserId: current.ownerUserId,
            trainNumber: trip.trainNumber,
            createdAt: current.createdAt,
            updatedAt: current.updatedAt,
            deletedAt: current.deletedAt,
            rollingStock: trip.rollingStock,
            companyName: trip.companyName,
            fromStation: trip.fromStation,
            toStation: trip.toStation,
            departureTime: trip.departureTime,
            arrivalTime: trip.arrivalTime,
            mileageKm: trip.mileageKm,
            viaRouteSegments: trip.viaRouteSegments,
            seatType: trip.seatType,
            seatNumber: trip.seatNumber,
            price: trip.price,
            isRailTrip: trip.isRailTrip,
            isLocalOnly: current.isLocalOnly,
            notes: trip.notes,
          ),
        );
      }
      imported++;
    }
    return TripExcelImportResult(imported: imported, skipped: 0);
  }

  static List<TripRecord> parseWorkbook(Uint8List bytes) {
    late final Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } catch (_) {
      throw const TripExcelImportException('无法读取文件，请确认文件是有效的 .xlsx 工作簿');
    }
    if (workbook.tables.isEmpty) {
      throw const TripExcelImportException('工作簿中没有可读取的工作表');
    }
    final sheet = workbook.tables['行程'] ?? workbook.tables.values.first;
    if (sheet.rows.isEmpty) {
      throw const TripExcelImportException('工作表中没有数据');
    }

    final headers = <String, int>{};
    for (var column = 0; column < sheet.rows.first.length; column++) {
      final name = _cellText(sheet.rows.first[column]).trim();
      if (name.isNotEmpty) headers[name] = column;
    }
    final missing = requiredHeaders.where((name) => !headers.containsKey(name));
    if (missing.isNotEmpty) {
      throw TripExcelImportException('缺少必填列：${missing.join('、')}');
    }

    final trips = <TripRecord>[];
    final errors = <String>[];
    for (var index = 1; index < sheet.rows.length; index++) {
      final row = sheet.rows[index];
      if (row.every((cell) => _cellText(cell).trim().isEmpty)) continue;
      try {
        trips.add(_parseRow(row, headers, index + 1));
      } on TripExcelImportException catch (error) {
        errors.add(error.message);
        if (errors.length == 5) break;
      }
    }
    if (errors.isNotEmpty) {
      final suffix = errors.length == 5 ? '\n请修正以上问题后重新导入' : '';
      throw TripExcelImportException('${errors.join('\n')}$suffix');
    }
    if (trips.isEmpty) {
      throw const TripExcelImportException('工作表中没有可导入的行程');
    }
    return trips;
  }

  static TripRecord _parseRow(
    List<Data?> row,
    Map<String, int> headers,
    int rowNumber,
  ) {
    String text(String header) => _cellText(_cell(row, headers[header])).trim();
    CellValue? value(String header) => _cell(row, headers[header])?.value;
    String requiredText(String header) {
      final result = text(header);
      if (result.isEmpty) _rowError(rowNumber, '$header不能为空');
      return result;
    }

    final localId = _id(value('本地记录号'), rowNumber);
    final departure = _dateTime(value('出发时间'), rowNumber, '出发时间', true)!;
    final arrival = _dateTime(value('到达时间'), rowNumber, '到达时间', false);
    if (arrival != null && arrival.isBefore(departure)) {
      _rowError(rowNumber, '到达时间不能早于出发时间');
    }
    final createdAt = _dateTime(value('录入时间'), rowNumber, '录入时间', false);
    final mileage = _number(value('里程(km)'), rowNumber, '里程(km)');
    final price = _number(value('票价(元)'), rowNumber, '票价(元)');
    if (mileage < 0) _rowError(rowNumber, '里程(km)不能为负数');
    if (price < 0) _rowError(rowNumber, '票价(元)不能为负数');

    final from = requiredText('出发站');
    final to = requiredText('到达站');
    final segments = _segments(text('经由线路(JSON)'), rowNumber);
    final routeError = validateViaRouteSegments(
      segments,
      startStation: from,
      endStation: to,
    );
    if (routeError != null) _rowError(rowNumber, routeError);

    return TripRecord(
      id: localId,
      trainNumber: requiredText('车次/班次'),
      createdAt: createdAt,
      rollingStock: _optional(text('车型')),
      companyName: _optional(text('承运单位')),
      fromStation: from,
      toStation: to,
      departureTime: departure,
      arrivalTime: arrival,
      mileageKm: mileage,
      viaRouteSegments: segments,
      seatType: _optional(text('席别')),
      seatNumber: _optional(text('座位号')),
      price: price,
      isRailTrip: _railTrip(text('行程类型'), rowNumber),
      notes: _optional(text('备注')),
    );
  }
}

Data? _cell(List<Data?> row, int? index) =>
    index == null || index >= row.length ? null : row[index];

String _cellText(Data? cell) => cell?.value?.toString() ?? '';

Never _rowError(int row, String message) =>
    throw TripExcelImportException('第$row行：$message');

DateTime? _dateTime(CellValue? value, int row, String column, bool required) {
  if (value == null || value.toString().trim().isEmpty) {
    if (required) _rowError(row, '$column不能为空');
    return null;
  }
  if (value is DateTimeCellValue) return value.asDateTimeLocal();
  if (value is DateCellValue) return value.asDateTimeLocal();
  final source = value.toString().trim().replaceFirst('T', ' ');
  final match = RegExp(
    r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
  ).firstMatch(source);
  if (match == null) {
    _rowError(row, '$column格式应为 yyyy-MM-dd HH:mm:ss');
  }
  final result = DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.tryParse(match.group(4) ?? '') ?? 0,
    int.tryParse(match.group(5) ?? '') ?? 0,
    int.tryParse(match.group(6) ?? '') ?? 0,
  );
  if (result.year != int.parse(match.group(1)!) ||
      result.month != int.parse(match.group(2)!) ||
      result.day != int.parse(match.group(3)!) ||
      result.hour != (int.tryParse(match.group(4) ?? '') ?? 0) ||
      result.minute != (int.tryParse(match.group(5) ?? '') ?? 0) ||
      result.second != (int.tryParse(match.group(6) ?? '') ?? 0)) {
    _rowError(row, '$column不是有效日期');
  }
  return result;
}

int _id(CellValue? value, int row) {
  if (value == null || value.toString().trim().isEmpty) return 0;
  final result = switch (value) {
    IntCellValue() => value.value,
    DoubleCellValue() =>
      value.value == value.value.roundToDouble() ? value.value.toInt() : null,
    _ => int.tryParse(value.toString().trim()),
  };
  if (result == null || result <= 0) _rowError(row, '本地记录号必须是正整数');
  return result;
}

double _number(CellValue? value, int row, String column) {
  if (value == null || value.toString().trim().isEmpty) return 0;
  final result = switch (value) {
    IntCellValue() => value.value.toDouble(),
    DoubleCellValue() => value.value,
    _ => double.tryParse(value.toString().trim()),
  };
  if (result == null || !result.isFinite) _rowError(row, '$column必须是数字');
  return result;
}

List<ViaRouteSegment> _segments(String source, int row) {
  if (source.isEmpty) return const [];
  try {
    final decoded = jsonDecode(source) as List<dynamic>;
    return decoded
        .map((item) => ViaRouteSegment.fromJson(item as Map<String, dynamic>))
        .toList();
  } catch (_) {
    _rowError(row, '经由线路(JSON)格式无效，建议保留导出文件中的原值');
  }
}

bool _railTrip(String value, int row) {
  if (value.isEmpty || value == '铁路行程' || value == '铁路') return true;
  if (value == '非铁路行程' || value == '非铁路') return false;
  _rowError(row, '行程类型应为“铁路行程”或“非铁路行程”');
}

String? _optional(String value) => value.isEmpty ? null : value;
