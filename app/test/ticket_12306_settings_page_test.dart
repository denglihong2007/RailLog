import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/pages/settings/ticket_12306_settings_page.dart';
import 'package:raillog/src/services/ticket_12306_auth_settings.dart';
import 'package:raillog/src/services/ticket_12306_service.dart';
import 'package:raillog/src/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpPage(WidgetTester tester, {Widget? page}) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        ),
        home: page ?? const Ticket12306SettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('未配置时摆出账号密码、扫码与核验入口', (tester) async {
    await pumpPage(tester);

    expect(find.text('登录方式'), findsOneWidget);
    expect(find.text('账号密码'), findsOneWidget);
    expect(find.text('扫码登录'), findsOneWidget);
    expect(find.text('记住密码'), findsOneWidget);
    expect(find.text('人证核验（可选）'), findsOneWidget);
    expect(find.text('使用 12306 App 扫码登录'), findsNothing);
    expect(find.text('先完成登录凭证配置，再进行人证核验。'), findsOneWidget);

    await tester.tap(find.text('扫码登录'));
    await tester.pumpAndSettle();
    expect(find.text('使用 12306 App 扫码登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已保存凭证且服务端确认有效时显示账号与核验状态', (tester) async {
    await _saveCredentials();
    final service = _FakeTicket12306Service(
      credentialState: const Ticket12306CredentialState(
        loginValid: true,
        invoiceVerified: true,
        username: '张三',
      ),
    );

    await pumpPage(tester, page: Ticket12306SettingsPage(service: service));

    expect(find.text('已登录：张三'), findsOneWidget);
    expect(find.textContaining('人证核验已完成'), findsOneWidget);
    expect(find.text('人证核验已通过'), findsOneWidget);

    await tester.tap(find.text('扫码登录'));
    await tester.pumpAndSettle();
    expect(find.text('当前已登录'), findsOneWidget);
    expect(find.text('扫码重新登录'), findsOneWidget);
    expect(find.text('使用 12306 App 扫码登录'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('扫码请求出现时保留紫色小窗提示', (tester) async {
    final service = _QrFakeTicket12306Service();

    await pumpPage(tester, page: Ticket12306SettingsPage(service: service));

    await tester.tap(find.text('扫码登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('获取二维码'));
    await tester.pumpAndSettle();

    expect(find.text('建议开启小窗模式'), findsOneWidget);
    expect(find.text('避免切回应用时网络请求中断'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('账号密码登录成功后保存账号密码并显示已登录', (tester) async {
    final service = _FakeTicket12306Service();

    await pumpPage(tester, page: Ticket12306SettingsPage(service: service));

    await tester.enterText(find.byType(TextFormField).at(0), '13800000000');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.text('已登录：张三'), findsOneWidget);
    expect(find.text('登录成功：张三'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('ticket_12306.account.username'),
      '13800000000',
    );
    expect(preferences.getString('ticket_12306.account.password'), 'secret');
    expect(tester.takeException(), isNull);
  });

  testWidgets('密码错误时显示服务端提示', (tester) async {
    final service = _FakeTicket12306Service(
      loginError: const Ticket12306AuthException('密码输入错误'),
    );

    await pumpPage(tester, page: Ticket12306SettingsPage(service: service));

    await tester.enterText(find.byType(TextFormField).at(0), '13800000000');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.text('登录失败：密码输入错误'), findsOneWidget);
    expect(find.text('已登录：张三'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('需要短信验证时先填证件后四位，再填验证码登录', (tester) async {
    final service = _FakeTicket12306Service(loginCheckCode: '3');

    await pumpPage(tester, page: Ticket12306SettingsPage(service: service));

    await tester.enterText(find.byType(TextFormField).at(0), '13800000000');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.text('证件号后 4 位'), findsOneWidget);
    expect(find.text('短信验证码'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(2), '1234');
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '获取验证码'));
    await tester.pumpAndSettle();

    expect(service.smsRequested, isTrue);
    expect(find.text('验证码已发送，请输入 6 位短信验证码'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(3), '123456');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(service.lastSmsCode, '123456');
    expect(find.text('已登录：张三'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('服务端判定登录凭证失效时清除本地凭证', (tester) async {
    await _saveCredentials();
    final service = _FakeTicket12306Service(
      credentialState: const Ticket12306CredentialState(
        loginValid: false,
        invoiceVerified: false,
      ),
    );

    await pumpPage(tester, page: Ticket12306SettingsPage(service: service));

    expect(find.text('登录凭证已过期，请重新登录'), findsWidgets);
    expect(find.text('已登录：张三'), findsNothing);
    expect(await Ticket12306AuthSettings.load(), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('服务端判定人证核验凭证失效时提示重新核验', (tester) async {
    await _saveCredentials(invoiceVerified: true);
    final service = _FakeTicket12306Service(
      credentialState: const Ticket12306CredentialState(
        loginValid: true,
        invoiceVerified: false,
        username: '张三',
      ),
    );

    await pumpPage(tester, page: Ticket12306SettingsPage(service: service));

    expect(find.text('人证核验凭证已过期，请重新核验'), findsOneWidget);
    expect(find.textContaining('人证核验未完成'), findsOneWidget);
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

class _QrFakeTicket12306Service extends _FakeTicket12306Service {
  @override
  Future<Ticket12306QrCode> createQrCode() async =>
      const Ticket12306QrCode(
        uuid: 'qr',
        imageBase64:
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
            '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );

  @override
  Future<Ticket12306QrStatus> checkQrStatus(String uuid) async =>
      const Ticket12306QrStatus(code: '3', message: '二维码已过期，请重新获取');
}

class _FakeTicket12306Service extends Ticket12306Service {
  _FakeTicket12306Service({
    this.loginCheckCode = '0',
    this.credentialState = const Ticket12306CredentialState(
      loginValid: true,
      invoiceVerified: false,
      username: '张三',
    ),
    this.loginError,
  });

  final String loginCheckCode;
  final Ticket12306CredentialState credentialState;
  final Object? loginError;

  bool smsRequested = false;
  String? lastSmsCode;

  @override
  bool restoreCredentials(Ticket12306Credentials credentials) => true;

  @override
  Future<Ticket12306CredentialState> checkCredentials() async =>
      credentialState;

  @override
  Future<String> checkLoginVerify(String username) async => loginCheckCode;

  @override
  Future<void> requestSmsCode({
    required String username,
    required String idSuffix,
  }) async {
    smsRequested = true;
  }

  @override
  Future<String> loginWithPassword(
    String username,
    String password, {
    String smsCode = '',
  }) async {
    lastSmsCode = smsCode;
    final error = loginError;
    if (error != null) throw error;
    return 'uamtk';
  }

  @override
  Future<String> completeLogin(String uamtk) async => '张三';

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
}
