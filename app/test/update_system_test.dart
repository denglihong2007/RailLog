import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/app_update_info.dart';
import 'package:raillog/src/services/update_service.dart';
import 'package:raillog/src/widgets/update_prompt.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('解析服务器下发的完整更新信息', () {
    final update = AppUpdateInfo.fromJson(_updateJson());

    expect(update.releaseUrl, 'https://github.com/example/release');
    expect(update.androidDownloadUrl, 'https://github.com/example/app.apk');
    expect(update.androidDomesticDownloadUrl, 'https://pan.example/app');
    expect(update.releaseNotes, '新增行程更新系统');
    expect(update.publishedAt, DateTime.utc(2026, 7, 17, 4, 30));
  });

  test('当前平台使用服务器下发的对应下载链接', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final update = AppUpdateInfo.fromJson(_updateJson());

    expect(
      UpdateService.githubUrlForCurrentPlatform(update),
      'https://github.com/example/app.apk',
    );
    expect(
      UpdateService.domesticUrlForCurrentPlatform(update),
      'https://pan.example/app',
    );
  });

  test('当前平台网盘链接缺失时回退到服务器下发的可用链接', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final json = _updateJson()
      ..['windowsDomesticDownloadUrl'] = ' '
      ..['androidDomesticDownloadUrl'] = 'https://pan.example/shared';
    final update = AppUpdateInfo.fromJson(json);

    expect(
      UpdateService.domesticUrlForCurrentPlatform(update),
      'https://pan.example/shared',
    );
  });

  testWidgets('发现更新弹窗展示日志、时间和两类下载入口', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final json = _updateJson()..['releaseNotes'] = '## 更新内容\n\n- 新增行程更新系统';
    final result = UpdateCheckResult(
      currentVersion: '1.0.0',
      latest: AppUpdateInfo.fromJson(json),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showUpdatePrompt(context, result),
            child: const Text('检查'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('检查'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('更新内容'), findsOneWidget);
    expect(find.text('新增行程更新系统'), findsOneWidget);
    expect(find.textContaining('发布于'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('国内网盘'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}

Map<String, dynamic> _updateJson() => {
  'version': '1.1.0',
  'tagName': 'v1.1.0',
  'name': 'RailLog 1.1.0',
  'publishedAt': '2026-07-17T04:30:00Z',
  'releaseNotes': '新增行程更新系统',
  'releaseUrl': 'https://github.com/example/release',
  'windowsDownloadUrl': 'https://github.com/example/app.exe',
  'androidDownloadUrl': 'https://github.com/example/app.apk',
  'domesticDownloadName': '国内网盘',
  'windowsDomesticDownloadUrl': 'https://pan.example/windows',
  'androidDomesticDownloadUrl': 'https://pan.example/app',
  'downloadPageUrl': 'https://example.com/download',
};
