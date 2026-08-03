import 'dart:async';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/pages/main_navigation_page.dart';
import 'package:raillog/src/services/cloud_sync_service.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/services/train_service.dart';
import 'package:raillog/src/services/theme_settings.dart';
import 'package:raillog/src/services/ticket_generator_settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await ThemeSettings.instance.initialize();
  } catch (error) {
    debugPrint('主题偏好读取失败，将使用默认设置：$error');
  }

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  try {
    await DbHelper.instance.database;
    await TicketGeneratorSettings.instance.initialize();
    await TrainService.initializeStationCodes();
    await SessionService.instance.initialize();
    await CloudSyncService.instance.initialize();
    DbHelper.instance.onTripsChanged = CloudSyncService.instance.syncIfSignedIn;
    DbHelper.instance.activeUserId = () => SessionService.instance.user?.id;
    SessionService.instance.onAuthenticated =
        CloudSyncService.instance.syncIfSignedIn;
    unawaited(CloudSyncService.instance.syncIfSignedIn());
    debugPrint('RailLog 数据库初始化成功！');
  } catch (e) {
    debugPrint('RailLog 数据库初始化失败: $e');
  }

  runApp(const RailLogApp());
}

class RailLogApp extends StatelessWidget {
  const RailLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => AnimatedBuilder(
        animation: ThemeSettings.instance,
        builder: (context, _) {
          final settings = ThemeSettings.instance;
          final useDynamic = settings.useSystemColor;
          final lightScheme = useDynamic && lightDynamic != null
              ? lightDynamic
              : ColorScheme.fromSeed(
                  seedColor: settings.seedColor,
                  brightness: Brightness.light,
                );
          final darkScheme = useDynamic && darkDynamic != null
              ? darkDynamic
              : ColorScheme.fromSeed(
                  seedColor: settings.seedColor,
                  brightness: Brightness.dark,
                );
          return MaterialApp(
            title: '轨记',
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            themeMode: settings.themeMode,
            theme: _theme(lightScheme),
            darkTheme: _theme(darkScheme),
            home: const MainNavigationPage(),
          );
        },
      ),
    );
  }

  ThemeData _theme(ColorScheme colorScheme) => ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: 'Noto Sans SC',
  );
}
