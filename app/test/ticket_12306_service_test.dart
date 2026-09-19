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

    test('treats a refunded ticket as importable while reschedules are not', () {
      final refunded = Ticket12306Service.parseOrderTicket(const {
        'start_train_date_page': '2026-09-01 08:00',
        'ticket_status_name': '已退票',
      });
      final rescheduled = Ticket12306Service.parseOrderTicket(const {
        'start_train_date_page': '2026-09-01 08:00',
        'ticket_status_name': '已改签',
      });

      expect(refunded!.canImport, isTrue);
      expect(rescheduled!.canImport, isFalse);
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
