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

  /// 删除数据库文件及其旁文件（`-wal` / `-shm` / `-journal`）。
  ///
  /// 只在传入文件名而非目录通配，因为同目录下还躺着打包进来的只读参考库
  /// （`rail_tracks_reference.db`、`routes_reference.db`），它们不能被连带删掉。
  ///
  /// 历史遗留目录里的同名副本也要一起删：`writablePath` 在目标文件不存在时
  /// 会从那里再拷一份回来，只删目标文件的话重置会形同虚设。
  static Future<void> deleteDatabaseFiles(String fileName) async {
    final basePaths = <String>{
      path_util.join(await directory(), fileName),
      path_util.join(await getDatabasesPath(), fileName),
    };

    // Windows 上 close() 之后文件句柄未必立刻释放，给几次重试的机会。
    for (var attempt = 1; ; attempt++) {
      final locked = await _deleteOnce(basePaths);
      if (locked == null) return;
      if (attempt >= 3) {
        throw FileSystemException('本地数据库文件仍被占用，无法删除', locked);
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  /// 返回仍被占用、删不掉的主文件路径；全部删干净时返回 null。
  static Future<String?> _deleteOnce(Set<String> basePaths) async {
    String? locked;
    for (final basePath in basePaths) {
      for (final suffix in const ['', '-wal', '-shm', '-journal']) {
        final file = File('$basePath$suffix');
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          // 旁文件删不掉不影响重建；主文件删不掉才算失败。
          if (suffix.isEmpty) locked = file.path;
        }
      }
    }
    return locked;
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
