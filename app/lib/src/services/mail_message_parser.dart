import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart';
import 'package:raillog/src/models/ticket_12306_order.dart';

/// 邮件头里的展示字段。先只取这些筛出候选邮件，再决定下载哪些正文。
class ParsedMailHeaders {
  const ParsedMailHeaders({
    required this.subject,
    required this.from,
    required this.date,
    required this.messageId,
  });

  final String subject;
  final String from;
  final DateTime? date;
  final String messageId;
}

/// 一封邮件的可检索文本。HTML 邮件会先转成纯文本，保留换行与中文标点。
class ParsedMailContent {
  const ParsedMailContent({
    required this.subject,
    required this.from,
    required this.date,
    required this.messageId,
    required this.text,
  });

  final String subject;
  final String from;
  final DateTime? date;
  final String messageId;
  final String text;
}

/// 轻量 MIME 解析器，只覆盖 12306 通知邮件用到的部分：
/// 头字段折行、RFC 2047 编码字、multipart、base64 / quoted-printable
/// 以及 UTF-8 / GBK / GB2312 / Big5 字符集。
class MailMimeParser {
  const MailMimeParser._();

  static ParsedMailHeaders parseHeaders(Uint8List rawHeaders) {
    final headers = _parseHeaderMap(rawHeaders);
    return ParsedMailHeaders(
      subject: _decodeHeaderValue(headers['subject'] ?? ''),
      from: _decodeHeaderValue(headers['from'] ?? ''),
      date: _parseMailDate(headers['date'] ?? ''),
      messageId: _cleanMessageId(headers['message-id'] ?? ''),
    );
  }

  static ParsedMailContent parse(Uint8List raw) {
    final split = _splitHeaderAndBody(raw);
    final headers = _parseHeaderMap(split.headers);
    final htmlParts = <String>[];
    final plainParts = <String>[];
    _collectTextParts(headers, split.body, htmlParts, plainParts);
    // multipart/alternative 会同时带纯文本与 HTML 两份内容，取一份即可，
    // 否则同一张车票会被解析两遍。
    final useHtml = htmlParts.isNotEmpty;
    final rawText = (useHtml ? htmlParts : plainParts).join('\n');
    return ParsedMailContent(
      subject: _decodeHeaderValue(headers['subject'] ?? ''),
      from: _decodeHeaderValue(headers['from'] ?? ''),
      date: _parseMailDate(headers['date'] ?? ''),
      messageId: _cleanMessageId(headers['message-id'] ?? ''),
      // 纯文本里的 <...> 是正文，不是 HTML 标签，不能当标签删掉。
      text: useHtml ? htmlToText(rawText) : _normalizeText(rawText),
    );
  }

  /// 把 HTML 邮件转成便于正则匹配的纯文本。
  static String htmlToText(String html) {
    if (!html.contains('<')) return _normalizeText(html);
    var value = html
        .replaceAll(
          RegExp(r'<(script|style)\b[^>]*>[\s\S]*?</\1>', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(p|div|tr|td|li|h[1-6]|table)>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), '');
    value = _decodeEntities(value);
    return _normalizeText(value);
  }

  static String _normalizeText(String value) => value
      .replaceAll(' ', ' ')
      .replaceAll(RegExp(r'[ \t\f\v]+'), ' ')
      .replaceAll(RegExp(r'\s*\n\s*'), '\n')
      .trim();

  static void _collectTextParts(
    Map<String, String> headers,
    Uint8List body,
    List<String> htmlParts,
    List<String> plainParts,
  ) {
    final contentType = _parseContentType(headers['content-type']);
    if (contentType.mimeType.startsWith('multipart/')) {
      final boundary = contentType.parameters['boundary'];
      if (boundary == null || boundary.isEmpty) return;
      for (final part in _splitMultipart(body, boundary)) {
        final split = _splitHeaderAndBody(part);
        _collectTextParts(
          _parseHeaderMap(split.headers),
          split.body,
          htmlParts,
          plainParts,
        );
      }
      return;
    }
    if (contentType.mimeType != 'text/html' &&
        contentType.mimeType != 'text/plain') {
      return;
    }
    final decoded = _decodeTransferEncoding(
      headers['content-transfer-encoding'],
      body,
    );
    final text = decodeCharset(
      decoded,
      contentType.parameters['charset'] ?? 'us-ascii',
    );
    if (contentType.mimeType == 'text/html') {
      htmlParts.add(text);
    } else {
      plainParts.add(text);
    }
  }

  static _HeaderAndBody _splitHeaderAndBody(Uint8List raw) {
    for (var index = 0; index + 1 < raw.length; index++) {
      if (raw[index] == 10 && raw[index + 1] == 10) {
        return _HeaderAndBody(raw.sublist(0, index), raw.sublist(index + 2));
      }
      if (index + 3 < raw.length &&
          raw[index] == 13 &&
          raw[index + 1] == 10 &&
          raw[index + 2] == 13 &&
          raw[index + 3] == 10) {
        return _HeaderAndBody(raw.sublist(0, index), raw.sublist(index + 4));
      }
    }
    return _HeaderAndBody(raw, Uint8List(0));
  }

  static Map<String, String> _parseHeaderMap(Uint8List rawHeaders) {
    final text = _decodeRawText(rawHeaders);
    final headers = <String, String>{};
    String? currentName;
    final buffer = StringBuffer();

    void flush() {
      final name = currentName;
      if (name == null) return;
      headers[name] = buffer.toString().trim();
      buffer.clear();
    }

    for (final line in text.split(RegExp(r'\r?\n'))) {
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (currentName != null) buffer.write(' ${line.trim()}');
        continue;
      }
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      flush();
      currentName = line.substring(0, colon).trim().toLowerCase();
      buffer.write(line.substring(colon + 1).trim());
    }
    flush();
    return headers;
  }

  static String _decodeRawText(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  static List<Uint8List> _splitMultipart(Uint8List body, String boundary) {
    final raw = latin1.decode(body);
    final marker = '--$boundary';
    final parts = <Uint8List>[];
    var searchIndex = 0;

    while (true) {
      final markerIndex = raw.indexOf(marker, searchIndex);
      if (markerIndex < 0) break;
      var afterMarker = markerIndex + marker.length;
      if (raw.startsWith('--', afterMarker)) break;
      final lineEnd = raw.indexOf('\n', afterMarker);
      if (lineEnd < 0) break;
      final partStart = lineEnd + 1;
      final nextMarker = raw.indexOf(marker, partStart);
      if (nextMarker < 0) break;
      var partEnd = nextMarker;
      if (partEnd > partStart && raw.codeUnitAt(partEnd - 1) == 10) partEnd--;
      if (partEnd > partStart && raw.codeUnitAt(partEnd - 1) == 13) partEnd--;
      parts.add(
        Uint8List.fromList(latin1.encode(raw.substring(partStart, partEnd))),
      );
      searchIndex = nextMarker;
    }
    return parts;
  }

  static Uint8List _decodeTransferEncoding(String? encoding, Uint8List body) {
    final value = (encoding ?? '').trim().toLowerCase();
    if (value == 'base64') {
      try {
        final text = latin1
            .decode(body)
            .replaceAll(RegExp(r'\s'), '')
            .replaceAll('-', '+')
            .replaceAll('_', '/');
        return Uint8List.fromList(base64Decode(_padBase64(text)));
      } on FormatException {
        return body;
      }
    }
    if (value == 'quoted-printable') {
      return _decodeQuotedPrintable(body);
    }
    return body;
  }

  static Uint8List _decodeQuotedPrintable(Uint8List body) {
    final input = latin1.decode(body);
    final result = <int>[];
    for (var index = 0; index < input.length; index++) {
      final char = input[index];
      if (char == '=') {
        if (index + 1 < input.length && input[index + 1] == '\n') {
          index++;
          continue;
        }
        if (index + 2 < input.length &&
            input[index + 1] == '\r' &&
            input[index + 2] == '\n') {
          index += 2;
          continue;
        }
        if (index + 2 < input.length) {
          final value = int.tryParse(
            input.substring(index + 1, index + 3),
            radix: 16,
          );
          if (value != null) {
            result.add(value);
            index += 2;
            continue;
          }
        }
      }
      result.add(input.codeUnitAt(index));
    }
    return Uint8List.fromList(result);
  }

  static String decodeCharset(Uint8List bytes, String charset) {
    final name = charset
        .trim()
        .toLowerCase()
        .replaceAll('"', '')
        .replaceAll("'", '');
    return switch (name) {
      '' ||
      'utf-8' ||
      'utf8' ||
      'unicode-1-1-utf-8' => utf8.decode(bytes, allowMalformed: true),
      'gbk' ||
      'gb2312' ||
      'gb18030' ||
      'cp936' ||
      'x-gbk' ||
      'gb_2312-80' => gbk.decode(bytes, allowInvalid: true),
      'big5' ||
      'big-5' ||
      'cp950' => const Big5Codec(allowInvalid: true).decode(bytes),
      'iso-8859-1' || 'latin1' || 'latin-1' || 'l1' => latin1.decode(bytes),
      'us-ascii' || 'ascii' => ascii.decode(bytes, allowInvalid: true),
      _ => _decodeUnknownCharset(bytes),
    };
  }

  static String _decodeUnknownCharset(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      final decoded = gbk.decode(bytes, allowInvalid: true);
      if (!decoded.contains('�')) return decoded;
      return latin1.decode(bytes);
    }
  }

  static String _decodeHeaderValue(String value) {
    if (!value.contains('=?')) return value.trim();
    final joined = value.replaceAllMapped(
      RegExp(r'(\?=)\s+(=\?)'),
      (match) => '${match.group(1)}${match.group(2)}',
    );
    final decoded = joined.replaceAllMapped(
      RegExp(r'=\?([^?]+)\?([BbQq])\?([^?]*)\?='),
      (match) {
        final charset = match.group(1) ?? 'utf-8';
        final encoding = (match.group(2) ?? 'B').toUpperCase();
        final payload = match.group(3) ?? '';
        try {
          final bytes = switch (encoding) {
            'Q' => _decodeQEncoding(payload),
            _ => base64Decode(_padBase64(payload)),
          };
          return decodeCharset(Uint8List.fromList(bytes), charset);
        } on FormatException {
          return match.group(0) ?? '';
        }
      },
    );
    return decoded.trim();
  }

  static List<int> _decodeQEncoding(String value) {
    final bytes = <int>[];
    for (var index = 0; index < value.length; index++) {
      final char = value[index];
      if (char == '_') {
        bytes.add(0x20);
        continue;
      }
      if (char == '=' && index + 2 < value.length) {
        final decoded = int.tryParse(
          value.substring(index + 1, index + 3),
          radix: 16,
        );
        if (decoded != null) {
          bytes.add(decoded);
          index += 2;
          continue;
        }
      }
      final codeUnit = value.codeUnitAt(index);
      if (codeUnit <= 0xFF) {
        bytes.add(codeUnit);
      } else {
        bytes.addAll(utf8.encode(char));
      }
    }
    return bytes;
  }

  static String _padBase64(String value) {
    final remainder = value.length % 4;
    if (remainder == 0) return value;
    return value + '=' * (4 - remainder);
  }

  static String _decodeEntities(String value) =>
      value.replaceAllMapped(RegExp(r'&(#x?[0-9A-Fa-f]+|[A-Za-z]+);'), (match) {
        final token = match.group(1)!;
        if (token.startsWith('#x') || token.startsWith('#X')) {
          final code = int.tryParse(token.substring(2), radix: 16);
          if (code != null) return String.fromCharCode(code);
        } else if (token.startsWith('#')) {
          final code = int.tryParse(token.substring(1));
          if (code != null) return String.fromCharCode(code);
        }
        return switch (token.toLowerCase()) {
          'nbsp' => ' ',
          'amp' => '&',
          'lt' => '<',
          'gt' => '>',
          'quot' => '"',
          'apos' => "'",
          'mdash' => '—',
          'ndash' => '–',
          'hellip' => '…',
          'ldquo' => '“',
          'rdquo' => '”',
          'lsquo' => '‘',
          'rsquo' => '’',
          'middot' => '·',
          _ => match.group(0)!,
        };
      });

  static _ParsedContentType _parseContentType(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const _ParsedContentType('text/plain', {'charset': 'us-ascii'});
    }
    final segments = _splitParameters(raw);
    final mimeType = segments.isEmpty
        ? 'text/plain'
        : segments.first.trim().toLowerCase();
    final parameters = <String, String>{};
    for (final segment in segments.skip(1)) {
      final equals = segment.indexOf('=');
      if (equals <= 0) continue;
      final name = segment.substring(0, equals).trim().toLowerCase();
      var value = segment.substring(equals + 1).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      parameters[name] = value;
    }
    return _ParsedContentType(mimeType, parameters);
  }

  static List<String> _splitParameters(String value) {
    final segments = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var index = 0; index < value.length; index++) {
      final char = value[index];
      if (char == '"') quoted = !quoted;
      if (char == ';' && !quoted) {
        segments.add(buffer.toString());
        buffer.clear();
        continue;
      }
      buffer.write(char);
    }
    if (buffer.isNotEmpty) segments.add(buffer.toString());
    return segments;
  }

  static DateTime? _parseMailDate(String value) {
    final match = RegExp(
      r'^\s*(?:[A-Za-z]{3},\s*)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+'
      r'(\d{1,2}):(\d{2})(?::(\d{2}))?',
    ).firstMatch(value);
    if (match == null) return null;
    const months = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final month = months[match.group(2)!.toLowerCase()];
    if (month == null) return null;
    return DateTime(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.tryParse(match.group(6) ?? '') ?? 0,
    );
  }

  static String _cleanMessageId(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('<') && trimmed.endsWith('>')) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
    return trimmed;
  }
}

/// 从 12306「网上购票系统-用户支付通知」一类邮件里提取车票。
///
/// 正文里的车票行形如：
/// `1.张三，2025年05月25日07:36开，安康站-西安站，C232次列车，5车3C号，二等座，成人票，票价70.0元，电子客票。`
class TicketEmailParser {
  const TicketEmailParser._();

  static final _ticketPattern = RegExp(
    r'(\d{1,2})\.\s*([^，,]+?)\s*[，,]\s*'
    r'(\d{4})年(\d{1,2})月(\d{1,2})日\s*(\d{1,2})[:：](\d{2})\s*开\s*[，,]\s*'
    r'([^，,]+?)\s*[-—–]\s*([^，,]+?)\s*[，,]\s*'
    r'([A-Za-z]?\s*\d+[A-Za-z0-9]*)\s*次列车\s*[，,]\s*'
    r'([^，,]+?)\s*[，,]\s*([^，,]+?)\s*[，,]\s*([^，,]+?)\s*[，,]\s*'
    r'票价\s*([0-9]+(?:\.[0-9]+)?)\s*元',
  );

  static List<Ticket12306Order> parse(
    String content, {
    required String messageId,
    String subject = '',
    DateTime? emailDate,
  }) {
    final text = _stripQuoteMarkers(content).replaceAll(RegExp(r'\s+'), ' ');
    if (!text.contains('次列车') || !text.contains('票价')) return const [];

    final sequenceNo = _extractOrderNumber(text);
    final statusText = _statusFromSubject(subject);
    final orders = <Ticket12306Order>[];

    for (final match in _ticketPattern.allMatches(text)) {
      final passengerName = match.group(2)!.trim();
      final startTime = DateTime(
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
        int.parse(match.group(7)!),
      );
      final fromStation = match.group(8)!.trim();
      final toStation = match.group(9)!.trim();
      final trainCode = match.group(10)!.replaceAll(RegExp(r'\s+'), '');
      final seat = _parseSeat(match.group(11)!.trim());
      final seatType = match.group(12)!.trim();
      final price = double.tryParse(match.group(14)!) ?? 0;
      final stableId = [
        messageId,
        orders.length,
        trainCode,
        startTime.toIso8601String(),
        passengerName,
      ].join('|');

      orders.add(
        Ticket12306Order(
          id: stableId,
          sequenceNo: sequenceNo,
          startTime: startTime,
          arriveTime: null,
          trainCode: trainCode,
          fromStation: fromStation,
          toStation: toStation,
          distance: 0,
          passengerName: passengerName,
          seatType: seatType,
          coachName: seat.coachName,
          seatName: seat.seatName,
          price: price,
          statusText: statusText,
        ),
      );
    }
    return orders;
  }

  /// 纯文本转发/回复会在每行前加 `>`。先按行去掉引用标记，再把被客户端
  /// 折开的行拼回一行；否则折行处的 `>` 会被当成车厢号的一部分。
  static String _stripQuoteMarkers(String value) {
    if (!value.contains('>')) return value;
    return value
        .split(RegExp(r'\r?\n'))
        .map((line) => line.replaceFirst(RegExp(r'^\s*(?:>\s*)+'), ''))
        .join('\n');
  }

  static String _extractOrderNumber(String text) {
    final match = RegExp(r'订单号[码为是：:\s]*([A-Za-z0-9]+)').firstMatch(text);
    return match?.group(1) ?? '';
  }

  static String _statusFromSubject(String subject) {
    if (subject.contains('退票')) return '退票';
    if (subject.contains('改签')) return '改签';
    return '邮件导入';
  }

  static _ParsedSeat _parseSeat(String value) {
    final match = RegExp(r'^(\d+)\s*车\s*(.+?)\s*号?$').firstMatch(value);
    if (match != null) {
      return _ParsedSeat(match.group(1)!, match.group(2)!.trim());
    }
    if (value == '无座' || value == '不对号入座') {
      return _ParsedSeat('99', value);
    }
    return _ParsedSeat('', value);
  }
}

class _HeaderAndBody {
  const _HeaderAndBody(this.headers, this.body);

  final Uint8List headers;
  final Uint8List body;
}

class _ParsedContentType {
  const _ParsedContentType(this.mimeType, this.parameters);

  final String mimeType;
  final Map<String, String> parameters;
}

class _ParsedSeat {
  const _ParsedSeat(this.coachName, this.seatName);

  final String coachName;
  final String seatName;
}
