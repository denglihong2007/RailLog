import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:raillog/src/services/ticket_12306_auth_settings.dart';
import 'package:raillog/src/services/ticket_12306_service.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/settings/settings_section.dart';
import 'package:raillog/src/widgets/settings/settings_sub_page.dart';

class Ticket12306SettingsPage extends StatefulWidget {
  const Ticket12306SettingsPage({super.key, this.service, this.serviceFactory});

  final Ticket12306Service? service;

  /// 账号密码登录使用独立会话，避免清掉当前扫码登录的 Cookie。
  final Ticket12306Service Function()? serviceFactory;

  @override
  State<Ticket12306SettingsPage> createState() =>
      _Ticket12306SettingsPageState();
}

enum _LoginMethod { account, qr }

class _Ticket12306SettingsPageState extends State<Ticket12306SettingsPage> {
  late final Ticket12306Service _service =
      widget.service ?? Ticket12306Service();
  Ticket12306Service? _accountService;

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _idSuffixController = TextEditingController();
  final _smsCodeController = TextEditingController();

  Ticket12306Credentials? _credentials;
  bool _loading = true;
  bool _checkingCredentials = false;

  Uint8List? _loginQrImage;
  String? _loginStatus;
  bool _loginStatusIsError = false;
  bool _loginBusy = false;
  int _loginGeneration = 0;
  _LoginMethod _loginMethod = _LoginMethod.account;

  bool _savePassword = true;
  bool _obscurePassword = true;
  bool _accountBusy = false;
  bool _smsRequired = false;
  bool _smsCodeSent = false;
  String? _accountStatus;
  bool _accountStatusIsError = false;
  int _accountGeneration = 0;

  Uint8List? _verifyQrImage;
  String? _verifyStatus;
  bool _verifyStatusIsError = false;
  bool _verifyBusy = false;
  int _verifyGeneration = 0;

  bool get _isLoggedIn => _credentials?.isComplete ?? false;

  bool get _canRequestSms =>
      !_accountBusy &&
      RegExp(r'^\d{3}[0-9Xx]$').hasMatch(_idSuffixController.text.trim());

  bool get _canSubmitAccount {
    if (_accountBusy) return false;
    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      return false;
    }
    if (_smsRequired) {
      return _smsCodeSent &&
          RegExp(r'^\d{6}$').hasMatch(_smsCodeController.text.trim());
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _loginGeneration++;
    _accountGeneration++;
    _verifyGeneration++;
    _closeAccountService();
    _usernameController.dispose();
    _passwordController.dispose();
    _idSuffixController.dispose();
    _smsCodeController.dispose();
    _service.dispose();
    super.dispose();
  }

  Ticket12306Service _newLoginService() =>
      widget.serviceFactory?.call() ?? widget.service ?? Ticket12306Service();

  void _closeAccountService() {
    _accountService?.dispose();
    _accountService = null;
  }

  Future<void> _load() async {
    final credentials = await Ticket12306AuthSettings.load();
    final account = await Ticket12306AuthSettings.loadAccount();
    if (!mounted) return;
    final usable = credentials?.isComplete ?? false;
    if (usable) _service.restoreCredentials(credentials!);
    _usernameController.text =
        account != null && account.username.trim().isNotEmpty
        ? account.username
        : (credentials?.username ?? '');
    _passwordController.text = account?.password ?? '';
    _savePassword = account?.savePassword ?? true;
    setState(() {
      _credentials = usable ? credentials : null;
      _loading = false;
      if (credentials != null && !usable) {
        _loginStatus = '登录凭证已过期，请重新登录';
        _loginStatusIsError = true;
        _accountStatus = '登录凭证已过期，请重新登录';
        _accountStatusIsError = true;
      }
    });
    if (usable) await _checkCredentialValidity();
  }

  /// 向 12306 确认登录与人证核验凭证是否仍然有效。
  Future<void> _checkCredentialValidity() async {
    final current = _credentials;
    if (current == null || _checkingCredentials) return;
    setState(() => _checkingCredentials = true);
    try {
      final state = await _service.checkCredentials();
      if (!mounted || _credentials != current) return;
      if (!state.loginValid) {
        await Ticket12306AuthSettings.clear();
        _service.clearSession();
        if (!mounted) return;
        setState(() {
          _credentials = null;
          _loginQrImage = null;
          _loginStatus = '登录凭证已过期，请重新登录';
          _loginStatusIsError = true;
          _accountStatus = '登录凭证已过期，请重新登录';
          _accountStatusIsError = true;
          _verifyQrImage = null;
          _verifyStatus = null;
          _verifyStatusIsError = false;
        });
        return;
      }
      final exported = _service.exportCredentials(
        invoiceVerified: state.invoiceVerified,
        loginAt: current.loginAt,
      );
      if (exported.cookies.isEmpty) return;
      final updated = Ticket12306Credentials(
        username: state.username.trim().isEmpty
            ? current.username
            : state.username,
        cookies: exported.cookies,
        loginAt: current.loginAt,
        invoiceVerified: state.invoiceVerified,
      );
      await Ticket12306AuthSettings.save(updated);
      if (!mounted) return;
      setState(() {
        _credentials = updated;
        if (current.invoiceVerified && !state.invoiceVerified) {
          _verifyStatus = '人证核验凭证已过期，请重新核验';
          _verifyStatusIsError = true;
        }
      });
    } catch (_) {
      // 网络不可用时保留上次的凭证状态，避免误判为过期。
    } finally {
      if (mounted) setState(() => _checkingCredentials = false);
    }
  }

  Future<void> _startLogin() async {
    final generation = ++_loginGeneration;
    final previous = _credentials;
    _accountGeneration++;
    _closeAccountService();
    setState(() {
      _accountBusy = false;
      _smsRequired = false;
      _smsCodeSent = false;
      _accountStatus = null;
      _accountStatusIsError = false;
      _loginBusy = true;
      _loginQrImage = null;
      _loginStatus = '正在获取登录二维码...';
      _loginStatusIsError = false;
    });
    try {
      final qr = await _service.createQrCode();
      if (!mounted || generation != _loginGeneration) return;
      setState(() {
        _loginQrImage = _decodeQrImage(qr.imageBase64);
        _loginStatus = '请使用铁路 12306 App 扫码并确认登录';
      });
      await _pollLogin(qr.uuid, generation);
    } catch (error) {
      if (!mounted || generation != _loginGeneration) return;
      if (previous != null) _service.restoreCredentials(previous);
      setState(() {
        _loginStatusIsError = true;
        _loginStatus = '登录失败：$error';
      });
    } finally {
      if (mounted && generation == _loginGeneration) {
        setState(() => _loginBusy = false);
      }
    }
  }

  Future<void> _pollLogin(String uuid, int generation) async {
    while (mounted && generation == _loginGeneration) {
      final status = await _service.checkQrStatus(uuid);
      if (!mounted || generation != _loginGeneration) return;
      setState(() {
        _loginStatusIsError = false;
        _loginStatus = status.message.isEmpty ? '等待扫码确认' : status.message;
      });
      if (status.code == '2') {
        final ticket = status.uamtk;
        if (ticket == null || ticket.isEmpty) {
          throw const Ticket12306Exception('扫码成功，但未获得登录票据');
        }
        await _completeQrLogin(ticket, generation);
        return;
      }
      if (status.code == '3') {
        throw const Ticket12306Exception('二维码已过期，请重新获取');
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> _completeQrLogin(String uamtk, int generation) async {
    setState(() => _loginStatus = '正在完成登录校验...');
    final username = await _service.completeLogin(uamtk);
    if (!mounted || generation != _loginGeneration) return;
    final credentials = _service.exportCredentials(invoiceVerified: false);
    await Ticket12306AuthSettings.save(credentials);
    if (!mounted || generation != _loginGeneration) return;
    setState(() {
      _credentials = credentials;
      _loginQrImage = null;
      _loginStatus = '登录成功：${username.isEmpty ? '已登录账号' : username}';
      _loginStatusIsError = false;
      _accountStatus = '扫码登录成功';
      _accountStatusIsError = false;
      _smsRequired = false;
      _smsCodeSent = false;
      _smsCodeController.clear();
      _idSuffixController.clear();
      _verifyQrImage = null;
      _verifyStatus = null;
      _verifyStatusIsError = false;
    });
  }

  Future<void> _startAccountLogin() async {
    if (_accountBusy) return;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _accountStatus = '请填写 12306 账号和密码';
        _accountStatusIsError = true;
      });
      return;
    }
    final generation = ++_accountGeneration;
    _loginGeneration++;
    _closeAccountService();
    final loginService = _accountService = _newLoginService();
    setState(() {
      _accountBusy = true;
      _accountStatus = '正在检查登录环境...';
      _accountStatusIsError = false;
      _loginBusy = false;
      _loginQrImage = null;
      _loginStatus = null;
      _loginStatusIsError = false;
    });
    try {
      final checkCode = await loginService.checkLoginVerify(username);
      if (!mounted || generation != _accountGeneration) return;
      if (checkCode == '3') {
        setState(() {
          _smsRequired = true;
          _smsCodeSent = false;
          _smsCodeController.clear();
          _accountStatus = '请输入账号绑定的证件号后 4 位，然后获取短信验证码';
          _accountStatusIsError = false;
        });
        return;
      }
      if (checkCode != '0') {
        throw const Ticket12306Exception('该账号登录需要滑块或额外验证，请改用扫码登录');
      }
      setState(() => _accountStatus = '正在登录...');
      final credentials = await _performAccountLogin(
        loginService,
        username: username,
        password: password,
        smsCode: '',
      );
      if (generation == _accountGeneration) _closeAccountService();
      if (!mounted || generation != _accountGeneration) return;
      _service.restoreCredentials(credentials);
      _applyAccountLogin(credentials, username);
    } catch (error) {
      if (generation == _accountGeneration) _closeAccountService();
      if (!mounted || generation != _accountGeneration) return;
      setState(() {
        _accountStatusIsError = true;
        _accountStatus = '登录失败：$error';
      });
    } finally {
      if (mounted && generation == _accountGeneration) {
        setState(() => _accountBusy = false);
      }
    }
  }

  Future<void> _submitSmsLogin() async {
    if (_accountBusy) return;
    final loginService = _accountService;
    if (loginService == null) {
      setState(() {
        _accountStatus = '验证码会话已失效，请重新登录';
        _accountStatusIsError = true;
      });
      return;
    }
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final smsCode = _smsCodeController.text.trim();
    if (smsCode.length != 6) {
      setState(() {
        _accountStatus = '请输入 6 位短信验证码';
        _accountStatusIsError = true;
      });
      return;
    }
    final generation = ++_accountGeneration;
    setState(() {
      _accountBusy = true;
      _accountStatus = '正在登录...';
      _accountStatusIsError = false;
    });
    try {
      final credentials = await _performAccountLogin(
        loginService,
        username: username,
        password: password,
        smsCode: smsCode,
      );
      if (generation == _accountGeneration) _closeAccountService();
      if (!mounted || generation != _accountGeneration) return;
      _service.restoreCredentials(credentials);
      _applyAccountLogin(credentials, username);
    } catch (error) {
      if (generation == _accountGeneration) _closeAccountService();
      if (!mounted || generation != _accountGeneration) return;
      setState(() {
        _smsRequired = false;
        _smsCodeSent = false;
        _smsCodeController.clear();
        _idSuffixController.clear();
        _accountStatusIsError = true;
        _accountStatus = '登录失败：$error';
      });
    } finally {
      if (mounted && generation == _accountGeneration) {
        setState(() => _accountBusy = false);
      }
    }
  }

  Future<Ticket12306Credentials> _performAccountLogin(
    Ticket12306Service service, {
    required String username,
    required String password,
    required String smsCode,
  }) async {
    final uamtk = await service.loginWithPassword(
      username,
      password,
      smsCode: smsCode,
    );
    await service.completeLogin(uamtk);
    final credentials = service.exportCredentials(invoiceVerified: false);
    await Ticket12306AuthSettings.save(credentials);
    await Ticket12306AuthSettings.saveAccount(
      username: username,
      password: password,
      savePassword: _savePassword,
    );
    return credentials;
  }

  void _applyAccountLogin(Ticket12306Credentials credentials, String username) {
    if (!_savePassword) _passwordController.clear();
    setState(() {
      _credentials = credentials;
      _smsRequired = false;
      _smsCodeSent = false;
      _smsCodeController.clear();
      _idSuffixController.clear();
      _loginQrImage = null;
      _loginStatus = null;
      _loginStatusIsError = false;
      _verifyQrImage = null;
      _verifyStatus = null;
      _verifyStatusIsError = false;
      _accountStatus =
          '登录成功：${credentials.username.trim().isEmpty ? username : credentials.username}';
      _accountStatusIsError = false;
    });
  }

  Future<void> _requestSmsCode() async {
    if (_accountBusy) return;
    final loginService = _accountService;
    if (loginService == null) {
      setState(() {
        _smsRequired = false;
        _smsCodeSent = false;
        _accountStatus = '验证码会话已失效，请重新登录';
        _accountStatusIsError = true;
      });
      return;
    }
    final username = _usernameController.text.trim();
    final idSuffix = _idSuffixController.text.trim();
    if (!RegExp(r'^\d{3}[0-9Xx]$').hasMatch(idSuffix)) {
      setState(() {
        _accountStatus = '请输入账号绑定证件号的后 4 位';
        _accountStatusIsError = true;
      });
      return;
    }
    final generation = ++_accountGeneration;
    setState(() {
      _accountBusy = true;
      _accountStatus = '正在发送短信验证码...';
      _accountStatusIsError = false;
    });
    try {
      await loginService.requestSmsCode(username: username, idSuffix: idSuffix);
      if (!mounted || generation != _accountGeneration) return;
      setState(() {
        _smsCodeSent = true;
        _accountStatus = '验证码已发送，请输入 6 位短信验证码';
        _accountStatusIsError = false;
      });
    } catch (error) {
      if (!mounted || generation != _accountGeneration) return;
      setState(() {
        _accountStatusIsError = true;
        _accountStatus = '发送验证码失败：$error';
      });
    } finally {
      if (mounted && generation == _accountGeneration) {
        setState(() => _accountBusy = false);
      }
    }
  }

  void _resetSmsFlow() {
    _accountGeneration++;
    _closeAccountService();
    setState(() {
      _smsRequired = false;
      _smsCodeSent = false;
      _smsCodeController.clear();
      _idSuffixController.clear();
      _accountStatus = null;
      _accountStatusIsError = false;
      _accountBusy = false;
    });
  }

  Future<void> _onSavePasswordChanged(bool value) async {
    setState(() => _savePassword = value);
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (!value) {
      await Ticket12306AuthSettings.saveAccount(
        username: username,
        password: '',
        savePassword: false,
      );
    } else if (username.isNotEmpty && password.isNotEmpty) {
      await Ticket12306AuthSettings.saveAccount(
        username: username,
        password: password,
        savePassword: true,
      );
    }
  }

  Future<void> _startVerification() async {
    if (!_isLoggedIn) return;
    final generation = ++_verifyGeneration;
    setState(() {
      _verifyBusy = true;
      _verifyQrImage = null;
      _verifyStatus = '正在获取人证核验二维码...';
      _verifyStatusIsError = false;
    });
    try {
      final qr = await _service.createInvoiceVerificationQr();
      if (!mounted || generation != _verifyGeneration) return;
      setState(() {
        _verifyQrImage = _decodeQrImage(qr.imageBase64);
        _verifyStatus = '请使用铁路 12306 App 扫码完成人证核验';
      });
      await _pollVerification(qr.uuid, generation);
    } catch (error) {
      if (!mounted || generation != _verifyGeneration) return;
      setState(() {
        _verifyStatusIsError = true;
        _verifyStatus = '核验失败：$error';
      });
    } finally {
      if (mounted && generation == _verifyGeneration) {
        setState(() => _verifyBusy = false);
      }
    }
  }

  Future<void> _pollVerification(String uuid, int generation) async {
    while (mounted && generation == _verifyGeneration) {
      final status = await _service.checkInvoiceVerificationQr(uuid);
      if (!mounted || generation != _verifyGeneration) return;
      if (status.code == '2') {
        await _completeVerification(generation);
        return;
      }
      if (status.code != '0' && status.code != '1') {
        throw const Ticket12306Exception('人证核验状态异常，请重新获取二维码');
      }
      setState(() {
        _verifyStatusIsError = false;
        _verifyStatus = status.message;
      });
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> _completeVerification(int generation) async {
    final credentials = _credentials;
    if (credentials == null || !_service.hasSession) {
      throw const Ticket12306AuthException('登录凭证已失效，请重新登录');
    }
    final updated = _service.exportCredentials(
      invoiceVerified: true,
      loginAt: credentials.loginAt,
    );
    await Ticket12306AuthSettings.save(updated);
    if (!mounted || generation != _verifyGeneration) return;
    setState(() {
      _credentials = updated;
      _verifyQrImage = null;
      _verifyStatus = '人证核验已通过，可加载电子发票和本人车票';
      _verifyStatusIsError = false;
    });
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除 12306 登录数据'),
        content: const Text('将清除登录凭证、人证核验凭证和已保存的账号密码，之后需要重新登录。'),
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
    _loginGeneration++;
    _accountGeneration++;
    _verifyGeneration++;
    _closeAccountService();
    _service.clearSession();
    await Ticket12306AuthSettings.clear();
    await Ticket12306AuthSettings.clearAccount();
    if (!mounted) return;
    _usernameController.clear();
    _passwordController.clear();
    _idSuffixController.clear();
    _smsCodeController.clear();
    setState(() {
      _credentials = null;
      _loginQrImage = null;
      _loginStatus = null;
      _loginStatusIsError = false;
      _loginBusy = false;
      _accountBusy = false;
      _smsRequired = false;
      _smsCodeSent = false;
      _accountStatus = null;
      _accountStatusIsError = false;
      _verifyQrImage = null;
      _verifyStatus = null;
      _verifyStatusIsError = false;
      _verifyBusy = false;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已清除 12306 登录数据')));
  }

  @override
  Widget build(BuildContext context) {
    final credentials = _credentials;
    if (_loading) {
      return const SettingsSubPage(
        title: '12306 导入',
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }
    return SettingsSubPage(
      title: '12306 导入',
      children: [
        const SettingsSectionHeader(title: '登录'),
        const SizedBox(height: AppSpacing.sm),
        if (_isLoggedIn && credentials != null) ...[
          _SessionSummaryCard(
            credentials: credentials,
            checking: _checkingCredentials,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _buildLoginCard(),
        const SizedBox(height: AppSpacing.xxl),
        const SettingsSectionHeader(title: '人证核验'),
        const SizedBox(height: AppSpacing.sm),
        _buildVerificationCard(),
        const SizedBox(height: AppSpacing.xxl),
        _buildUsageCard(),
      ],
    );
  }

  void _selectLoginMethod(_LoginMethod method) {
    if (method == _loginMethod) return;
    if (_loginMethod == _LoginMethod.qr) {
      _cancelQrLogin();
    } else {
      _cancelAccountLogin();
    }
    setState(() => _loginMethod = method);
  }

  void _cancelQrLogin() {
    _loginGeneration++;
    final current = _credentials;
    if (current != null) _service.restoreCredentials(current);
    _loginBusy = false;
    _loginQrImage = null;
    _loginStatus = null;
    _loginStatusIsError = false;
  }

  void _cancelAccountLogin() {
    _accountGeneration++;
    _closeAccountService();
    _accountBusy = false;
    _smsRequired = false;
    _smsCodeSent = false;
    _smsCodeController.clear();
    _idSuffixController.clear();
    _accountStatus = null;
    _accountStatusIsError = false;
  }

  Widget _buildLoginCard() {
    return SettingsCard(
      title: '登录方式',
      icon: Icons.login,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<_LoginMethod>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _LoginMethod.account, label: Text('账号密码')),
                ButtonSegment(value: _LoginMethod.qr, label: Text('扫码登录')),
              ],
              selected: {_loginMethod},
              onSelectionChanged: (values) => _selectLoginMethod(values.first),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_loginMethod == _LoginMethod.account)
            _buildAccountLoginBody()
          else
            _buildQrLoginBody(),
        ],
      ),
    );
  }

  Widget _buildVerificationCard() {
    final credentials = _credentials;
    return SettingsCard(
      title: '人证核验（可选）',
      icon: Icons.domain_verification_outlined,
      trailing:
          _isLoggedIn &&
              !_verifyBusy &&
              !_verifyStatusIsError &&
              _verifyQrImage == null &&
              (credentials?.invoiceVerified ?? false)
          ? TextButton(onPressed: _startVerification, child: const Text('重新核验'))
          : null,
      child: _buildVerificationBody(),
    );
  }

  Widget _buildUsageCard() {
    final colors = Theme.of(context).colorScheme;
    return SettingsCard(
      title: '说明与清理',
      icon: Icons.help_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '账号密码只保存在本机，登录时用 SM4 加密提交给 12306。',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '人证核验可选：核验后可加载近 180 天电子发票和近 1 年本人车票；'
            '不核验也能导入近 1 个月订单。',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '打开此页会检查登录与人证核验凭证是否过期；'
            '需要短信验证时请输入账号绑定证件号的后 4 位。',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _clear,
              child: const Text('清除 12306 登录数据'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountLoginBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _usernameController,
          readOnly: _smsRequired,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: '12306 账号',
            helperText: '手机号、邮箱或用户名',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _passwordController,
          readOnly: _smsRequired,
          obscureText: _obscurePassword,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: '密码',
            helperText: '登录时用 SM4 加密提交给 12306',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          onFieldSubmitted: (_) => _startAccountLogin(),
        ),
        Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _onSavePasswordChanged(!_savePassword),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _savePassword,
                      onChanged: (value) =>
                          _onSavePasswordChanged(value ?? false),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    const Text('记住密码'),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Text(
              '仅保存在本机',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (_smsRequired) ...[
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _idSuffixController,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '证件号后 4 位',
              helperText: '账号绑定的身份证最后 4 位，最后一位可以是 X',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _smsCodeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: '短信验证码',
                    helperText: '12306 发送的 6 位验证码',
                    prefixIcon: Icon(Icons.sms_outlined),
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (_) => _submitSmsLogin(),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OutlinedButton(
                  onPressed: _canRequestSms ? _requestSmsCode : null,
                  child: Text(_smsCodeSent ? '重新发送' : '获取验证码'),
                ),
              ),
            ],
          ),
        ],
        if (_accountStatus != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _FormStatus(message: _accountStatus!, isError: _accountStatusIsError),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _canSubmitAccount
                    ? (_smsRequired ? _submitSmsLogin : _startAccountLogin)
                    : null,
                icon: _accountBusy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(_isLoggedIn ? '重新登录' : '登录'),
              ),
            ),
            if (_smsRequired) ...[
              const SizedBox(width: AppSpacing.md),
              OutlinedButton(
                onPressed: _accountBusy ? null : _resetSmsFlow,
                child: const Text('返回'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildQrLoginBody() {
    final scanRequested = _loginBusy || _loginQrImage != null;
    final showPanel = !_isLoggedIn || scanRequested || _loginStatusIsError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (scanRequested) ...[
          const _SmallWindowTip(),
          const SizedBox(height: AppSpacing.md),
        ],
        if (showPanel)
          _QrPanel(
            icon: Icons.phone_android,
            title: '使用 12306 App 扫码登录',
            qrImage: _loginQrImage,
            status: _loginStatus,
            statusIsError: _loginStatusIsError,
            isBusy: _loginBusy,
            actionLabel: _loginQrImage == null ? '获取二维码' : '重新获取',
            onAction: _startLogin,
          )
        else ...[
          const _CredentialStatus(
            icon: Icons.verified_user_outlined,
            title: '当前已登录',
            subtitle: '如需切换账号，可以重新扫码登录。',
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: _startLogin,
            icon: const Icon(Icons.qr_code_2),
            label: const Text('扫码重新登录'),
          ),
        ],
      ],
    );
  }

  Widget _buildVerificationBody() {
    final colors = Theme.of(context).colorScheme;
    final credentials = _credentials;
    if (!_isLoggedIn || credentials == null) {
      return Text(
        '先完成登录凭证配置，再进行人证核验。',
        style: TextStyle(color: colors.onSurfaceVariant),
      );
    }
    final scanRequested = _verifyBusy || _verifyQrImage != null;
    final showQrPanel =
        scanRequested || _verifyStatusIsError || !credentials.invoiceVerified;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (scanRequested) ...[
          const _SmallWindowTip(),
          const SizedBox(height: AppSpacing.md),
        ],
        if (credentials.invoiceVerified && !showQrPanel)
          const _CredentialStatus(
            icon: Icons.verified_outlined,
            title: '人证核验已通过',
            subtitle: '可加载电子发票行程与本人车票',
          )
        else if (!showQrPanel)
          Text(
            '人证核验为可选步骤。完成后可加载近 180 天电子发票行程和近 1 年本人车票；'
            '不核验也可以导入近 1 个月订单。',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        if (credentials.invoiceVerified && showQrPanel)
          const SizedBox(height: AppSpacing.md),
        if (showQrPanel)
          _QrPanel(
            icon: Icons.domain_verification_outlined,
            title: '扫码完成人证核验',
            qrImage: _verifyQrImage,
            status: _verifyStatus,
            statusIsError: _verifyStatusIsError,
            isBusy: _verifyBusy,
            actionLabel: _verifyQrImage == null ? '开始核验' : '重新获取',
            onAction: _startVerification,
          ),
      ],
    );
  }
}

class _SmallWindowTip extends StatelessWidget {
  const _SmallWindowTip();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard.filled(
      color: colors.tertiaryContainer,
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          Icons.picture_in_picture_alt_outlined,
          color: colors.onTertiaryContainer,
        ),
        title: Text(
          '建议开启小窗模式',
          style: TextStyle(color: colors.onTertiaryContainer),
        ),
        subtitle: Text(
          '避免切回应用时网络请求中断',
          style: TextStyle(color: colors.onTertiaryContainer),
        ),
      ),
    );
  }
}

class _SessionSummaryCard extends StatelessWidget {
  const _SessionSummaryCard({
    required this.credentials,
    required this.checking,
  });

  final Ticket12306Credentials credentials;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final username = credentials.username.trim();
    final details = [
      '登录于 ${_formatDateTime(credentials.loginAt)}',
      credentials.invoiceVerified ? '人证核验已完成' : '人证核验未完成',
      if (checking) '正在检查凭证...',
    ].join(' · ');
    return AppCard.filled(
      color: colors.primaryContainer,
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.verified_user_outlined, color: colors.primary),
        title: Text(username.isEmpty ? '已登录 12306' : '已登录：$username'),
        subtitle: Text(details),
      ),
    );
  }
}

class _CredentialStatus extends StatelessWidget {
  const _CredentialStatus({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: colors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(color: colors.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

class _FormStatus extends StatelessWidget {
  const _FormStatus({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: isError ? colors.errorContainer : colors.secondaryContainer,
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
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

class _QrPanel extends StatelessWidget {
  const _QrPanel({
    required this.icon,
    required this.title,
    required this.qrImage,
    required this.status,
    required this.statusIsError,
    required this.isBusy,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final Uint8List? qrImage;
  final String? status;
  final bool statusIsError;
  final bool isBusy;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 32, color: colors.primary),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (status != null) ...[
          const SizedBox(height: 6),
          Text(
            status!,
            style: TextStyle(
              color: statusIsError ? colors.error : colors.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: isBusy ? null : onAction,
          icon: isBusy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.qr_code_2),
          label: Text(actionLabel),
        ),
      ],
    );
    final qr = qrImage == null
        ? null
        : Container(
            width: 168,
            height: 168,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Image.memory(qrImage!, gaplessPlayback: true),
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              details,
              if (qr != null) ...[const SizedBox(height: 20), Align(child: qr)],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: details),
            if (qr != null) ...[const SizedBox(width: 28), qr],
          ],
        );
      },
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

Uint8List _decodeQrImage(String source) {
  final comma = source.indexOf(',');
  return base64Decode(comma >= 0 ? source.substring(comma + 1) : source);
}
