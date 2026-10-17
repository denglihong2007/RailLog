import 'package:flutter/material.dart';
import 'package:raillog/src/journal/journal_layout.dart';
import 'package:raillog/src/journal/journal_style.dart';
import 'package:raillog/src/services/journal_export_service.dart';
import 'package:raillog/src/services/journal_settings.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/settings/settings_section.dart';
import 'package:raillog/src/widgets/settings/settings_sub_page.dart';

/// 手账的版式偏好，外加一条「导出空白模板」的出口。
///
/// 单独开一页而不是并进「外观与显示」：这个功能有**两块**内容——一个持久
/// 偏好和一个导出动作。塞进显示页会让那一页冒出下载按钮，塞进数据页又会
/// 让数据页冒出风格选择。
class JournalSettingsPage extends StatefulWidget {
  const JournalSettingsPage({super.key});

  @override
  State<JournalSettingsPage> createState() => _JournalSettingsPageState();
}

class _JournalSettingsPageState extends State<JournalSettingsPage> {
  bool _isExporting = false;

  Future<void> _exportBlankTemplate() async {
    final pages = await _askBlankPageCount();
    if (pages == null || !mounted) return;

    setState(() => _isExporting = true);
    try {
      final result = await JournalExportService.exportBlankTemplate(
        pageCount: pages,
        style: JournalSettings.instance.style,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已导出空白模板 ${result.pageCount} 页\n保存位置：${result.savedPath}',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } on JournalExportException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出空白模板失败：$error')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// 印几页要问一句：这是拿去打印的，误触印出一沓废纸的代价很实际。
  /// 选过的页数记住，下次默认就是它。
  Future<int?> _askBlankPageCount() {
    final settings = JournalSettings.instance;
    var selected = settings.blankPages;
    return showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('导出空白模板'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('每页印三格手账，整页使用，不裁开。'),
              const SizedBox(height: AppSpacing.lg),
              SegmentedButton<int>(
                segments: [
                  for (final count in JournalSettings.blankPageOptions)
                    ButtonSegment(value: count, label: Text('$count 页')),
                ],
                selected: {selected},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    setDialogState(() => selected = selection.single),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                settings.setBlankPages(selected);
                Navigator.of(context).pop(selected);
              },
              child: const Text('导出'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SettingsSubPage(
    title: '行程手账',
    children: [
      const _StyleCard(),
      const SizedBox(height: AppSpacing.md),
      _BlankTemplateCard(
        busy: _isExporting,
        onExport: _exportBlankTemplate,
      ),
      const SizedBox(height: AppSpacing.md),
      const _FormatNoteCard(),
    ],
  );
}

class _StyleCard extends StatelessWidget {
  const _StyleCard();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: JournalSettings.instance,
    builder: (context, _) {
      final settings = JournalSettings.instance;
      return SettingsCard(
        title: '手账版式',
        icon: Icons.menu_book_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                '选中的版式会用在行程列表导出的手账上',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            // 两个 5 字标签在 360dp 下会把勾图标挤出去，必须关掉。
            SegmentedButton<JournalStyle>(
              segments: [
                for (final style in JournalStyle.values)
                  ButtonSegment(value: style, label: Text(style.label)),
              ],
              selected: {settings.style},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  settings.setStyle(selection.single),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final style in JournalStyle.values) ...[
                  if (style != JournalStyle.values.first)
                    const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _StylePreview(
                      style: style,
                      selected: style == settings.style,
                      onTap: () => settings.setStyle(style),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              settings.style.description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// 用 Flutter widget 画的示意图：只示意版面与配色，不示意字形。
class _StylePreview extends StatelessWidget {
  const _StylePreview({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final JournalStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '手账版式 ${style.label}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 104,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: CustomPaint(
                painter: _PreviewPainter(style: style),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 0),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      'G1  北京南 → 上海虹桥',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF212121),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              style.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? scheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  const _PreviewPainter({required this.style});

  final JournalStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    if (style == JournalStyle.retro) {
      _paintRetro(canvas, size);
    } else {
      _paintGrid(canvas, size);
    }
  }

  static void _paintRetro(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRect(
      Rect.fromLTWH(4, 4, size.width - 8, size.height - 8),
      Paint()
        ..color = const Color(0xFF3A3A3A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.drawRect(
      Rect.fromLTWH(7, 7, size.width - 14, size.height - 14),
      Paint()
        ..color = const Color(0xFF9A9A9A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    // 四角三角：复古车票簿的识别特征。
    final corner = Paint()..color = const Color(0xFF3A3A3A);
    for (final (x, y, dx, dy) in [
      (7.0, 7.0, 1.0, 1.0),
      (size.width - 7, 7.0, -1.0, 1.0),
      (7.0, size.height - 7, 1.0, -1.0),
      (size.width - 7, size.height - 7, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y)
          ..lineTo(x + dx * 10, y)
          ..lineTo(x, y + dy * 10)
          ..close(),
        corner,
      );
    }
    // 三趟行程之间只隔一条细线：图上是一页连续的纸，不是三张卡片。
    final bandHeight = size.height / 3;
    final rule = Paint()
      ..color = const Color(0xFFC4C4C4)
      ..strokeWidth = 0.8;
    for (var band = 0; band < 3; band++) {
      final top = band * bandHeight;
      if (band > 0) {
        canvas.drawLine(
          Offset(7, top - 1.2),
          Offset(size.width - 7, top - 1.2),
          Paint()
            ..color = const Color(0xFF9A9A9A)
            ..strokeWidth = 1,
        );
        canvas.drawLine(
          Offset(7, top + 1.2),
          Offset(size.width - 7, top + 1.2),
          Paint()
            ..color = const Color(0xFFC4C4C4)
            ..strokeWidth = 0.6,
        );
      }
      for (var index = 0; index < 2; index++) {
        final y = top + bandHeight * (0.62 + index * 0.16);
        canvas.drawLine(Offset(12, y), Offset(size.width - 12, y), rule);
      }
    }
  }

  static void _paintGrid(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
    final grid = Paint()
      ..color = const Color(0xFFDCDCDC)
      ..strokeWidth = 0.6;
    const step = 8.0;
    final bandHeight = size.height / 3;
    for (var band = 0; band < 3; band++) {
      final top = band * bandHeight;
      // 每格顶部留出勾选行，格网不压字。
      final gridTop = top + bandHeight * 0.3;
      final bottom = top + bandHeight;
      for (var x = 0.0; x <= size.width; x += step) {
        canvas.drawLine(Offset(x, gridTop), Offset(x, bottom), grid);
      }
      for (var y = gridTop; y <= bottom; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      }
      if (band > 0) {
        canvas.drawLine(
          Offset(0, top),
          Offset(size.width, top),
          Paint()
            ..color = const Color(0xFFB4B4B4)
            ..strokeWidth = 1,
        );
      }
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 5, size.height),
      Paint()..color = const Color(0xFF212121),
    );
    canvas.drawRect(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Paint()
        ..color = const Color(0xFFB4B4B4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_PreviewPainter oldDelegate) =>
      oldDelegate.style != style;
}

class _BlankTemplateCard extends StatelessWidget {
  const _BlankTemplateCard({required this.busy, required this.onExport});

  final bool busy;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) => SettingsCard(
    title: '空白模板',
    icon: Icons.description_outlined,
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.print_outlined),
      title: const Text('导出空白手账模板'),
      subtitle: const Text('同样的版面，只印字段名提示，打印出来手写'),
      trailing: busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download_outlined),
      onTap: busy ? null : onExport,
    ),
  );
}

class _FormatNoteCard extends StatelessWidget {
  const _FormatNoteCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SettingsCard(
      title: '版面说明',
      icon: Icons.straighten_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'A4 纵向，每页 ${JournalLayout.tripsPerPage} 趟行程，整页使用、不裁开，'
            '适合直接打孔装进活页本。两种版式都是白底灰阶，黑白打印即可。'
            '每趟行程只预印车次、区间、时刻、里程、席位与票价，'
            '其余纸面全部留给手写：一行天气/心情/评分勾选，加上横线（方格本为 5mm 格网）书写区。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '不印页码——活页本可以任意插页，页码只会添乱。'
            '行程数凑不满三格时，末页空余的格位按空白模板印，可以直接手写补记。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
