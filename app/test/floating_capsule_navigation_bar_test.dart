import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/widgets/floating_capsule_navigation_bar.dart';

/// 纯布局测试：这个 widget 不碰任何 I/O，可以放心泵。
const _destinations = [
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
];

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  double textScale = 1,
  ValueChanged<int>? onSelected,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: _NavHost(onSelected: onSelected),
    ),
  );
  await tester.pumpAndSettle();
}

class _NavHost extends StatefulWidget {
  const _NavHost({this.onSelected});

  final ValueChanged<int>? onSelected;

  @override
  State<_NavHost> createState() => _NavHostState();
}

class _NavHostState extends State<_NavHost> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      bottomNavigationBar: FloatingCapsuleNavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) {
          widget.onSelected?.call(index);
          setState(() => _index = index);
        },
        destinations: _destinations,
      ),
    );
  }
}

/// 胶囊外壳是组件子树里的第一个 [Material]，内层还有一层透明的用于水波纹。
final _pillFinder = find
    .descendant(
      of: find.byType(FloatingCapsuleNavigationBar),
      matching: find.byType(Material),
    )
    .first;

void main() {
  testWidgets('选中项图标与文字并排，未选中项只留图标', (tester) async {
    await _pump(tester, width: 360);

    expect(tester.takeException(), isNull);

    final pillSize = tester.getSize(_pillFinder);
    expect(pillSize.height, 52);
    expect(pillSize.width, lessThan(360 - 32));
    expect(pillSize.width, greaterThan(240));
    expect(tester.getCenter(_pillFinder).dx, moreOrLessEquals(180, epsilon: 1));
    expect(find.byType(BackdropFilter), findsOneWidget);

    expect(find.text('主页'), findsOneWidget);
    for (final label in ['录入', '统计', '设置']) {
      expect(find.text(label), findsNothing, reason: label);
    }
  });

  testWidgets('点未选中项会回调，并展开这一项的图标与文字', (tester) async {
    var tapped = -1;
    await _pump(tester, width: 360, onSelected: (index) => tapped = index);

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();

    expect(tapped, 1);
    expect(find.text('录入'), findsOneWidget);
    expect(find.text('主页'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320dp 窄屏、2 倍字体下也不溢出', (tester) async {
    await _pump(tester, width: 320, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(tester.getSize(_pillFinder).width, lessThan(320 - 32));

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('主页'), findsNothing);
  });
}
