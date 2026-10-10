import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/user_profile.dart';
import 'package:raillog/src/pages/settings/account_security_page.dart';
import 'package:raillog/src/pages/settings/community_page.dart';
import 'package:raillog/src/pages/settings/data_sync_settings_page.dart';
import 'package:raillog/src/pages/settings/display_settings_page.dart';
import 'package:raillog/src/pages/settings/my_reviews_page.dart';
import 'package:raillog/src/pages/settings/profile_edit_page.dart';
import 'package:raillog/src/pages/settings/settings_page.dart';
import 'package:raillog/src/pages/settings/ticket_generator_settings_page.dart';
import 'package:raillog/src/pages/settings/ticket_ocr_settings_page.dart';
import 'package:raillog/src/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _user = UserProfile(
  id: 'u_0123456789abcdefghijkl',
  email: 'someone@example.com',
  displayName: '铁道迷',
  showEmailOnProfile: true,
);

/// 窄屏（360 逻辑像素）下渲染，用来抓 RenderFlex 溢出与未布局的报错。
Future<void> _pumpSettled(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(
        ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
      ),
      home: page,
    ),
  );
  // 不用 pumpAndSettle：OCR 页有常驻的加载指示器，永远settle 不下来。
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpNarrow(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpSettled(tester, page);
  }

  testWidgets('设置根页面渲染无异常', (tester) async {
    await pumpNarrow(tester, const Scaffold(body: SettingsPage()));
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('外观与显示'), findsOneWidget);
    expect(find.text('我的评价'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('我的评价页在未登录时渲染登录提示', (tester) async {
    await pumpNarrow(tester, const MyReviewsPage());
    expect(find.text('我的评价'), findsOneWidget);
    expect(find.text('登录后可以查看自己发表过的评价。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('外观与显示页渲染无异常', (tester) async {
    await pumpNarrow(tester, const DisplaySettingsPage());
    expect(find.text('跟随系统主题色'), findsOneWidget);
    expect(find.text('底图显示层级'), findsOneWidget);
    expect(find.text('默认展开线路站点'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('火车票生成器页渲染无异常', (tester) async {
    await pumpNarrow(tester, const TicketGeneratorSettingsPage());
    expect(find.text('默认票面信息'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('车票识别页渲染无异常', (tester) async {
    await pumpNarrow(tester, const TicketOcrSettingsPage());
    expect(find.text('百度车票识别'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('数据与同步页在未登录时渲染无异常', (tester) async {
    await pumpNarrow(tester, const DataSyncSettingsPage());
    expect(find.text('本地模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('账户与安全页在未登录时渲染无异常', (tester) async {
    await pumpNarrow(tester, const AccountSecurityPage());
    expect(find.text('登录或注册'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('社群与支持页渲染无异常', (tester) async {
    await pumpNarrow(tester, const CommunityPage());
    expect(find.text('QQ 交流群'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('个人资料页渲染无异常', (tester) async {
    await pumpNarrow(tester, const ProfileEditPage(user: _user));
    expect(find.text('昵称'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('车票识别的密钥停顿后才落盘，失焦立刻落盘', (tester) async {
    await pumpNarrow(tester, const TicketOcrSettingsPage());
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('baidu_ocr_api_key'), isNull);

    await tester.enterText(find.byType(TextFormField).first, 'my-api-key');
    await tester.pump(const Duration(milliseconds: 100));
    // 还在防抖窗口里，没有逐字写盘。
    expect(preferences.getString('baidu_ocr_api_key'), isNull);

    await tester.pump(const Duration(milliseconds: 600));
    expect(preferences.getString('baidu_ocr_api_key'), 'my-api-key');

    // 失焦不等防抖，立即落盘。
    await tester.enterText(find.byType(TextFormField).first, 'renamed');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.tap(find.byType(TextFormField).last);
    await tester.pump();
    expect(preferences.getString('baidu_ocr_api_key'), 'renamed');
  }, timeout: const Timeout(Duration(seconds: 30)));
}
