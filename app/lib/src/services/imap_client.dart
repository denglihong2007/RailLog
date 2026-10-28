import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:raillog/src/services/mail_import_exception.dart';

class ImapResponse {
  const ImapResponse(this.text, this.literals);

  /// 不含 literal 的响应文本；literal 以原位置的空字符串代替。
  final String text;
  final List<Uint8List> literals;
}

class ImapFetchedHeader {
  const ImapFetchedHeader({
    required this.uid,
    required this.headerBytes,
    required this.internalDate,
  });

  final int uid;
  final Uint8List headerBytes;
  final DateTime? internalDate;
}

/// 只实现本项目需要的 IMAP 子集：登录、选择收件箱、按条件搜索 UID、
/// 取邮件头与整封邮件。不依赖第三方包，避免与现有依赖冲突。
class ImapClient {
  ImapClient._(this._socket) : _reader = _ImapReader(_socket);

  final Socket _socket;
  final _ImapReader _reader;
  int _tagCounter = 0;
  bool _closed = false;

  static Future<ImapClient> connect({
    required String host,
    required int port,
    required bool useTls,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    Socket socket;
    try {
      socket = useTls
          ? await SecureSocket.connect(host, port, timeout: timeout)
          : await Socket.connect(host, port, timeout: timeout);
    } on SocketException catch (error) {
      throw MailImportException('无法连接邮箱服务器 $host:$port：${error.message}');
    } on HandshakeException catch (error) {
      throw MailImportException('邮箱服务器 TLS 握手失败：${error.message}');
    }

    socket.setOption(SocketOption.tcpNoDelay, true);
    final client = ImapClient._(socket);
    try {
      final greeting = await client._reader.readLine().timeout(timeout);
      if (!greeting.startsWith('* OK') && !greeting.startsWith('* PREAUTH')) {
        client.close();
        throw MailImportException('邮箱服务器拒绝连接：$greeting');
      }
    } on TimeoutException {
      client.close();
      throw const MailImportException('等待邮箱服务器响应超时');
    } on MailImportException {
      client.close();
      rethrow;
    } catch (error) {
      client.close();
      throw MailImportException('读取邮箱服务器响应失败：$error');
    }
    return client;
  }

  Future<void> login(String emailAddress, String password) async {
    try {
      await execute('LOGIN ${_quote(emailAddress)} ${_quote(password)}');
    } on MailImportException catch (error) {
      throw MailImportException('邮箱登录失败，请检查邮箱地址和授权码：${error.message}');
    }
    // 163 / 126 等邮箱要求客户端先发送 ID 命令，否则 SELECT 会被拒绝。
    try {
      await execute('ID ("name" "RailLog" "version" "1.0" "vendor" "RailLog")');
    } on MailImportException {
      // 不支持 ID 的服务器会返回 BAD，忽略即可。
    }
  }

  Future<int> selectInbox() async {
    final responses = await execute('SELECT "INBOX"');
    for (final response in responses) {
      final match = RegExp(r'^\* (\d+) EXISTS').firstMatch(response.text);
      if (match != null) return int.parse(match.group(1)!);
    }
    return 0;
  }

  /// 搜索近 [since] 之后、发件人、主题或正文与 12306 有关的邮件 UID。
  /// 返回按 UID 升序排列的列表，只保留最近 [maxMessages] 封。
  Future<List<int>> searchTicketEmails({
    required DateTime since,
    int maxMessages = 300,
  }) async {
    final date = _formatImapDate(since);
    final queries = [
      'UID SEARCH SINCE $date FROM "12306"',
      'UID SEARCH SINCE $date FROM "rails.com.cn"',
      'UID SEARCH SINCE $date SUBJECT "12306"',
      // 手动转发后发件人会变成转发者，原发件地址只留在正文里。
      'UID SEARCH SINCE $date TEXT "rails.com.cn"',
    ];
    final uids = <int>{};
    for (final query in queries) {
      try {
        final responses = await execute(query);
        for (final response in responses) {
          if (!response.text.startsWith('* SEARCH')) continue;
          for (final token
              in response.text
                  .substring('* SEARCH'.length)
                  .trim()
                  .split(RegExp(r'\s+'))) {
            final uid = int.tryParse(token);
            if (uid != null) uids.add(uid);
          }
        }
      } on MailImportException {
        // 少部分服务器不支持某个搜索键，继续用其余条件。
      }
    }
    final sorted = uids.toList()..sort();
    if (sorted.length <= maxMessages) return sorted;
    return sorted.sublist(sorted.length - maxMessages);
  }

  Future<List<ImapFetchedHeader>> fetchHeaders(List<int> uids) async {
    if (uids.isEmpty) return const [];
    final result = <ImapFetchedHeader>[];
    for (final chunk in _chunks(uids)) {
      final responses = await execute(
        'UID FETCH ${chunk.join(',')} '
        '(UID INTERNALDATE BODY.PEEK[HEADER.FIELDS '
        '(DATE FROM SUBJECT MESSAGE-ID)])',
      );
      for (final response in responses) {
        final uid = _readUid(response.text);
        if (uid == null || response.literals.isEmpty) continue;
        result.add(
          ImapFetchedHeader(
            uid: uid,
            headerBytes: response.literals.first,
            internalDate: _readInternalDate(response.text),
          ),
        );
      }
    }
    return result;
  }

  Future<Map<int, Uint8List>> fetchMessages(List<int> uids) async {
    if (uids.isEmpty) return const {};
    final result = <int, Uint8List>{};
    for (final chunk in _chunks(uids)) {
      final responses = await execute(
        'UID FETCH ${chunk.join(',')} (UID BODY.PEEK[])',
      );
      for (final response in responses) {
        final uid = _readUid(response.text);
        if (uid == null || response.literals.isEmpty) continue;
        result[uid] = response.literals.first;
      }
    }
    return result;
  }

  Future<List<ImapResponse>> execute(
    String command, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (_closed) throw const MailImportException('邮箱连接已关闭');
    final tag = 'A${++_tagCounter}';
    try {
      return await _execute(tag, command).timeout(
        timeout,
        onTimeout: () {
          close();
          throw const MailImportException('邮箱服务器响应超时');
        },
      );
    } on TimeoutException {
      throw const MailImportException('邮箱服务器响应超时');
    } on SocketException catch (error) {
      throw MailImportException('邮箱连接中断：${error.message}');
    }
  }

  Future<List<ImapResponse>> _execute(String tag, String command) async {
    _socket.write('$tag $command\r\n');
    await _socket.flush();
    final responses = <ImapResponse>[];

    while (true) {
      var text = await _reader.readLine();
      final literals = <Uint8List>[];
      var literal = _literalTail.firstMatch(text);
      while (literal != null) {
        final length = int.parse(literal.group(1)!);
        final data = await _reader.readBytes(length);
        literals.add(data);
        final rest = await _reader.readLine();
        text = text.substring(0, literal.start) + rest;
        literal = _literalTail.firstMatch(text);
      }

      if (text.startsWith('$tag ')) {
        final status = text.substring(tag.length + 1).trim();
        if (status.toUpperCase().startsWith('OK')) return responses;
        throw MailImportException('邮箱操作失败：$status');
      }
      if (text.startsWith('* BYE')) {
        throw MailImportException('邮箱服务器断开了连接：$text');
      }
      if (text.startsWith('+')) continue;
      responses.add(ImapResponse(text, literals));
    }
  }

  Future<void> logout() async {
    if (_closed) return;
    try {
      await execute('LOGOUT', timeout: const Duration(seconds: 10));
    } on Object {
      // 注销失败不影响已取到的数据。
    } finally {
      close();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _reader.dispose();
    _socket.destroy();
  }

  static Iterable<List<int>> _chunks(List<int> values) sync* {
    const chunkSize = 100;
    for (var start = 0; start < values.length; start += chunkSize) {
      final end = start + chunkSize < values.length
          ? start + chunkSize
          : values.length;
      yield values.sublist(start, end);
    }
  }

  static int? _readUid(String text) =>
      int.tryParse(RegExp(r'\bUID (\d+)').firstMatch(text)?.group(1) ?? '');

  static DateTime? _readInternalDate(String text) {
    final match = RegExp(r'INTERNALDATE "([^"]+)"').firstMatch(text);
    if (match == null) return null;
    return _parseImapDateTime(match.group(1)!);
  }

  static DateTime? _parseImapDateTime(String value) {
    final match = RegExp(
      r'^(\d{1,2})-([A-Za-z]{3})-(\d{4}) '
      r'(\d{1,2}):(\d{2}):(\d{2}) ([+-])(\d{2})(\d{2})$',
    ).firstMatch(value.trim());
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
    final offsetMinutes =
        int.parse(match.group(8)!) * 60 + int.parse(match.group(9)!);
    final signedOffset = match.group(7) == '-' ? -offsetMinutes : offsetMinutes;
    return DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    ).subtract(Duration(minutes: signedOffset)).toLocal();
  }

  static String _formatImapDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${value.day.toString().padLeft(2, '0')}-'
        '${months[value.month - 1]}-${value.year}';
  }

  static String _quote(String value) =>
      '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  static final _literalTail = RegExp(r'\{(\d+)\}$');
}

class _ImapReader {
  _ImapReader(Socket socket) : _iterator = StreamIterator<Uint8List>(socket);

  final StreamIterator<Uint8List> _iterator;
  final List<int> _buffer = [];
  bool _disposed = false;

  Future<String> readLine() async {
    while (true) {
      for (var index = 0; index < _buffer.length; index++) {
        if (_buffer[index] != 10) continue;
        final hasCr = index > 0 && _buffer[index - 1] == 13;
        final lineEnd = hasCr ? index - 1 : index;
        final line = latin1.decode(_buffer.sublist(0, lineEnd));
        _buffer.removeRange(0, index + 1);
        return line;
      }
      await _fill();
    }
  }

  Future<Uint8List> readBytes(int count) async {
    while (_buffer.length < count) {
      await _fill();
    }
    final result = Uint8List.fromList(_buffer.sublist(0, count));
    _buffer.removeRange(0, count);
    return result;
  }

  Future<void> _fill() async {
    if (_disposed || !await _iterator.moveNext()) {
      throw const MailImportException('邮箱服务器已断开连接');
    }
    _buffer.addAll(_iterator.current);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_iterator.cancel());
  }
}
