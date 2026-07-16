import 'dart:async';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/material.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/pages/main_navigation_page.dart';
import 'package:raillog/src/services/cloud_sync_service.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/services/train_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  try {
    await DbHelper.instance.database;
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
    return MaterialApp(
      title: '轨记',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
        fontFamily: 'Noto Sans SC',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
        fontFamily: 'Noto Sans SC',
      ),
      home: const MainNavigationPage(),
    );
  }
}
