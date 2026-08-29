import 'dart:io';

import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

abstract final class DatabasePathService {
  static Future<String> directory() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return getDatabasesPath();
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final databaseDirectory = Directory(
      path_util.join(supportDirectory.path, 'databases'),
    );
    await databaseDirectory.create(recursive: true);
    return databaseDirectory.path;
  }

  static Future<String> writablePath(
    String fileName, {
    bool migrateLegacyDesktopDatabase = false,
  }) async {
    final targetPath = path_util.join(await directory(), fileName);
    if (!migrateLegacyDesktopDatabase ||
        (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) ||
        await File(targetPath).exists()) {
      return targetPath;
    }

    final legacyPath = path_util.join(await getDatabasesPath(), fileName);
    final legacyFile = File(legacyPath);
    if (legacyPath != targetPath && await legacyFile.exists()) {
      await legacyFile.copy(targetPath);
    }
    return targetPath;
  }
}
