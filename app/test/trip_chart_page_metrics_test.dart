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
}) {
  final departure = DateTime(2026, 1, id);
  return DashboardTripEntry(
    id: id,
    trainNumber: 'G$id',
    fromStation: '北京南',
    toStation: '上海虹桥',
    departureTime: departure,
    arrivalTime: departure.add(duration),
    mileageKm: mileageKm,
    seatType: '二等座',
    seatNumber: '5车12A号',
    price: price,
    isRailTrip: true,
  );
}

void main() {
  testWidgets('里程选项卡包含对应的出行指标', (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        ),
        home: TripChartPage(
          trips: [
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
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    // 默认在「次数」选项卡，没有对应的平均指标。
    expect(find.text('出行指标'), findsNothing);

    await tester.tap(find.text('里程'));
    await tester.pump(const Duration(milliseconds: 800));

    final scrollable = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('出行指标'),
      400,
      scrollable: scrollable,
    );
    expect(find.text('出行指标'), findsOneWidget);
    expect(find.text('平均总旅速'), findsOneWidget);
    expect(find.text('平均里程'), findsOneWidget);
    expect(find.text('平均时长'), findsNothing);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
