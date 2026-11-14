import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/pages/more_statistics_page.dart';
import 'package:raillog/src/theme/app_theme.dart';

DashboardTripEntry _trip({
  required int id,
  required String seatType,
  required String seatNumber,
  required double mileageKm,
  required double price,
  required Duration? duration,
}) {
  final departure = DateTime(2026, 1, id);
  return DashboardTripEntry(
    id: id,
    trainNumber: 'G$id',
    fromStation: '北京南',
    toStation: '上海虹桥',
    departureTime: departure,
    arrivalTime: duration == null ? null : departure.add(duration),
    mileageKm: mileageKm,
    seatType: seatType,
    seatNumber: seatNumber,
    price: price,
    isRailTrip: true,
  );
}

final _trips = [
  _trip(
    id: 1,
    seatType: '二等座',
    seatNumber: '5车12A号',
    mileageKm: 1000,
    price: 600,
    duration: const Duration(hours: 5),
  ),
  _trip(
    id: 2,
    seatType: '硬卧',
    seatNumber: '5车13号下铺',
    mileageKm: 800,
    price: 300,
    duration: const Duration(hours: 8),
  ),
  _trip(
    id: 3,
    seatType: '硬座',
    seatNumber: '5车17号',
    mileageKm: 400,
    price: 80,
    duration: const Duration(hours: 6),
  ),
  _trip(
    id: 4,
    seatType: '二等座',
    seatNumber: '5车无座',
    mileageKm: 0,
    price: 0,
    duration: null,
  ),
];

Future<void> _pumpPage(
  WidgetTester tester, {
  Future<bool?> Function(BuildContext, DashboardTripEntry)? openTrip,
}) async {
  tester.view.physicalSize = const Size(360, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(
        ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
      ),
      home: MoreStatisticsPage(trips: _trips, openTrip: openTrip),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('窄屏渲染全部统计区块且无布局异常', (tester) async {
    await _pumpPage(tester);

    expect(find.text('坐席统计'), findsOneWidget);
    expect(find.text('靠窗 1 次 · 50%'), findsOneWidget);
    expect(find.text('靠过道 1 次 · 50%'), findsOneWidget);
    expect(find.text('铺位统计'), findsOneWidget);
    expect(find.text('席别统计'), findsOneWidget);
    expect(find.text('出行指标'), findsNothing);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('点击座位把对应行程交给详情入口', (tester) async {
    DashboardTripEntry? opened;
    await _pumpPage(
      tester,
      openTrip: (context, trip) async {
        opened = trip;
        return false;
      },
    );

    await tester.tap(find.textContaining('A · 尾号'));
    await tester.pump();

    expect(opened?.id, 1);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('点击靠窗汇总把对应行程交给详情入口', (tester) async {
    DashboardTripEntry? opened;
    await _pumpPage(
      tester,
      openTrip: (context, trip) async {
        opened = trip;
        return false;
      },
    );

    await tester.tap(find.text('靠窗 1 次 · 50%'));
    await tester.pump();

    expect(opened?.id, 1);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
