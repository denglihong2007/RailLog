import 'package:dio/dio.dart';
import 'package:raillog/src/models/oauth_consent.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/session_service.dart';

class OAuthConsentService {
  OAuthConsentService._();

  static Future<List<OAuthConsent>> fetch() async {
    final token = SessionService.instance.token;
    if (token == null) throw const OAuthConsentException('请先登录');
    try {
      final response = await ApiClient.instance.dio.get<List<dynamic>>(
        '/api/oauth/consents',
        options: ApiClient.instance.authorized(token),
      );
      return [
        for (final item in response.data ?? const [])
          if (item is Map)
            OAuthConsent.fromJson(Map<String, dynamic>.from(item)),
      ];
    } on DioException catch (error) {
      throw OAuthConsentException(apiErrorMessage(error));
    }
  }

  static Future<void> revoke(String clientId) async {
    final token = SessionService.instance.token;
    if (token == null) throw const OAuthConsentException('请先登录');
    try {
      await ApiClient.instance.dio.delete<void>(
        '/api/oauth/consents/${Uri.encodeComponent(clientId)}',
        options: ApiClient.instance.authorized(token),
      );
    } on DioException catch (error) {
      throw OAuthConsentException(apiErrorMessage(error));
    }
  }
}

class OAuthConsentException implements Exception {
  const OAuthConsentException(this.message);

  final String message;

  @override
  String toString() => message;
}
