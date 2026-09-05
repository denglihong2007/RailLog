import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:raillog/src/services/trip_excel_import_service.dart';

Future<void> showExcelImportGuide(
  BuildContext context, {
  required VoidCallback onPick,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.upload_file_outlined),
      title: const Text('从 Excel 导入行程'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: const SingleChildScrollView(child: ExcelImportGuide()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onPick();
          },
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('选择 Excel 文件'),
        ),
      ],
    ),
  );
}

Future<TripExcelImportResult?> pickAndImportExcel(BuildContext context) async {
  const excelType = XTypeGroup(
    label: 'Excel 工作簿',
    extensions: ['xlsx'],
    mimeTypes: [
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ],
  );
  final selection = await openFile(acceptedTypeGroups: const [excelType]);
  if (selection == null || !context.mounted) return null;
  try {
    final bytes = await selection.readAsBytes();
    final result = await TripExcelImportService.importBytes(bytes);
    if (!context.mounted) return null;
    final skipped = result.skipped == 0 ? '' : '，跳过 ${result.skipped} 条重复行程';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已导入 ${result.imported} 条行程$skipped')),
    );
    return result;
  } on TripExcelImportException catch (error) {
    if (!context.mounted) return null;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.error_outline,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: const Text('无法导入'),
        content: SelectableText(error.message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
    return null;
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('导入失败：$error')));
    return null;
  }
}

class ExcelImportGuide extends StatelessWidget {
  const ExcelImportGuide({super.key});

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
          detail: '本地记录号、车次/班次、出发站、到达站、出发时间。首行必须是列名，列的顺序可以调整。本地记录号可留空。',
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
            '导入规则：本地记录号匹配时更新原行程；记录号为空或不存在时新增行程。',
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
