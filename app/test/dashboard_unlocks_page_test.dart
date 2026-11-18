import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/dashboard_unlock_entry.dart';
import 'package:raillog/src/pages/dashboard_unlocks_page.dart';
import 'package:raillog/src/pages/entity_detail_page.dart';
import 'package:raillog/src/theme/app_theme.dart';

DashboardUnlockEntry _entry(String name) => DashboardUnlockEntry(
  name: name,
  trainNumber: 'G1',
  unlockTime: DateTime(2026, 1, 1),
  action: DashboardUnlockAction.ride,
  fromStation: '北京南',
  toStation: '上海虹桥',
  tripIds: const [1],
);

final _trip = DashboardTripEntry(
  id: 1,
  trainNumber: 'G1',
  fromStation: '北京南',
  toStation: '上海虹桥',
  departureTime: DateTime(2026, 1, 1),
  arrivalTime: DateTime(2026, 1, 1, 5),
  mileageKm: 1318,
  seatType: '二等座',
  seatNumber: '5车12A号',
  price: 600,
  isRailTrip: true,
);

Future<void> _pumpPage(
  WidgetTester tester, {
  Size size = const Size(360, 800),
  String? primaryViewLabel,
  List<DashboardUnlockView> otherViews = const [],
  Future<bool?> Function(BuildContext, DashboardTripEntry)? openTrip,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(
        ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
      ),
      home: DashboardUnlocksPage(
        title: '车型种类',
        icon: Icons.train_outlined,
        entries: [_entry('CR400AF')],
        allTrips: [_trip],
        entityType: EntityType.rollingStock,
        primaryViewLabel: primaryViewLabel,
        otherViews: otherViews,
        openTrip: openTrip,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('切换到车号口径后条目改为打开行程', (tester) async {
    DashboardTripEntry? opened;
    await _pumpPage(
      tester,
      primaryViewLabel: '车型',
      otherViews: [
        DashboardUnlockView(label: '车号', entries: [_entry('CR400AF-2011')]),
      ],
      openTrip: (context, trip) async {
        opened = trip;
        return null;
      },
    );

    expect(find.text('CR400AF'), findsOneWidget);
    expect(find.text('CR400AF-2011'), findsNothing);

    await tester.tap(find.text('车号'));
    await tester.pumpAndSettle();
    expect(find.text('CR400AF-2011'), findsOneWidget);
    expect(find.text('CR400AF'), findsNothing);

    await tester.tap(find.text('CR400AF-2011'));
    await tester.pumpAndSettle();
    expect(opened?.id, 1);
  });

  testWidgets('切到路局口径后解锁进度按路局计算', (tester) async {
    await _pumpPage(
      tester,
      primaryViewLabel: '单位',
      otherViews: [
        DashboardUnlockView(
          label: '路局',
          entries: [_entry('上海局')],
          progressCatalog: Future.value(['上海局', '北京局']),
        ),
      ],
    );

    await tester.tap(find.text('路局'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('窄屏下标题与口径切换不溢出', (tester) async {
    await _pumpPage(
      tester,
      size: const Size(320, 800),
      primaryViewLabel: '车型',
      otherViews: [
        DashboardUnlockView(label: '车号', entries: [_entry('CR400AF-2011')]),
      ],
    );
    expect(tester.takeException(), isNull);
  });
}
