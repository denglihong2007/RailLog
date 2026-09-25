import 'dart:io';

import 'package:flutter/material.dart';
import 'package:raillog/src/services/map_payload_store.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_windows/webview_windows.dart' as windows;

class TripMapWebView extends StatelessWidget {
  const TripMapWebView({
    super.key,
    required this.html,
    required this.backgroundColor,
  });

  final String html;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows) {
      return _WindowsWebView(html: html, backgroundColor: backgroundColor);
    }
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      return _MobileWebView(html: html, backgroundColor: backgroundColor);
    }
    return const _WebViewError(message: '当前平台暂不支持地图视图');
  }
}

class _WindowsWebView extends StatefulWidget {
  const _WindowsWebView({required this.html, required this.backgroundColor});

  final String html;
  final Color backgroundColor;

  @override
  State<_WindowsWebView> createState() => _WindowsWebViewState();
}

class _WindowsWebViewState extends State<_WindowsWebView> {
  final windows.WebviewController _controller = windows.WebviewController();
  final MapPayloadStore _payloads = MapPayloadStore();
  Object? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final version = await windows.WebviewController.getWebViewVersion();
      if (version == null) {
        throw StateError('未安装 Microsoft Edge WebView2 Runtime');
      }
      await _controller.initialize();
      await _controller.setBackgroundColor(widget.backgroundColor);
      await _controller.setPopupWindowPolicy(
        windows.WebviewPopupWindowPolicy.deny,
      );
      // 先把 Webview 挂上去再装载内容：装载出问题时能看到底色或错误，而不是一直转圈
      if (mounted) setState(() {});
      await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _reload() async {
    try {
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  /// 见 [MapPayloadStore]：WebView2 的 `NavigateToString` 吃不下大段 HTML，
  /// 这里落盘后用 `file://` 加载。
  Future<void> _load() async {
    final file = await _payloads.write(widget.html);
    if (file == null || !mounted) return; // 有更新的内容在排队，或页面已销毁
    await _controller.loadUrl(Uri.file(file.path).toString());
  }

  @override
  void didUpdateWidget(covariant _WindowsWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backgroundColor != widget.backgroundColor &&
        _controller.value.isInitialized) {
      _controller.setBackgroundColor(widget.backgroundColor);
    }
    if (oldWidget.html != widget.html && _controller.value.isInitialized) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) return _WebViewError(message: error.toString());
    if (!_controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return windows.Webview(
      _controller,
      permissionRequested: (_, _, _) async =>
          windows.WebviewPermissionDecision.deny,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _payloads.dispose();
    super.dispose();
  }
}

class _MobileWebView extends StatefulWidget {
  const _MobileWebView({required this.html, required this.backgroundColor});

  final String html;
  final Color backgroundColor;

  @override
  State<_MobileWebView> createState() => _MobileWebViewState();
}

class _MobileWebViewState extends State<_MobileWebView> {
  late final mobile.WebViewController _controller;
  final MapPayloadStore _payloads = MapPayloadStore();
  bool _loaded = false;
  bool _inlineFallback = false;

  @override
  void initState() {
    super.initState();
    _controller = mobile.WebViewController()
      ..setJavaScriptMode(mobile.JavaScriptMode.unrestricted)
      ..setBackgroundColor(widget.backgroundColor);
    if (Platform.isAndroid) {
      _controller.setNavigationDelegate(
        mobile.NavigationDelegate(
          onPageFinished: (_) => _loaded = true,
          onWebResourceError: _onWebResourceError,
        ),
      );
    }
    _load();
  }

  /// 安卓落盘后用 `file://` 加载：`loadHtmlString` 会退化成 data URL 走 Binder，
  /// 上限约 1 MB（见 [MapPayloadStore]）。iOS/macOS 的 WKWebView 没有这个上限，
  /// 保持原来的字符串加载不动。
  Future<void> _load() async {
    _loaded = false;
    _inlineFallback = false;
    if (!Platform.isAndroid) {
      await _controller.loadHtmlString(widget.html);
      return;
    }
    final file = await _payloads.write(widget.html);
    if (file == null || !mounted) return; // 有更新的内容在排队，或页面已销毁
    await _controller.loadFile(file.path);
  }

  /// 极少数设备可能不给 `file://` 权限，这时退回原来的字符串加载：
  /// 小地图照旧能显示，大地图至少不会比改动前更差（只退一次，不来回切）。
  void _onWebResourceError(mobile.WebResourceError error) {
    if (_loaded || _inlineFallback || error.isForMainFrame != true) return;
    _inlineFallback = true;
    _controller.loadHtmlString(widget.html);
  }

  @override
  void didUpdateWidget(covariant _MobileWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backgroundColor != widget.backgroundColor) {
      _controller.setBackgroundColor(widget.backgroundColor);
    }
    if (oldWidget.html != widget.html) _load();
  }

  @override
  void dispose() {
    _payloads.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => mobile.WebViewWidget(
    controller: _controller,
    gestureRecognizers: const {},
  );
}

class _WebViewError extends StatelessWidget {
  const _WebViewError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.map_outlined,
            size: 40,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
