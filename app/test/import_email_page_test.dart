import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/ticket_12306_order.dart';
import 'package:raillog/src/pages/import_email_page.dart';
import 'package:raillog/src/services/mail_account_settings.dart';
import 'package:raillog/src/services/mail_import_service.dart';
import 'package:raillog/src/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'mail_account.email': 'user@qq.com',
      'mail_account.password': 'secret',
      'mail_account.host': 'imap.qq.com',
      'mail_account.port': 993,
      'mail_account.protocol': 'imap',
      'mail_account.use_tls': true,
    });
  });

  Future<void> pumpNarrow(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        ),
        home: page,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('读取邮箱后直接展示车票卡片，不需要选择邮件', (tester) async {
    final service = _FakeMailImportService(
      messages: [
        MailMessageSummary(
          uid: 1,
          remoteId: '1',
          subject: '网上购票系统-用户支付通知',
          from: '12306@rails.com.cn',
          date: DateTime(2026, 5, 24, 23, 2),
          messageId: 'm1@example.com',
        ),
      ],
      batches: [
        MailTicketBatch(
          uid: 1,
          orders: [
            _order(
              id: 'normal',
              trainCode: 'C232',
              fromStation: '安康站',
              toStation: '西安站',
              startTime: DateTime(2026, 5, 25, 7, 36),
              statusText: '邮件导入',
            ),
            _order(
              id: 'refund',
              trainCode: 'G1',
              fromStation: '北京南',
              toStation: '上海虹桥',
              startTime: DateTime(2026, 5, 26, 8),
              statusText: '退票',
              coachName: '8',
              seatName: '1A',
            ),
          ],
        ),
      ],
    );

    await pumpNarrow(tester, ImportEmailPage(service: service));

    expect(find.text('选择待导入车票'), findsOneWidget);
    expect(find.text('已读取 1 封邮件，找到 2 张车票'), findsOneWidget);
    expect(find.text('C232'), findsOneWidget);
    expect(find.text('安康站 → 西安站'), findsOneWidget);
    expect(find.text('张三'), findsNWidgets(2));
    expect(find.text('二等座 5车3C'), findsOneWidget);
    expect(find.text('¥70'), findsNWidgets(2));
    expect(find.text('退票'), findsOneWidget);
    // 邮件本身不再作为可勾选的行出现。
    expect(find.text('网上购票系统-用户支付通知'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);

    await tester.tap(find.text('C232'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 / 1'), findsOneWidget);
    expect(find.text('开始确认'), findsOneWidget);
    expect(find.text('共 1 条待确认'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有 12306 邮件时显示空状态', (tester) async {
    final service = _FakeMailImportService(
      messages: const [],
      batches: const [],
    );

    await pumpNarrow(tester, ImportEmailPage(service: service));

    expect(find.text('近两年没有找到 12306 购票通知邮件'), findsOneWidget);
    expect(find.text('暂无可导入车票'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Ticket12306Order _order({
  required String id,
  required String trainCode,
  required String fromStation,
  required String toStation,
  required DateTime startTime,
  required String statusText,
  String coachName = '5',
  String seatName = '3C',
}) => Ticket12306Order(
  id: id,
  sequenceNo: 'EN12345678',
  startTime: startTime,
  arriveTime: null,
  trainCode: trainCode,
  fromStation: fromStation,
  toStation: toStation,
  distance: 0,
  passengerName: '张三',
  seatType: '二等座',
  coachName: coachName,
  seatName: seatName,
  price: 70,
  statusText: statusText,
);

class _FakeMailImportService extends MailImportService {
  const _FakeMailImportService({required this.messages, required this.batches});

  final List<MailMessageSummary> messages;
  final List<MailTicketBatch> batches;

  @override
  Future<List<MailMessageSummary>> listMessages(
    MailAccountConfig config, {
    DateTime? since,
    int maxMessages = 300,
  }) async => messages;

  @override
  Future<List<MailTicketBatch>> fetchTickets(
    MailAccountConfig config,
    List<MailMessageSummary> messages,
  ) async => batches;
}
