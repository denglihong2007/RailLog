import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'train_ticket_ocr_models.dart';

class AliyunOcrCredentials {
  const AliyunOcrCredentials({
    required this.accessKeyId,
    required this.accessKeySecret,
  });

  final String accessKeyId;
  final String accessKeySecret;

  bool get isComplete =>
      accessKeyId.trim().isNotEmpty && accessKeySecret.trim().isNotEmpty;
}

abstract final class AliyunOcrSettings {
  static const _accessKeyIdPreference = 'aliyun_ocr_access_key_id';
  static const _accessKeySecretPreference = 'aliyun_ocr_access_key_secret';

  static Future<AliyunOcrCredentials> load() async {
    final preferences = await SharedPreferences.getInstance();
    return AliyunOcrCredentials(
      accessKeyId: preferences.getString(_accessKeyIdPreference) ?? '',
      accessKeySecret: preferences.getString(_accessKeySecretPreference) ?? '',
    );
  }

  static Future<void> save({
    required String accessKeyId,
    required String accessKeySecret,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_accessKeyIdPreference, accessKeyId.trim());
    await preferences.setString(
      _accessKeySecretPreference,
      accessKeySecret.trim(),
    );
  }
}

/// 阿里云文字识别（ocr-api 2021-07-07）的火车票识别。
///
/// 与视觉智能开放平台旧版 RecognizeTrainTicket 不同，这一版支持把图片
/// 二进制直接放进请求 body，不必先上传 OSS，适合客户端本地选图。
class AliyunTrainTicketOcrService {
  AliyunTrainTicketOcrService({
    Dio? dio,
    this.endpoint = defaultEndpoint,
    DateTime Function()? clock,
    String Function()? nonceGenerator,
  }) : _dio = dio ?? Dio(),
       _clock = clock ?? DateTime.now,
       _nonceGenerator = nonceGenerator ?? _generateNonce;

  static const defaultEndpoint = 'ocr-api.cn-hangzhou.aliyuncs.com';
  static const apiVersion = '2021-07-07';
  static const action = 'RecognizeTrainInvoice';
  static const maxImageBytes = 10 * 1024 * 1024;

  final Dio _dio;
  final String endpoint;
  final DateTime Function() _clock;
  final String Function() _nonceGenerator;

  Future<TrainTicketOcrResult> recognize(
    Uint8List imageBytes,
    AliyunOcrCredentials credentials,
  ) async {
    if (!credentials.isComplete) {
      throw const TrainTicketOcrException(
        '请先在设置中填写阿里云 AccessKey ID 和 AccessKey Secret',
      );
    }
    if (imageBytes.isEmpty) {
      throw const TrainTicketOcrException('车票图片为空，请重新选择');
    }
    if (imageBytes.length > maxImageBytes) {
      throw const TrainTicketOcrException('车票图片超过 10 MB，请压缩后重试');
    }

    final parameters = <String, String>{
      'Action': action,
      'Version': apiVersion,
      'Format': 'JSON',
      'AccessKeyId': credentials.accessKeyId.trim(),
      'SignatureMethod': 'HMAC-SHA1',
      'SignatureVersion': '1.0',
      'SignatureNonce': _nonceGenerator(),
      'Timestamp': AliyunRpcSignature.formatTimestamp(_clock()),
    };
    parameters['Signature'] = AliyunRpcSignature.sign(
      method: 'POST',
      parameters: parameters,
      accessKeySecret: credentials.accessKeySecret.trim(),
    );
    // 自己拼 query，避免 Dio 的编码方式与签名时的 RFC3986 编码不一致。
    final query = parameters.entries
        .map(
          (entry) =>
              '${AliyunRpcSignature.percentEncode(entry.key)}='
              '${AliyunRpcSignature.percentEncode(entry.value)}',
        )
        .join('&');

    try {
      final response = await _dio.post<dynamic>(
        'https://$endpoint/?$query',
        data: imageBytes,
        options: Options(
          contentType: 'application/octet-stream',
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      return _parseResponse(response.data);
    } on DioException catch (error) {
      throw TrainTicketOcrException(_describeError(error));
    }
  }

  static TrainTicketOcrResult _parseResponse(dynamic raw) {
    final body = _asMap(raw);
    if (body == null) {
      throw const TrainTicketOcrException('阿里云返回了无法解析的响应');
    }
    final code = body['Code']?.toString();
    if (code != null && code.isNotEmpty) {
      throw TrainTicketOcrException(
        _errorMessage(code, body['Message']?.toString()),
      );
    }

    final wrapper = _asMap(body['Data']);
    if (wrapper == null) {
      throw const TrainTicketOcrException('未识别到火车票信息');
    }
    final data = _asMap(wrapper['data']);
    if (data == null) {
      throw const TrainTicketOcrException('未识别到火车票信息');
    }

    final trainNumber = _text(
      data['trainNumber'],
    ).replaceAll(RegExp(r'\s|次$'), '').toUpperCase();
    final fromStation = _text(data['departureStation']);
    final toStation = _text(data['arrivalStation']);
    final date = _text(data['departureTime']);
    if (trainNumber.isEmpty ||
        fromStation.isEmpty ||
        toStation.isEmpty ||
        date.isEmpty) {
      throw const TrainTicketOcrException('车次、始发站、终到站或乘车日期识别不完整，请重新拍摄');
    }

    return TrainTicketOcrResult(
      trainNumber: trainNumber,
      fromStation: fromStation,
      toStation: toStation,
      departureTime: TrainTicketOcrParsing.dateTime(date),
      seatType: TrainTicketOcrParsing.seatType(_text(data['seatType'])),
      seatNumber: _nullableText(data['seatNumber']),
      price: TrainTicketOcrParsing.price(_text(data['fare'])),
    );
  }

  static String _describeError(DioException error) {
    final body = _asMap(error.response?.data);
    if (body != null) {
      final code = body['Code']?.toString();
      final message = body['Message']?.toString();
      if ((code != null && code.isNotEmpty) ||
          (message != null && message.isNotEmpty)) {
        return _errorMessage(code, message);
      }
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => '连接阿里云超时，请检查网络后重试',
      DioExceptionType.connectionError => '无法连接阿里云，请检查网络后重试',
      _ => '阿里云识别失败，请稍后重试',
    };
  }

  static String _errorMessage(String? code, String? message) {
    final friendly = _friendlyMessage(code);
    if (friendly != null) {
      return code == null || code.isEmpty ? friendly : '$friendly（$code）';
    }
    if (message != null && message.isNotEmpty) {
      return code == null || code.isEmpty ? message : '$message（$code）';
    }
    return code == null || code.isEmpty ? '阿里云识别失败' : '阿里云识别失败（$code）';
  }

  static String? _friendlyMessage(String? code) {
    if (code == null || code.isEmpty) return null;
    if (code == 'SignatureDoesNotMatch' ||
        code.startsWith('InvalidAccessKeyId')) {
      return '阿里云鉴权失败，请检查 AccessKey ID 和 AccessKey Secret';
    }
    if (code == 'noPermission' || code.startsWith('Forbidden')) {
      return '当前 AccessKey 没有文字识别权限，请开通 OCR 服务并授予 AliyunOCRFullAccess';
    }
    return null;
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  static String? _nullableText(dynamic value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }

  static String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

/// 阿里云 RPC 接口的 HMAC-SHA1 签名（SignatureVersion 1.0）。
abstract final class AliyunRpcSignature {
  static String sign({
    required String method,
    required Map<String, String> parameters,
    required String accessKeySecret,
  }) {
    final canonical = canonicalizedQueryString(parameters);
    final stringToSign =
        '$method&${percentEncode('/')}&${percentEncode(canonical)}';
    final digest = Hmac(
      sha1,
      utf8.encode('$accessKeySecret&'),
    ).convert(utf8.encode(stringToSign));
    return base64Encode(digest.bytes);
  }

  static String canonicalizedQueryString(Map<String, String> parameters) {
    final keys =
        parameters.keys
            .where((key) => key != 'Signature' && parameters[key]!.isNotEmpty)
            .toList()
          ..sort();
    return keys
        .map(
          (key) => '${percentEncode(key)}=${percentEncode(parameters[key]!)}',
        )
        .join('&');
  }

  /// RFC3986：只保留 A-Z、a-z、0-9、`-`、`_`、`.`、`~`，其余按 UTF-8 编码。
  static String percentEncode(String value) {
    final buffer = StringBuffer();
    for (final byte in utf8.encode(value)) {
      final unreserved =
          (byte >= 0x41 && byte <= 0x5A) ||
          (byte >= 0x61 && byte <= 0x7A) ||
          (byte >= 0x30 && byte <= 0x39) ||
          byte == 0x2D ||
          byte == 0x5F ||
          byte == 0x2E ||
          byte == 0x7E;
      if (unreserved) {
        buffer.writeCharCode(byte);
      } else {
        buffer
          ..write('%')
          ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
      }
    }
    return buffer.toString();
  }

  static String formatTimestamp(DateTime time) {
    final utc = time.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-'
        '${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:'
        '${two(utc.second)}Z';
  }
}
