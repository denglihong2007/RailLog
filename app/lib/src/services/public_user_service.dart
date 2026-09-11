import 'package:dio/dio.dart';
import 'package:raillog/src/models/public_user_dashboard.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/session_service.dart';

class PublicUserService {
  PublicUserService._();

  static Future<PublicUserDashboard> fetch(String userId) async {
    final token = SessionService.instance.token;
    try {
      final response = await ApiClient.instance.dio.get<Map<String, dynamic>>(
        '/api/users/${Uri.encodeComponent(userId)}',
        options: token == null ? null : ApiClient.instance.authorized(token),
      );
      return PublicUserDashboard.fromJson(response.data!);
    } on DioException catch (error) {
      throw PublicUserException(apiErrorMessage(error));
    }
  }
}

class PublicUserException implements Exception {
  const PublicUserException(this.message);

  final String message;

  @override
  String toString() => message;
}
