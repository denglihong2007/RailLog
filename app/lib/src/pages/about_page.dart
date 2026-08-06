import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/update_service.dart';
import 'package:raillog/src/widgets/update_prompt.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();
  bool _checkingUpdate = false;
  String _updateSubtitle = '从 RailLog 云服务检查最新版本';

  Future<void> _checkForUpdate() async {
    if (_checkingUpdate) return;
    setState(() {
      _checkingUpdate = true;
      _updateSubtitle = '正在检查';
    });
    try {
      final result = await UpdateService.check();
      if (!mounted) return;
      setState(() {
        _updateSubtitle = result.hasUpdate
            ? '发现新版本 ${result.latest.version}'
            : '已是最新版本 ${result.currentVersion}';
      });
      if (result.hasUpdate) {
        await showUpdatePrompt(context, result);
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
      }
    } on UpdateException catch (error) {
      if (mounted) {
        setState(() => _updateSubtitle = error.message);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          ColoredBox(
            color: colors.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Row(
                    children: [
                      Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Image.asset(
                            'assets/icon/icon.png',
                            width: 64,
                            height: 64,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '轨记',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: colors.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'RailLog',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: colors.onPrimaryContainer),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FutureBuilder<PackageInfo>(
                      future: _packageInfo,
                      builder: (context, snapshot) {
                        final package = snapshot.data;
                        final version = package == null
                            ? '读取中'
                            : '${package.version}+${package.buildNumber}';
                        return _AboutSection(
                          title: '软件信息',
                          children: [
                            _InfoTile(
                              icon: Icons.info_outline,
                              title: '软件版本',
                              subtitle: version,
                            ),
                            ListTile(
                              leading: const Icon(Icons.system_update_outlined),
                              title: const Text('检查更新'),
                              subtitle: Text(_updateSubtitle),
                              trailing: _checkingUpdate
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.chevron_right),
                              onTap: _checkingUpdate ? null : _checkForUpdate,
                            ),
                            const _InfoTile(
                              icon: Icons.fingerprint,
                              title: '应用标识',
                              subtitle: 'com.deliho.raillog',
                            ),
                            const _InfoTile(
                              icon: Icons.balance_outlined,
                              title: '开源许可',
                              subtitle: 'GNU General Public License v3.0',
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    _AboutSection(
                      title: '使用的 API',
                      children: [
                        _LinkTile(
                          icon: Icons.train_outlined,
                          title: '中国铁路 12306',
                          subtitle: '车站、车次、时刻、余票与票价',
                          url: 'https://www.12306.cn/',
                        ),
                        _LinkTile(
                          icon: Icons.directions_railway_outlined,
                          title: 'Rail.Re API',
                          subtitle: '列车车型数据',
                          url: 'https://api.rail.re/',
                        ),
                        _LinkTile(
                          icon: Icons.route_outlined,
                          title: '数智枫都 API',
                          subtitle: '担当企业与里程数据',
                          url: 'https://api.xfkenzify.com:3443/',
                        ),
                        _LinkTile(
                          icon: Icons.travel_explore_outlined,
                          title: 'RailGo API',
                          subtitle: '综合信息查询',
                          url: 'https://api.railgo.dev/',
                        ),
                        _LinkTile(
                          icon: Icons.cloud_outlined,
                          title: 'RailLog 云服务',
                          subtitle: ApiClient.baseUrl,
                          url: ApiClient.baseUrl,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const _AboutSection(
                      title: '项目链接',
                      children: [
                        _LinkTile(
                          icon: Icons.code,
                          title: '开源地址',
                          subtitle: 'denglihong2007/RailLog',
                          url: 'https://github.com/denglihong2007/RailLog',
                        ),
                        _LinkTile(
                          icon: Icons.language,
                          title: '官方网站',
                          subtitle: 'www.raillog.top',
                          url: 'https://www.raillog.top/',
                        ),
                        _LinkTile(
                          icon: Icons.person_outline,
                          title: '开发者',
                          subtitle: 'denglihong2007',
                          url: 'https://github.com/denglihong2007',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const _AboutSection(
                      title: '赞助者名单',
                      children: [
                        _InfoTile(
                          icon: Icons.favorite_outline,
                          title: '冰镇杨梅汁儿 依神Sh1on 枫糖',
                          subtitle: '感谢对 RailLog 的资金支持',
                        ),
                        _InfoTile(
                          icon: Icons.data_object_outlined,
                          title: '枫糖 wangxiaole',
                          subtitle: '收集相关数据',
                        ),
                        _InfoTile(
                          icon: Icons.texture_outlined,
                          title: '杰瑞瞎搞（Bilibili）',
                          subtitle: '提供车票底纹、字体',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const _AboutSection(
                      title: '友情链接',
                      children: [
                        _LinkTile(
                          icon: Icons.travel_explore_outlined,
                          title: '铁路快查',
                          subtitle: 'railgo.dev',
                          url: 'https://railgo.dev/',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Material(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1)
                  const Divider(height: 1, indent: 56),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
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
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.open_in_new, size: 20),
      onTap: () => _openExternalLink(context, url),
    );
  }
}

Future<void> _openExternalLink(BuildContext context, String value) async {
  final uri = Uri.tryParse(value);
  final opened =
      uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法打开链接')));
  }
}
