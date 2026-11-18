import 'dart:convert';

import 'package:raillog/src/services/ticket_12306_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本机保存的 12306 账号密码，用于下次登录时自动填入。
class Ticket12306SavedAccount {
  const Ticket12306SavedAccount({
    required this.username,
    required this.password,
    this.savePassword = true,
  });

  final String username;
  final String password;
  final bool savePassword;
}

/// 12306 会话凭证的本机存储。Cookie 按项目现有做法放进偏好设置，
/// 只保存在本机，不上传服务器。
abstract final class Ticket12306AuthSettings {
  static const _credentialsKey = 'ticket_12306.credentials';
  static const _usernameKey = 'ticket_12306.account.username';
  static const _passwordKey = 'ticket_12306.account.password';
  static const _savePasswordKey = 'ticket_12306.account.save_password';

  static Future<Ticket12306Credentials?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_credentialsKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return Ticket12306Credentials.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  static Future<void> save(Ticket12306Credentials credentials) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _credentialsKey,
      jsonEncode(credentials.toJson()),
    );
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_credentialsKey);
  }

  static Future<Ticket12306SavedAccount?> loadAccount() async {
    final preferences = await SharedPreferences.getInstance();
    final username = preferences.getString(_usernameKey) ?? '';
    final password = preferences.getString(_passwordKey) ?? '';
    if (username.trim().isEmpty && password.isEmpty) return null;
    return Ticket12306SavedAccount(
      username: username,
      password: password,
      savePassword: preferences.getBool(_savePasswordKey) ?? true,
    );
  }

  static Future<void> saveAccount({
    required String username,
    required String password,
    required bool savePassword,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setString(_usernameKey, username.trim()),
      if (savePassword && password.isNotEmpty)
        preferences.setString(_passwordKey, password)
      else
        preferences.remove(_passwordKey),
      preferences.setBool(_savePasswordKey, savePassword),
    ]);
  }

  static Future<void> clearAccount() async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(_usernameKey),
      preferences.remove(_passwordKey),
      preferences.remove(_savePasswordKey),
    ]);
  }
}
