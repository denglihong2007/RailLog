import 'package:flutter/material.dart';
import 'package:raillog/src/pages/add_trip_page.dart';
import 'package:raillog/src/pages/home_page.dart';
import 'package:raillog/src/pages/search_page.dart';
import 'package:raillog/src/pages/settings_page.dart';
import 'package:raillog/src/pages/statistics_page.dart';
import 'package:raillog/src/services/cloud_sync_service.dart';
import 'package:raillog/src/services/engagement_prompt_service.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/services/update_service.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';
import 'package:raillog/src/widgets/engagement_prompt.dart';
import 'package:raillog/src/widgets/update_prompt.dart';

const _mainDestinations = [
  NavigationDestination(
    icon: Icon(Icons.home_outlined),
    selectedIcon: Icon(Icons.home),
    label: '主页',
  ),
  NavigationDestination(
    icon: Icon(Icons.add_circle_outline),
    selectedIcon: Icon(Icons.add_circle),
    label: '录入',
  ),
  NavigationDestination(
    icon: Icon(Icons.search_outlined),
    selectedIcon: Icon(Icons.search),
    label: '搜索',
  ),
  NavigationDestination(
    icon: Icon(Icons.bar_chart_outlined),
    selectedIcon: Icon(Icons.bar_chart),
    label: '统计',
  ),
  NavigationDestination(
    icon: Icon(Icons.settings_outlined),
    selectedIcon: Icon(Icons.settings),
    label: '设置',
  ),
];

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIdx = 0;
  int _homeRefreshToken = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const HomePage(),
      AddTripPage(onTripSaved: _showHomeAfterSave),
      const SearchPage(),
      const StatisticsPage(),
      const SettingsPage(),
    ];
    CloudSyncService.instance.onDataChanged = _refreshHome;
    SessionService.instance.addListener(_refreshHome);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  @override
  void dispose() {
    if (CloudSyncService.instance.onDataChanged == _refreshHome) {
      CloudSyncService.instance.onDataChanged = null;
    }
    SessionService.instance.removeListener(_refreshHome);
    super.dispose();
  }

  void _refreshHome() {
    if (!mounted) return;
    setState(() {
      // Keep HomePage's state (and its currently rendered data) while asking
      // it to refresh. Replacing it with a UniqueKey causes a second full
      // loading screen during the startup cloud sync.
      _pages[0] = HomePage(refreshToken: ++_homeRefreshToken);
      _pages[3] = StatisticsPage(key: UniqueKey());
    });
  }

  void _showHomeAfterSave() {
    setState(() {
      _pages[0] = HomePage(refreshToken: ++_homeRefreshToken);
      _currentIdx = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showEngagementPromptAfterSave();
    });
  }

  Future<void> _showEngagementPromptAfterSave() async {
    await maybeShowEngagementPrompt(context, EngagementPromptEvent.tripSaved);
  }

  Future<void> _checkForUpdate() async {
    if (!UpdateService.supportsAutomaticChecks) return;
    try {
      final result = await UpdateService.check();
      if (mounted && result.hasUpdate) await showUpdatePrompt(context, result);
    } on UpdateException {
      // Startup update checks stay silent when the network is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Theme.of(context).platform == TargetPlatform.windows ||
        Theme.of(context).platform == TargetPlatform.macOS ||
        Theme.of(context).platform == TargetPlatform.linux;
    final appBar = isDesktop ? null : AppBar(title: const Text('轨记'));

    return _AdaptiveNavigationScaffold(
      appBar: appBar,
      selectedIndex: _currentIdx,
      onSelectedIndexChange: (index) {
        setState(() {
          _currentIdx = index;
        });
      },
      destinations: _mainDestinations,
      body: SafeArea(
        bottom: false,
        child: M3FadeThroughSwitcher(
          child: KeyedSubtree(
            key: ValueKey(_currentIdx),
            child: _pages[_currentIdx],
          ),
        ),
      ),
    );
  }
}

class _AdaptiveNavigationScaffold extends StatelessWidget {
  const _AdaptiveNavigationScaffold({
    required this.appBar,
    required this.selectedIndex,
    required this.onSelectedIndexChange,
    required this.destinations,
    required this.body,
  });

  static const compactBreakpoint = 600.0;
  static const expandedBreakpoint = 840.0;

  final PreferredSizeWidget? appBar;
  final int selectedIndex;
  final ValueChanged<int> onSelectedIndexChange;
  final List<NavigationDestination> destinations;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < compactBreakpoint) {
          return Scaffold(
            appBar: appBar,
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelectedIndexChange,
              destinations: destinations,
            ),
          );
        }

        final extended = constraints.maxWidth >= expandedBreakpoint;
        return Scaffold(
          appBar: appBar,
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NavigationRail(
                selectedIndex: selectedIndex,
                onDestinationSelected: onSelectedIndexChange,
                extended: extended,
                labelType: extended ? null : NavigationRailLabelType.all,
                groupAlignment: -1,
                destinations: [
                  for (final destination in destinations)
                    NavigationRailDestination(
                      icon: destination.icon,
                      selectedIcon: destination.selectedIcon,
                      label: Text(destination.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }
}
