import 'package:dio/dio.dart';
import 'package:raillog/src/models/achievement_unlock_trip.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/session_service.dart';

class AchievementUnlockService {
  AchievementUnlockService._();

  static Future<AchievementUnlockTrips> fetch(String achievementId) async {
    final token = SessionService.instance.token;
    if (token == null) throw const AchievementUnlockException('请先登录');
    try {
      final response = await ApiClient.instance.dio.get<Map<String, dynamic>>(
        '/api/achievements/${Uri.encodeComponent(achievementId)}/trips',
        options: ApiClient.instance.authorized(token),
      );
      return AchievementUnlockTrips.fromJson(response.data!);
    } on DioException catch (error) {
      throw AchievementUnlockException(apiErrorMessage(error));
    }
  }
}

class AchievementUnlockException implements Exception {
  const AchievementUnlockException(this.message);
  final String message;
  @override
  String toString() => message;
}
