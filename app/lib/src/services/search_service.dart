import 'package:dio/dio.dart';
import 'package:raillog/src/models/search_result.dart';
import 'package:raillog/src/services/api_client.dart';

class SearchService {
  SearchService._();

  static Future<List<EntitySearchResult>> searchEntities({
    required String type,
    required String query,
  }) async {
    try {
      final response = await ApiClient.instance.dio.get<List<dynamic>>(
        '/api/search/entities',
        queryParameters: {'type': type, 'q': query, 'limit': 30},
      );
      return (response.data ?? const [])
          .map(
            (item) => EntitySearchResult.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      throw SearchException(apiErrorMessage(error));
    }
  }

  static Future<List<UserSearchResult>> searchUsers(String query) async {
    try {
      final response = await ApiClient.instance.dio.get<List<dynamic>>(
        '/api/search/users',
        queryParameters: {'q': query, 'limit': 30},
      );
      return (response.data ?? const [])
          .map(
            (item) => UserSearchResult.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      throw SearchException(apiErrorMessage(error));
    }
  }
}

class SearchException implements Exception {
  const SearchException(this.message);

  final String message;

  @override
  String toString() => message;
}
