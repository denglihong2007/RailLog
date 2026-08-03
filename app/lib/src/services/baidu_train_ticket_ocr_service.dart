import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BaiduOcrCredentials {
  const BaiduOcrCredentials({required this.apiKey, required this.secretKey});

  final String apiKey;
  final String secretKey;

  bool get isComplete =>
      apiKey.trim().isNotEmpty && secretKey.trim().isNotEmpty;
}

abstract final class BaiduOcrSettings {
  static const _apiKeyPreference = 'baidu_ocr_api_key';
  static const _secretKeyPreference = 'baidu_ocr_secret_key';

  static Future<BaiduOcrCredentials> load() async {
    final preferences = await SharedPreferences.getInstance();
    return BaiduOcrCredentials(
      apiKey: preferences.getString(_apiKeyPreference) ?? '',
      secretKey: preferences.getString(_secretKeyPreference) ?? '',
    );
  }

  static Future<void> save({
    required String apiKey,
    required String secretKey,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_apiKeyPreference, apiKey.trim());
    await preferences.setString(_secretKeyPreference, secretKey.trim());
  }
}

class TrainTicketOcrResult {
  const TrainTicketOcrResult({
    required this.trainNumber,
    required this.fromStation,
    required this.toStation,
    required this.departureTime,
    required this.seatType,
    required this.seatNumber,
    required this.price,
  });

  final String trainNumber;
  final String fromStation;
  final String toStation;
  final DateTime departureTime;
  final String? seatType;
  final String? seatNumber;
  final double? price;
}

class BaiduTrainTicketOcrService {
  BaiduTrainTicketOcrService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<TrainTicketOcrResult> recognize(
    Uint8List imageBytes,
    BaiduOcrCredentials credentials,
  ) async {
    if (!credentials.isComplete) {
      throw const BaiduOcrException('请先在设置中填写百度 OCR API Key 和 Secret Key');
    }
    final tokenResponse = await _dio.post<Map<String, dynamic>>(
      'https://aip.baidubce.com/oauth/2.0/token',
      queryParameters: {
        'grant_type': 'client_credentials',
        'client_id': credentials.apiKey.trim(),
        'client_secret': credentials.secretKey.trim(),
      },
    );
    final accessToken = tokenResponse.data?['access_token']?.toString();
    if (accessToken == null || accessToken.isEmpty) {
      throw BaiduOcrException(
        tokenResponse.data?['error_description']?.toString() ?? '百度 OCR 鉴权失败',
      );
    }

    final response = await _dio.post<Map<String, dynamic>>(
      'https://aip.baidubce.com/rest/2.0/ocr/v1/train_ticket',
      queryParameters: {'access_token': accessToken},
      data: {'image': base64Encode(imageBytes)},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final data = response.data ?? const <String, dynamic>{};
    if (data['error_code'] != null) {
      throw BaiduOcrException(data['error_msg']?.toString() ?? '火车票识别失败');
    }
    final words = data['words_result'];
    if (words is! Map) throw const BaiduOcrException('未识别到火车票信息');
    final values = Map<String, dynamic>.from(words);
    final trainNumber = _word(values, const [
      'train_num',
      'train_number',
    ]).replaceAll(RegExp(r'\s|次$'), '').toUpperCase();
    final fromStation = _word(values, const [
      'starting_station',
      'start_station',
    ]);
    final toStation = _word(values, const [
      'destination_station',
      'end_station',
    ]);
    final date = _word(values, const ['date', 'ticket_date']);
    if (trainNumber.isEmpty ||
        fromStation.isEmpty ||
        toStation.isEmpty ||
        date.isEmpty) {
      throw const BaiduOcrException('车次、始发站、终到站或乘车日期识别不完整，请重新拍摄');
    }
    return TrainTicketOcrResult(
      trainNumber: trainNumber,
      fromStation: fromStation,
      toStation: toStation,
      departureTime: _parseDateTime(date),
      seatType: _normalizeSeatType(
        _nullableWord(values, const ['seat_category', 'seat_type']),
      ),
      seatNumber: _nullableWord(values, const ['seat_num', 'seat_number']),
      price: _parsePrice(
        _word(values, const ['ticket_rates', 'ticket_price', 'price']),
      ),
    );
  }

  static String _word(Map<String, dynamic> words, List<String> keys) {
    for (final key in keys) {
      final value = words[key];
      if (value is Map) {
        final text = value['words']?.toString().trim() ?? '';
        if (text.isNotEmpty) return text;
      } else {
        final text = value?.toString().trim() ?? '';
        if (text.isNotEmpty) return text;
      }
    }
    return '';
  }

  static String? _nullableWord(Map<String, dynamic> words, List<String> keys) {
    final value = _word(words, keys);
    return value.isEmpty ? null : value;
  }

  static String? _normalizeSeatType(String? value) {
    final normalized = value?.replaceAll('新空调', '').trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  static DateTime _parseDateTime(String value) {
    final match = RegExp(
      r'(\d{4})\D+(\d{1,2})\D+(\d{1,2})(?:\D+(\d{1,2})[:：](\d{1,2}))?',
    ).firstMatch(value);
    if (match == null) throw const BaiduOcrException('无法解析乘车日期');
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.tryParse(match.group(4) ?? '') ?? 0,
      int.tryParse(match.group(5) ?? '') ?? 0,
    );
  }

  static double? _parsePrice(String value) {
    return double.tryParse(value.replaceAll(RegExp(r'[^\d.]'), ''));
  }
}

class BaiduOcrException implements Exception {
  const BaiduOcrException(this.message);
  final String message;
  @override
  String toString() => message;
}
