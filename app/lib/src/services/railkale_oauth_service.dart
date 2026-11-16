import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:raillog/src/services/session_service.dart';

/// 万花筒（RailKale）OAuth 授权
///
/// 场景：万花筒想读取本应用的行程，需要知道当前用户的 ID。
/// 为避免把用户 ID 直接塞进 URL（自定义 scheme 可能被其它应用截获），
/// 采用「一次性密钥 + 服务器转交」的方式：
///
///   ① 万花筒 → 万花筒服务器  GET  /oauth/key        申请一次性密钥
///   ② 万花筒 → RailLog        raillog://oauth/rk/{key}
///   ③ RailLog → 万花筒服务器   GET  /oauth/verify?key=  校验密钥
///   ④ RailLog → 万花筒服务器   POST /oauth/report     上报当前用户 UUID
///   ⑤ RailLog → 万花筒         railkale://oauth/done  跳回（不含敏感数据）
///   ⑥ 万花筒 → 万花筒服务器    GET  /oauth/result     取回 UUID 完成绑定
///
/// 因此本文件的职责只有 ③④⑤：校验 → 上报 → 跳回。
/// 数据一律走 HTTPS，跳转链接里不携带任何用户信息。
class RailKaleOAuthService {
  RailKaleOAuthService._();

  static final RailKaleOAuthService instance = RailKaleOAuthService._();

  /// 万花筒服务器地址（与其 App 内接口同源）
  static const railKaleBaseUrl = 'https://next.laide.net.cn/api/v3';

  /// 万花筒的应用 scheme，用于跳回
  static const railKaleScheme = 'railkale';

  /// 本应用接收的 scheme 与 host
  static const _scheme = 'raillog';
  static const _host = 'oauth';

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  /// 是否已经初始化过，避免重复监听
  bool _initialized = false;

  /// 正在处理中，防止同一次唤起被处理两次
  bool _busy = false;

  Dio get _dio => Dio(
    BaseOptions(
      baseUrl: railKaleBaseUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  /// 启动监听
  ///
  /// 需要在应用启动时调用一次。同时处理「冷启动」（应用未运行，
  /// 被 scheme 直接拉起）与「热启动」（应用在后台，被 scheme 唤醒）。
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // 冷启动：读一次初始链接
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        // 稍等，确保 SessionService 已恢复登录态
        unawaited(
          Future<void>.delayed(
            const Duration(milliseconds: 600),
            () => handleUri(initial),
          ),
        );
      }

      // 热启动：持续监听
      _subscription = _appLinks.uriLinkStream.listen(
        (uri) => unawaited(handleUri(uri)),
        onError: (Object error) {
          debugPrint('RailKale OAuth：链接解析失败 $error');
        },
      );
    } catch (error) {
      debugPrint('RailKale OAuth：初始化失败 $error');
    }
  }

  /// 释放监听（一般无需手动调用）
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _initialized = false;
  }

  /// 处理一次唤起的链接
  ///
  /// 对外暴露以便测试。
  Future<void> handleUri(Uri uri) async {
    if (!_matches(uri)) return;
    if (_busy) return;
    _busy = true;
    try {
      await _process(uri);
    } finally {
      _busy = false;
    }
  }

  /// 判断是否为本服务负责的链接
  bool _matches(Uri uri) {
    return uri.scheme == _scheme && uri.host == _host;
  }

  /// 从 raillog://oauth/rk/{key} 中取出 key
  @visibleForTesting
  String? extractKey(Uri uri) {
    final segments = uri.pathSegments;
    // path 形如 ['rk', '{key}']
    if (segments.length < 2) return null;
    if (segments.first != 'rk') return null;
    final key = segments[1].trim();
    return key.isEmpty ? null : key;
  }

  Future<void> _process(Uri uri) async {
    final key = extractKey(uri);
    if (key == null) {
      debugPrint('RailKale OAuth：链接中缺少密钥 $uri');
      return;
    }

    // ① 校验密钥
    final valid = await _verify(key);
    if (!valid) {
      debugPrint('RailKale OAuth：密钥无效或已过期');
      return;
    }

    // ② 未登录时无法提供用户 ID，先跳回让万花筒等待超时
    final userId = SessionService.instance.user?.id;
    if (userId == null || userId.isEmpty) {
      debugPrint('RailKale OAuth：当前未登录，已放弃上报');
      await _jumpBack();
      return;
    }

    // ③ 上报用户 UUID（失败也要跳回，否则用户会卡在本应用里）
    try {
      await _report(key: key, userId: userId);
    } catch (error) {
      debugPrint('RailKale OAuth：上报失败 $error');
    }

    // ④ 跳回万花筒
    await _jumpBack();
  }

  /// 校验密钥是否合法
  Future<bool> _verify(String key) async {
    try {
      final response = await _dio.get<dynamic>(
        '/oauth/verify',
        queryParameters: {'key': key},
      );
      final data = response.data;
      if (data is Map) {
        // 服务端用 valid 表示结果，success 只代表请求本身成功
        return data['valid'] == true;
      }
      return false;
    } catch (error) {
      debugPrint('RailKale OAuth：校验请求失败 $error');
      return false;
    }
  }

  /// 上报当前登录用户的 UUID
  Future<void> _report({required String key, required String userId}) async {
    try {
      await _dio.post<dynamic>(
        '/oauth/report',
        data: {'key': key, 'uuid': userId},
      );
    } on DioException catch (error) {
      // 同一密钥重复上报会被拒绝，这里只记录不抛出
      debugPrint('RailKale OAuth：服务端拒绝了上报 ${error.response?.data}');
    }
  }

  /// 跳回万花筒
  Future<void> _jumpBack() async {
    final uri = Uri.parse('$railKaleScheme://oauth/done');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('RailKale OAuth：跳回万花筒失败（可能未安装）$error');
    }
  }
}
