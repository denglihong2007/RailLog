import 'dart:async';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:material_ui/material_ui.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/journal_settings.dart';
import 'package:raillog/src/services/map_settings.dart';
import 'package:raillog/src/pages/home_page.dart';
import 'package:raillog/src/pages/main_navigation_page.dart';
import 'package:raillog/src/services/cloud_sync_service.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/services/train_service.dart';
import 'package:raillog/src/services/theme_settings.dart';
import 'package:raillog/src/services/ticket_generator_settings.dart';
import 'package:raillog/src/services/trip_list_settings.dart';
import 'package:raillog/src/services/user_level_settings.dart';
import 'package:raillog/src/theme/app_theme.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await ThemeSettings.instance.initialize();
  } catch (error) {
    debugPrint('主题偏好读取失败，将使用默认设置：$error');
  }

  try {
    await MapSettings.instance.initialize();
  } catch (error) {
    debugPrint('地图偏好读取失败，将使用默认设置：$error');
  }

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  try {
    await DbHelper.instance.database;
    await TicketGeneratorSettings.instance.initialize();
    await TripListSettings.instance.initialize();
    await JournalSettings.instance.initialize();
    await UserLevelSettings.instance.initialize();
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
            localizationsDelegates:
                GlobalMaterialLocalizations.delegates,
            // flutter_markdown_plus 等仍基于 package:flutter/material 的依赖
            // 需要 legacy ThemeData / MaterialLocalizations。
            builder: (context, child) =>
                // ignore: deprecated_member_use
                MaterialUiCompatibilityBridge(child: child!),
            themeMode: settings.themeMode,
            theme: _theme(lightScheme),
            darkTheme: _theme(darkScheme),
            themeAnimationDuration: m3MotionDuration,
            themeAnimationCurve: Easing.standard,
            onGenerateRoute: _onGenerateRoute,
            home: const MainNavigationPage(),
          );
        },
      ),
    );
  }

  ThemeData _theme(ColorScheme colorScheme) => AppTheme.build(colorScheme);

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    const userRoutePrefix = '/users/';
    final routeName = settings.name;
    if (routeName == null || !routeName.startsWith(userRoutePrefix)) {
      return null;
    }
    final userId = Uri.decodeComponent(
      routeName.substring(userRoutePrefix.length),
    );
    if (userId.isEmpty) return null;
    return m3PageRoute(
      settings: settings,
      builder: (_) => PublicUserPage(userId: userId),
    );
  }
}
