import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/widgets/user_level_badge.dart';

/// 用户等级分界线。
///
/// 优先使用管理后台下发的配置，其次使用本地缓存，最后回退到 App 内置默认值。
/// 启动时先读缓存（快、离线可用），再在后台刷新服务端配置。
class UserLevelSettings {
  UserLevelSettings._();

  static final UserLevelSettings instance = UserLevelSettings._();
  static const _key = 'user_level_thresholds';

  Future<void> initialize() async {
    try {
      final stored = await DbHelper.instance.getSetting(_key);
      final parsed = _parse(stored);
      if (parsed != null) applyUserLevelThresholds(parsed);
    } catch (error) {
      debugPrint('等级分界线缓存读取失败，使用内置默认值：$error');
    }
    unawaited(refresh());
  }

  Future<void> refresh() async {
    try {
      final response = await ApiClient.instance.dio.get('/api/user-levels');
      final data = response.data;
      final parsed = data is Map ? _parseThresholds(data['thresholds']) : null;
      if (parsed == null) return;
      applyUserLevelThresholds(parsed);
      await DbHelper.instance.setSetting(_key, jsonEncode(parsed));
    } catch (error) {
      debugPrint('等级分界线同步失败，继续使用缓存值：$error');
    }
  }

  static List<int>? _parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return _parseThresholds(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static List<int>? _parseThresholds(Object? value) {
    if (value is! List) return null;
    final thresholds = <int>[];
    for (final item in value) {
      if (item is int) {
        thresholds.add(item);
      } else if (item is num) {
        thresholds.add(item.toInt());
      } else {
        return null;
      }
    }
    if (thresholds.length < 2 || thresholds[0] != 0) return null;
    for (var level = 1; level < thresholds.length; level++) {
      if (thresholds[level] <= thresholds[level - 1]) return null;
    }
    return thresholds;
  }
}
