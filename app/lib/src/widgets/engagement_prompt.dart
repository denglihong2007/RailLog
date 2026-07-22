import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:raillog/src/services/engagement_prompt_service.dart';
import 'package:url_launcher/url_launcher.dart';

enum _EngagementPromptAction { later, disable, primary }

Future<void> maybeShowEngagementPrompt(
  BuildContext context,
  EngagementPromptEvent event,
) async {
  final kind = await EngagementPromptService.recordEvent(event);
  if (!context.mounted || kind == null) return;
  await showEngagementPrompt(context, kind);
}

Future<void> maybeShowAchievementEngagementPrompt(
  BuildContext context,
  int unlockedCount,
) async {
  final kind = await EngagementPromptService.recordAchievementViewed(
    unlockedCount,
  );
  if (!context.mounted || kind == null) return;
  await showEngagementPrompt(context, kind);
}

Future<void> showEngagementPrompt(
  BuildContext context,
  EngagementPromptKind kind,
) async {
  final share = kind == EngagementPromptKind.share;
  final action = await showDialog<_EngagementPromptAction>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        share ? Icons.ios_share_outlined : Icons.volunteer_activism_outlined,
      ),
      title: Text(share ? '愿意把轨记分享给朋友吗？' : '愿意支持轨记继续维护吗？'),
      content: Text(
        share
            ? '如果轨记对你有帮助，可以把官网链接分享给同样喜欢铁路和旅行记录的人。'
            : '轨记保持免费和开源。你的支持会用于服务器、数据整理和后续维护。',
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_EngagementPromptAction.disable),
          child: const Text('不再提示'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_EngagementPromptAction.later),
          child: const Text('暂不'),
        ),
        FilledButton.icon(
          onPressed: () =>
              Navigator.of(context).pop(_EngagementPromptAction.primary),
          icon: Icon(share ? Icons.copy_outlined : Icons.open_in_new),
          label: Text(share ? '复制分享文案' : '前往爱发电'),
        ),
      ],
    ),
  );

  if (action == _EngagementPromptAction.disable) {
    await EngagementPromptService.disable();
    return;
  }
  if (action != _EngagementPromptAction.primary || !context.mounted) return;

  if (share) {
    await Clipboard.setData(
      const ClipboardData(text: EngagementPromptService.websiteShareText),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('分享文案已复制')));
    return;
  }

  final opened = await launchUrl(
    Uri.parse(EngagementPromptService.donationUrl),
    mode: LaunchMode.externalApplication,
  );
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法打开爱发电，请稍后重试')));
  }
}
