import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/pages/manual_trip_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('新增页在行程属性中显示铁路行程和本地行程', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ManualTripPage()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pump();

    expect(find.text('行程属性'), findsOneWidget);
    expect(find.text('铁路行程'), findsOneWidget);
    expect(find.text('本地行程'), findsOneWidget);
  });

  testWidgets('编辑页将同步开关显示为云端行程', (tester) async {
    final trip = TripRecord(
      id: 1,
      trainNumber: 'G1',
      fromStation: '北京',
      toStation: '上海',
      departureTime: DateTime(2026, 1, 1, 8),
      arrivalTime: DateTime(2026, 1, 1, 12),
      viaRouteSegments: const [],
    );
    await tester.pumpWidget(
      MaterialApp(home: ManualTripPage(initialTrip: trip)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pump();

    expect(find.text('行程属性'), findsOneWidget);
    expect(find.text('铁路行程'), findsOneWidget);
    expect(find.text('云端行程'), findsOneWidget);
    expect(find.text('本地行程'), findsNothing);
  });
}
