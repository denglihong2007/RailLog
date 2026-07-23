import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/pages/all_trips_page.dart';

void main() {
  testWidgets('车票列表支持进入多选并显示批量操作', (tester) async {
    final trip = DashboardTripEntry(
      id: 1,
      ticketId: 101,
      trainNumber: 'G1',
      fromStation: '北京南',
      toStation: '上海虹桥',
      departureTime: DateTime(2026, 7, 23, 8),
      arrivalTime: DateTime(2026, 7, 23, 12, 30),
      mileageKm: 1318,
      seatType: '二等座',
      seatNumber: '01车01A号',
      price: 553,
      isRailTrip: true,
    );

    await tester.pumpWidget(
      MaterialApp(home: AllTripsPage(trips: [trip], enableSelection: true)),
    );
    await tester.tap(find.byTooltip('多选车票'));
    await tester.pump();
    expect(find.text('已选择 0 项'), findsOneWidget);
    await tester.tap(find.text('G1'));
    await tester.pump();

    expect(find.textContaining('已选择 1 项'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('下载图片'), findsOneWidget);
    expect(find.text('订购车票'), findsOneWidget);
    expect(find.byTooltip('全选当前结果'), findsOneWidget);
  });

  testWidgets('长按车票进入多选模式', (tester) async {
    final trip = DashboardTripEntry(
      id: 2,
      trainNumber: 'K2',
      fromStation: '广州',
      toStation: '长沙',
      departureTime: DateTime(2026, 7, 24, 9),
      arrivalTime: null,
      mileageKm: 0,
      seatType: null,
      seatNumber: null,
      price: 0,
      isRailTrip: true,
    );

    await tester.pumpWidget(
      MaterialApp(home: AllTripsPage(trips: [trip], enableSelection: true)),
    );
    await tester.longPress(find.text('K2'));
    await tester.pump();

    expect(find.textContaining('已选择 1 项'), findsOneWidget);
    final downloadButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '下载图片'),
    );
    final orderButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '订购车票'),
    );
    expect(downloadButton.onPressed, isNull);
    expect(orderButton.onPressed, isNull);
  });

  testWidgets('只读行程列表不开放多选操作', (tester) async {
    final trip = DashboardTripEntry(
      id: 3,
      ticketId: 103,
      trainNumber: 'D3',
      fromStation: '杭州东',
      toStation: '宁波',
      departureTime: DateTime(2026, 7, 25, 10),
      arrivalTime: DateTime(2026, 7, 25, 11),
      mileageKm: 150,
      seatType: '二等座',
      seatNumber: '02车02A号',
      price: 80,
      isRailTrip: true,
    );

    await tester.pumpWidget(MaterialApp(home: AllTripsPage(trips: [trip])));
    await tester.longPress(find.text('D3'));
    await tester.pump();

    expect(find.byTooltip('多选车票'), findsNothing);
    expect(find.text('订购车票'), findsNothing);
  });
}
