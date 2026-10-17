import 'dart:async';

import 'package:flutter/material.dart';
import 'package:raillog/src/services/aliyun_train_ticket_ocr_service.dart';
import 'package:raillog/src/services/baidu_train_ticket_ocr_service.dart';
import 'package:raillog/src/services/train_ticket_ocr_models.dart';
import 'package:raillog/src/services/train_ticket_ocr_service.dart';
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

  final _baiduApiKeyController = TextEditingController();
  final _baiduSecretKeyController = TextEditingController();
  final _aliyunAccessKeyIdController = TextEditingController();
  final _aliyunAccessKeySecretController = TextEditingController();
  late final List<FocusNode> _focusNodes;
  Timer? _saveDebounce;
  final _dirtyProviders = <TrainTicketOcrProvider>{};
  TrainTicketOcrProvider _provider = TrainTicketOcrProvider.baidu;
  bool _loading = true;
  bool _obscureBaiduSecret = true;
  bool _obscureAliyunSecret = true;

  @override
  void initState() {
    super.initState();
    _focusNodes = [
      for (var index = 0; index < 4; index++)
        FocusNode()..addListener(_flushWhenUnfocused),
    ];
    _load();
  }

  @override
  void dispose() {
    // 防抖窗口内直接返回时补写一次，避免丢掉最后一次输入；先同步读出
    // 输入框内容，再推迟到本帧结束，免得在销毁过程中触发监听者重建。
    if (_saveDebounce?.isActive ?? false) {
      final values = _readCredentials();
      final providers = {..._dirtyProviders};
      scheduleMicrotask(() => unawaited(_persist(values, providers)));
    }
    _saveDebounce?.cancel();
    for (final node in _focusNodes) {
      node.dispose();
    }
    _baiduApiKeyController.dispose();
    _baiduSecretKeyController.dispose();
    _aliyunAccessKeyIdController.dispose();
    _aliyunAccessKeySecretController.dispose();
    super.dispose();
  }

  void _flushWhenUnfocused() {
    if (_focusNodes.any((node) => node.hasFocus)) return;
    _flush();
  }

  void _scheduleSave(TrainTicketOcrProvider provider) {
    _dirtyProviders.add(provider);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_saveDebounceDuration, _flush);
  }

  void _flush() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    if (_dirtyProviders.isEmpty) return;
    final providers = {..._dirtyProviders};
    _dirtyProviders.clear();
    unawaited(_persist(_readCredentials(), providers));
  }

  ({
    String baiduApiKey,
    String baiduSecretKey,
    String aliyunAccessKeyId,
    String aliyunAccessKeySecret,
  })
  _readCredentials() => (
    baiduApiKey: _baiduApiKeyController.text,
    baiduSecretKey: _baiduSecretKeyController.text,
    aliyunAccessKeyId: _aliyunAccessKeyIdController.text,
    aliyunAccessKeySecret: _aliyunAccessKeySecretController.text,
  );

  Future<void> _persist(
    ({
      String baiduApiKey,
      String baiduSecretKey,
      String aliyunAccessKeyId,
      String aliyunAccessKeySecret,
    })
    values,
    Set<TrainTicketOcrProvider> providers,
  ) {
    return Future.wait([
      if (providers.contains(TrainTicketOcrProvider.baidu))
        BaiduOcrSettings.save(
          apiKey: values.baiduApiKey,
          secretKey: values.baiduSecretKey,
        ),
      if (providers.contains(TrainTicketOcrProvider.aliyun))
        AliyunOcrSettings.save(
          accessKeyId: values.aliyunAccessKeyId,
          accessKeySecret: values.aliyunAccessKeySecret,
        ),
    ]);
  }

  Future<void> _load() async {
    final provider = await TicketOcrSettings.loadProvider();
    final baidu = await BaiduOcrSettings.load();
    final aliyun = await AliyunOcrSettings.load();
    if (!mounted) return;
    _provider = provider;
    _baiduApiKeyController.text = baidu.apiKey;
    _baiduSecretKeyController.text = baidu.secretKey;
    _aliyunAccessKeyIdController.text = aliyun.accessKeyId;
    _aliyunAccessKeySecretController.text = aliyun.accessKeySecret;
    setState(() => _loading = false);
  }

  void _selectProvider(TrainTicketOcrProvider provider) {
    if (provider == _provider) return;
    _flush();
    setState(() => _provider = provider);
    unawaited(TicketOcrSettings.saveProvider(provider));
  }

  Future<void> _openHelp(String url, String failureMessage) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SettingsSubPage(
      title: '车票识别',
      children: [
        SettingsCard(
          title: '识别服务商',
          icon: Icons.cloud_outlined,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<TrainTicketOcrProvider>(
                      segments: const [
                        ButtonSegment(
                          value: TrainTicketOcrProvider.baidu,
                          label: Text('百度智能云'),
                        ),
                        ButtonSegment(
                          value: TrainTicketOcrProvider.aliyun,
                          label: Text('阿里云'),
                        ),
                      ],
                      selected: {_provider},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) =>
                          _selectProvider(selection.single),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '车票图片会发送给所选服务商完成识别，密钥只保存在本机。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
        ),
        if (!_loading) ...[
          const SizedBox(height: AppSpacing.md),
          if (_provider == TrainTicketOcrProvider.baidu)
            _buildBaiduCard()
          else
            _buildAliyunCard(),
        ],
      ],
    );
  }

  Widget _buildBaiduCard() {
    return SettingsCard(
      title: '百度车票识别',
      icon: Icons.document_scanner_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _baiduApiKeyController,
            focusNode: _focusNodes[0],
            autocorrect: false,
            onChanged: (_) => _scheduleSave(TrainTicketOcrProvider.baidu),
            decoration: InputDecoration(
              labelText: 'API Key',
              helperText: '请从百度智能云控制台获取',
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                tooltip: '查看百度火车票识别说明',
                onPressed: () => _openHelp(
                  'https://ai.baidu.com/tech/ocr_receipts/train_ticket',
                  '无法打开百度火车票识别页面',
                ),
                icon: const Icon(Icons.help_outline),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _baiduSecretKeyController,
            focusNode: _focusNodes[1],
            obscureText: _obscureBaiduSecret,
            onChanged: (_) => _scheduleSave(TrainTicketOcrProvider.baidu),
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Secret Key',
              helperText: '请从百度智能云控制台获取',
              prefixIcon: const Icon(Icons.password_outlined),
              suffixIcon: IconButton(
                tooltip: _obscureBaiduSecret ? '显示密钥' : '隐藏密钥',
                onPressed: () =>
                    setState(() => _obscureBaiduSecret = !_obscureBaiduSecret),
                icon: Icon(
                  _obscureBaiduSecret
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAliyunCard() {
    return SettingsCard(
      title: '阿里云车票识别',
      icon: Icons.document_scanner_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _aliyunAccessKeyIdController,
            focusNode: _focusNodes[2],
            autocorrect: false,
            onChanged: (_) => _scheduleSave(TrainTicketOcrProvider.aliyun),
            decoration: InputDecoration(
              labelText: 'AccessKey ID',
              helperText: '请从阿里云 AccessKey 管理页面获取',
              prefixIcon: const Icon(Icons.badge_outlined),
              suffixIcon: IconButton(
                tooltip: '查看阿里云火车票识别说明',
                onPressed: () => _openHelp(
                  'https://help.aliyun.com/zh/ocr/developer-reference/'
                      'api-ocr-api-2021-07-07-recognizetraininvoice',
                  '无法打开阿里云火车票识别页面',
                ),
                icon: const Icon(Icons.help_outline),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _aliyunAccessKeySecretController,
            focusNode: _focusNodes[3],
            obscureText: _obscureAliyunSecret,
            onChanged: (_) => _scheduleSave(TrainTicketOcrProvider.aliyun),
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'AccessKey Secret',
              helperText: '建议使用已授予 AliyunOCRFullAccess 权限的 RAM 子账号',
              prefixIcon: const Icon(Icons.password_outlined),
              suffixIcon: IconButton(
                tooltip: _obscureAliyunSecret ? '显示密钥' : '隐藏密钥',
                onPressed: () => setState(
                  () => _obscureAliyunSecret = !_obscureAliyunSecret,
                ),
                icon: Icon(
                  _obscureAliyunSecret
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}
