import 'package:flutter/material.dart';
import 'package:raillog/src/models/user_profile.dart';
import 'package:raillog/src/pages/about_page.dart';
import 'package:raillog/src/pages/auth_page.dart';
import 'package:raillog/src/pages/password_reset_page.dart';
import 'package:raillog/src/services/cloud_sync_service.dart';
import 'package:raillog/src/services/session_service.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SessionService.instance,
      builder: (context, _) {
        final user = SessionService.instance.user;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: user == null
                    ? _SignedOutSettings(onLogin: () => _openLogin(context))
                    : _SignedInSettings(user: user),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openLogin(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AuthPage()));
  }
}

class _SignedOutSettings extends StatelessWidget {
  const _SignedOutSettings({required this.onLogin});
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Icon(Icons.account_circle_outlined, size: 72, color: colors.primary),
        const SizedBox(height: 16),
        Text(
          '登录 RailLog',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          '登录后可同步行程和个人资料',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onLogin,
          icon: const Icon(Icons.login),
          label: const Text('登录或注册'),
        ),
        const SizedBox(height: 32),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.cloud_off_outlined),
          title: const Text('本地模式'),
          subtitle: const Text('当前行程仅保存在此设备'),
        ),
        const Divider(),
        _aboutTile(context),
      ],
    );
  }
}

class _SignedInSettings extends StatelessWidget {
  const _SignedInSettings({required this.user});
  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _Avatar(user: user, radius: 34),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.email,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (user.bio?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 6),
                    Text(
                      user.bio!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: '编辑个人资料',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ProfileEditPage(user: user)),
              ),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(),
        Text('云同步', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: CloudSyncService.instance,
          builder: (context, _) {
            final sync = CloudSyncService.instance;
            return Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.sync_lock_outlined),
                  title: const Text('自动同步'),
                  subtitle: const Text('行程新增、修改或删除后自动同步到云端'),
                  value: sync.autoSyncEnabled,
                  onChanged: (value) => sync.setAutoSyncEnabled(value),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    sync.lastError == null
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                  ),
                  title: Text(sync.isSyncing ? '正在同步' : '行程云同步'),
                  subtitle: Text(_syncSubtitle(sync)),
                  trailing: IconButton(
                    tooltip: '立即同步',
                    onPressed: sync.isSyncing ? null : () => _sync(context),
                    icon: sync.isSyncing
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                  ),
                ),
              ],
            );
          },
        ),
        const Divider(),
        Text('账号', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_reset_outlined),
          title: const Text('重置密码'),
          subtitle: Text('通过 ${user.email} 接收验证码'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _resetPassword(context),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.logout),
          title: const Text('退出登录'),
          onTap: () => _logout(context),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          textColor: Theme.of(context).colorScheme.error,
          iconColor: Theme.of(context).colorScheme.error,
          leading: const Icon(Icons.person_remove_outlined),
          title: const Text('注销账号'),
          subtitle: const Text('云端账号和云端行程将永久删除'),
          onTap: () => _deleteAccount(context),
        ),
        const Divider(),
        _aboutTile(context, contentPadding: EdgeInsets.zero),
      ],
    );
  }

  String _syncSubtitle(CloudSyncService sync) {
    if (sync.lastError != null) return sync.lastError!;
    final value = sync.lastSyncedAt;
    if (value == null) return '尚未同步';
    final local = value.toLocal();
    return '上次同步 ${local.year}-${_two(local.month)}-${_two(local.day)} '
        '${_two(local.hour)}:${_two(local.minute)}';
  }

  Future<void> _sync(BuildContext context) async {
    try {
      await CloudSyncService.instance.sync();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('同步完成')));
      }
    } on SessionException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    await SessionService.instance.logout();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已退出登录')));
    }
  }

  Future<void> _resetPassword(BuildContext context) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PasswordResetPage(initialEmail: user.email),
      ),
    );
    if (changed != true || !context.mounted) return;
    await SessionService.instance.invalidate();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('密码已重置，请使用新密码重新登录')));
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('注销账号？'),
        content: const Text('此操作无法撤销。账号资料和所有云端行程都会永久删除，本机行程仍会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('永久注销'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await SessionService.instance.deleteAccount();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('账号已注销')));
      }
    } on SessionException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key, required this.user});
  final UserProfile user;

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _avatarController;
  late final TextEditingController _bioController;
  late bool _showEmail;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.displayName);
    _avatarController = TextEditingController(text: widget.user.avatarUrl);
    _bioController = TextEditingController(text: widget.user.bio);
    _showEmail = widget.user.showEmailOnProfile;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _avatarController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await SessionService.instance.updateProfile(
        displayName: _nameController.text,
        avatarUrl: _avatarController.text,
        bio: _bioController.text,
        showEmailOnProfile: _showEmail,
      );
      if (mounted) Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('个人资料')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameController,
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
                    TextFormField(
                      controller: _avatarController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: '头像图片地址',
                        prefixIcon: Icon(Icons.image_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _bioController,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 300,
                      decoration: const InputDecoration(
                        labelText: '个人简介',
                        prefixIcon: Icon(Icons.notes_outlined),
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('在个人资料中公开邮箱'),
                      value: _showEmail,
                      onChanged: (value) => setState(() => _showEmail = value),
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _save,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: const Text('保存'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.radius});
  final UserProfile user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = user.avatarUrl?.trim();
    return CircleAvatar(
      radius: radius,
      child: url == null || url.isEmpty
          ? Text(
              user.displayName.isEmpty
                  ? '?'
                  : user.displayName[0].toUpperCase(),
              style: TextStyle(fontSize: radius * 0.7),
            )
          : ClipOval(
              child: Image.network(
                url,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.person_outline),
              ),
            ),
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

Widget _aboutTile(BuildContext context, {EdgeInsetsGeometry? contentPadding}) {
  return ListTile(
    contentPadding: contentPadding,
    leading: const Icon(Icons.info_outline),
    title: const Text('关于'),
    subtitle: const Text('软件信息、API 与项目链接'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AboutPage())),
  );
}
