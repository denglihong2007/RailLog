import 'package:flutter/material.dart';
import 'package:raillog/src/widgets/settings/settings_section.dart';
import 'package:raillog/src/widgets/settings/settings_sub_page.dart';
import 'package:url_launcher/url_launcher.dart';

class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSubPage(
      title: '社群与支持',
      children: [
        const SettingsListCard(
          title: '加入我们',
          icon: Icons.groups_outlined,
          children: [
            _CommunityLinkTile(
              icon: Icons.groups_outlined,
              title: 'QQ 交流群',
              subtitle: '群号：972024237（密码：114514）',
              url: 'https://qm.qq.com/q/pm5xqNdoE8',
            ),
            _CommunityLinkTile(
              icon: Icons.volunteer_activism_outlined,
              title: '爱发电',
              subtitle: '支持 RailLog 的开发与维护',
              url: 'https://afdian.com/a/CRSim',
            ),
            _CommunityLinkTile(
              icon: Icons.ondemand_video_outlined,
              title: 'Bilibili',
              subtitle: 'RailLog 相关视频与动态',
              url: 'https://space.bilibili.com/436826066',
            ),
          ],
        ),
      ],
    );
  }
}

class _CommunityLinkTile extends StatelessWidget {
  const _CommunityLinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.url,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String url;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.open_in_new, size: 20),
    onTap: () => _openLink(context, url),
  );
}

Future<void> _openLink(BuildContext context, String value) async {
  final uri = Uri.tryParse(value);
  final opened =
      uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法打开链接')));
  }
}
