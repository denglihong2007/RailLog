import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();
  static const baseUrl = String.fromEnvironment(
    'RAILLOG_API_URL',
    defaultValue: kReleaseMode
        ? 'https://api.raillog.top'
        : 'http://localhost:5149',
  );

  final Dio dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  Options authorized(String token) =>
      Options(headers: {'Authorization': 'Bearer $token'});
}

String apiErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    if (error.response?.statusCode == 401) return '登录已失效，请重新登录';
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return '无法连接服务器，请检查 API 地址和网络';
    }
  }
  return '操作失败，请稍后重试';
}
