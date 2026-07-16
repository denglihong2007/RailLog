import 'package:flutter/material.dart';
import 'package:flutter_adaptive_scaffold/flutter_adaptive_scaffold.dart';
import 'package:raillog/src/pages/home_page.dart';
import 'package:raillog/src/pages/add_trip_page.dart';
import 'package:raillog/src/pages/settings_page.dart';
import 'package:raillog/src/pages/statistics_page.dart';
import 'package:raillog/src/services/cloud_sync_service.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/services/update_service.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';
import 'package:raillog/src/widgets/update_prompt.dart';

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIdx = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const HomePage(),
      AddTripPage(onTripSaved: _showHomeAfterSave),
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
      _pages[0] = HomePage(key: UniqueKey());
      _pages[2] = StatisticsPage(key: UniqueKey());
    });
  }

  void _showHomeAfterSave() {
    setState(() {
      _pages[0] = HomePage(key: UniqueKey());
      _currentIdx = 0;
    });
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
    return AdaptiveScaffold(
      appBar: AppBar(title: const Text('轨记')),

      selectedIndex: _currentIdx,

      onSelectedIndexChange: (int index) {
        setState(() {
          _currentIdx = index;
        });
      },

      destinations: const [
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
          icon: Icon(Icons.bar_chart_outlined),
          selectedIcon: Icon(Icons.bar_chart),
          label: '统计',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: '设置',
        ),
      ],
      body: (_) => SafeArea(
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
