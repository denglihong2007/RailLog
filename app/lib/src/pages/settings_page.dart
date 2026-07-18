import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:raillog/src/models/user_profile.dart';
import 'package:raillog/src/pages/about_page.dart';
import 'package:raillog/src/pages/auth_page.dart';
import 'package:raillog/src/pages/password_reset_page.dart';
import 'package:raillog/src/pages/update_log_page.dart';
import 'package:raillog/src/services/cloud_sync_service.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/services/theme_settings.dart';
import 'package:raillog/src/services/ticket_generator_settings.dart';
import 'package:raillog/src/services/trip_excel_export_service.dart';
import 'package:raillog/src/widgets/cached_avatar.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SessionService.instance,
      builder: (context, _) {
        final user = SessionService.instance.user;
        return ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '设置',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      user == null
                          ? _SignedOutSettings(
                              onLogin: () => _openLogin(context),
                            )
                          : _SignedInSettings(user: user),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SettingsCategoryHeader(title: '账户'),
        const SizedBox(height: 8),
        _SettingsCard(
          title: '账户',
          icon: Icons.account_circle_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('登录 RailLog', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '登录后可同步行程和个人资料',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login),
                label: const Text('登录或注册'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const _SettingsCategoryHeader(title: '个性化'),
        const SizedBox(height: 8),
        _appearanceSettings(context),
        const SizedBox(height: 12),
        const _TicketGeneratorSettingsSection(),
        const SizedBox(height: 24),
        const _SettingsCategoryHeader(title: '数据与存储'),
        const SizedBox(height: 8),
        const _DataExportSection(),
        const SizedBox(height: 12),
        const _SettingsCard(
          title: '存储',
          icon: Icons.storage_outlined,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('本地模式'),
            subtitle: Text('当前行程仅保存在此设备'),
          ),
        ),
        const SizedBox(height: 24),
        const _SettingsCategoryHeader(title: '应用'),
        const SizedBox(height: 8),
        _applicationSettings(context),
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
        const _SettingsCategoryHeader(title: '账户'),
        const SizedBox(height: 8),
        _SettingsCard(
          title: '个人资料',
          icon: Icons.person_outline,
          child: Row(
            children: [
              _Avatar(user: user, radius: 30),
              const SizedBox(width: 14),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (user.bio?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 5),
                      Text(
                        user.bio!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: '编辑个人资料',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProfileEditPage(user: user),
                  ),
                ),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const _SettingsCategoryHeader(title: '个性化'),
        const SizedBox(height: 8),
        _appearanceSettings(context),
        const SizedBox(height: 12),
        const _TicketGeneratorSettingsSection(),
        const SizedBox(height: 24),
        const _SettingsCategoryHeader(title: '同步与数据'),
        const SizedBox(height: 8),
        _SettingsCard(
          title: '云同步',
          icon: Icons.cloud_sync_outlined,
          child: AnimatedBuilder(
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
                  const Divider(height: 1),
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
        ),
        const SizedBox(height: 12),
        const _DataExportSection(),
        const SizedBox(height: 24),
        const _SettingsCategoryHeader(title: '安全'),
        const SizedBox(height: 8),
        _SettingsCard(
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
                onTap: () => _resetPassword(context),
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
                textColor: Theme.of(context).colorScheme.error,
                iconColor: Theme.of(context).colorScheme.error,
                leading: const Icon(Icons.person_remove_outlined),
                title: const Text('注销账号'),
                subtitle: const Text('云端账号和云端行程将永久删除'),
                onTap: () => _deleteAccount(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const _SettingsCategoryHeader(title: '应用'),
        const SizedBox(height: 8),
        _applicationSettings(context),
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

class _SettingsCategoryHeader extends StatelessWidget {
  const _SettingsCategoryHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colors.primary),
                const SizedBox(width: 10),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _DataExportSection extends StatefulWidget {
  const _DataExportSection();

  @override
  State<_DataExportSection> createState() => _DataExportSectionState();
}

class _DataExportSectionState extends State<_DataExportSection> {
  bool _isExporting = false;

  Future<void> _export() async {
    setState(() => _isExporting = true);
    try {
      final result = await TripExcelExportService.exportVisibleTrips();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已导出 ${result.tripCount} 条行程\n保存位置：${result.savedPath}',
          ),
        ),
      );
    } on TripExcelExportException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：$error')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: '数据',
      icon: Icons.table_chart_outlined,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.table_view_outlined),
        title: const Text('导出行程到 Excel'),
        subtitle: const Text('保存到系统默认位置，并导出当前可见的全部行程详情'),
        trailing: _isExporting
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.download_outlined),
        onTap: _isExporting ? null : _export,
      ),
    );
  }
}

class _TicketGeneratorSettingsSection extends StatefulWidget {
  const _TicketGeneratorSettingsSection();

  @override
  State<_TicketGeneratorSettingsSection> createState() =>
      _TicketGeneratorSettingsSectionState();
}

class _TicketGeneratorSettingsSectionState
    extends State<_TicketGeneratorSettingsSection> {
  late final TextEditingController _passengerController;
  late final TextEditingController _maskedIdController;
  late final TextEditingController _serialPrefixController;

  @override
  void initState() {
    super.initState();
    final settings = TicketGeneratorSettings.instance;
    _passengerController = TextEditingController(text: settings.passenger);
    _maskedIdController = TextEditingController(text: settings.maskedId);
    _serialPrefixController = TextEditingController(
      text: settings.serialPrefix,
    );
  }

  @override
  void dispose() {
    _passengerController.dispose();
    _maskedIdController.dispose();
    _serialPrefixController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: '火车票生成器',
      icon: Icons.confirmation_number_outlined,
      child: AnimatedBuilder(
        animation: TicketGeneratorSettings.instance,
        builder: (context, _) {
          final settings = TicketGeneratorSettings.instance;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('默认车票展示样式', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<TicketDisplayStyle>(
                segments: const [
                  ButtonSegment(
                    value: TicketDisplayStyle.red,
                    icon: Icon(Icons.confirmation_number_outlined),
                    label: Text('红票'),
                  ),
                  ButtonSegment(
                    value: TicketDisplayStyle.blue,
                    icon: Icon(Icons.airplane_ticket_outlined),
                    label: Text('蓝票'),
                  ),
                  ButtonSegment(
                    value: TicketDisplayStyle.md3,
                    icon: Icon(Icons.view_agenda_outlined),
                    label: Text('MD3'),
                  ),
                ],
                selected: {settings.displayStyle},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    settings.setDisplayStyle(selection.single),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.ac_unit_outlined),
                title: const Text('普速显示“新空调”'),
                subtitle: const Text('硬座、硬卧、软座和软卧等席别自动添加前缀'),
                value: settings.showNewAirConditioned,
                onChanged: settings.setShowNewAirConditioned,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _passengerController,
                decoration: const InputDecoration(
                  labelText: '默认乘车人',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                maxLength: 30,
                textInputAction: TextInputAction.next,
                onChanged: settings.setPassenger,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入默认乘车人' : null,
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _maskedIdController,
                decoration: const InputDecoration(
                  labelText: '脱敏身份证号码',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
                maxLength: 30,
                textInputAction: TextInputAction.next,
                onChanged: settings.setMaskedId,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入脱敏身份证号码' : null,
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _serialPrefixController,
                decoration: InputDecoration(
                  labelText: '票号前缀',
                  helperText: '21 位票号的前 14 位',
                  prefixIcon: const Icon(Icons.numbers_outlined),
                  suffixIcon: IconButton(
                    tooltip: '票号构成说明',
                    onPressed: () => _showSerialNumberHelp(context),
                    icon: const Icon(Icons.help_outline),
                  ),
                  border: const OutlineInputBorder(),
                ),
                maxLength: 14,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: settings.setSerialPrefix,
                validator: (value) => RegExp(r'^\d{14}$').hasMatch(value ?? '')
                    ? null
                    : '请输入 14 位数字',
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showSerialNumberHelp(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('铁路磁票票号说明'),
      content: const SingleChildScrollView(
        child: Text(
          '铁路磁票（报销凭证）的21位票号由以下五部分顺序构成：\n\n'
          '• 前5位：数字格式的车站TMIS码（可前往 rail.re 查询具体车站）；\n'
          '• 第6至7位：出票机器类型（00-09为人工售票窗口，20-29为车票代售点，30-39为自动售票机）；\n'
          '• 第8至10位：3位数字的出票机器编号；\n'
          '• 第11至14位：MMDD格式的4位结算日期（一般为乘车日期的下一天）；\n'
          '• 最后7位：票纸编号（通常由1位字母和6位数字组合而成，该软件自动生成而无需设置）。',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
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
    return CachedAvatar(
      name: user.displayName,
      imageUrl: user.avatarUrl,
      size: radius * 2,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      textStyle: TextStyle(fontSize: radius * 0.7),
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

Widget _appearanceSettings(BuildContext context) {
  return _SettingsCard(
    title: '外观',
    icon: Icons.palette_outlined,
    child: AnimatedBuilder(
      animation: ThemeSettings.instance,
      builder: (context, _) {
        final settings = ThemeSettings.instance;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<AppThemePreference>(
              segments: const [
                ButtonSegment(
                  value: AppThemePreference.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('系统'),
                ),
                ButtonSegment(
                  value: AppThemePreference.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('浅色'),
                ),
                ButtonSegment(
                  value: AppThemePreference.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('深色'),
                ),
              ],
              selected: {settings.preference},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  settings.setPreference(selection.single),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.format_paint_outlined),
              title: const Text('跟随系统主题色'),
              subtitle: const Text('可用时使用设备动态配色'),
              value: settings.useSystemColor,
              onChanged: settings.setUseSystemColor,
            ),
            if (!settings.useSystemColor)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _ThemeColorSwatch(color: settings.seedColor),
                title: const Text('主题色'),
                subtitle: Text(settings.seedColorLabel),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _chooseThemeColor(context),
              ),
          ],
        );
      },
    ),
  );
}

Future<void> _chooseThemeColor(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('选择主题色', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 16,
              children: [
                for (final option in themeSeedOptions)
                  _ThemeColorOption(option: option),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _ThemeColorOption extends StatelessWidget {
  const _ThemeColorOption({required this.option});

  final ThemeSeedOption option;

  @override
  Widget build(BuildContext context) {
    final selected =
        ThemeSettings.instance.seedColor.toARGB32() == option.color.toARGB32();
    return Tooltip(
      message: option.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          ThemeSettings.instance.setSeedColor(option.color);
          Navigator.of(context).pop();
        },
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: option.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeColorSwatch extends StatelessWidget {
  const _ThemeColorSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 28,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

Widget _applicationSettings(BuildContext context) {
  return _SettingsCard(
    title: '应用',
    icon: Icons.apps_outlined,
    child: Column(
      children: [
        _updateLogTile(context, contentPadding: EdgeInsets.zero),
        const Divider(height: 1),
        _aboutTile(context, contentPadding: EdgeInsets.zero),
      ],
    ),
  );
}

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

Widget _updateLogTile(
  BuildContext context, {
  EdgeInsetsGeometry? contentPadding,
}) {
  return ListTile(
    contentPadding: contentPadding,
    leading: const Icon(Icons.newspaper_outlined),
    title: const Text('更新日志'),
    subtitle: const Text('查看最新版本的发布时间与更新内容'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const UpdateLogPage())),
  );
}
