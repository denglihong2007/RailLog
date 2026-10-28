import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:raillog/src/services/mail_account_settings.dart';
import 'package:raillog/src/services/mail_import_service.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/settings/settings_section.dart';
import 'package:raillog/src/widgets/settings/settings_sub_page.dart';

class EmailConnectionSettingsPage extends StatefulWidget {
  const EmailConnectionSettingsPage({super.key});

  @override
  State<EmailConnectionSettingsPage> createState() =>
      _EmailConnectionSettingsPageState();
}

class _EmailConnectionSettingsPageState
    extends State<EmailConnectionSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '993');
  bool _loading = true;
  bool _testing = false;
  bool _obscurePassword = true;
  bool _useTls = true;
  MailProtocol _protocol = MailProtocol.imap;
  String? _status;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await MailAccountSettings.load();
    if (!mounted) return;
    if (config != null) {
      _emailController.text = config.emailAddress;
      _passwordController.text = config.password;
      _hostController.text = config.host;
      _portController.text = '${config.port}';
      _protocol = config.protocol;
      _useTls = config.useTls;
      _previousSuggestion = MailAccountSettings.suggestHost(
        config.emailAddress,
        config.protocol,
      );
    }
    setState(() => _loading = false);
  }

  void _onEmailChanged(String value) {
    final suggestion = MailAccountSettings.suggestHost(value, _protocol);
    if (suggestion != null) {
      final host = _hostController.text.trim();
      if (host.isEmpty || host == _previousSuggestion) {
        _hostController.text = suggestion;
      }
      _previousSuggestion = suggestion;
    }
    setState(() {});
  }

  /// 输入受限邮箱时，在表单里直接给出可以照做的下一步。
  String? get _providerHint {
    final email = _emailController.text.trim().toLowerCase();
    final at = email.lastIndexOf('@');
    if (at < 0 || at == email.length - 1) return null;
    return switch (email.substring(at + 1)) {
      'outlook.com' || 'hotmail.com' || 'live.com' || 'msn.com' =>
        'Outlook 邮箱无法直接连接。请在 Outlook 里打开 12306 邮件，点「转发」'
            '发到 QQ、163 等邮箱，再回来填写那个邮箱。',
      'gmail.com' || 'googlemail.com' => 'Gmail 不能使用登录密码，请开启两步验证并生成应用专用密码。',
      'icloud.com' ||
      'me.com' ||
      'mac.com' => 'iCloud 需要使用 App 专用密码，并且只支持 IMAP。',
      'yahoo.com' || 'aol.com' => 'Yahoo / AOL 需要使用应用密码，账号密码无法登录。',
      'proton.me' ||
      'protonmail.com' => 'Proton Mail 免费版不支持 IMAP / POP3，建议转发到 QQ、163 等邮箱。',
      'fastmail.com' ||
      'fastmail.fm' => 'Fastmail 必须使用应用密码，基础版不提供 IMAP / POP3 访问。',
      'zoho.com' || 'zoho.com.cn' || 'zohomail.com' => 'Zoho 开启两步验证后需要使用应用密码。',
      'yandex.com' ||
      'yandex.ru' ||
      'ya.ru' => 'Yandex 可能要求用 @ 前的用户名登录；连不上时可以转发到 QQ、163 邮箱。',
      _ => null,
    };
  }

  void _onProtocolChanged(MailProtocol protocol) {
    if (protocol == _protocol) return;
    final email = _emailController.text.trim();
    final previousDefaultPort = _protocol.defaultPort;
    final previousSuggestion = MailAccountSettings.suggestHost(
      email,
      _protocol,
    );
    final host = _hostController.text.trim();
    final replaceHost =
        host.isEmpty ||
        host == previousSuggestion ||
        host == _previousSuggestion;
    final suggestion = MailAccountSettings.suggestHost(email, protocol);

    setState(() => _protocol = protocol);
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port == previousDefaultPort) {
      _portController.text = '${protocol.defaultPort}';
    }
    if (suggestion != null && replaceHost) {
      _hostController.text = suggestion;
    }
    _previousSuggestion = suggestion;
  }

  String? _previousSuggestion;

  MailAccountConfig _currentConfig() => MailAccountConfig(
    emailAddress: _emailController.text.trim(),
    password: _passwordController.text,
    host: _hostController.text.trim(),
    port: int.tryParse(_portController.text.trim()) ?? _protocol.defaultPort,
    protocol: _protocol,
    useTls: _useTls,
  );

  Future<bool> _save({bool showSnackBar = true}) async {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    await MailAccountSettings.save(_currentConfig());
    if (!mounted) return true;
    if (showSnackBar) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('邮箱连接已保存')));
    }
    return true;
  }

  Future<void> _testConnection() async {
    if (_testing) return;
    if (!await _save(showSnackBar: false)) return;
    if (!mounted) return;
    setState(() {
      _testing = true;
      _status = null;
      _statusIsError = false;
    });
    try {
      final count = await const MailImportService().testConnection(
        _currentConfig(),
      );
      if (!mounted) return;
      setState(() {
        _status = '连接成功，收件箱共 $count 封邮件';
        _statusIsError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = '连接失败：$error';
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除邮箱连接'),
        content: const Text('清除后需要重新填写邮箱连接信息，才能继续从邮箱导入。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await MailAccountSettings.clear();
    if (!mounted) return;
    setState(() {
      _emailController.clear();
      _passwordController.clear();
      _hostController.clear();
      _portController.text = '${MailProtocol.imap.defaultPort}';
      _protocol = MailProtocol.imap;
      _useTls = true;
      _status = null;
      _statusIsError = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清除邮箱连接')));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SettingsSubPage(
      title: '邮箱导入',
      children: [
        SettingsCard(
          title: '邮箱连接',
          icon: Icons.alternate_email,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: '邮箱地址',
                          helperText: '例如 name@qq.com',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) return '请填写邮箱地址';
                          if (email.indexOf('@') <= 0) return '邮箱地址格式不正确';
                          return null;
                        },
                        onChanged: _onEmailChanged,
                      ),
                      if (_providerHint != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _InlineHint(message: _providerHint!),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SegmentedButton<MailProtocol>(
                          segments: [
                            for (final protocol in MailProtocol.values)
                              ButtonSegment(
                                value: protocol,
                                label: Text(protocol.label),
                              ),
                          ],
                          selected: {_protocol},
                          onSelectionChanged: (values) =>
                              _onProtocolChanged(values.first),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '选择邮箱网页端已开启的接收协议。IMAP 支持在服务器端搜索，'
                        '邮件较多时更快；POP3 需要逐封读取邮件头。',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: '密码 / 授权码 / 应用密码',
                          helperText: '国内邮箱填授权码；Gmail、iCloud 等填应用专用密码',
                          prefixIcon: const Icon(Icons.password_outlined),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword ? '显示授权码' : '隐藏授权码',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            (value ?? '').isEmpty ? '请填写密码或授权码' : null,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _hostController,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: '${_protocol.label} 服务器',
                          helperText: '根据邮箱地址自动填写，可手动修改',
                          prefixIcon: const Icon(Icons.dns_outlined),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) => (value?.trim() ?? '').isEmpty
                            ? '请填写 ${_protocol.label} 服务器'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _portController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: '端口',
                                prefixIcon: Icon(Icons.numbers_outlined),
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                final port = int.tryParse(value?.trim() ?? '');
                                if (port == null || port <= 0 || port > 65535) {
                                  return '端口不正确';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: SwitchListTile(
                              value: _useTls,
                              contentPadding: EdgeInsets.zero,
                              title: const Text('SSL/TLS'),
                              subtitle: Text('常用端口 ${_protocol.defaultPort}'),
                              onChanged: (value) =>
                                  setState(() => _useTls = value),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (_status != null) ...[
                        _StatusBanner(
                          message: _status!,
                          isError: _statusIsError,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _testing ? null : _save,
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('保存'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _testing ? null : _testConnection,
                              icon: _testing
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.wifi_tethering),
                              label: const Text('测试连接'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        SettingsCard(
          title: '各邮箱的限制',
          icon: Icons.shield_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MailProviderHint(
                name: 'Outlook / Hotmail / Live / Microsoft 365',
                description:
                    '已停用密码和授权码登录，无法直接连接。可以在 Outlook 中打开'
                    '12306 邮件，点「转发」发到 QQ、163 等邮箱后再导入。',
              ),
              _MailProviderHint(
                name: 'QQ / 163 / 126 等国内邮箱',
                description:
                    '需要在网页端开启 IMAP / POP3 服务并生成授权码，不能用登录密码。'
                    'QQ：设置 → 账号 → POP3/IMAP/SMTP 服务；'
                    '163 / 126：设置 → POP3/SMTP/IMAP。'
                    '139、189、阿里云、搜狐等也在网页端开启服务后生成授权码。',
              ),
              _MailProviderHint(
                name: 'Gmail',
                description:
                    'Google 已停用账号密码登录。请先开启两步验证，在 Google 账号的'
                    '「应用专用密码」中生成 16 位密码后填入。Google Workspace 账号'
                    '可能无法生成，需要管理员开通或改用 OAuth。',
              ),
              _MailProviderHint(
                name: 'Yahoo / AOL',
                description: '需要使用应用密码，账号密码无法登录。请在账号安全设置中生成后填入。',
              ),
              _MailProviderHint(
                name: 'iCloud',
                description:
                    '需要使用 App 专用密码（Apple 账户 → 登录与安全 → '
                    'App 专用密码）。iCloud 不支持 POP3，请选择 IMAP。',
              ),
              _MailProviderHint(
                name: 'Fastmail / Zoho',
                description:
                    'Fastmail 必须使用应用密码，基础版不提供 IMAP / POP3 访问；'
                    'Zoho 开启两步验证后需要使用应用密码。',
              ),
              _MailProviderHint(
                name: 'Proton Mail',
                description:
                    '免费版不提供 IMAP / POP3；付费版也要通过桌面端 Bridge 连接。'
                    '也可以把 12306 邮件手动转发到 QQ、163 等邮箱。',
              ),
              _MailProviderHint(
                name: 'Yandex',
                description:
                    '需要在 设置 → 邮件客户端 中开启 IMAP 和「应用密码与 OAuth 令牌」，'
                    '再生成应用密码。个人账号通常要用 @ 前的用户名登录，'
                    'RailLog 按完整邮箱地址登录，可能连不上；可以改用转发到 QQ、163 邮箱。',
              ),
              _MailProviderHint(
                name: '企业 / 学校邮箱',
                description:
                    '管理员可能关闭 IMAP / POP3、要求 OAuth 登录，'
                    '或禁止向外部地址转发，需要联系管理员。',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SettingsCard(
          title: '使用说明',
          icon: Icons.help_outline,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '请先在邮箱网页端开启 IMAP 或 POP3 服务。RailLog 只读取邮件内容，'
                '不会发送或删除邮件，连接信息只保存在本机。',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'IMAP 可在服务器端按发件人、主题和时间搜索；POP3 只能按顺序'
                '逐封读取邮件头，邮件较多时会慢一些。',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '手动转发的车票如果没有解析出来，可以切换到 POP3 再读取。',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _testing ? null : _clear,
                  child: const Text('清除邮箱连接'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InlineHint extends StatelessWidget {
  const _InlineHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.tertiaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 20,
              color: colors.onTertiaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MailProviderHint extends StatelessWidget {
  const _MailProviderHint({required this.name, required this.description});

  final String name;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: name,
              style: TextStyle(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const TextSpan(text: '：'),
            TextSpan(text: description),
          ],
        ),
        style: TextStyle(color: colors.onSurfaceVariant),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: isError ? colors.errorContainer : colors.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError
                  ? colors.onErrorContainer
                  : colors.onSecondaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isError
                      ? colors.onErrorContainer
                      : colors.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
