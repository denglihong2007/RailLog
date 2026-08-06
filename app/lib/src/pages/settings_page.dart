import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:raillog/src/models/user_profile.dart';
import 'package:raillog/src/pages/about_page.dart';
import 'package:raillog/src/pages/auth_page.dart';
import 'package:raillog/src/pages/password_reset_page.dart';
import 'package:raillog/src/pages/update_log_page.dart';
import 'package:raillog/src/services/cloud_sync_service.dart';
import 'package:raillog/src/services/baidu_train_ticket_ocr_service.dart';
import 'package:raillog/src/services/engagement_prompt_service.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/services/theme_settings.dart';
import 'package:raillog/src/services/ticket_generator_settings.dart';
import 'package:raillog/src/services/trip_excel_export_service.dart';
import 'package:raillog/src/services/trip_excel_import_service.dart';
import 'package:raillog/src/widgets/cached_avatar.dart';
import 'package:raillog/src/widgets/engagement_prompt.dart';
import 'package:url_launcher/url_launcher.dart';

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
        const SizedBox(height: 12),
        const _BaiduOcrSettingsSection(),
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
        _communitySettings(),
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
        const _BaiduOcrSettingsSection(),
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
        _communitySettings(),
        const SizedBox(height: 12),
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
  bool _isImporting = false;

  Future<void> _export() async {
    setState(() => _isExporting = true);
    var exported = false;
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
      exported = true;
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
    if (exported && mounted) {
      await maybeShowEngagementPrompt(
        context,
        EngagementPromptEvent.excelExported,
      );
    }
  }

  Future<void> _showImportGuide() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.upload_file_outlined),
        title: const Text('从 Excel 导入行程'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: const SingleChildScrollView(child: _ExcelImportGuide()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _pickAndImport();
            },
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('选择 Excel 文件'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndImport() async {
    const excelType = XTypeGroup(
      label: 'Excel 工作簿',
      extensions: ['xlsx'],
      mimeTypes: [
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ],
    );
    final selection = await openFile(acceptedTypeGroups: const [excelType]);
    if (selection == null || !mounted) return;
    setState(() => _isImporting = true);
    try {
      final bytes = await selection.readAsBytes();
      final result = await TripExcelImportService.importBytes(bytes);
      if (!mounted) return;
      final skipped = result.skipped == 0 ? '' : '，跳过 ${result.skipped} 条重复行程';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 ${result.imported} 条行程$skipped')),
      );
    } on TripExcelImportException catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('无法导入'),
          content: SelectableText(error.message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败：$error')));
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: '数据',
      icon: Icons.table_chart_outlined,
      child: Column(
        children: [
          ListTile(
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
            onTap: _isExporting || _isImporting ? null : _export,
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('从 Excel 导入行程'),
            subtitle: const Text('按照规范整理表格后批量导入，重复行程将自动跳过'),
            trailing: _isImporting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _isImporting || _isExporting ? null : _showImportGuide,
          ),
        ],
      ),
    );
  }
}

class _ExcelImportGuide extends StatelessWidget {
  const _ExcelImportGuide();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '请先按以下规范整理表格。最稳妥的做法是先导出一份 RailLog Excel，在其“行程”工作表中追加记录。',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        const _ImportGuideItem(
          icon: Icons.view_column_outlined,
          title: '必填列',
          detail: '车次/班次、出发站、到达站、出发时间。首行必须是列名，列的顺序可以调整。',
        ),
        const SizedBox(height: 14),
        const _ImportGuideItem(
          icon: Icons.calendar_month_outlined,
          title: '日期与数字',
          detail: '时间使用 Excel 日期单元格，或 yyyy-MM-dd HH:mm:ss；里程和票价只填写数字。',
        ),
        const SizedBox(height: 14),
        const _ImportGuideItem(
          icon: Icons.description_outlined,
          title: '文件与编码',
          detail: '保存为 .xlsx 文件。该格式使用 Unicode，无需另选字符编码；不支持 .xls 或 .csv。',
        ),
        const SizedBox(height: 14),
        const _ImportGuideItem(
          icon: Icons.tune_outlined,
          title: '其他字段',
          detail: '可使用导出文件中的其他列；行程编号和乘坐时长会忽略，经由线路应保留 JSON 格式。',
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '重复判断：车次/班次 + 出发站 + 到达站 + 出发时间',
            style: TextStyle(color: colors.onSecondaryContainer),
          ),
        ),
      ],
    );
  }
}

class _ImportGuideItem extends StatelessWidget {
  const _ImportGuideItem({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 3),
            Text(detail),
          ],
        ),
      ),
    ],
  );
}

class _BaiduOcrSettingsSection extends StatefulWidget {
  const _BaiduOcrSettingsSection();

  @override
  State<_BaiduOcrSettingsSection> createState() =>
      _BaiduOcrSettingsSectionState();
}

class _BaiduOcrSettingsSectionState extends State<_BaiduOcrSettingsSection> {
  final _apiKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();
  bool _loading = true;
  bool _obscureSecret = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _secretKeyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final credentials = await BaiduOcrSettings.load();
    if (!mounted) return;
    _apiKeyController.text = credentials.apiKey;
    _secretKeyController.text = credentials.secretKey;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    await BaiduOcrSettings.save(
      apiKey: _apiKeyController.text,
      secretKey: _secretKeyController.text,
    );
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
    return _SettingsCard(
      title: '百度车票识别',
      icon: Icons.document_scanner_outlined,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _apiKeyController,
                  autocorrect: false,
                  onChanged: (_) => _save(),
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
                const SizedBox(height: 12),
                TextFormField(
                  controller: _secretKeyController,
                  obscureText: _obscureSecret,
                  onChanged: (_) => _save(),
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
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _serialPrefixController,
                decoration: InputDecoration(
                  labelText: '票号前缀',
                  helperText: '21 位票号的前 10 位',
                  prefixIcon: const Icon(Icons.numbers_outlined),
                  suffixIcon: IconButton(
                    tooltip: '票号构成说明',
                    onPressed: () => _showSerialNumberHelp(context),
                    icon: const Icon(Icons.help_outline),
                  ),
                  border: const OutlineInputBorder(),
                ),
                maxLength: 10,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: settings.setSerialPrefix,
                validator: (value) => RegExp(r'^\d{10}$').hasMatch(value ?? '')
                    ? null
                    : '请输入 10 位数字',
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
          '• 第11至14位：MMDD格式的4位结算日期（一般为乘车日期的下一天，由软件自动生成而无需设置）；\n'
          '• 最后7位：票纸编号（通常由1位字母和6位数字组合而成，由软件自动生成而无需设置）。',
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

Widget _communitySettings() {
  return _SettingsCard(
    title: '社群',
    icon: Icons.groups_outlined,
    child: Column(
      children: [
        _communityLinkTile(
          icon: Icons.groups_outlined,
          title: 'QQ 交流群',
          subtitle: '群号：972024237（密码：114514）',
          url: 'https://qm.qq.com/q/pm5xqNdoE8',
        ),
        const Divider(height: 1),
        _communityLinkTile(
          icon: Icons.volunteer_activism_outlined,
          title: '爱发电',
          subtitle: '支持 RailLog 的开发与维护',
          url: 'https://afdian.com/a/CRSim',
        ),
        const Divider(height: 1),
        _communityLinkTile(
          icon: Icons.ondemand_video_outlined,
          title: 'Bilibili',
          subtitle: 'RailLog 相关视频与动态',
          url: 'https://space.bilibili.com/436826066',
        ),
      ],
    ),
  );
}

Widget _communityLinkTile({
  required IconData icon,
  required String title,
  required String subtitle,
  required String url,
}) {
  return Builder(
    builder: (context) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.open_in_new, size: 20),
      onTap: () => _openCommunityLink(context, url),
    ),
  );
}

Future<void> _openCommunityLink(BuildContext context, String value) async {
  final uri = Uri.tryParse(value);
  final opened =
      uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法打开链接')));
  }
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
