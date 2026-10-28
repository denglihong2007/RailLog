import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/pages/all_trips_page.dart';

/// 纯 UI 测试：注入 openTrip，页面不会碰数据库。
Future<void> _pump(
  WidgetTester tester, {
  List<DashboardTripEntry>? trips,
  bool? compact,
  Size size = const Size(800, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: AllTripsPage(
        trips: trips ?? _groupedTrips(),
        enableSelection: true,
        enableGrouping: true,
        compactView: compact,
        openTrip: (context, trip) async => null,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('分组卡片显示聚合值，点击展开为原行程卡片', (tester) async {
    await _pump(tester);

    expect(find.text('京沪往返'), findsOneWidget);
    expect(find.text('2 趟'), findsOneWidget);
    expect(find.text('2026-01-01'), findsOneWidget);
    expect(find.text('500 km'), findsOneWidget);
    expect(find.text('¥250.00'), findsOneWidget);
    expect(find.text('3时'), findsOneWidget);
    expect(find.text('二等座'), findsOneWidget);
    expect(find.text('G1'), findsNothing);

    await tester.tap(find.text('京沪往返'));
    await tester.pumpAndSettle();

    // 展开后是原样的行程卡片，紧跟在分组卡片后面。
    expect(find.text('G1'), findsOneWidget);
    expect(find.text('G2'), findsOneWidget);
    expect(find.text('二等座'), findsNWidgets(3));
    // 未分组的那趟仍是独立卡片。
    expect(find.text('D3'), findsOneWidget);

    await tester.tap(find.text('京沪往返'));
    await tester.pumpAndSettle();
    expect(find.text('G1'), findsNothing);
  });

  testWidgets('进入多选后分组拆开，退出后恢复', (tester) async {
    await _pump(tester);

    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pumpAndSettle();

    expect(find.text('京沪往返'), findsNothing);
    expect(find.text('G1'), findsOneWidget);
    expect(find.text('G2'), findsOneWidget);

    await tester.tap(find.text('G1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已选择 1 项'), findsOneWidget);

    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();

    expect(find.text('京沪往返'), findsOneWidget);
  });

  testWidgets('不同分组使用不同配色，组内卡片沿用分组配色', (tester) async {
    await _pump(
      tester,
      trips: [
        _entry(
          id: 1,
          trainNumber: 'G1',
          from: '北京南',
          to: '济南西',
          departure: DateTime(2026, 1, 1, 8),
          arrival: DateTime(2026, 1, 1, 9),
          groupName: '甲组',
        ),
        _entry(
          id: 2,
          trainNumber: 'G2',
          from: '济南西',
          to: '上海虹桥',
          departure: DateTime(2026, 1, 1, 10),
          arrival: DateTime(2026, 1, 1, 12),
          groupName: '甲组',
        ),
        _entry(
          id: 3,
          trainNumber: 'G3',
          from: '上海虹桥',
          to: '杭州东',
          departure: DateTime(2026, 1, 2, 9),
          arrival: DateTime(2026, 1, 2, 10),
          groupName: '乙组',
        ),
      ],
    );

    final firstColor = _headerColor(tester, '甲组');
    final secondColor = _headerColor(tester, '乙组');
    expect(firstColor, isNot(secondColor));

    await tester.tap(find.text('甲组'));
    await tester.pumpAndSettle();

    expect(_headerColor(tester, 'G1'), firstColor);
    expect(_headerColor(tester, 'G2'), firstColor);
  });

  testWidgets('紧凑视图只保留基础信息，卡片明显变矮', (tester) async {
    await _pump(tester, compact: true);

    // 分组卡片：分组名、趟数、起讫站与总价，不再显示坐席与里程。
    expect(find.text('京沪往返'), findsOneWidget);
    expect(find.text('2 趟 · 2026-01-01 08:00'), findsOneWidget);
    expect(find.text('北京南 → 上海虹桥'), findsOneWidget);
    expect(find.text('¥250.00'), findsOneWidget);
    expect(find.text('二等座'), findsNothing);
    expect(find.text('500 km'), findsNothing);

    // 未分组的行程同样是紧凑卡片。
    expect(find.text('D3 · 2026-01-02 09:00'), findsOneWidget);
    expect(find.text('上海虹桥 → 杭州东'), findsOneWidget);
    expect(find.text('¥73.00'), findsOneWidget);

    final groupHeight = tester
        .getSize(find.byKey(const ValueKey('group:京沪往返')))
        .height;
    expect(groupHeight, lessThan(80));

    // 展开后成员行程也用紧凑卡片，且保留分组配色。
    await tester.tap(find.text('京沪往返'));
    await tester.pumpAndSettle();

    expect(find.text('G1 · 2026-01-01 08:00'), findsOneWidget);
    expect(find.text('北京南 → 济南西'), findsOneWidget);
    expect(find.text('¥100.00'), findsOneWidget);
    expect(find.text('二等座'), findsNothing);
    expect(find.text('200 km'), findsNothing);
  });

  testWidgets('分组卡片按组内最新一趟的出发时间排序', (tester) async {
    // 单列布局，方便直接比较卡片的上下位置。
    await _pump(
      tester,
      size: const Size(400, 1000),
      trips: [
        _entry(
          id: 1,
          trainNumber: 'G1',
          from: '北京南',
          to: '济南西',
          departure: DateTime(2026, 1, 1, 8),
          groupName: '周末',
        ),
        _entry(
          id: 2,
          trainNumber: 'G2',
          from: '济南西',
          to: '北京南',
          departure: DateTime(2026, 1, 3, 8),
          groupName: '周末',
        ),
        _entry(
          id: 3,
          trainNumber: 'D3',
          from: '上海虹桥',
          to: '杭州东',
          departure: DateTime(2026, 1, 2, 9),
          groupName: null,
        ),
      ],
    );

    // 默认按出发时间倒序。分组取组内最晚一趟（1 月 3 日），
    // 应排在 1 月 2 日的独立行程前面，而不是按最早的 1 月 1 日落到后面。
    final groupTop = tester.getTopLeft(find.text('周末')).dy;
    final singleTop = tester.getTopLeft(find.text('D3')).dy;
    expect(groupTop, lessThan(singleTop));
  });

  testWidgets('往返分组用折返站作为终到站并显示双向箭头', (tester) async {
    await _pump(
      tester,
      trips: [
        _entry(
          id: 1,
          trainNumber: 'G1',
          from: '北京南',
          to: '济南西',
          departure: DateTime(2026, 1, 1, 8),
          arrival: DateTime(2026, 1, 1, 9),
          groupName: '往返',
        ),
        _entry(
          id: 2,
          trainNumber: 'G2',
          from: '济南西',
          to: '上海虹桥',
          departure: DateTime(2026, 1, 1, 10),
          arrival: DateTime(2026, 1, 1, 12),
          groupName: '往返',
        ),
        _entry(
          id: 3,
          trainNumber: 'G3',
          from: '上海虹桥',
          to: '济南西',
          departure: DateTime(2026, 1, 2, 8),
          arrival: DateTime(2026, 1, 2, 10),
          groupName: '往返',
        ),
        _entry(
          id: 4,
          trainNumber: 'G4',
          from: '济南西',
          to: '北京南',
          departure: DateTime(2026, 1, 2, 11),
          arrival: DateTime(2026, 1, 2, 13),
          groupName: '往返',
        ),
      ],
    );

    expect(find.text('往返'), findsOneWidget);
    expect(find.text('上海虹桥'), findsOneWidget);
    expect(find.text('北京南'), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
  });
}

/// 取卡片标题区的底色（卡片里第一个包裹文字的 Container）。
Color? _headerColor(WidgetTester tester, String text) {
  final container = tester.widget<Container>(
    find.ancestor(of: find.text(text), matching: find.byType(Container)).first,
  );
  return container.color;
}

List<DashboardTripEntry> _groupedTrips() => [
  _entry(
    id: 1,
    trainNumber: 'G1',
    from: '北京南',
    to: '济南西',
    departure: DateTime(2026, 1, 1, 8),
    arrival: DateTime(2026, 1, 1, 9),
    mileage: 200,
    price: 100,
    seatType: '二等座',
  ),
  _entry(
    id: 2,
    trainNumber: 'G2',
    from: '济南西',
    to: '上海虹桥',
    departure: DateTime(2026, 1, 1, 10),
    arrival: DateTime(2026, 1, 1, 12),
    mileage: 300,
    price: 150,
    seatType: '二等座',
  ),
  _entry(
    id: 3,
    trainNumber: 'D3',
    from: '上海虹桥',
    to: '杭州东',
    departure: DateTime(2026, 1, 2, 9),
    arrival: DateTime(2026, 1, 2, 10),
    mileage: 160,
    price: 73,
    groupName: null,
  ),
];

DashboardTripEntry _entry({
  required int id,
  required String trainNumber,
  required String from,
  required String to,
  required DateTime departure,
  DateTime? arrival,
  double mileage = 0,
  double price = 0,
  String? seatType,
  String? groupName = '京沪往返',
}) => DashboardTripEntry(
  id: id,
  trainNumber: trainNumber,
  fromStation: from,
  toStation: to,
  departureTime: departure,
  arrivalTime: arrival,
  mileageKm: mileage,
  seatType: seatType,
  seatNumber: null,
  price: price,
  isRailTrip: true,
  groupName: groupName,
);
