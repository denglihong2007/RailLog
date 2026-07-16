import 'package:dio/dio.dart';
import 'package:raillog/src/models/global_statistics.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/session_service.dart';

class StatisticsService {
  StatisticsService._();

  static Future<GlobalStatistics> fetch() async {
    final token = SessionService.instance.token;
    if (token == null) throw const StatisticsException('请先登录');
    try {
      final response = await ApiClient.instance.dio.get<Map<String, dynamic>>(
        '/api/statistics',
        options: ApiClient.instance.authorized(token),
      );
      return GlobalStatistics.fromJson(response.data!);
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await SessionService.instance.invalidate();
        throw const StatisticsException('登录已失效，请重新登录');
      }
      throw StatisticsException(apiErrorMessage(error));
    }
  }
}

class StatisticsException implements Exception {
  const StatisticsException(this.message);

  final String message;

  @override
  String toString() => message;
}
