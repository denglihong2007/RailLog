import 'package:dio/dio.dart';
import 'package:raillog/src/models/online_intersection.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/session_service.dart';

class IntersectionService {
  IntersectionService._();

  static Future<List<OnlineIntersection>> fetch() async {
    final token = SessionService.instance.token;
    if (token == null) return const [];
    try {
      final response = await ApiClient.instance.dio.get<Map<String, dynamic>>(
        '/api/intersections',
        options: ApiClient.instance.authorized(token),
      );
      final rows =
          response.data?['intersections'] as List<dynamic>? ?? const [];
      return rows
          .map(
            (row) => OnlineIntersection.fromJson(row as Map<String, dynamic>),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      throw IntersectionException(apiErrorMessage(error));
    }
  }
}

class IntersectionException implements Exception {
  const IntersectionException(this.message);

  final String message;

  @override
  String toString() => message;
}
