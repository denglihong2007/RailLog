import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/user_profile.dart';
import 'package:raillog/src/models/via_route_segment.dart';
import 'package:raillog/src/pages/settings/account_security_page.dart';
import 'package:raillog/src/pages/settings/community_page.dart';
import 'package:raillog/src/pages/settings/data_sync_settings_page.dart';
import 'package:raillog/src/pages/settings/display_settings_page.dart';
import 'package:raillog/src/pages/settings/email_connection_settings_page.dart';
import 'package:raillog/src/pages/settings/journal_settings_page.dart';
import 'package:raillog/src/pages/settings/my_reviews_page.dart';
import 'package:raillog/src/pages/settings/profile_edit_page.dart';
import 'package:raillog/src/pages/settings/settings_page.dart';
import 'package:raillog/src/pages/settings/ticket_generator_settings_page.dart';
import 'package:raillog/src/pages/settings/ticket_ocr_settings_page.dart';
import 'package:raillog/src/pages/settings/timetable_rebuild_page.dart';
import 'package:raillog/src/pages/settings/timetable_rebuild_review_page.dart';
import 'package:raillog/src/services/timetable_rebuild_service.dart';
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
    expect(find.text('行程手账'), findsOneWidget);
    expect(find.text('我的评价'), findsOneWidget);
    expect(find.text('历史时刻表重建'), findsOneWidget);
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

  testWidgets('邮箱导入设置页展示各邮箱的限制与转发提示', (tester) async {
    await pumpNarrow(tester, const EmailConnectionSettingsPage());
    expect(find.text('邮箱连接'), findsOneWidget);
    expect(find.text('各邮箱的限制'), findsOneWidget);
    expect(
      find.textContaining('Outlook / Hotmail / Live / Microsoft 365'),
      findsOneWidget,
    );
    expect(find.textContaining('点「转发」发到 QQ、163 等邮箱后再导入'), findsOneWidget);
    expect(find.textContaining('自动转发'), findsNothing);
    expect(find.textContaining('规则'), findsNothing);
    expect(find.textContaining('Google 已停用账号密码登录'), findsOneWidget);
    expect(find.textContaining('iCloud 不支持 POP3'), findsOneWidget);
    expect(find.textContaining('Proton Mail'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('输入受限邮箱地址时直接给出对应提示', (tester) async {
    await pumpNarrow(tester, const EmailConnectionSettingsPage());
    final emailField = find.byType(TextFormField).first;

    await tester.enterText(emailField, 'someone@outlook.com');
    await tester.pump();
    expect(find.textContaining('Outlook 邮箱无法直接连接'), findsOneWidget);

    await tester.enterText(emailField, 'someone@gmail.com');
    await tester.pump();
    expect(find.textContaining('Outlook 邮箱无法直接连接'), findsNothing);
    expect(find.textContaining('Gmail 不能使用登录密码'), findsOneWidget);
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

  // 只注入空车票：真实加载器会走 sqflite，在 widget 测试里是静默挂死。
  testWidgets('历史时刻表重建页渲染无异常', (tester) async {
    await pumpNarrow(
      tester,
      TimetableRebuildPage(tripsLoader: () async => const <TripRecord>[]),
    );
    expect(find.text('历史时刻表重建'), findsOneWidget);
    expect(find.text('全部 0'), findsOneWidget);
    expect(find.text('缺到点 0'), findsOneWidget);
    expect(find.text('经由损坏'), findsOneWidget);
    expect(find.text('没有符合当前筛选条件的行程'), findsOneWidget);
    // 筛选条应该贴着内容左边，而不是缩成一小块悬在页面中间。
    expect(tester.getTopLeft(find.text('全部 0')).dx, lessThan(100));
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  // 车票全是注入的；只要不点重建按钮就不会碰历史时刻表接口。
  testWidgets('历史时刻表重建页复用全部行程的多选与筛选', (tester) async {
    final trips = [
      TripRecord(
        id: 1,
        trainNumber: 'G1',
        fromStation: '北京南',
        toStation: '上海虹桥',
        departureTime: DateTime(2024, 5, 1, 8),
        viaRouteSegments: const [],
      ),
      TripRecord(
        id: 2,
        trainNumber: 'D3',
        fromStation: '南京南',
        toStation: '杭州东',
        departureTime: DateTime(2024, 5, 2, 9),
        arrivalTime: DateTime(2024, 5, 2, 11),
        viaRouteSegments: const [],
      ),
    ];
    await pumpNarrow(
      tester,
      TimetableRebuildPage(tripsLoader: () async => trips),
    );
    expect(find.text('缺到点 1'), findsOneWidget);
    expect(find.text('G1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pump();
    await tester.tap(find.text('G1'));
    await tester.pump();
    expect(find.text('重建到点'), findsOneWidget);
    expect(find.text('重建经由'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  // 经由必须整段摆出来：截断的话用户没法确认后半段改成了什么。
  testWidgets('确认页完整列出新旧经由的每一段', (tester) async {
    final oldSegments = [
      const ViaRouteSegment(routeName: '旧线', fromStation: '甲', toStation: '乙'),
    ];
    final newSegments = [
      for (var index = 0; index < 9; index++)
        ViaRouteSegment(
          routeName: '测试线$index',
          fromStation: '站$index',
          toStation: '站${index + 1}',
        ),
    ];
    final trip = TripRecord(
      id: 1,
      trainNumber: 'G1',
      fromStation: '甲',
      toStation: '站9',
      departureTime: DateTime(2024, 5, 1, 8),
      viaRouteSegments: oldSegments,
    );
    await pumpNarrow(
      tester,
      TimetableRebuildReviewPage(
        plan: TimetableRebuildPlan(
          mode: TimetableRebuildMode.viaRoute,
          proposals: [
            TimetableRebuildProposal.viaRoute(
              trip: trip,
              viaRouteSegments: newSegments,
            ),
          ],
          issues: const [],
          unchanged: 0,
          cancelled: false,
        ),
      ),
    );
    expect(find.text('原经由'), findsOneWidget);
    expect(find.text('新经由'), findsOneWidget);
    expect(find.text('9 段'), findsOneWidget);
    expect(find.textContaining('旧线'), findsOneWidget);
    for (var index = 0; index < 9; index++) {
      expect(find.textContaining('测试线$index'), findsOneWidget);
    }
    expect(find.textContaining('还有'), findsNothing);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('社群与支持页渲染无异常', (tester) async {
    await pumpNarrow(tester, const CommunityPage());
    expect(find.text('QQ 交流群'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  // 只渲染不点击：点「导出空白模板」会走 DbHelper→sqflite，在 widget 测试里
  // 是静默挂死，不是失败。
  testWidgets('行程手账页渲染无异常', (tester) async {
    await pumpNarrow(tester, const JournalSettingsPage());
    expect(find.text('手账版式'), findsOneWidget);
    expect(find.text('复古车票簿'), findsNWidgets(2)); // 分段按钮 + 预览标签
    expect(find.text('简约方格本'), findsNWidgets(2));
    expect(find.text('导出空白手账模板'), findsOneWidget);
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

  testWidgets('车票识别可切换到阿里云并保存密钥', (tester) async {
    await pumpNarrow(tester, const TicketOcrSettingsPage());
    expect(find.text('识别服务商'), findsOneWidget);
    expect(find.text('阿里云车票识别'), findsNothing);

    await tester.tap(find.text('阿里云'));
    await tester.pump();
    expect(find.text('阿里云车票识别'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('ticket_ocr_provider'), 'aliyun');

    await tester.enterText(find.byType(TextFormField).first, 'aliyun-id');
    await tester.pump(const Duration(milliseconds: 600));
    expect(preferences.getString('aliyun_ocr_access_key_id'), 'aliyun-id');

    // 重新进入页面时仍停留在阿里云。
    await pumpNarrow(tester, const TicketOcrSettingsPage());
    expect(find.text('阿里云车票识别'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
