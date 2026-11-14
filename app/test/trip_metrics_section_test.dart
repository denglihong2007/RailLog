import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/trip_metrics_statistics.dart';
import 'package:raillog/src/theme/app_theme.dart';
import 'package:raillog/src/widgets/trip_metrics_section.dart';

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

  Future<void> pumpSection(
    WidgetTester tester, {
    required Set<TripMetricKind> kinds,
    required TripListOpener onOpenTrips,
  }) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: AppSpacing.page,
            child: TripMetricsSection(
              metrics: TripMetricsStatistics.fromTrips(trips),
              kinds: kinds,
              onOpenTrips: onOpenTrips,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('展示五项指标且无布局异常', (tester) async {
    await pumpSection(
      tester,
      kinds: TripMetricKind.values.toSet(),
      onOpenTrips: (title, trips) async {},
    );

    for (final title in ['平均总旅速', '平均里程', '平均单位票价', '平均单程票价', '平均时长']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('200 km/h'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('只展示当前选项卡对应的指标', (tester) async {
    await pumpSection(
      tester,
      kinds: const {TripMetricKind.unitPrice, TripMetricKind.ticketPrice},
      onOpenTrips: (title, trips) async {},
    );

    expect(find.text('平均单位票价'), findsOneWidget);
    expect(find.text('平均单程票价'), findsOneWidget);
    expect(find.text('平均总旅速'), findsNothing);
    expect(find.text('平均里程'), findsNothing);
    expect(find.text('平均时长'), findsNothing);
    expect(find.text('按单段行程平均。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('点击平均值把对应行程交给详情入口', (tester) async {
    String? openedTitle;
    List<DashboardTripEntry>? openedTrips;
    await pumpSection(
      tester,
      kinds: TripMetricKind.values.toSet(),
      onOpenTrips: (title, trips) async {
        openedTitle = title;
        openedTrips = trips;
      },
    );

    await tester.tap(find.text('200 km/h'));
    await tester.pump();

    expect(openedTitle, '平均总旅速');
    expect(openedTrips?.map((trip) => trip.id).toSet(), {1, 2});
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
