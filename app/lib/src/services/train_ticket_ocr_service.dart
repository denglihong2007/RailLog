import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'aliyun_train_ticket_ocr_service.dart';
import 'baidu_train_ticket_ocr_service.dart';
import 'train_ticket_ocr_models.dart';

/// 当前服务商及其两套密钥的快照，避免识别过程中用户切换设置导致混用。
class TrainTicketOcrConfig {
  const TrainTicketOcrConfig({
    required this.provider,
    required this.baidu,
    required this.aliyun,
  });

  final TrainTicketOcrProvider provider;
  final BaiduOcrCredentials baidu;
  final AliyunOcrCredentials aliyun;

  bool get isComplete => switch (provider) {
    TrainTicketOcrProvider.baidu => baidu.isComplete,
    TrainTicketOcrProvider.aliyun => aliyun.isComplete,
  };

  String get missingCredentialsMessage => switch (provider) {
    TrainTicketOcrProvider.baidu => '请先在设置中填写百度 OCR API Key 和 Secret Key',
    TrainTicketOcrProvider.aliyun =>
      '请先在设置中填写阿里云 AccessKey ID 和 AccessKey Secret',
  };
}

abstract final class TicketOcrSettings {
  static const providerPreference = 'ticket_ocr_provider';

  static Future<TrainTicketOcrProvider> loadProvider() async {
    final preferences = await SharedPreferences.getInstance();
    return TrainTicketOcrProvider.fromPreference(
      preferences.getString(providerPreference),
    );
  }

  static Future<void> saveProvider(TrainTicketOcrProvider provider) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(providerPreference, provider.preferenceValue);
  }

  static Future<TrainTicketOcrConfig> loadConfig() async {
    final provider = await loadProvider();
    final baidu = await BaiduOcrSettings.load();
    final aliyun = await AliyunOcrSettings.load();
    return TrainTicketOcrConfig(
      provider: provider,
      baidu: baidu,
      aliyun: aliyun,
    );
  }
}

/// 按设置里选中的服务商分派识别请求。
class TrainTicketOcrService {
  TrainTicketOcrService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<TrainTicketOcrResult> recognize(
    Uint8List imageBytes,
    TrainTicketOcrConfig config,
  ) async {
    if (!config.isComplete) {
      throw TrainTicketOcrException(config.missingCredentialsMessage);
    }
    return switch (config.provider) {
      TrainTicketOcrProvider.baidu => BaiduTrainTicketOcrService(
        dio: _dio,
      ).recognize(imageBytes, config.baidu),
      TrainTicketOcrProvider.aliyun => AliyunTrainTicketOcrService(
        dio: _dio,
      ).recognize(imageBytes, config.aliyun),
    };
  }
}
