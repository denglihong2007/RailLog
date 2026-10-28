import 'dart:typed_data';

import 'package:raillog/src/models/ticket_12306_order.dart';
import 'package:raillog/src/services/imap_client.dart';
import 'package:raillog/src/services/mail_account_settings.dart';
import 'package:raillog/src/services/mail_import_exception.dart';
import 'package:raillog/src/services/mail_message_parser.dart';
import 'package:raillog/src/services/pop3_client.dart';

class MailMessageSummary {
  const MailMessageSummary({
    required this.uid,
    required this.remoteId,
    required this.subject,
    required this.from,
    required this.date,
    required this.messageId,
  });

  final int uid;

  /// 协议内的稳定标识：IMAP 是 UID，POP3 是 UIDL。
  /// 列表与下载分两次连接，下载时靠它重新定位同一封邮件。
  final String remoteId;
  final String subject;
  final String from;
  final DateTime? date;
  final String messageId;

  String get displaySubject {
    final value = subject.trim();
    return value.isEmpty ? '(无主题)' : value;
  }
}

class MailTicketBatch {
  const MailTicketBatch({required this.uid, required this.orders});

  final int uid;
  final List<Ticket12306Order> orders;
}

class MailImportService {
  const MailImportService();

  /// 连接并登录后返回收件箱邮件数，用于设置页的「测试连接」。
  Future<int> testConnection(MailAccountConfig config) async {
    if (config.protocol == MailProtocol.pop3) {
      final client = await _connectPop3(config);
      try {
        return await client.messageCount();
      } finally {
        await client.quit();
      }
    }
    final client = await _connectImap(config);
    try {
      return await client.selectInbox();
    } finally {
      await client.logout();
    }
  }

  Future<List<MailMessageSummary>> listMessages(
    MailAccountConfig config, {
    DateTime? since,
    int maxMessages = 300,
  }) async {
    final cutoff = since ?? DateTime.now().subtract(const Duration(days: 730));
    if (config.protocol == MailProtocol.pop3) {
      return _listPop3Messages(config, cutoff, maxMessages);
    }
    final client = await _connectImap(config);
    try {
      await client.selectInbox();
      final uids = await client.searchTicketEmails(
        since: cutoff,
        maxMessages: maxMessages,
      );
      if (uids.isEmpty) return const [];
      final headers = await client.fetchHeaders(uids);
      final summaries = headers.map(_summaryFromHeader).toList();
      _sortByDateDesc(summaries);
      return summaries;
    } finally {
      await client.logout();
    }
  }

  /// 下载所选邮件的完整内容并解析车票。一封支付通知通常对应一张票，
  /// 但同一订单可能一次购买多张，所以每个 UID 返回一组。
  Future<List<MailTicketBatch>> fetchTickets(
    MailAccountConfig config,
    List<MailMessageSummary> messages,
  ) async {
    if (messages.isEmpty) return const [];
    if (config.protocol == MailProtocol.pop3) {
      return _fetchPop3Tickets(config, messages);
    }
    final client = await _connectImap(config);
    try {
      await client.selectInbox();
      final rawMessages = await client.fetchMessages(
        messages.map((message) => message.uid).toList(growable: false),
      );
      final batches = <MailTicketBatch>[];
      for (final message in messages) {
        final raw = rawMessages[message.uid];
        if (raw == null) continue;
        batches.add(_parseBatch(message, raw));
      }
      return batches;
    } finally {
      await client.logout();
    }
  }

  /// POP3 没有服务端搜索：先取 UIDL，再对最近的邮件逐个 TOP 取头部，
  /// 最后在本地筛出 12306 的通知。
  Future<List<MailMessageSummary>> _listPop3Messages(
    MailAccountConfig config,
    DateTime cutoff,
    int maxMessages,
  ) async {
    final client = await _connectPop3(config);
    try {
      final count = await client.messageCount();
      if (count == 0) return const [];
      final uidl = await client.uidl();
      final numbers = uidl.isNotEmpty
          ? (uidl.keys.toList()..sort())
          : List<int>.generate(count, (index) => index + 1);
      final selected = numbers.length > maxMessages
          ? numbers.sublist(numbers.length - maxMessages)
          : numbers;

      final summaries = <MailMessageSummary>[];
      for (final number in selected) {
        final headerBytes = await client.topHeaders(number);
        final parsed = MailMimeParser.parseHeaders(headerBytes);
        if (!_looksLikeTicketMail(parsed.from, parsed.subject)) continue;
        final date = parsed.date;
        if (date != null && date.isBefore(cutoff)) continue;
        summaries.add(
          MailMessageSummary(
            uid: number,
            remoteId: uidl[number] ?? '$number',
            subject: parsed.subject,
            from: parsed.from,
            date: date,
            messageId: parsed.messageId,
          ),
        );
      }
      _sortByDateDesc(summaries);
      return summaries;
    } finally {
      await client.quit();
    }
  }

  Future<List<MailTicketBatch>> _fetchPop3Tickets(
    MailAccountConfig config,
    List<MailMessageSummary> messages,
  ) async {
    final client = await _connectPop3(config);
    try {
      final uidl = await client.uidl();
      final numbersByRemoteId = <String, int>{
        for (final entry in uidl.entries) entry.value: entry.key,
      };
      final batches = <MailTicketBatch>[];
      for (final message in messages) {
        final number =
            numbersByRemoteId[message.remoteId] ??
            int.tryParse(message.remoteId) ??
            message.uid;
        try {
          final raw = await client.retrieve(number);
          batches.add(_parseBatch(message, raw));
        } on MailImportException {
          // 邮件可能已在两次连接之间被删除，跳过即可。
        }
      }
      return batches;
    } finally {
      await client.quit();
    }
  }

  MailTicketBatch _parseBatch(MailMessageSummary message, Uint8List raw) {
    final content = MailMimeParser.parse(raw);
    final messageId = [
      content.messageId,
      message.messageId,
      'mail-${message.uid}',
    ].firstWhere((value) => value.trim().isNotEmpty);
    final subject = content.subject.trim().isEmpty
        ? message.subject
        : content.subject;
    return MailTicketBatch(
      uid: message.uid,
      orders: TicketEmailParser.parse(
        content.text,
        messageId: messageId,
        subject: subject,
        emailDate: content.date ?? message.date,
      ),
    );
  }

  MailMessageSummary _summaryFromHeader(ImapFetchedHeader header) {
    final parsed = MailMimeParser.parseHeaders(header.headerBytes);
    return MailMessageSummary(
      uid: header.uid,
      remoteId: '${header.uid}',
      subject: parsed.subject,
      from: parsed.from,
      date: parsed.date ?? header.internalDate,
      messageId: parsed.messageId,
    );
  }

  Future<ImapClient> _connectImap(MailAccountConfig config) async {
    _ensureConfigured(config);
    final client = await ImapClient.connect(
      host: config.host.trim(),
      port: config.port,
      useTls: config.useTls,
    );
    try {
      await client.login(config.emailAddress.trim(), config.password);
      return client;
    } on Object {
      client.close();
      rethrow;
    }
  }

  Future<Pop3Client> _connectPop3(MailAccountConfig config) async {
    _ensureConfigured(config);
    final client = await Pop3Client.connect(
      host: config.host.trim(),
      port: config.port,
      useTls: config.useTls,
    );
    try {
      await client.login(config.emailAddress.trim(), config.password);
      return client;
    } on Object {
      client.close();
      rethrow;
    }
  }

  void _ensureConfigured(MailAccountConfig config) {
    if (!config.isComplete) {
      throw MailImportException(config.missingSettingsMessage);
    }
  }

  /// POP3 只能看邮件头，所以除发件人外还要认「网上购票系统」这个主题；
  /// 手动转发到 QQ / 163 后，发件人会变成转发者，但主题通常保留。
  bool _looksLikeTicketMail(String from, String subject) {
    final value = '${from.toLowerCase()} ${subject.toLowerCase()}';
    return value.contains('12306') ||
        value.contains('rails.com.cn') ||
        value.contains('网上购票系统');
  }

  void _sortByDateDesc(List<MailMessageSummary> summaries) {
    summaries.sort((a, b) {
      final left = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });
  }
}
