import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      await _controller.loadStringContent(widget.html);
      if (mounted) setState(() {});
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error);
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void didUpdateWidget(covariant _WindowsWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backgroundColor != widget.backgroundColor &&
        _controller.value.isInitialized) {
      _controller.setBackgroundColor(widget.backgroundColor);
    }
    if (oldWidget.html != widget.html && _controller.value.isInitialized) {
      _controller.loadStringContent(widget.html);
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

  @override
  void initState() {
    super.initState();
    _controller = mobile.WebViewController()
      ..setJavaScriptMode(mobile.JavaScriptMode.unrestricted)
      ..setBackgroundColor(widget.backgroundColor)
      ..loadHtmlString(widget.html);
  }

  @override
  void didUpdateWidget(covariant _MobileWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backgroundColor != widget.backgroundColor) {
      _controller.setBackgroundColor(widget.backgroundColor);
    }
    if (oldWidget.html != widget.html) _controller.loadHtmlString(widget.html);
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
