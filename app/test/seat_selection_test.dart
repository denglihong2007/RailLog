import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/seat_selection.dart';
import 'package:raillog/src/widgets/trip_details/trip_form_common.dart';

void main() {
  test('未知车厢和座位以零保存并可重新解析', () {
    const selection = SeatSelection(
      mode: '席位',
      carriageNumber: SeatOptions.unknownNumber,
      primaryNumber: SeatOptions.unknownNumber,
      secondaryNumber: 'A',
    );

    expect(selection.seatNumber, '0车0号');
    final parsed = parseTripSeat('二等座', selection.seatNumber);
    expect(parsed.seatMode, '席位');
    expect(parsed.carriageNumber, SeatOptions.unknownNumber);
    expect(parsed.primarySeatNumber, SeatOptions.unknownNumber);
    expect(parsed.secondarySeatNumber, '无');
  });

  test('99号车厢保持原有存储逻辑', () {
    const selection = SeatSelection(
      mode: '席位',
      carriageNumber: 99,
      primaryNumber: 12,
      secondaryNumber: 'A',
    );

    expect(selection.seatNumber, '99车12A号');
  });

  testWidgets('票价输入框提示积分兑换填写零', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TripPriceField(controller: controller)),
      ),
    );

    expect(find.text('积分兑换请填0'), findsOneWidget);
  });
}
