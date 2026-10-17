import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/pages/all_trips_page.dart';

/// 纯 UI 测试：注入 openTrip，页面不会碰数据库。
Future<void> _pump(
  WidgetTester tester, {
  List<DashboardTripEntry>? trips,
}) async {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: AllTripsPage(
        trips: trips ?? _groupedTrips(),
        enableSelection: true,
        enableGrouping: true,
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
