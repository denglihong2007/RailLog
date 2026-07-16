import 'package:dio/dio.dart';
import 'package:raillog/src/models/public_user_dashboard.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/session_service.dart';

class PublicTripService {
  PublicTripService._();

  static Future<PublicTripDetails> fetch(int ticketId) async {
    final token = SessionService.instance.token;
    if (token == null) throw const PublicTripException('请先登录');
    try {
      final response = await ApiClient.instance.dio.get<Map<String, dynamic>>(
        '/api/trips/$ticketId',
        options: ApiClient.instance.authorized(token),
      );
      return PublicTripDetails.fromJson(response.data!);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        throw const PublicTripException('未找到这条行程记录');
      }
      throw PublicTripException(apiErrorMessage(error));
    }
  }
}

class PublicTripException implements Exception {
  const PublicTripException(this.message);

  final String message;

  @override
  String toString() => message;
}
