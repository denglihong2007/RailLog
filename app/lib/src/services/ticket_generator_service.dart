import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_saver/file_saver.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/download_file_service.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/services/ticket_generator_settings.dart';

abstract final class TicketGeneratorService {
  static Future<Uint8List> generateImage({required int tripId}) =>
      _generateImage(tripId: tripId);

  static Future<String> saveImage({
    required int tripId,
    required Uint8List bytes,
  }) => DownloadFileService.save(
    name: 'RailLog_车票_$tripId',
    bytes: bytes,
    fileExtension: 'png',
    mimeType: MimeType.png,
    androidMimeType: 'image/png',
  );

  static Future<TicketPdfDownloadKey> createPdfDownloadKey({
    required int tripId,
  }) async {
    final token = SessionService.instance.token;
    if (token == null) throw const TicketGeneratorException('请先登录');
    final settings = TicketGeneratorSettings.instance;
    if (settings.displayStyle == TicketDisplayStyle.md3) {
      throw const TicketGeneratorException('MD3 样式无需生成车票文件');
    }
    try {
      final response = await ApiClient.instance.dio.post<Map<String, dynamic>>(
        '/api/ticket-generator/pdf-key',
        data: _requestData(tripId, settings),
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data;
      final key = data?['key'] as String?;
      final expiresAt = DateTime.tryParse(data?['expiresAt'] as String? ?? '');
      if (key == null || key.isEmpty || expiresAt == null) {
        throw const TicketGeneratorException('服务器未返回有效的下载 Key');
      }
      return TicketPdfDownloadKey(key: key, expiresAt: expiresAt);
    } on TicketGeneratorException {
      rethrow;
    } catch (error) {
      throw TicketGeneratorException(apiErrorMessage(error));
    }
  }

  static Future<Uint8List> _generateImage({required int tripId}) async {
    final token = SessionService.instance.token;
    if (token == null) throw const TicketGeneratorException('请先登录');
    final settings = TicketGeneratorSettings.instance;
    if (settings.displayStyle == TicketDisplayStyle.md3) {
      throw const TicketGeneratorException('MD3 样式无需生成车票文件');
    }
    try {
      final response = await ApiClient.instance.dio.post<List<int>>(
        '/api/ticket-generator/image',
        data: _requestData(tripId, settings),
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.bytes,
        ),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw const TicketGeneratorException('服务器未返回车票文件');
      }
      return Uint8List.fromList(data);
    } on TicketGeneratorException {
      rethrow;
    } catch (error) {
      throw TicketGeneratorException(apiErrorMessage(error));
    }
  }

  static Map<String, dynamic> _requestData(
    int tripId,
    TicketGeneratorSettings settings,
  ) => {
    'tripId': tripId,
    'style': settings.requestStyle,
    'passenger': settings.passenger,
    'maskedId': settings.maskedId,
    'serialPrefix': settings.serialPrefix,
    'showNewAirConditioned': settings.showNewAirConditioned,
  };
}

class TicketPdfDownloadKey {
  const TicketPdfDownloadKey({required this.key, required this.expiresAt});

  final String key;
  final DateTime expiresAt;
}

class TicketGeneratorException implements Exception {
  const TicketGeneratorException(this.message);
  final String message;

  @override
  String toString() => message;
}
