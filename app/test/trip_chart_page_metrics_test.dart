import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/pages/trip_chart_page.dart';
import 'package:raillog/src/theme/app_theme.dart';

DashboardTripEntry _trip({
  required int id,
  required double mileageKm,
  required double price,
  required Duration duration,
  bool isRailTrip = true,
}) {
  final departure = DateTime(2026, 1, id);
  return DashboardTripEntry(
    id: id,
    trainNumber: isRailTrip ? 'G$id' : '大巴$id',
    fromStation: '北京南',
    toStation: '上海虹桥',
    departureTime: departure,
    arrivalTime: departure.add(duration),
    mileageKm: mileageKm,
    seatType: '二等座',
    seatNumber: '5车12A号',
    price: price,
    isRailTrip: isRailTrip,
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  List<DashboardTripEntry> trips,
) async {
  tester.view.physicalSize = const Size(390, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(
        ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
      ),
      home: TripChartPage(trips: trips),
    ),
  );
  await tester.pump(const Duration(milliseconds: 800));
}

Finder _pageScrollable() => find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

void main() {
  final trips = [
    _trip(
      id: 1,
      mileageKm: 1000,
      price: 500,
      duration: const Duration(hours: 5),
    ),
    _trip(
      id: 2,
      mileageKm: 100,
      price: 50,
      duration: const Duration(minutes: 30),
    ),
  ];

  testWidgets('底部出行指标始终可见，图表按指标切换标记', (tester) async {
    await _pumpPage(tester, trips);

    // 次数是离散计数，用柱状图。
    expect(find.byType(BarChart), findsOneWidget);

    await tester.tap(find.text('里程'));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(LineChart), findsOneWidget);

    await tester.tap(find.text('次数'));
    await tester.pump(const Duration(milliseconds: 800));

    await tester.scrollUntilVisible(
      find.text('出行指标'),
      400,
      scrollable: _pageScrollable(),
    );
    expect(find.text('出行指标'), findsOneWidget);
    for (final title in ['平均旅速', '平均里程', '平均单位票价', '平均单程票价', '平均时长']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('日历热力图按用户数据自适应色阶', (tester) async {
    await _pumpPage(tester, trips);

    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pumpAndSettle();

    // 两条行程落在同一个周桶，只有一个非零值，色阶退化为单档。
    expect(find.text('有行程'), findsOneWidget);
    // 周视图：行是当月第几周，列是月份，年份作为分组表头。
    expect(find.text('第1周'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('行为当月第几周，列为月份'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('筛选非铁路后，图表与出行指标同口径', (tester) async {
    await _pumpPage(tester, [
      ...trips,
      _trip(
        id: 3,
        mileageKm: 300,
        price: 80,
        duration: const Duration(hours: 2),
        isRailTrip: false,
      ),
    ]);

    expect(find.text('3 段行程'), findsWidgets);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text('筛选'), findsOneWidget);

    await tester.tap(find.text('非铁路'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.text('1 段行程'), findsWidgets);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
