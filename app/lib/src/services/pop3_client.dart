import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:raillog/src/services/mail_import_exception.dart';

/// 只实现本项目需要的 POP3 子集：登录、统计、UIDL、TOP 取邮件头、
/// RETR 取整封邮件。POP3 没有服务端搜索，筛选在调用方完成。
class Pop3Client {
  Pop3Client._(this._socket) : _reader = _Pop3Reader(_socket);

  final Socket _socket;
  final _Pop3Reader _reader;
  bool _closed = false;

  static Future<Pop3Client> connect({
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
    final client = Pop3Client._(socket);
    try {
      final greeting = await client._reader.readLine().timeout(timeout);
      if (!greeting.startsWith('+OK')) {
        client.close();
        throw MailImportException('邮箱服务器拒绝连接：${_errorText(greeting)}');
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
    _ensureSingleLine(emailAddress, '邮箱地址');
    _ensureSingleLine(password, '授权码');
    try {
      await _command('USER $emailAddress');
      await _command('PASS $password');
    } on MailImportException catch (error) {
      throw MailImportException('邮箱登录失败，请检查邮箱地址和授权码：${error.message}');
    }
  }

  /// 返回收件箱邮件数（不含标记删除的邮件）。
  Future<int> messageCount() async {
    final status = await _command('STAT');
    final parts = status.substring(3).trim().split(RegExp(r'\s+'));
    return int.tryParse(parts.first) ?? 0;
  }

  /// 邮件序号 → 唯一标识。服务器不支持 UIDL 时返回空表。
  Future<Map<int, String>> uidl() async {
    try {
      final bytes = await _multiline('UIDL');
      final result = <int, String>{};
      for (final line in latin1.decode(bytes).split(RegExp(r'\r?\n'))) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final space = trimmed.indexOf(' ');
        if (space <= 0) continue;
        final number = int.tryParse(trimmed.substring(0, space));
        if (number == null) continue;
        final uniqueId = trimmed.substring(space + 1).trim();
        if (uniqueId.isNotEmpty) result[number] = uniqueId;
      }
      return result;
    } on MailImportException {
      return const {};
    }
  }

  /// 只取邮件头。少数服务器不支持 TOP，退回整封下载。
  Future<Uint8List> topHeaders(int messageNumber) async {
    try {
      return await _multiline('TOP $messageNumber 0');
    } on MailImportException {
      return retrieve(messageNumber);
    }
  }

  Future<Uint8List> retrieve(int messageNumber) =>
      _multiline('RETR $messageNumber');

  Future<String> _command(String command) async {
    if (_closed) throw const MailImportException('邮箱连接已关闭');
    try {
      return await _sendAndReadStatus(command).timeout(
        const Duration(seconds: 45),
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

  Future<Uint8List> _multiline(String command) async {
    if (_closed) throw const MailImportException('邮箱连接已关闭');
    try {
      return await _sendAndReadMultiline(command).timeout(
        const Duration(seconds: 60),
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

  Future<String> _sendAndReadStatus(String command) async {
    _socket.write('$command\r\n');
    await _socket.flush();
    final status = await _reader.readLine();
    if (!status.startsWith('+OK')) {
      throw MailImportException('邮箱操作失败：${_errorText(status)}');
    }
    return status;
  }

  Future<Uint8List> _sendAndReadMultiline(String command) async {
    await _sendAndReadStatus(command);
    return _reader.readMultiline();
  }

  Future<void> quit() async {
    if (_closed) return;
    try {
      await _command('QUIT');
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

  static String _errorText(String status) {
    final trimmed = status.trim();
    if (trimmed.toUpperCase().startsWith('-ERR')) {
      return trimmed.substring(4).trim();
    }
    return trimmed;
  }

  static void _ensureSingleLine(String value, String label) {
    if (value.contains('\r') || value.contains('\n')) {
      throw MailImportException('$label包含非法字符');
    }
  }
}

class _Pop3Reader {
  _Pop3Reader(Socket socket) : _iterator = StreamIterator<Uint8List>(socket);

  final StreamIterator<Uint8List> _iterator;
  final List<int> _buffer = [];
  bool _disposed = false;

  Future<String> readLine() async => latin1.decode(await readLineBytes());

  Future<Uint8List> readLineBytes() async {
    while (true) {
      for (var index = 0; index < _buffer.length; index++) {
        if (_buffer[index] != 10) continue;
        final hasCr = index > 0 && _buffer[index - 1] == 13;
        final lineEnd = hasCr ? index - 1 : index;
        final line = Uint8List.fromList(_buffer.sublist(0, lineEnd));
        _buffer.removeRange(0, index + 1);
        return line;
      }
      await _fill();
    }
  }

  /// 读取多行响应，直到单独一行的 `.`。按 POP3 规则去掉行首的点
  /// （dot-stuffing），行尾统一补 CRLF。
  Future<Uint8List> readMultiline() async {
    final builder = BytesBuilder(copy: false);
    while (true) {
      var line = await readLineBytes();
      if (line.length == 1 && line[0] == 0x2E) break;
      if (line.isNotEmpty && line[0] == 0x2E) {
        line = line.sublist(1);
      }
      builder.add(line);
      builder.addByte(13);
      builder.addByte(10);
    }
    return builder.takeBytes();
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
