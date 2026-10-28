import 'package:flutter/material.dart';
import 'package:raillog/src/services/map_settings.dart';
import 'package:raillog/src/services/theme_settings.dart';
import 'package:raillog/src/services/trip_detail_settings.dart';
import 'package:raillog/src/services/trip_list_settings.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';
import 'package:raillog/src/widgets/settings/settings_section.dart';
import 'package:raillog/src/widgets/settings/settings_sub_page.dart';

/// 主题、地图底图与行程详情的显示偏好。三块内容都很轻，收在同一页里。
class DisplaySettingsPage extends StatelessWidget {
  const DisplaySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSubPage(
      title: '外观与显示',
      children: [
        const _ThemeCard(),
        const SizedBox(height: AppSpacing.md),
        const _MapCard(),
        const SizedBox(height: AppSpacing.md),
        const _TripListCard(),
        const SizedBox(height: AppSpacing.md),
        const _TripDetailCard(),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: ThemeSettings.instance,
    builder: (context, _) {
      final settings = ThemeSettings.instance;
      return SettingsCard(
        title: '主题',
        icon: Icons.palette_outlined,
        child: Column(
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
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.format_paint_outlined),
              title: const Text('跟随系统主题色'),
              subtitle: const Text('可用时使用设备动态配色'),
              value: settings.useSystemColor,
              onChanged: settings.setUseSystemColor,
            ),
            M3AnimatedVisibility(
              visible: !settings.useSystemColor,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ThemeColorSwatch(color: settings.seedColor),
                title: const Text('主题色'),
                subtitle: Text(settings.seedColorLabel),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _chooseThemeColor(context),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _MapCard extends StatelessWidget {
  const _MapCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: MapSettings.instance,
      builder: (context, _) {
        final settings = MapSettings.instance;
        return SettingsCard(
          title: '底图显示层级',
          icon: Icons.map_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<MapDetailLevel>(
                segments: [
                  for (final level in MapDetailLevel.values)
                    ButtonSegment(value: level, label: Text(level.label)),
                ],
                selected: {settings.detailLevel},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    settings.setDetailLevel(selection.single),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '越简略，底图的道路、兴趣点和文字标注越少，铁路轨迹越突出',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TripListCard extends StatelessWidget {
  const _TripListCard();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: TripListSettings.instance,
    builder: (context, _) {
      final settings = TripListSettings.instance;
      return SettingsCard(
        title: '行程列表',
        icon: Icons.view_agenda_outlined,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.compress),
          title: const Text('紧凑视图'),
          subtitle: const Text('车票卡片只显示车次、日期、起讫站与票价，一屏可看更多行程'),
          value: settings.compactMode,
          onChanged: settings.setCompactMode,
        ),
      );
    },
  );
}

class _TripDetailCard extends StatelessWidget {
  const _TripDetailCard();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: TripDetailSettings.instance,
    builder: (context, _) {
      final settings = TripDetailSettings.instance;
      return SettingsCard(
        title: '行程详情',
        icon: Icons.alt_route_outlined,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.route_outlined),
          title: const Text('默认展开线路站点'),
          subtitle: const Text('查看行程详情时展开经由线路的中间车站'),
          value: settings.expandRouteStationsByDefault,
          onChanged: settings.setExpandRouteStationsByDefault,
        ),
      );
    },
  );
}

Future<void> _chooseThemeColor(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xs,
          AppSpacing.xl,
          AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('选择主题色', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xl),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.lg,
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
    return Semantics(
      button: true,
      selected: selected,
      label: '主题色 ${option.label}',
      child: Tooltip(
        message: option.label,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
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
                      ? Icon(
                          Icons.check,
                          color:
                              ThemeData.estimateBrightnessForColor(
                                    option.color,
                                  ) ==
                                  Brightness.dark
                              ? Colors.white
                              : Colors.black87,
                        )
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
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
      ),
    );
  }
}

/// 主题色行的色块预览。
class ThemeColorSwatch extends StatelessWidget {
  const ThemeColorSwatch({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 28,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
