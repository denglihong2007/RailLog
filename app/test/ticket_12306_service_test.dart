import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/ticket_12306_order.dart';
import 'package:raillog/src/services/ticket_12306_service.dart';

Ticket12306Order _order({
  String trainCode = 'G1',
  String fromStation = '北京南',
  String toStation = '上海虹桥',
  DateTime? startTime,
  String passengerName = '张三',
  String coachName = '05',
  String seatName = '12A',
  String statusText = '已支付',
}) {
  return Ticket12306Order(
    id: '$trainCode|$passengerName',
    sequenceNo: 'E123456789',
    startTime: startTime ?? DateTime(2026, 9, 1, 8, 0),
    arriveTime: DateTime(2026, 9, 1, 12, 30),
    trainCode: trainCode,
    fromStation: fromStation,
    toStation: toStation,
    distance: 1318,
    passengerName: passengerName,
    seatType: '二等座',
    coachName: coachName,
    seatName: seatName,
    price: 553,
    statusText: statusText,
  );
}

void main() {
  group('Ticket12306Service.parseOrderTicket', () {
    test('maps order payload fields into a trip order', () {
      final parsed = Ticket12306Service.parseOrderTicket(
        const {
          'start_train_date_page': '2026-09-01 08:00',
          'seat_type_name': '二等座',
          'coach_name': '05',
          'seat_name': '12A',
          'str_ticket_price_page': '¥553.00',
          'ticket_status_name': '已支付',
          'sequence_no': 'E123456789',
          'stationTrainDTO': {
            'station_train_code': 'G1',
            'from_station_name': '北京南',
            'to_station_name': '上海虹桥',
            'distance': '1318',
            'arrive_date_local': '2026-09-01',
            'arrive_time_local': '12:30',
          },
          'passengerDTO': {'passenger_name': '张三'},
        },
        sequenceNo: 'E123456789',
      );

      expect(parsed, isNotNull);
      expect(parsed!.trainCode, 'G1');
      expect(parsed.fromStation, '北京南');
      expect(parsed.toStation, '上海虹桥');
      expect(parsed.startTime, DateTime(2026, 9, 1, 8, 0));
      expect(parsed.arriveTime, DateTime(2026, 9, 1, 12, 30));
      expect(parsed.distance, 1318);
      expect(parsed.price, 553);
      expect(parsed.passengerName, '张三');
      expect(parsed.seatDisplay, '二等座 05车12A');
      expect(parsed.seatNumber, '05车12A');
      expect(parsed.statusText, '已支付');
      expect(parsed.canImport, isTrue);
    });

    test('accepts Chinese date separators and missing station details', () {
      final parsed = Ticket12306Service.parseOrderTicket(const {
        'start_train_date_page': '2026年9月1日 20:05',
        'sequence_no': 'E1',
      });

      expect(parsed, isNotNull);
      expect(parsed!.startTime, DateTime(2026, 9, 1, 20, 5));
      expect(parsed.arriveTime, isNull);
      expect(parsed.trainCode, isEmpty);
      expect(parsed.price, 0);
    });

    test('returns null when the departure time cannot be parsed', () {
      expect(
        Ticket12306Service.parseOrderTicket(const {
          'start_train_date_page': '',
          'sequence_no': 'E1',
        }),
        isNull,
      );
    });

    test('marks refunded and rescheduled tickets as not importable', () {
      final refunded = Ticket12306Service.parseOrderTicket(const {
        'start_train_date_page': '2026-09-01 08:00',
        'ticket_status_name': '已退票',
      });
      final rescheduled = Ticket12306Service.parseOrderTicket(const {
        'start_train_date_page': '2026-09-01 08:00',
        'ticket_status_name': '已改签',
      });

      expect(refunded!.canImport, isFalse);
      expect(rescheduled!.canImport, isFalse);
    });
  });

  group('Ticket12306Service.credentials', () {
    test('restores unexpired cookies and exports them again', () {
      final service = Ticket12306Service();
      addTearDown(service.dispose);

      final restored = service.restoreCredentials(
        Ticket12306Credentials(
          username: '张三',
          loginAt: DateTime(2026, 11, 18, 10, 30),
          cookies: [
            Ticket12306Cookie(
              name: 'tk',
              value: 'abc',
              domain: 'kyfw.12306.cn',
              path: '/',
              expires: DateTime.now().add(const Duration(days: 1)),
            ),
            const Ticket12306Cookie(
              name: 'RAIL_EXPIRATION',
              value: '123',
              domain: 'kyfw.12306.cn',
              path: '/',
            ),
          ],
        ),
      );

      expect(restored, isTrue);
      expect(service.hasSession, isTrue);
      expect(service.username, '张三');

      final exported = service.exportCredentials(invoiceVerified: true);
      expect(exported.username, '张三');
      expect(exported.cookies, hasLength(2));
      expect(exported.invoiceVerified, isTrue);
      expect(
        exported.loginAt.difference(DateTime.now()).inMinutes,
        inInclusiveRange(-1, 1),
      );
    });

    test('drops expired cookies when restoring', () {
      final service = Ticket12306Service();
      addTearDown(service.dispose);

      final restored = service.restoreCredentials(
        Ticket12306Credentials(
          username: '张三',
          loginAt: DateTime(2026, 11, 18),
          cookies: [
            Ticket12306Cookie(
              name: 'tk',
              value: 'abc',
              expires: DateTime.now().subtract(const Duration(minutes: 1)),
            ),
          ],
        ),
      );

      expect(restored, isFalse);
      expect(service.hasSession, isFalse);
    });
  });

  group('describeTicket12306LoginFailure', () {
    test('keeps the server message for a wrong password', () {
      expect(describeTicket12306LoginFailure(4, '密码输入错误'), '密码输入错误');
    });

    test('falls back to a generic message when the server returns none', () {
      expect(describeTicket12306LoginFailure(4, ''), '账号或密码错误');
    });

    test('points extra verification accounts to QR login', () {
      expect(
        describeTicket12306LoginFailure(97, '请完成验证'),
        '该账号还需要额外身份验证，请改用扫码登录',
      );
    });

    test('keeps the password-too-old message', () {
      expect(
        describeTicket12306LoginFailure(101, ''),
        '密码太久没有修改，请先在 12306 修改密码',
      );
    });
  });

  group('Ticket12306Service.parsePersonalTicket', () {
    test('maps 本人车票 payload fields into a trip order', () {
      final parsed = Ticket12306Service.parsePersonalTicket(const {
        'local_start_time': '202611081633',
        'local_arrive_time': '202611081723',
        'start_date': '2026-11-08',
        'start_time': '16:33',
        'arrive_date': '20261108',
        'arrive_time': '17:23',
        'train_code': 'D1937',
        'board_train_code': 'D1937',
        'from_station_name': '广元',
        'to_station_name': '绵阳',
        'distance': '165',
        'passenger_name': '邓力洪',
        'seat_type_name': '二等座',
        'coach_name': '99',
        'seat_name': '无座',
        'ticket_price': '750',
        'status_name': '已出站',
        'sequence_no': 'YD18073845',
        'ext_ticket_no': '4541370001110900001562026',
      });

      expect(parsed, isNotNull);
      expect(parsed!.trainCode, 'D1937');
      expect(parsed.fromStation, '广元');
      expect(parsed.toStation, '绵阳');
      expect(parsed.startTime, DateTime(2026, 11, 8, 16, 33));
      expect(parsed.arriveTime, DateTime(2026, 11, 8, 17, 23));
      expect(parsed.distance, 165);
      expect(parsed.price, 75);
      expect(parsed.passengerName, '邓力洪');
      expect(parsed.statusText, '已出站');
      expect(parsed.canImport, isTrue);
    });

    test('falls back to the separate date and time fields', () {
      final parsed = Ticket12306Service.parsePersonalTicket(const {
        'start_date': '2026-11-08',
        'start_time': '16:33',
        'arrive_date': '20261108',
        'arrive_time': '17:23',
        'train_code': 'D1937',
      });

      expect(parsed, isNotNull);
      expect(parsed!.startTime, DateTime(2026, 11, 8, 16, 33));
      expect(parsed.arriveTime, DateTime(2026, 11, 8, 17, 23));
    });

    test('returns null when the departure time cannot be parsed', () {
      expect(
        Ticket12306Service.parsePersonalTicket(const {'train_code': 'D1937'}),
        isNull,
      );
    });
  });

  group('Ticket12306Service.buildPersonalTripWindows', () {
    test('splits a year into windows of at most 180 days', () {
      final windows = Ticket12306Service.buildPersonalTripWindows(
        DateTime(2026, 11, 19),
      );

      expect(windows, hasLength(3));
      expect(windows[0].start, DateTime(2026, 5, 24));
      expect(windows[0].end, DateTime(2026, 11, 19));
      expect(windows[1].start, DateTime(2025, 11, 25));
      expect(windows[1].end, DateTime(2026, 5, 23));
      expect(windows[2].start, DateTime(2025, 11, 20));
      expect(windows[2].end, DateTime(2025, 11, 24));
      for (final window in windows) {
        expect(
          window.end.difference(window.start).inDays + 1,
          lessThanOrEqualTo(180),
        );
      }
    });

    test('keeps short ranges in a single window', () {
      final windows = Ticket12306Service.buildPersonalTripWindows(
        DateTime(2026, 11, 19),
        totalDays: 30,
      );

      expect(windows, hasLength(1));
      expect(windows.single.start, DateTime(2026, 10, 21));
      expect(windows.single.end, DateTime(2026, 11, 19));
    });
  });

  group('Ticket12306Service.mergeTrips', () {
    test('deduplicates the same ticket and prefers the extra source', () {
      final base = _order(statusText: '已支付');
      final extra = _order(statusText: '已开具电子发票');

      final merged = Ticket12306Service.mergeTrips([base], [extra]);

      expect(merged, hasLength(1));
      expect(merged.single.statusText, '已开具电子发票');
    });

    test('keeps order-only tickets and sorts by departure descending', () {
      final orderOnly = _order(
        trainCode: 'K1',
        startTime: DateTime(2026, 8, 1, 9, 0),
      );
      final shared = _order(startTime: DateTime(2026, 9, 1, 8, 0));
      final extraOnly = _order(
        trainCode: 'D2',
        startTime: DateTime(2026, 9, 10, 7, 0),
      );

      final merged = Ticket12306Service.mergeTrips([
        orderOnly,
        shared,
      ], [extraOnly, _order(startTime: DateTime(2026, 9, 1, 8, 0))]);

      expect(merged.map((order) => order.trainCode), ['D2', 'G1', 'K1']);
    });

    test('treats a different seat as a different ticket', () {
      final merged = Ticket12306Service.mergeTrips([
        _order(seatName: '12A'),
      ], [
        _order(seatName: '12B'),
      ]);

      expect(merged, hasLength(2));
    });

    test('treats a different passenger as a different ticket', () {
      final merged = Ticket12306Service.mergeTrips([
        _order(passengerName: '张三'),
      ], [
        _order(passengerName: '李四'),
      ]);

      expect(merged, hasLength(2));
    });
  });
}
