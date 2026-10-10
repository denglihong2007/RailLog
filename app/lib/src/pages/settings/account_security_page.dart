import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:raillog/src/models/user_profile.dart';
import 'package:raillog/src/pages/auth_page.dart';
import 'package:raillog/src/pages/password_reset_page.dart';
import 'package:raillog/src/pages/settings/profile_edit_page.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';
import 'package:raillog/src/widgets/settings/settings_section.dart';
import 'package:raillog/src/widgets/settings/settings_sub_page.dart';

class AccountSecurityPage extends StatelessWidget {
  const AccountSecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSubPage(
      title: '账户与安全',
      children: [
        AnimatedBuilder(
          animation: SessionService.instance,
          builder: (context, _) {
            final user = SessionService.instance.user;
            if (user == null) {
              return SettingsCard(
                title: '账户',
                icon: Icons.account_circle_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '登录 RailLog',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '登录后可同步行程和个人资料',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: () => _openLogin(context),
                      icon: const Icon(Icons.login),
                      label: const Text('登录或注册'),
                    ),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _profileCard(context, user),
                const SizedBox(height: AppSpacing.md),
                _securityCard(context, user),
              ],
            );
          },
        ),
      ],
    );
  }
}

Widget _profileCard(BuildContext context, UserProfile user) {
  return SettingsCard(
    title: '个人资料',
    icon: Icons.person_outline,
    child: Row(
      children: [
        UserAvatar(name: user.displayName, imageUrl: user.avatarUrl, size: 60),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.displayName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                user.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ID  ',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Expanded(
                    child: Tooltip(
                      message: '长按复制 ID',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.extraSmall),
                        onLongPress: () => _copyUserId(context, user.id),
                        child: Text(
                          user.id,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (user.bio?.isNotEmpty ?? false) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(user.bio!, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: '编辑个人资料',
          onPressed: () => Navigator.of(context).push<void>(
            m3PageRoute(builder: (_) => ProfileEditPage(user: user)),
          ),
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
    ),
  );
}

Widget _securityCard(BuildContext context, UserProfile user) {
  final colors = Theme.of(context).colorScheme;
  return SettingsCard(
    title: '账号安全',
    icon: Icons.security_outlined,
    child: Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_reset_outlined),
          title: const Text('重置密码'),
          subtitle: Text('通过 ${user.email} 接收验证码'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _resetPassword(context, user),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.logout),
          title: const Text('退出登录'),
          onTap: () => _logout(context),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          textColor: colors.error,
          iconColor: colors.error,
          leading: const Icon(Icons.person_remove_outlined),
          title: const Text('注销账号'),
          subtitle: const Text('云端账号和云端行程将永久删除'),
          onTap: () => _deleteAccount(context),
        ),
      ],
    ),
  );
}

Future<void> _openLogin(BuildContext context) async {
  await Navigator.of(
    context,
  ).push<void>(m3PageRoute(builder: (_) => const AuthPage()));
}

Future<void> _copyUserId(BuildContext context, String userId) async {
  await Clipboard.setData(ClipboardData(text: userId));
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('ID 已复制')));
}

Future<void> _logout(BuildContext context) async {
  await SessionService.instance.logout();
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已退出登录')));
  }
}

Future<void> _resetPassword(BuildContext context, UserProfile user) async {
  final changed = await Navigator.of(context).push<bool>(
    m3PageRoute(
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
