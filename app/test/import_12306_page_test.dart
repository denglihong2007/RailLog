import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/ticket_12306_order.dart';
import 'package:raillog/src/pages/import_12306_page.dart';
import 'package:raillog/src/services/ticket_12306_auth_settings.dart';
import 'package:raillog/src/services/ticket_12306_service.dart';
import 'package:raillog/src/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
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

  testWidgets('未配置凭证时提示去设置', (tester) async {
    await pumpPage(tester, const Import12306Page());

    expect(find.text('尚未配置 12306 登录凭证'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
    expect(find.text('选择待导入车票'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已保存凭证时直接查询订单，不再显示扫码登录', (tester) async {
    await _saveCredentials();
    final service = _FakeTicket12306Service(orders: [_order('G1')]);

    await pumpPage(tester, Import12306Page(service: service));

    expect(find.text('共查询到 1 张车票'), findsOneWidget);
    expect(find.text('G1'), findsOneWidget);
    expect(find.text('选择待导入车票'), findsOneWidget);
    expect(find.textContaining('人证核验未核验'), findsOneWidget);
    expect(find.text('查看更多行程'), findsOneWidget);
    expect(find.text('使用 12306 App 扫码登录'), findsNothing);
    expect(service.restored, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('人证核验后合并本人车票与电子发票', (tester) async {
    await _saveCredentials(invoiceVerified: true);
    final service = _FakeTicket12306Service(
      orders: [_order('G1')],
      personalOrders: [_order('D7')],
      invoiceOrders: [_order('D2')],
    );

    await pumpPage(tester, Import12306Page(service: service));

    expect(service.personalQueried, isTrue);
    expect(service.invoiceQueried, isTrue);
    expect(find.text('D7'), findsOneWidget);
    expect(find.text('D2'), findsOneWidget);
    expect(find.text('共查询到 3 张车票'), findsOneWidget);
    expect(find.textContaining('已加载扩展行程'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('凭证查询失效时引导回设置页', (tester) async {
    await _saveCredentials();
    final service = _FakeTicket12306Service(orders: const [], authError: true);

    await pumpPage(tester, Import12306Page(service: service));

    expect(find.text('登录凭证已失效'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
    expect(find.text('选择待导入车票'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('服务端判定登录凭证过期时直接提示去设置', (tester) async {
    await _saveCredentials();
    final service = _FakeTicket12306Service(
      orders: [_order('G1')],
      loginExpired: true,
    );

    await pumpPage(tester, Import12306Page(service: service));

    expect(find.text('登录凭证已失效'), findsOneWidget);
    expect(service.orderQueried, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('服务端判定人证核验过期时只加载近期订单', (tester) async {
    await _saveCredentials(invoiceVerified: true);
    final service = _FakeTicket12306Service(
      orders: [_order('G1')],
      invoiceOrders: [_order('D2')],
      invoiceExpiredOnServer: true,
    );

    await pumpPage(tester, Import12306Page(service: service));

    expect(service.personalQueried, isFalse);
    expect(service.invoiceQueried, isFalse);
    expect(find.text('G1'), findsOneWidget);
    expect(find.text('D2'), findsNothing);
    expect(find.text('人证核验凭证已过期，本次只加载近 1 个月订单，请前往设置重新核验'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _saveCredentials({bool invoiceVerified = false}) {
  return Ticket12306AuthSettings.save(
    Ticket12306Credentials(
      username: '张三',
      loginAt: DateTime(2026, 11, 18, 10, 30),
      invoiceVerified: invoiceVerified,
      cookies: [
        Ticket12306Cookie(
          name: 'tk',
          value: 'abc',
          expires: DateTime.now().add(const Duration(days: 1)),
        ),
      ],
    ),
  );
}

Ticket12306Order _order(String trainCode) => Ticket12306Order(
  id: trainCode,
  sequenceNo: 'E123456789',
  startTime: DateTime(2026, 9, 1, 8),
  arriveTime: DateTime(2026, 9, 1, 12, 30),
  trainCode: trainCode,
  fromStation: '北京南',
  toStation: '上海虹桥',
  distance: 1318,
  passengerName: '李四',
  seatType: '二等座',
  coachName: '05',
  seatName: '12A',
  price: 553,
  statusText: '已支付',
);

class _FakeTicket12306Service extends Ticket12306Service {
  _FakeTicket12306Service({
    required this.orders,
    this.invoiceOrders = const [],
    this.authError = false,
    this.loginExpired = false,
    this.invoiceExpiredOnServer = false,
    this.personalOrders = const [],
  });

  final List<Ticket12306Order> orders;
  final List<Ticket12306Order> invoiceOrders;
  final List<Ticket12306Order> personalOrders;
  final bool authError;
  final bool loginExpired;
  final bool invoiceExpiredOnServer;
  Ticket12306Credentials? restored;
  bool invoiceQueried = false;
  bool personalQueried = false;
  bool orderQueried = false;

  @override
  bool restoreCredentials(Ticket12306Credentials credentials) {
    restored = credentials;
    return true;
  }

  @override
  Future<Ticket12306CredentialState> checkCredentials() async =>
      Ticket12306CredentialState(
        loginValid: !loginExpired,
        invoiceVerified:
            !invoiceExpiredOnServer && (restored?.invoiceVerified ?? false),
        username: '张三',
      );

  @override
  Ticket12306Credentials exportCredentials({
    required bool invoiceVerified,
    DateTime? loginAt,
  }) => Ticket12306Credentials(
    username: '张三',
    loginAt: loginAt ?? DateTime(2026, 11, 18, 10, 30),
    invoiceVerified: invoiceVerified,
    cookies: [
      Ticket12306Cookie(
        name: 'tk',
        value: 'abc',
        expires: DateTime.now().add(const Duration(days: 1)),
      ),
    ],
  );

  @override
  Future<List<Ticket12306Order>> queryOrderTrips({DateTime? now}) async {
    orderQueried = true;
    if (authError) {
      throw const Ticket12306AuthException('登录凭证已失效');
    }
    return orders;
  }

  @override
  Future<List<Ticket12306Order>> queryPersonalTrips({DateTime? now}) async {
    personalQueried = true;
    return personalOrders;
  }

  @override
  Future<List<Ticket12306Order>> queryInvoiceTrips({DateTime? now}) async {
    invoiceQueried = true;
    return invoiceOrders;
  }
}
