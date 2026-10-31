import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:raillog/src/models/ticket_12306_order.dart';
import 'package:xml/xml.dart';

class TicketInvoiceImportException implements Exception {
  const TicketInvoiceImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一个待解析的发票文件。
class InvoiceImportFile {
  const InvoiceImportFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// 文件夹扫描结果；文件过多时只读取前 [_maxFolderFiles] 个。
class InvoiceFileSet {
  const InvoiceFileSet({required this.files, required this.truncated});

  final List<InvoiceImportFile> files;
  final bool truncated;
}

/// 一次导入的解析结果。失败的文件只记录原因，不影响其他文件。
class InvoiceImportBatch {
  const InvoiceImportBatch({
    required this.orders,
    required this.fileCount,
    required this.failures,
  });

  final List<Ticket12306Order> orders;
  final int fileCount;
  final List<String> failures;
}

/// 解析 12306 下载的铁路电子客票 PDF / OFD 文件。
///
/// 两类文件都内嵌同一份 XBRL 附件（`rai_issuer_*.xml`），车次、站点、席别、
/// 票价都在里面；票面文字是缺少 ToUnicode 的自定义编码，不能直接取文本。
class TicketInvoiceImportService {
  const TicketInvoiceImportService._();

  static const supportedExtensions = {'pdf', 'ofd'};
  static const _maxFolderFiles = 500;

  static bool isSupportedName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return supportedExtensions.contains(name.substring(dot + 1).toLowerCase());
  }

  /// 递归读取文件夹里的 PDF / OFD 文件，跳过 Office 临时文件。
  static Future<InvoiceFileSet> readDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw const TicketInvoiceImportException('找不到所选文件夹');
    }
    final files = <InvoiceImportFile>[];
    var truncated = false;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final name = entity.path.split(RegExp(r'[\\/]')).last;
      if (name.startsWith('~\$') || !isSupportedName(name)) continue;
      if (files.length >= _maxFolderFiles) {
        truncated = true;
        break;
      }
      files.add(
        InvoiceImportFile(name: name, bytes: await entity.readAsBytes()),
      );
    }
    files.sort((a, b) => a.name.compareTo(b.name));
    return InvoiceFileSet(files: files, truncated: truncated);
  }

  /// 解析一批文件并按车票去重（同一张发票的 PDF 与 OFD 只会保留一条）。
  static InvoiceImportBatch importFiles(Iterable<InvoiceImportFile> files) {
    final orders = <String, Ticket12306Order>{};
    final failures = <String>[];
    var fileCount = 0;
    for (final file in files) {
      fileCount++;
      try {
        final order = parseBytes(file.name, file.bytes);
        orders.putIfAbsent(order.dedupKey, () => order);
      } on TicketInvoiceImportException catch (error) {
        failures.add('${file.name}：${error.message}');
      } catch (error) {
        failures.add('${file.name}：$error');
      }
    }
    final sorted = orders.values.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    return InvoiceImportBatch(
      orders: sorted,
      fileCount: fileCount,
      failures: failures,
    );
  }

  static Ticket12306Order parseBytes(String name, Uint8List bytes) {
    final extension = isSupportedName(name)
        ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
        : '';
    final xml = switch (extension) {
      'pdf' => _extractPdfPayload(bytes),
      'ofd' => _extractOfdPayload(bytes),
      _ => throw const TicketInvoiceImportException('仅支持 PDF / OFD 电子发票'),
    };
    if (xml == null) {
      throw const TicketInvoiceImportException(
        '未找到铁路电子客票数据，请确认是从 12306 下载的原始电子发票',
      );
    }
    return parseXbrl(xml);
  }

  static Ticket12306Order parseXbrl(String xml) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(xml);
    } catch (_) {
      throw const TicketInvoiceImportException('发票数据无法解析');
    }

    // XBRL 里每个字段只出现一次，按本地名取值即可避开命名空间前缀差异。
    final values = <String, String>{};
    for (final element in document.descendants.whereType<XmlElement>()) {
      values.putIfAbsent(element.name.local, () => element.innerText.trim());
    }

    final travelDate = _parseDate(values['TravelDate'] ?? '');
    final departureTime = _parseClock(values['DepartureTime'] ?? '');
    final trainCode = values['TrainNumber'] ?? '';
    final fromStation = values['DepartureStation'] ?? '';
    final toStation = values['DestinationStation'] ?? '';
    if (travelDate == null || departureTime == null) {
      throw const TicketInvoiceImportException('发票缺少乘车日期或发车时间');
    }
    if (trainCode.isEmpty || fromStation.isEmpty || toStation.isEmpty) {
      throw const TicketInvoiceImportException('发票缺少车次或始发终到站');
    }

    final invoiceNumber = values['ElectronicInvoiceRailwayETicketNumber'] ?? '';
    final ticketNumber = values['ETicketNumber'] ?? '';
    final passengerName = values['Name'] ?? '';
    final startTime = DateTime(
      travelDate.year,
      travelDate.month,
      travelDate.day,
      departureTime.hour,
      departureTime.minute,
    );
    final price =
        double.tryParse((values['Fare'] ?? '').replaceAll(',', '')) ?? 0;

    return Ticket12306Order(
      id: invoiceNumber.isNotEmpty
          ? invoiceNumber
          : ticketNumber.isNotEmpty
          ? ticketNumber
          : '$trainCode|${startTime.toIso8601String()}|$passengerName',
      sequenceNo: invoiceNumber,
      startTime: startTime,
      arriveTime: null,
      trainCode: trainCode,
      fromStation: fromStation,
      toStation: toStation,
      // 电子发票不含里程，站序会按历史时刻表补全。
      distance: 0,
      passengerName: passengerName,
      seatType: values['SeatLevel'] ?? '',
      coachName: _stripSuffix(values['Carriage'] ?? '', '车'),
      seatName: _stripSuffix(values['Seat'] ?? '', '号'),
      price: price < 0 ? 0 : price,
      // 红字发票对应退票/冲红，不能再按乘车行程导入。
      statusText: (values['NumberOfOriginalInvoice'] ?? '').isNotEmpty
          ? '红字发票'
          : '电子发票',
    );
  }

  static String? _extractOfdPayload(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const TicketInvoiceImportException('OFD 文件已损坏或格式不正确');
    }
    for (final file in archive.files) {
      if (!file.isFile || !file.name.toLowerCase().endsWith('.xml')) continue;
      final content = file.content;
      if (content is! List<int>) continue;
      final text = utf8.decode(content, allowMalformed: true);
      if (_looksLikeXbrl(text)) return text;
    }
    return null;
  }

  /// PDF 的铁路发票把 XBRL 放在 EmbeddedFile 流里（FlateDecode 压缩）。
  /// 这里只做最小限度的对象扫描：找 `stream` 关键字，按 /Length 取流，
  /// 解压后看内容是不是 XBRL，不依赖完整的 PDF 语法解析。
  static String? _extractPdfPayload(Uint8List bytes) {
    if (bytes.length < 5 || String.fromCharCodes(bytes, 0, 5) != '%PDF-') {
      throw const TicketInvoiceImportException('PDF 文件已损坏或格式不正确');
    }
    final raw = String.fromCharCodes(bytes);
    var cursor = 0;
    while (true) {
      final index = raw.indexOf('stream', cursor);
      if (index < 0) break;
      cursor = index + 6;
      // 跳过 endstream 里的 stream。
      if (index > 0 && raw.codeUnitAt(index - 1) == 0x64) continue;
      final payload = _readPdfStream(bytes, raw, index);
      if (payload == null) continue;
      final candidates = [_inflate(payload), payload];
      for (final data in candidates) {
        if (data == null) continue;
        final text = utf8.decode(data, allowMalformed: true);
        if (_looksLikeXbrl(text)) return text;
      }
    }
    return null;
  }

  static List<int>? _readPdfStream(
    Uint8List bytes,
    String raw,
    int keywordIndex,
  ) {
    var start = keywordIndex + 6;
    if (start < raw.length && raw.codeUnitAt(start) == 0x0D) start++;
    if (start < raw.length && raw.codeUnitAt(start) == 0x0A) start++;
    if (start >= bytes.length) return null;

    final objectStart = raw.lastIndexOf('obj', keywordIndex);
    final length = _directStreamLength(
      raw.substring(objectStart < 0 ? 0 : objectStart, keywordIndex),
    );
    if (length != null && start + length <= bytes.length) {
      return bytes.sublist(start, start + length);
    }

    final end = raw.indexOf('endstream', start);
    if (end < 0) return null;
    var trimmedEnd = end;
    if (trimmedEnd > start && raw.codeUnitAt(trimmedEnd - 1) == 0x0A) {
      trimmedEnd--;
    }
    if (trimmedEnd > start && raw.codeUnitAt(trimmedEnd - 1) == 0x0D) {
      trimmedEnd--;
    }
    return bytes.sublist(start, trimmedEnd);
  }

  static final _directLength = RegExp(r'/Length\s+(\d+)(?!\s+\d+\s+R)');

  /// `/Length 45 0 R` 是对象引用，不能当字节数用。
  static int? _directStreamLength(String objectDict) {
    final match = _directLength.firstMatch(objectDict);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static List<int>? _inflate(List<int> data) {
    try {
      return ZLibDecoder().decodeBytes(data);
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeXbrl(String text) =>
      text.contains('ElectronicInvoiceRailwayETicketNumber') &&
      text.contains('DepartureStation');

  static DateTime? _parseDate(String value) {
    final match = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  static ({int hour, int minute})? _parseClock(String value) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})(?::\d{2})?$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return (hour: hour, minute: minute);
  }

  static String _stripSuffix(String value, String suffix) {
    final trimmed = value.trim();
    if (!trimmed.endsWith(suffix)) return trimmed;
    return trimmed.substring(0, trimmed.length - suffix.length).trim();
  }
}
