import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/services/mail_account_settings.dart';
import 'package:raillog/src/services/mail_import_exception.dart';
import 'package:raillog/src/services/mail_import_service.dart';
import 'package:raillog/src/services/pop3_client.dart';

void main() {
  test('登录后能读取 UIDL、邮件头和整封邮件，并还原被转义的点', () async {
    final server = await _ScriptedServer.start([
      [
        '+OK POP3 ready',
        '+OK user accepted',
        '+OK logged in',
        '+OK 2 4096',
        '+OK unique-id listing',
        '1 AAA',
        '2 BBB',
        '.',
        '+OK top of message follows',
        'Date: Sat, 24 May 2025 23:02:28 +0800',
        'From: 12306@rails.com.cn',
        'Subject: test message',
        'Message-ID: <first@example.com>',
        '',
        '.',
        '+OK message follows',
        'From: 12306@rails.com.cn',
        'Subject: test message',
        '',
        '..leading dot',
        '..two dots',
        '.',
        '+OK bye',
      ],
    ]);

    final client = await Pop3Client.connect(
      host: server.host,
      port: server.port,
      useTls: false,
    );
    try {
      await client.login('user@example.com', 'secret');
      expect(await client.messageCount(), 2);
      expect(await client.uidl(), {1: 'AAA', 2: 'BBB'});

      final header = latin1.decode(await client.topHeaders(1));
      expect(header, contains('Message-ID: <first@example.com>'));

      final message = latin1.decode(await client.retrieve(2));
      expect(message, contains('\n.leading dot\r\n'));
      expect(message, contains('\n.two dots\r\n'));
      expect(message, isNot(contains('..leading dot')));
    } finally {
      await client.quit();
    }
  });

  test('服务器不支持 TOP 时回退到整封下载', () async {
    final server = await _ScriptedServer.start([
      [
        '+OK POP3 ready',
        '+OK user accepted',
        '+OK logged in',
        '-ERR TOP not supported',
        '+OK message follows',
        'Subject: fallback',
        '',
        '.',
        '+OK bye',
      ],
    ]);

    final client = await Pop3Client.connect(
      host: server.host,
      port: server.port,
      useTls: false,
    );
    try {
      await client.login('user@example.com', 'secret');
      final header = latin1.decode(await client.topHeaders(3));
      expect(header, contains('Subject: fallback'));
    } finally {
      await client.quit();
    }
  });

  test('登录失败时给出可读提示', () async {
    final server = await _ScriptedServer.start([
      ['+OK POP3 ready', '+OK user accepted', '-ERR invalid credentials'],
    ]);

    final client = await Pop3Client.connect(
      host: server.host,
      port: server.port,
      useTls: false,
    );
    try {
      await expectLater(
        client.login('user@example.com', 'wrong'),
        throwsA(
          isA<MailImportException>().having(
            (error) => error.message,
            'message',
            contains('邮箱登录失败'),
          ),
        ),
      );
    } finally {
      client.close();
    }
  });

  test('POP3 列表在本地筛出 12306 邮件，下载时按 UIDL 找回同一封', () async {
    const subject = '网上购票系统-用户支付通知';
    final subjectEncoded = base64.encode(utf8.encode(subject));
    const ticketLine =
        '1.张三，2026年05月25日07:36开，安康站-西安站，C232次列车，'
        '5车3C号，二等座，成人票，票价70.0元，电子客票。';
    final body = base64.encode(
      utf8.encode('<html><body><div>$ticketLine</div></body></html>'),
    );
    final server = await _ScriptedServer.start([
      [
        '+OK POP3 ready',
        '+OK user accepted',
        '+OK logged in',
        '+OK 2 4096',
        '+OK unique-id listing',
        '1 AAA',
        '2 BBB',
        '.',
        '+OK top follows',
        'Date: Sun, 24 May 2026 10:00:00 +0800',
        'From: 12306@rails.com.cn',
        'Subject: =?utf-8?B?$subjectEncoded?=',
        'Message-ID: <m1@example.com>',
        '',
        '.',
        '+OK top follows',
        'Date: Sat, 23 May 2026 10:00:00 +0800',
        'From: newsletter@example.com',
        'Subject: weekly news',
        'Message-ID: <m2@example.com>',
        '',
        '.',
        '+OK bye',
      ],
      [
        '+OK POP3 ready',
        '+OK user accepted',
        '+OK logged in',
        '+OK unique-id listing',
        '1 AAA',
        '2 BBB',
        '.',
        '+OK message follows',
        'Date: Sun, 24 May 2026 10:00:00 +0800',
        'From: 12306@rails.com.cn',
        'Subject: =?utf-8?B?$subjectEncoded?=',
        'Message-ID: <m1@example.com>',
        'MIME-Version: 1.0',
        'Content-Type: text/html; charset="utf-8"',
        'Content-Transfer-Encoding: base64',
        '',
        body,
        '.',
        '+OK bye',
      ],
    ]);
    final config = MailAccountConfig(
      emailAddress: 'user@example.com',
      password: 'secret',
      host: server.host,
      port: server.port,
      protocol: MailProtocol.pop3,
      useTls: false,
    );
    const service = MailImportService();

    final summaries = await service.listMessages(config);
    expect(summaries, hasLength(1));
    expect(summaries.single.remoteId, 'AAA');
    expect(summaries.single.uid, 1);
    expect(summaries.single.subject, subject);
    expect(summaries.single.date, DateTime(2026, 5, 24, 10));

    final batches = await service.fetchTickets(config, summaries);
    expect(batches, hasLength(1));
    expect(batches.single.uid, 1);
    final order = batches.single.orders.single;
    expect(order.trainCode, 'C232');
    expect(order.fromStation, '安康站');
    expect(order.toStation, '西安站');
    expect(order.passengerName, '张三');
  });

  test('POP3 列表能识别手动转发到 QQ 邮箱的 12306 通知', () async {
    const subject = '转发: 网上购票系统-用户支付通知';
    final subjectEncoded = base64.encode(utf8.encode(subject));
    final server = await _ScriptedServer.start([
      [
        '+OK POP3 ready',
        '+OK user accepted',
        '+OK logged in',
        '+OK 1 2048',
        '+OK unique-id listing',
        '1 CCC',
        '.',
        '+OK top follows',
        'Date: Sun, 24 May 2026 10:00:00 +0800',
        'From: someone@outlook.com',
        'Subject: =?utf-8?B?$subjectEncoded?=',
        'Message-ID: <forwarded@example.com>',
        '',
        '.',
        '+OK bye',
      ],
    ]);
    final config = MailAccountConfig(
      emailAddress: 'user@qq.com',
      password: 'secret',
      host: server.host,
      port: server.port,
      protocol: MailProtocol.pop3,
      useTls: false,
    );

    final summaries = await const MailImportService().listMessages(config);
    expect(summaries, hasLength(1));
    expect(summaries.single.subject, subject);
    expect(summaries.single.from, 'someone@outlook.com');
  });
}

/// 按客户端命令顺序预先写好响应的本地服务器；测试不关心请求内容，
/// 只验证客户端能否按协议顺序读出这些响应。
class _ScriptedServer {
  _ScriptedServer._(this._server);

  final ServerSocket _server;

  static Future<_ScriptedServer> start(List<List<String>> scripts) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    var connection = 0;
    server.listen((socket) {
      final index = connection < scripts.length
          ? connection
          : scripts.length - 1;
      connection++;
      socket.add(latin1.encode('${scripts[index].join('\r\n')}\r\n'));
      socket.flush().then((_) => socket.close());
    });
    return _ScriptedServer._(server);
  }

  String get host => InternetAddress.loopbackIPv4.address;

  int get port => _server.port;
}
