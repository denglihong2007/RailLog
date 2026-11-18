import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/services/ticket_12306_auth_settings.dart';
import 'package:raillog/src/services/ticket_12306_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('保存并恢复登录凭证与核验状态', () async {
    await Ticket12306AuthSettings.save(
      Ticket12306Credentials(
        username: '张三',
        loginAt: DateTime(2026, 11, 18, 10, 30),
        invoiceVerified: true,
        cookies: [
          Ticket12306Cookie(
            name: 'tk',
            value: 'abc',
            domain: 'kyfw.12306.cn',
            path: '/',
            expires: DateTime.now().add(const Duration(days: 1)),
          ),
        ],
      ),
    );

    final loaded = await Ticket12306AuthSettings.load();

    expect(loaded, isNotNull);
    expect(loaded!.username, '张三');
    expect(loaded.cookies.single.name, 'tk');
    expect(loaded.cookies.single.value, 'abc');
    expect(loaded.cookies.single.domain, 'kyfw.12306.cn');
    expect(loaded.invoiceVerified, isTrue);
    expect(loaded.isComplete, isTrue);

    await Ticket12306AuthSettings.clear();
    expect(await Ticket12306AuthSettings.load(), isNull);
  });

  test('损坏的数据按未配置处理', () async {
    SharedPreferences.setMockInitialValues({
      'ticket_12306.credentials': '{oops',
    });

    expect(await Ticket12306AuthSettings.load(), isNull);
  });

  test('只剩过期 Cookie 时视为未配置', () {
    final credentials = Ticket12306Credentials(
      username: '张三',
      loginAt: DateTime(2026, 11, 18),
      cookies: [
        Ticket12306Cookie(
          name: 'tk',
          value: 'abc',
          expires: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ],
    );

    expect(credentials.isComplete, isFalse);
  });

  test('保存并恢复账号密码', () async {
    await Ticket12306AuthSettings.saveAccount(
      username: '13800000000',
      password: 'secret',
      savePassword: true,
    );

    final account = await Ticket12306AuthSettings.loadAccount();

    expect(account, isNotNull);
    expect(account!.username, '13800000000');
    expect(account.password, 'secret');
    expect(account.savePassword, isTrue);

    await Ticket12306AuthSettings.clearAccount();
    expect(await Ticket12306AuthSettings.loadAccount(), isNull);
  });

  test('关闭保存密码时只保留账号', () async {
    await Ticket12306AuthSettings.saveAccount(
      username: '13800000000',
      password: 'secret',
      savePassword: false,
    );

    final account = await Ticket12306AuthSettings.loadAccount();

    expect(account!.username, '13800000000');
    expect(account.password, isEmpty);
    expect(account.savePassword, isFalse);
  });
}
