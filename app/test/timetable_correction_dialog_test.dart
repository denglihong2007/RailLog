import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:raillog/src/models/trip_schedule_times.dart';
import 'package:raillog/src/widgets/trip_details/timetable_correction_dialog.dart';

DateTime _at(int hour, int minute) => DateTime(2026, 1, 1, hour, minute);

TripScheduleTimes _times() => TripScheduleTimes(
  stops: [
    TripScheduleStop(
      stationName: '北京南',
      arrival: null,
      departure: _at(8, 0),
      mileage: 0,
    ),
    TripScheduleStop(
      stationName: '沧州西',
      arrival: _at(8, 40),
      departure: _at(8, 42),
      mileage: 210,
    ),
    TripScheduleStop(
      stationName: '上海虹桥',
      arrival: _at(12, 0),
      departure: null,
      mileage: 1323,
    ),
  ],
  boardingIndex: 0,
  alightingIndex: 2,
);

Widget _host(_ResultHolder holder, TripScheduleTimes times) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            final corrected = await showTimetableCorrectionDialog(
              context,
              times: times,
            );
            if (corrected != null) holder.value = corrected;
          },
          child: const Text('打开'),
        ),
      ),
    ),
  );
}

class _ResultHolder {
  List<TripScheduleStop>? value;
}

void main() {
  testWidgets('矫正对话框拒绝非法时刻，应用后返回新的站序', (tester) async {
    final result = _ResultHolder();
    await tester.pumpWidget(_host(result, _times()));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('手动矫正时刻表'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '25:99');
    await tester.tap(find.text('应用'));
    await tester.pump();
    expect(find.text('时刻格式应为 HH:mm，例如 08:05'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '08:50');
    await tester.enterText(find.byType(TextField).at(1), '08:52');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(result.value, isNotNull);
    expect(result.value![1].arrival, _at(8, 50));
    // 没改动的发点原样保留。
    expect(result.value![1].departure, _at(8, 52));
  });

  testWidgets('发点早于到点时拒绝应用', (tester) async {
    final result = _ResultHolder();
    await tester.pumpWidget(_host(result, _times()));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '08:50');
    await tester.tap(find.text('应用'));
    await tester.pump();

    expect(find.text('发点不能早于到点'), findsOneWidget);
    expect(result.value, isNull);
  });

  testWidgets('到发时刻都留空时该站按通过处理', (tester) async {
    final result = _ResultHolder();
    await tester.pumpWidget(_host(result, _times()));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '');
    await tester.enterText(fields.at(1), '');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(result.value, isNotNull);
    expect(result.value![1].arrival, isNull);
    expect(result.value![1].departure, isNull);
  });

  test('构造参数的断言挡住越界的上下车站', () {
    expect(
      () => TripScheduleTimes(
        stops: _times().stops,
        boardingIndex: 1,
        alightingIndex: 1,
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
