import 'package:flutter/material.dart';
import 'package:raillog/src/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// 提交成就创意的表单。本页只负责收集内容并拼出 GitHub 新建 Issue 的地址 ——
/// 真正的提交发生在浏览器里，用户还有机会再改一遍。
class AchievementProposalPage extends StatefulWidget {
  const AchievementProposalPage({super.key});

  @override
  State<AchievementProposalPage> createState() =>
      _AchievementProposalPageState();
}

class _AchievementProposalPageState extends State<AchievementProposalPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _requirementController = TextEditingController();
  final _narrativeController = TextEditingController();
  final _technicalController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _requirementController.dispose();
    _narrativeController.dispose();
    _technicalController.dispose();
    super.dispose();
  }

  static String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return '请填写成就名称';
    if (!_fourHanCharacters.hasMatch(name)) return '成就名称需为四个汉字';
    return null;
  }

  static String? _validateRequired(String? value, String label) =>
      (value?.trim().isEmpty ?? true) ? '请填写$label' : null;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final uri = achievementProposalIssueUri(
      name: _nameController.text,
      requirement: _requirementController.text,
      narrative: _narrativeController.text,
      technicalNote: _technicalController.text,
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开 GitHub，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('提交成就创意')),
      body: Center(
        child: SingleChildScrollView(
          padding: AppSpacing.page,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppLayout.formMaxWidth),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 20, color: colors.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          '点击提交后会打开 GitHub 的新建 Issue 页面，'
                          '你可以再确认一遍内容后发布。',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  TextFormField(
                    controller: _nameController,
                    // 不设 maxLength：LengthLimitingTextInputFormatter 会在拼音
                    // 还没选字时就把组合串截断。字数交给校验器，输入法自由组词。
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '成就名称',
                      helperText: '四个汉字',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateName,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _requirementController,
                    minLines: 2,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: '达成条件',
                      hintText: '例如：乘坐过全国 18 个铁路局的旅客列车',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => _validateRequired(value, '达成条件'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _narrativeController,
                    minLines: 2,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: '注释',
                      hintText: '解锁后展示给用户的文案',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => _validateRequired(value, '注释'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _technicalController,
                    minLines: 2,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: '技术性说明（可选）',
                      hintText: '供开发者参考的判定细节，如数据来源、统计口径等',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('提交到 GitHub'),
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

/// 成就名称必须是四个汉字。覆盖基本区、扩展 A 区与兼容区，够日常取名用。
final _fourHanCharacters = RegExp(
  r'^[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]{4}$',
);
Uri achievementProposalIssueUri({
  required String name,
  required String requirement,
  required String narrative,
  String? technicalNote,
}) {
  final technical = technicalNote?.trim() ?? '';
  final body = [
    '### 成就名称',
    '',
    name.trim(),
    '',
    '### 达成条件',
    '',
    requirement.trim(),
    '',
    '### 注释',
    '',
    narrative.trim(),
    '',
    '### 技术性说明',
    '',
    technical.isEmpty ? '（未填写）' : technical,
    '',
    '---',
    '本 Issue 由 RailLog App 的「提交成就创意」功能生成。',
  ].join('\n');
  // 自己编码而不用 Uri.https 的 queryParameters：后者把空格写成 `+`，
  // 而 GitHub 的预填正文用 `%20` 更稳妥。
  final query = [
    'title=${Uri.encodeComponent('[成就创意] ${name.trim()}')}',
    'body=${Uri.encodeComponent(body)}',
  ].join('&');
  return Uri.parse(
    'https://github.com/denglihong2007/RailLog/issues/new?$query',
  );
}
