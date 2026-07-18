import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class DownloadFileService {
  static const _androidChannel = MethodChannel('com.deliho.raillog/downloads');

  static Future<String> save({
    required String name,
    required Uint8List bytes,
    required String fileExtension,
    required MimeType mimeType,
    required String androidMimeType,
  }) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final path = await _androidChannel.invokeMethod<String>(
        'saveToDownloads',
        {
          'name': '$name.$fileExtension',
          'bytes': bytes,
          'mimeType': androidMimeType,
        },
      );
      if (path == null || path.isEmpty) {
        throw PlatformException(
          code: 'downloads_unavailable',
          message: '系统 Downloads 目录不可用',
        );
      }
      return path;
    }
    return FileSaver.instance.saveFile(
      name: name,
      bytes: bytes,
      fileExtension: fileExtension,
      mimeType: mimeType,
    );
  }
}
