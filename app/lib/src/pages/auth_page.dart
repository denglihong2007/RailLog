import 'package:flutter/material.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/pages/password_reset_page.dart';
import 'package:raillog/src/widgets/email_verification_field.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

enum _AuthMode { login, register }

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _verificationCodeController = TextEditingController();
  final _confirmController = TextEditingController();
  _AuthMode _mode = _AuthMode.login;
  bool _busy = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _verificationCodeController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      if (_mode == _AuthMode.login) {
        await SessionService.instance.login(
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        await SessionService.instance.register(
          email: _emailController.text,
          displayName: _nameController.text,
          password: _passwordController.text,
          verificationCode: _verificationCodeController.text,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on SessionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() => Navigator.of(context).push(
    m3PageRoute(
      builder: (_) => PasswordResetPage(initialEmail: _emailController.text),
    ),
  );

  Future<String> _sendRegistrationCode() {
    final email = _emailController.text.trim();
    if (!email.contains('@') || email.startsWith('@') || email.endsWith('@')) {
      throw const SessionException('请输入有效邮箱');
    }
    return SessionService.instance.sendVerificationCode(
      email: email,
      purpose: 'register',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRegister = _mode == _AuthMode.register;
    return Scaffold(
      appBar: AppBar(title: Text(isRegister ? '注册账号' : '登录')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<_AuthMode>(
                    segments: const [
                      ButtonSegment(
                        value: _AuthMode.login,
                        icon: Icon(Icons.login),
                        label: Text('登录'),
                      ),
                      ButtonSegment(
                        value: _AuthMode.register,
                        icon: Icon(Icons.person_add_outlined),
                        label: Text('注册'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: _busy
                        ? null
                        : (value) => setState(() => _mode = value.first),
                  ),
                  const SizedBox(height: 28),
                  if (isRegister) ...[
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '昵称',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 2
                          ? '昵称至少需要 2 个字符'
                          : null,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '邮箱',
                      prefixIcon: Icon(Icons.mail_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        !(value?.contains('@') ?? false) ? '请输入有效邮箱' : null,
                  ),
                  const SizedBox(height: 16),
                  if (isRegister) ...[
                    EmailVerificationField(
                      controller: _verificationCodeController,
                      enabled: !_busy,
                      onSend: _sendRegistrationCode,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: isRegister
                        ? TextInputAction.next
                        : TextInputAction.done,
                    onFieldSubmitted: isRegister ? null : (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: '密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) =>
                        (value?.length ?? 0) < 8 ? '密码至少需要 8 个字符' : null,
                  ),
                  if (isRegister) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: '确认密码',
                        prefixIcon: Icon(Icons.lock_reset_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => value != _passwordController.text
                          ? '两次输入的密码不一致'
                          : null,
                    ),
                  ],
                  if (!isRegister)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _forgotPassword,
                        child: const Text('忘记密码'),
                      ),
                    )
                  else
                    const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isRegister
                                ? Icons.person_add_outlined
                                : Icons.login,
                          ),
                    label: Text(isRegister ? '创建账号' : '登录'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
