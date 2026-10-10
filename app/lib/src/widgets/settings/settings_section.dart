import 'package:flutter/material.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/cached_avatar.dart';

/// 设置分组的小标题。放在卡片上方，用来切分大分组。
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

/// 内容型设置卡片：带图标 + 标题表头，正文保留内边距。
/// 适合开关、分段按钮、输入框这类需要留白的控件。
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => AppCard.filled(
    title: title,
    icon: icon,
    trailing: trailing,
    child: child,
  );
}

/// 列表型设置卡片：表头之外全是列表行，行与行之间自动补分隔线。
/// [title] 与 [icon] 都不传时整张卡片只剩列表行，供根页面
/// 「分组小标题 + 卡片列表」的写法使用。
class SettingsListCard extends StatelessWidget {
  const SettingsListCard({
    super.key,
    this.title,
    this.icon,
    required this.children,
  });

  final String? title;
  final IconData? icon;
  final List<Widget> children;

  /// 从 leading 图标右侧起画：卡片留白 16 + ListTile 的 leading 占位 40。
  /// 与 `about_page.dart` 里 `_AboutSection` 的取值一致。
  static const double _dividerIndent = 56;

  @override
  Widget build(BuildContext context) => AppCard.filled(
    title: title,
    icon: icon,
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1)
            const Divider(height: 1, indent: _dividerIndent),
        ],
      ],
    ),
  );
}

/// 设置项导航行，trailing 默认为 chevron_right。
class SettingsNavTile extends StatelessWidget {
  const SettingsNavTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.textColor,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? textColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final subtitleText = subtitle;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitleText == null ? null : Text(subtitleText),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      textColor: textColor,
      iconColor: iconColor,
      onTap: onTap,
    );
  }
}

/// 账户头像，统一走 [CachedAvatar] 的取图与首字母兜底。
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.size,
  });

  final String name;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) => CachedAvatar(
    name: name,
    imageUrl: imageUrl,
    size: size,
    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
    textStyle: TextStyle(fontSize: size * 0.35),
  );
}
