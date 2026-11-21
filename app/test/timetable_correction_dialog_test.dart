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

TripScheduleTimes _timesWithPass() => TripScheduleTimes(
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
      stationName: '德州东',
      arrival: null,
      departure: null,
      mileage: 315,
    ),
    TripScheduleStop(
      stationName: '上海虹桥',
      arrival: _at(12, 0),
      departure: null,
      mileage: 1323,
    ),
  ],
  boardingIndex: 0,
  alightingIndex: 3,
);

class _ResultHolder {
  TripScheduleOverlay? value;
}

Widget _host(
  _ResultHolder holder,
  TripScheduleOverlay overlay,
  List<String> stationNames, {
  List<double>? mileage,
}) {
  final scheduleTimes = overlay.annotate(
    stationNames: stationNames,
    mileage:
        mileage ??
        [
          for (var index = 0; index < stationNames.length; index++)
            index * 10.0,
        ],
  );
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            final corrected = await showTimetableCorrectionDialog(
              context,
              overlay: overlay,
              stationNames: stationNames,
              scheduleTimes: scheduleTimes,
              baseDate: _at(0, 0),
            );
            if (corrected != null) holder.value = corrected;
          },
          child: const Text('打开'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('底部编辑器显示停站与通过站的时间胶囊', (tester) async {
    final result = _ResultHolder();
    final overlay = TripScheduleOverlay(times: _timesWithPass());
    const names = ['北京南', '沧州西', '德州东', '上海虹桥'];
    const mileage = [0.0, 210.0, 315.0, 1323.0];
    await tester.pumpWidget(_host(result, overlay, names, mileage: mileage));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('编辑中间站时刻'), findsOneWidget);
    expect(find.text('沧州西'), findsOneWidget);
    expect(find.text('德州东'), findsOneWidget);
    expect(find.text('到 08:40'), findsOneWidget);
    expect(find.text('发 08:42'), findsOneWidget);
    expect(find.textContaining('通过 '), findsOneWidget);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(result.value, isNotNull);
    expect(result.value!.times!.stops[1].arrival, _at(8, 40));
    expect(result.value!.times!.stops[1].departure, _at(8, 42));
  });

  testWidgets('点击圆点可以从通过站改成停站', (tester) async {
    final result = _ResultHolder();
    final overlay = TripScheduleOverlay(times: _timesWithPass());
    const names = ['北京南', '沧州西', '德州东', '上海虹桥'];
    const mileage = [0.0, 210.0, 315.0, 1323.0];
    await tester.pumpWidget(_host(result, overlay, names, mileage: mileage));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 第二行是通过站德州东，点圆点改成停站。
    await tester.tap(find.byTooltip('点击改为停靠站'));
    await tester.pumpAndSettle();

    expect(find.text('发 时刻'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    final key = stationOccurrenceKeys(names)[2];
    final custom = result.value!.customTimes[key];
    expect(custom, isNotNull);
    expect(custom!.arrival, isNotNull);
    expect(custom.departure, isNull);
  });

  testWidgets('没有历史数据时直接显示添加时刻的胶囊', (tester) async {
    final result = _ResultHolder();
    const overlay = TripScheduleOverlay();
    const names = ['北京南', '广元', '绵阳'];
    await tester.pumpWidget(_host(result, overlay, names));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('到 时刻'), findsOneWidget);
    expect(find.text('发 时刻'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(result.value!.customTimes, isEmpty);
  });

  testWidgets('撤销修改会撤销本次编辑', (tester) async {
    final result = _ResultHolder();
    final overlay = TripScheduleOverlay(times: _timesWithPass());
    const names = ['北京南', '沧州西', '德州东', '上海虹桥'];
    const mileage = [0.0, 210.0, 315.0, 1323.0];
    await tester.pumpWidget(_host(result, overlay, names, mileage: mileage));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('点击改为停靠站'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('撤销修改'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(result.value!.customTimes, isEmpty);
    expect(result.value!.times!.passTimeOverrides, isEmpty);
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
