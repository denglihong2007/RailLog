import 'dart:async';

import 'package:flutter/material.dart';
import 'package:raillog/src/services/baidu_train_ticket_ocr_service.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/settings/settings_section.dart';
import 'package:raillog/src/widgets/settings/settings_sub_page.dart';
import 'package:url_launcher/url_launcher.dart';

class TicketOcrSettingsPage extends StatefulWidget {
  const TicketOcrSettingsPage({super.key});

  @override
  State<TicketOcrSettingsPage> createState() => _TicketOcrSettingsPageState();
}

class _TicketOcrSettingsPageState extends State<TicketOcrSettingsPage> {
  /// 输入过程中不逐字落盘：停顿这么久、或输入框失焦时才写入。
  static const _saveDebounceDuration = Duration(milliseconds: 500);

  final _apiKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();
  late final List<FocusNode> _focusNodes;
  Timer? _saveDebounce;
  bool _loading = true;
  bool _obscureSecret = true;

  @override
  void initState() {
    super.initState();
    _focusNodes = [
      for (var index = 0; index < 2; index++)
        FocusNode()..addListener(_flushWhenUnfocused),
    ];
    _load();
  }

  @override
  void dispose() {
    // 防抖窗口内直接返回时补写一次，避免丢掉最后一次输入；推迟到本帧结束，
    // 免得在销毁过程中触发监听者重建。
    if (_saveDebounce?.isActive ?? false) {
      final apiKey = _apiKeyController.text;
      final secretKey = _secretKeyController.text;
      scheduleMicrotask(
        () => unawaited(
          BaiduOcrSettings.save(apiKey: apiKey, secretKey: secretKey),
        ),
      );
    }
    _saveDebounce?.cancel();
    for (final node in _focusNodes) {
      node.dispose();
    }
    _apiKeyController.dispose();
    _secretKeyController.dispose();
    super.dispose();
  }

  void _flushWhenUnfocused() {
    if (_focusNodes.any((node) => node.hasFocus)) return;
    _flush();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_saveDebounceDuration, _flush);
  }

  void _flush() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    unawaited(
      BaiduOcrSettings.save(
        apiKey: _apiKeyController.text,
        secretKey: _secretKeyController.text,
      ),
    );
  }

  Future<void> _load() async {
    final credentials = await BaiduOcrSettings.load();
    if (!mounted) return;
    _apiKeyController.text = credentials.apiKey;
    _secretKeyController.text = credentials.secretKey;
    setState(() => _loading = false);
  }

  Future<void> _openHelp() async {
    final opened = await launchUrl(
      Uri.parse('https://ai.baidu.com/tech/ocr_receipts/train_ticket'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开百度火车票识别页面')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSubPage(
      title: '车票识别',
      children: [
        SettingsCard(
          title: '百度车票识别',
          icon: Icons.document_scanner_outlined,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _apiKeyController,
                      focusNode: _focusNodes[0],
                      autocorrect: false,
                      onChanged: (_) => _scheduleSave(),
                      decoration: InputDecoration(
                        labelText: 'API Key',
                        helperText: '请从百度智能云控制台获取',
                        prefixIcon: const Icon(Icons.key_outlined),
                        suffixIcon: IconButton(
                          tooltip: '查看百度火车票识别说明',
                          onPressed: _openHelp,
                          icon: const Icon(Icons.help_outline),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _secretKeyController,
                      focusNode: _focusNodes[1],
                      obscureText: _obscureSecret,
                      onChanged: (_) => _scheduleSave(),
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'Secret Key',
                        helperText: '请从百度智能云控制台获取',
                        prefixIcon: const Icon(Icons.password_outlined),
                        suffixIcon: IconButton(
                          tooltip: _obscureSecret ? '显示密钥' : '隐藏密钥',
                          onPressed: () =>
                              setState(() => _obscureSecret = !_obscureSecret),
                          icon: Icon(
                            _obscureSecret
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
