import 'package:flutter/material.dart';
import 'package:raillog/src/services/cloud_sync_service.dart';
import 'package:raillog/src/services/engagement_prompt_service.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/services/trip_excel_export_service.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/engagement_prompt.dart';
import 'package:raillog/src/widgets/excel_import_action.dart';
import 'package:raillog/src/widgets/settings/settings_section.dart';
import 'package:raillog/src/widgets/settings/settings_sub_page.dart';

class DataSyncSettingsPage extends StatefulWidget {
  const DataSyncSettingsPage({super.key});

  @override
  State<DataSyncSettingsPage> createState() => _DataSyncSettingsPageState();
}

class _DataSyncSettingsPageState extends State<DataSyncSettingsPage> {
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
    await showExcelImportGuide(context, onPick: _pickAndImport);
  }

  Future<void> _pickAndImport() async {
    setState(() => _isImporting = true);
    await pickAndImportExcel(context);
    if (mounted) setState(() => _isImporting = false);
  }

  Future<void> _sync() async {
    try {
      await CloudSyncService.instance.sync();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('同步完成')));
      }
    } on SessionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSubPage(
      title: '数据与同步',
      children: [
        AnimatedBuilder(
          animation: SessionService.instance,
          builder: (context, _) {
            final signedIn = SessionService.instance.user != null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (signedIn) ...[
                  _cloudSyncCard(context),
                  const SizedBox(height: AppSpacing.md),
                ] else ...[
                  const SettingsCard(
                    title: '存储',
                    icon: Icons.storage_outlined,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.cloud_off_outlined),
                      title: Text('本地模式'),
                      subtitle: Text('当前行程仅保存在此设备'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                _localDataCard(),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _cloudSyncCard(BuildContext context) {
    return AnimatedBuilder(
      animation: CloudSyncService.instance,
      builder: (context, _) {
        final sync = CloudSyncService.instance;
        return SettingsCard(
          title: '云同步',
          icon: Icons.cloud_sync_outlined,
          child: Column(
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
                  onPressed: sync.isSyncing ? null : _sync,
                  icon: sync.isSyncing
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _localDataCard() {
    return SettingsCard(
      title: '本地数据',
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

String _syncSubtitle(CloudSyncService sync) {
  if (sync.lastError != null) return sync.lastError!;
  final value = sync.lastSyncedAt;
  if (value == null) return '尚未同步';
  final local = value.toLocal();
  return '上次同步 ${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
