import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/services/mail_account_settings.dart';
import 'package:raillog/src/services/mail_message_parser.dart';

void main() {
  group('12306 通知邮件解析', () {
    test('GBK 正文与 base64 编码的 HTML 邮件能解析出车票', () {
      final raw = _buildEmail(
        subject: '网上购票系统-用户支付通知',
        contentType: 'text/html; charset="gbk"',
        encoding: 'base64',
        body: base64.encode(
          gbk.encode('''
<!DOCTYPE html>
<html>
<head><meta charset="gb2312"></head>
<body>
  <div>尊敬的 <span>张三</span></div>
  <div>订单号码
  EN12345678
  。具体购票信息如下：</div>
  <div>1.张三，2025年05月25日07:36开，安康站-西安站，C232次列车，5车3C号，二等座，成人票，票价70.0元，电子客票。</div>
</body>
</html>
'''),
        ),
      );

      final content = MailMimeParser.parse(raw);
      expect(content.subject, '网上购票系统-用户支付通知');
      expect(content.messageId, 'test-message-001@example.com');
      expect(content.date, DateTime(2025, 5, 24, 23, 2, 28));
      expect(content.text, contains('票价70.0元'));

      final orders = TicketEmailParser.parse(
        content.text,
        messageId: content.messageId,
        subject: content.subject,
      );
      expect(orders, hasLength(1));
      final order = orders.single;
      expect(order.trainCode, 'C232');
      expect(order.fromStation, '安康站');
      expect(order.toStation, '西安站');
      expect(order.passengerName, '张三');
      expect(order.seatType, '二等座');
      expect(order.coachName, '5');
      expect(order.seatName, '3C');
      expect(order.price, 70);
      expect(order.sequenceNo, 'EN12345678');
      expect(order.startTime, DateTime(2025, 5, 25, 7, 36));
      expect(order.statusText, '邮件导入');
    });

    test('multipart/alternative 只取 HTML 一份，多张车票都保留', () {
      final first =
          '1.张三，2025年05月25日07:36开，安康站-西安站，C232次列车，'
          '5车3C号，二等座，成人票，票价70.0元，电子客票。';
      final second =
          '2.李四，2025年05月25日07:36开，安康站-西安站，C232次列车，'
          '5车5A号，二等座，成人票，票价70.0元，电子客票。';
      final raw = _buildEmail(
        subject: '网上购票系统-用户支付通知',
        contentType: 'multipart/alternative; boundary="boundary42"',
        encoding: null,
        body: [
          '--boundary42',
          'Content-Type: text/plain; charset="utf-8"',
          'Content-Transfer-Encoding: quoted-printable',
          '',
          _quotedPrintable('$first\n$second\n'),
          '--boundary42',
          'Content-Type: text/html; charset="utf-8"',
          'Content-Transfer-Encoding: quoted-printable',
          '',
          _quotedPrintable('<div>$first</div><div>$second</div>'),
          '--boundary42--',
          '',
        ].join('\r\n'),
      );

      final content = MailMimeParser.parse(raw);
      final orders = TicketEmailParser.parse(
        content.text,
        messageId: content.messageId,
        subject: content.subject,
      );
      expect(orders, hasLength(2));
      expect(orders.map((order) => order.passengerName), ['张三', '李四']);
      expect(orders.map((order) => order.seatName), ['3C', '5A']);
    });

    test('手动转发到 QQ 邮箱的购票通知仍能解析出车票', () {
      final ticket =
          '1.张三，2025年05月25日07:36开，安康站-西安站，C232次列车，'
          '5车3C号，二等座，成人票，票价70.0元，电子客票。';
      final raw = _buildEmail(
        subject: '转发: 网上购票系统-用户支付通知',
        from: 'someone@outlook.com',
        contentType: 'text/html; charset="utf-8"',
        encoding: 'quoted-printable',
        body: _quotedPrintable(
          '<div>发件人: 12306 &lt;12306@rails.com.cn&gt;</div>'
          '<div>$ticket</div>',
        ),
      );

      final content = MailMimeParser.parse(raw);
      expect(content.from, 'someone@outlook.com');
      final orders = TicketEmailParser.parse(
        content.text,
        messageId: content.messageId,
        subject: content.subject,
      );
      expect(orders, hasLength(1));
      expect(orders.single.trainCode, 'C232');
      expect(orders.single.fromStation, '安康站');
    });

    test('纯文本转发的引用标记和折行不影响车票解析', () {
      final raw = _buildEmail(
        subject: 'Fwd: 网上购票系统-用户支付通知',
        from: 'someone@outlook.com',
        contentType: 'text/plain; charset="utf-8"',
        encoding: 'quoted-printable',
        body: _quotedPrintable(
          '---------- Forwarded message ----------\n'
          '发件人: 12306 <12306@rails.com.cn>\n'
          '主题: 网上购票系统-用户支付通知\n\n'
          '> 1.张三，2025年05月25日07:36开，安康站-西安站，C232次列车，\n'
          '> 5车3C号，二等座，成人票，票价70.0元，电子客票。\n',
        ),
      );

      final content = MailMimeParser.parse(raw);
      final orders = TicketEmailParser.parse(
        content.text,
        messageId: content.messageId,
        subject: content.subject,
      );
      expect(orders, hasLength(1));
      expect(orders.single.coachName, '5');
      expect(orders.single.seatName, '3C');
      expect(orders.single.price, 70);
    });

    test('转发或回复前缀不影响退票、改签状态识别', () {
      final content =
          '1.张三，2025年05月25日07:36开，安康站-西安站，C232次列车，'
          '5车3C号，二等座，成人票，票价70.0元，电子客票。';
      expect(
        TicketEmailParser.parse(
          content,
          messageId: 'forward-refund',
          subject: '转发: 铁路12306-退票成功通知',
        ).single.statusText,
        '退票',
      );
      expect(
        TicketEmailParser.parse(
          content,
          messageId: 'forward-change',
          subject: 'Fwd: 铁路12306-改签成功通知',
        ).single.statusText,
        '改签',
      );
    });

    test('折行的 GBK 编码主题可以正确还原', () {
      final subject = gbk.encode('网上购票系统-用户支付通知');
      final raw = Uint8List.fromList(
        latin1.encode(
          'Subject: =?gbk?B?${base64.encode(subject)}?=\r\n'
          'From: =?utf-8?B?${base64.encode(utf8.encode('12306'))}?= '
          '<12306@rails.com.cn>\r\n'
          'Message-ID: <abc@example.com>\r\n\r\n',
        ),
      );
      final headers = MailMimeParser.parseHeaders(raw);
      expect(headers.subject, '网上购票系统-用户支付通知');
      expect(headers.from, contains('12306@rails.com.cn'));
      expect(headers.messageId, 'abc@example.com');
    });

    test('退票通知里的车票会被标记为不可导入', () {
      final content =
          '1.张三，2025年05月25日07:36开，安康站-西安站，C232次列车，'
          '5车3C号，二等座，成人票，票价70.0元，电子客票。';
      final orders = TicketEmailParser.parse(
        content,
        messageId: 'refund-message',
        subject: '铁路12306-退票成功通知',
      );
      expect(orders.single.statusText, '退票');
      expect(orders.single.canImport, isFalse);
    });
  });

  group('邮箱服务器推断', () {
    test('常见邮箱域名按协议匹配服务器', () {
      expect(
        MailAccountSettings.suggestHost('a@qq.com', MailProtocol.imap),
        'imap.qq.com',
      );
      expect(
        MailAccountSettings.suggestHost('a@qq.com', MailProtocol.pop3),
        'pop.qq.com',
      );
      expect(
        MailAccountSettings.suggestHost('a@163.com', MailProtocol.pop3),
        'pop.163.com',
      );
      expect(
        MailAccountSettings.suggestHost('a@outlook.com', MailProtocol.pop3),
        'outlook.office365.com',
      );
      expect(
        MailAccountSettings.suggestHost('a@example.com', MailProtocol.imap),
        isNull,
      );
    });

    test('协议名可以往返保存', () {
      expect(MailProtocol.fromName('pop3'), MailProtocol.pop3);
      expect(MailProtocol.fromName('imap'), MailProtocol.imap);
      expect(MailProtocol.fromName('unknown'), MailProtocol.imap);
      expect(MailProtocol.imap.defaultPort, 993);
      expect(MailProtocol.pop3.defaultPort, 995);
    });
  });
}

Uint8List _buildEmail({
  required String subject,
  required String contentType,
  required String body,
  required String? encoding,
  String? from,
}) {
  final fromHeader =
      from ??
      '=?utf-8?B?${base64.encode(utf8.encode('12306'))}?= <12306@rails.com.cn>';
  final headers = [
    'Date: Sat, 24 May 2025 23:02:28 +0800',
    'From: $fromHeader',
    'To: passenger@example.com',
    'Message-ID: <test-message-001@example.com>',
    'Subject: =?utf-8?B?${base64.encode(utf8.encode(subject))}?=',
    'MIME-Version: 1.0',
    'Content-Type: $contentType',
    if (encoding != null) 'Content-Transfer-Encoding: $encoding',
  ];
  return Uint8List.fromList(
    latin1.encode('${headers.join('\r\n')}\r\n\r\n$body'),
  );
}

String _quotedPrintable(String value) {
  final buffer = StringBuffer();
  for (final byte in utf8.encode(value)) {
    if (byte >= 0x20 && byte <= 0x7E && byte != 0x3D) {
      buffer.writeCharCode(byte);
    } else if (byte == 0x0A) {
      buffer.write('\r\n');
    } else {
      buffer.write('=${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return buffer.toString();
}
