import 'package:dio/dio.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/services/achievement_unlock_notifier.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/cloud_sync_service.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/session_service.dart';

class AchievementService {
  AchievementService._();

  static Future<List<DashboardAchievement>> fetchCurrent() async {
    final token = SessionService.instance.token;
    if (token == null) throw const AchievementException('请先登录');
    try {
      final sync = CloudSyncService.instance;
      await sync.waitForCurrentSync();
      if (sync.lastError != null) {
        throw AchievementException(sync.lastError!);
      }
      final localTrips = await DbHelper.instance.getAllTrips();
      final response = await ApiClient.instance.dio.get<Map<String, dynamic>>(
        '/api/achievements',
        options: ApiClient.instance.authorized(token),
      );
      final achievements = dashboardAchievementsFromJson(
        response.data!,
        localTrips.map(DashboardTripEntry.fromTrip),
      );
      AchievementUnlockNotifier.instance.ingest(achievements);
      return achievements;
    } on DioException catch (error) {
      throw AchievementException(apiErrorMessage(error));
    } on AchievementException {
      rethrow;
    }
  }
}

class AchievementException implements Exception {
  const AchievementException(this.message);

  final String message;

  @override
  String toString() => message;
}
