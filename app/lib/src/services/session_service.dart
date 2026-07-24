import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:raillog/src/models/user_profile.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/db_helper.dart';

class SessionService extends ChangeNotifier {
  SessionService._();

  static final SessionService instance = SessionService._();
  static const _tokenKey = 'auth_token';
  static const _profileKey = 'auth_profile';

  String? _token;
  UserProfile? _user;
  Future<void> Function()? onAuthenticated;

  String? get token => _token;
  UserProfile? get user => _user;
  bool get isSignedIn => _token != null && _user != null;

  Future<void> initialize() async {
    _token = await DbHelper.instance.getSetting(_tokenKey);
    final profileJson = await DbHelper.instance.getSetting(_profileKey);
    if (_token == null || profileJson == null) {
      await _clearLocal();
      return;
    }
    try {
      _user = UserProfile.fromJson(
        jsonDecode(profileJson) as Map<String, dynamic>,
      );
    } catch (_) {
      await _clearLocal();
    }
  }

  Future<void> login({required String email, required String password}) async {
    try {
      final response = await ApiClient.instance.dio.post<Map<String, dynamic>>(
        '/api/auth/login',
        data: {'email': email.trim(), 'password': password},
      );
      await _storeAuth(response.data!);
      await onAuthenticated?.call();
    } catch (error) {
      throw SessionException(apiErrorMessage(error));
    }
  }

  Future<void> register({
    required String email,
    required String displayName,
    required String password,
    required String verificationCode,
  }) async {
    try {
      final response = await ApiClient.instance.dio.post<Map<String, dynamic>>(
        '/api/auth/register',
        data: {
          'email': email.trim(),
          'displayName': displayName.trim(),
          'password': password,
          'verificationCode': verificationCode.trim(),
        },
      );
      await _storeAuth(response.data!);
      await onAuthenticated?.call();
    } catch (error) {
      throw SessionException(apiErrorMessage(error));
    }
  }

  Future<void> updateProfile({
    required String displayName,
    String? avatarUrl,
    String? bio,
    required bool showEmailOnProfile,
  }) async {
    final authToken = _token;
    if (authToken == null) throw const SessionException('请先登录');
    try {
      final response = await ApiClient.instance.dio.post<Map<String, dynamic>>(
        '/api/profile',
        options: ApiClient.instance.authorized(authToken),
        data: {
          'displayName': displayName.trim(),
          'avatarUrl': _nullableText(avatarUrl),
          'bio': _nullableText(bio),
          'showEmailOnProfile': showEmailOnProfile,
        },
      );
      _user = UserProfile.fromJson(response.data!);
      await _persistProfile();
      notifyListeners();
    } catch (error) {
      throw SessionException(apiErrorMessage(error));
    }
  }

  Future<void> logout() async {
    final authToken = _token;
    try {
      if (authToken != null) {
        await ApiClient.instance.dio.post<void>(
          '/api/auth/logout',
          options: ApiClient.instance.authorized(authToken),
        );
      }
    } finally {
      await _clearLocal();
      notifyListeners();
    }
  }

  Future<void> deleteAccount() async {
    final authToken = _token;
    if (authToken == null) throw const SessionException('请先登录');
    try {
      await ApiClient.instance.dio.delete<void>(
        '/api/auth/account',
        options: ApiClient.instance.authorized(authToken),
      );
      await DbHelper.instance.releaseTripsForUser(_user!.id);
      await _clearLocal();
      notifyListeners();
    } catch (error) {
      throw SessionException(apiErrorMessage(error));
    }
  }

  Future<String> sendVerificationCode({
    required String email,
    required String purpose,
  }) async {
    try {
      final response = await ApiClient.instance.dio.post<Map<String, dynamic>>(
        '/api/auth/verification-code',
        data: {'email': email.trim(), 'purpose': purpose},
      );
      return response.data?['message'] as String? ?? '验证码已发送';
    } catch (error) {
      throw SessionException(apiErrorMessage(error));
    }
  }

  Future<String> resetPassword({
    required String email,
    required String verificationCode,
    required String newPassword,
  }) async {
    try {
      final response = await ApiClient.instance.dio.post<Map<String, dynamic>>(
        '/api/auth/reset-password',
        data: {
          'email': email.trim(),
          'verificationCode': verificationCode.trim(),
          'newPassword': newPassword,
        },
      );
      return response.data?['message'] as String? ?? '密码已重置';
    } catch (error) {
      throw SessionException(apiErrorMessage(error));
    }
  }

  Future<void> invalidate() async {
    await _clearLocal();
    notifyListeners();
  }

  Future<void> _storeAuth(Map<String, dynamic> json) async {
    _token = json['token'] as String;
    _user = UserProfile.fromJson(json['user'] as Map<String, dynamic>);
    await DbHelper.instance.setSetting(_tokenKey, _token);
    await _persistProfile();
    notifyListeners();
  }

  Future<void> _persistProfile() =>
      DbHelper.instance.setSetting(_profileKey, jsonEncode(_user!.toJson()));

  Future<void> _clearLocal() async {
    _token = null;
    _user = null;
    await DbHelper.instance.setSetting(_tokenKey, null);
    await DbHelper.instance.setSetting(_profileKey, null);
  }
}

class SessionException implements Exception {
  const SessionException(this.message);
  final String message;
  @override
  String toString() => message;
}

String? _nullableText(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}
