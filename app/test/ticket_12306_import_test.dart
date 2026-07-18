import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/ticket_12306_order.dart';
import 'package:raillog/src/pages/add_trip_page.dart';
import 'package:raillog/src/pages/import_12306_page.dart';
import 'package:raillog/src/pages/trip_details_page.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';
import 'package:raillog/src/services/ticket_12306_service.dart';

void main() {
  group('12306 invoice mapping', () {
    test('maps electronic invoice fields used by local trip records', () {
      final order = Ticket12306Service.parseInvoiceTicket({
        'local_start_time': '202607182135',
        'local_arrive_time': '202607190812',
        'board_train_code': 'Z123',
        'train_code': 'Z122',
        'from_station_name': '北京西',
        'to_station_name': '武昌',
        'distance': '1225',
        'passenger_name': '测试乘客',
        'seat_type_name': '硬卧',
        'coach_name': '08',
        'seat_name': '12号下铺',
        'ticket_price': '2155',
        'status_name': '已出站',
        'sequence_no': 'E123',
        'batch_no': '1',
        'ext_ticket_no': 'ticket-123',
      });

      expect(order, isNotNull);
      expect(order!.trainCode, 'Z123');
      expect(order.fromStation, '北京西');
      expect(order.toStation, '武昌');
      expect(order.startTime, DateTime(2026, 7, 18, 21, 35));
      expect(order.arriveTime, DateTime(2026, 7, 19, 8, 12));
      expect(order.distance, 1225);
      expect(order.price, 215.5);
      expect(order.seatDisplay, '硬卧 08车12号下铺');
      expect(order.seatNumber, '08车12号下铺');
      expect(order.canImport, isTrue);
    });

    test('rejects unusable records and changed or refunded tickets', () {
      expect(
        Ticket12306Service.parseInvoiceTicket(const {
          'local_start_time': 'invalid',
          'local_arrive_time': '202607190812',
        }),
        isNull,
      );
      for (final status in ['已退票', '已改签', '变更到站']) {
        final order = Ticket12306Order(
          id: status,
          sequenceNo: '',
          startTime: DateTime(2026),
          arriveTime: null,
          trainCode: 'G1',
          fromStation: '北京南',
          toStation: '上海虹桥',
          distance: 0,
          passengerName: '',
          seatType: '',
          coachName: '',
          seatName: '',
          price: 0,
          statusText: status,
        );
        expect(order.canImport, isFalse, reason: status);
      }
    });
  });

  testWidgets('12306 entry card opens the client import page', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AddTripPage(onTripSaved: () {})));

    await tester.scrollUntilVisible(
      find.text('12306 导入'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('12306 导入'));
    await tester.pumpAndSettle();

    expect(find.text('12306 行程'), findsOneWidget);
    expect(find.text('获取二维码'), findsOneWidget);
    expect(find.textContaining('服务端'), findsNothing);
  });

  testWidgets('import page keeps its MD3 layout usable at 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: Import12306Page(service: _FakeTicket12306Service())),
    );
    await tester.tap(find.text('获取二维码'));
    await tester.pumpAndSettle();

    expect(find.text('登录铁路 12306'), findsOneWidget);
    expect(find.text('核验电子发票访问'), findsWidgets);
    expect(find.text('选择待导入行程'), findsOneWidget);
    expect(find.text('Z123'), findsOneWidget);
    final service =
        tester.widget<Import12306Page>(find.byType(Import12306Page)).service!
            as _FakeTicket12306Service;
    expect(service.invoiceQrRequests, 1);
    expect(service.invoiceQueries, 1);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -760));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Z123'));
    await tester.pump();
    expect(find.text('开始确认'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('second QR code recommends keeping requests active in a window', (
    tester,
  ) async {
    final service = _PendingInvoiceVerificationService();
    await tester.pumpWidget(
      MaterialApp(home: Import12306Page(service: service)),
    );
    await tester.tap(find.text('获取二维码'));
    for (var index = 0; index < 8; index++) {
      await tester.pump();
    }

    expect(find.text('核验电子发票访问'), findsWidgets);
    expect(find.textContaining('小窗模式'), findsOneWidget);
    expect(find.byType(Card), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    service.completePendingCheck();
  });

  testWidgets('login QR code also recommends using a small window', (
    tester,
  ) async {
    final service = _PendingLoginVerificationService();
    await tester.pumpWidget(
      MaterialApp(home: Import12306Page(service: service)),
    );
    await tester.tap(find.text('获取二维码'));
    for (var index = 0; index < 6; index++) {
      await tester.pump();
    }

    expect(find.text('使用 12306 App 扫码'), findsOneWidget);
    expect(find.textContaining('小窗模式'), findsOneWidget);
    expect(find.byType(Card), findsWidgets);
    expect(
      tester.getTopLeft(find.text('建议开启小窗模式')).dy,
      lessThan(tester.getTopLeft(find.text('登录铁路 12306')).dy),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    service.completePendingCheck();
  });

  test('review page receives import progress and ticket values', () {
    final departure = DateTime(2026, 7, 18, 21, 35);
    final arrival = DateTime(2026, 7, 19, 8, 12);
    final page = TripDetailsPage(
      trainNumber: 'Z123',
      scheduleStops: [
        TrainScheduleStop(
          stationName: '北京西',
          stationNo: '01',
          arriveTime: '--',
          startTime: '21:35',
          runningTime: '00:00',
          arriveDay: '当日',
          arriveDayDifference: 0,
          arrivalDateTime: departure,
          departureDateTime: departure,
        ),
        TrainScheduleStop(
          stationName: '武昌',
          stationNo: '02',
          arriveTime: '08:12',
          startTime: '--',
          runningTime: '10:37',
          arriveDay: '次日',
          arriveDayDifference: 1,
          arrivalDateTime: arrival,
          departureDateTime: arrival,
        ),
      ],
      departureStopIndex: 0,
      arrivalStopIndex: 1,
      initialSeatType: '硬卧',
      initialSeatNumber: '08车12号下铺',
      initialMileageKm: 1225,
      initialPrice: 215.5,
      initialNotes: '已支付',
      reviewPosition: 1,
      reviewTotal: 2,
    );

    expect(page.reviewPosition, 1);
    expect(page.reviewTotal, 2);
    expect(page.initialSeatNumber, '08车12号下铺');
    expect(page.initialPrice, 215.5);
  });
}

class _FakeTicket12306Service extends Ticket12306Service {
  int invoiceQrRequests = 0;
  int invoiceQueries = 0;

  @override
  Future<Ticket12306QrCode> createQrCode() async => const Ticket12306QrCode(
    uuid: 'test-uuid',
    imageBase64:
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  @override
  Future<Ticket12306QrStatus> checkQrStatus(String uuid) async =>
      const Ticket12306QrStatus(
        code: '2',
        message: '登录成功',
        uamtk: 'test-ticket',
      );

  @override
  Future<String> completeLogin(String uamtk) async => '测试账号';

  @override
  Future<Ticket12306QrCode> createInvoiceVerificationQr() async {
    invoiceQrRequests++;
    return const Ticket12306QrCode(
      uuid: 'invoice-uuid',
      imageBase64:
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
  }

  @override
  Future<Ticket12306QrStatus> checkInvoiceVerificationQr(String uuid) async =>
      const Ticket12306QrStatus(code: '2', message: '电子发票访问核验通过');

  @override
  Future<List<Ticket12306Order>> queryInvoiceTrips({DateTime? now}) async {
    invoiceQueries++;
    return [
      Ticket12306Order(
        id: 'ticket-1',
        sequenceNo: 'sequence-1',
        startTime: DateTime(2026, 7, 18, 21, 35),
        arriveTime: DateTime(2026, 7, 19, 8, 12),
        trainCode: 'Z123',
        fromStation: '北京西',
        toStation: '武昌',
        distance: 1225,
        passengerName: '测试乘客',
        seatType: '硬卧',
        coachName: '08',
        seatName: '12号下铺',
        price: 215.5,
        statusText: '已支付',
      ),
    ];
  }
}

class _PendingInvoiceVerificationService extends _FakeTicket12306Service {
  final _pendingCheck = Completer<Ticket12306QrStatus>();

  @override
  Future<Ticket12306QrStatus> checkInvoiceVerificationQr(String uuid) =>
      _pendingCheck.future;

  void completePendingCheck() {
    if (!_pendingCheck.isCompleted) {
      _pendingCheck.complete(
        const Ticket12306QrStatus(code: '2', message: '电子发票访问核验通过'),
      );
    }
  }
}

class _PendingLoginVerificationService extends _FakeTicket12306Service {
  final _pendingCheck = Completer<Ticket12306QrStatus>();

  @override
  Future<Ticket12306QrStatus> checkQrStatus(String uuid) =>
      _pendingCheck.future;

  void completePendingCheck() {
    if (!_pendingCheck.isCompleted) {
      _pendingCheck.complete(
        const Ticket12306QrStatus(code: '3', message: '二维码已过期'),
      );
    }
  }
}
