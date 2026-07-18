import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/pages/settings_page.dart';
import 'package:raillog/src/services/theme_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ThemeSettings.instance.initialize();
    ThemeSettings.instance.setPreference(AppThemePreference.system);
    ThemeSettings.instance.setUseSystemColor(true);
    ThemeSettings.instance.setSeedColor(themeSeedOptions.first.color);
  });

  test('主题偏好可从本地加载并持久化', () async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'dark',
      'theme_use_system_color': false,
      'theme_seed_color': const Color(0xFFC62828).toARGB32(),
    });
    await ThemeSettings.instance.initialize();

    expect(ThemeSettings.instance.preference, AppThemePreference.dark);
    expect(ThemeSettings.instance.themeMode, ThemeMode.dark);
    expect(ThemeSettings.instance.useSystemColor, isFalse);
    expect(ThemeSettings.instance.seedColor, const Color(0xFFC62828));

    ThemeSettings.instance.setPreference(AppThemePreference.light);
    ThemeSettings.instance.setUseSystemColor(true);
    await Future<void>.delayed(Duration.zero);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('theme_mode'), 'light');
    expect(preferences.getBool('theme_use_system_color'), isTrue);
  });

  test('首次启动默认关闭跟随系统主题色', () async {
    SharedPreferences.setMockInitialValues({});
    await ThemeSettings.instance.initialize();

    expect(ThemeSettings.instance.useSystemColor, isFalse);
  });

  testWidgets('设置页在窄屏可切换深色模式和手动主题色', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SettingsPage())),
    );

    expect(find.text('外观'), findsOneWidget);
    expect(find.text('火车票生成器'), findsOneWidget);
    expect(find.text('川建国'), findsOneWidget);
    await tester.tap(find.text('深色'));
    await tester.pump();
    expect(ThemeSettings.instance.preference, AppThemePreference.dark);

    await tester.tap(find.text('跟随系统主题色'));
    await tester.pump();
    expect(ThemeSettings.instance.useSystemColor, isFalse);
    expect(find.text('主题色'), findsOneWidget);
  });
}
