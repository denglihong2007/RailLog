import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/seat_selection.dart';
import 'package:raillog/src/widgets/trip_details/trip_form_common.dart';

/// 把解析结果按两个页面保存时的写法还原成落库字符串，用来验往返。
({String seatType, String seatNumber}) roundTrip(String? type, String? number) {
  final parsed = parseTripSeat(type, number);
  if (parsed.seatMode == '其它') {
    return (
      seatType: parsed.customSeatType,
      seatNumber: parsed.customSeatNumber,
    );
  }
  return (
    seatType: composeSeatType(parsed.seatType, parsed.coachSeatType),
    seatNumber: SeatSelection(
      mode: parsed.seatMode,
      carriageNumber: parsed.carriageNumber,
      primaryNumber: parsed.primarySeatNumber,
      secondaryNumber: parsed.secondarySeatNumber,
      isExtraCarriage: parsed.isExtraCarriage,
    ).seatNumber,
  );
}

SeatSelection selection({
  String mode = '席位',
  int? carriage = 5,
  int primary = 12,
  String secondary = '无',
  bool extra = false,
}) => SeatSelection(
  mode: mode,
  carriageNumber: carriage,
  primaryNumber: primary,
  secondaryNumber: secondary,
  isExtraCarriage: extra,
);

void main() {
  group('SeatSelection.seatNumber', () {
    test('keeps the carriage prefix unchanged without 加车', () {
      expect(selection().seatNumber, '5车12号');
      expect(selection(carriage: 1).seatNumber, '1车12号');
      expect(selection(carriage: 99).seatNumber, '99车12号');
    });

    test('prefixes the carriage with 加 when 加车 is checked', () {
      expect(selection(extra: true).seatNumber, '加5车12号');
      expect(selection(carriage: 1, extra: true).seatNumber, '加1车12号');
      expect(selection(carriage: 10, extra: true).seatNumber, '加10车12号');
    });

    test('ignores 加车 when the carriage is unknown', () {
      expect(
        selection(carriage: SeatOptions.unknownNumber, extra: true).seatNumber,
        '0车12号',
      );
      expect(selection(carriage: null, extra: true).seatNumber, '99车12号');
    });

    test('keeps 加车 for the non-seat modes', () {
      expect(selection(mode: '无座', extra: true).seatNumber, '加5车无座');
      expect(selection(mode: '不对号入座', extra: true).seatNumber, '加5车不对号入座');
    });

    test('keeps the position suffix with 加车', () {
      expect(selection(secondary: '下铺', extra: true).seatNumber, '加5车12号下铺');
      expect(selection(secondary: 'A', extra: true).seatNumber, '加5车12A号');
      expect(
        selection(primary: SeatOptions.unknownNumber, extra: true).seatNumber,
        '加5车0号',
      );
    });
  });

  group('composeSeatType / splitSeatType', () {
    test('composes only when a coach seat type is set', () {
      expect(composeSeatType('硬座', null), '硬座');
      expect(composeSeatType('硬座', ''), '硬座');
      expect(composeSeatType('硬座', '硬卧'), '硬卧代硬座');
    });

    test('splits 车体席别代席别', () {
      final split = splitSeatType('硬卧代硬座');
      expect(split.seatType, '硬座');
      expect(split.coachSeatType, '硬卧');
    });

    test('splits on the last 代 so 混编 names survive', () {
      final split = splitSeatType('混编硬卧代硬座');
      expect(split.seatType, '硬座');
      expect(split.coachSeatType, '混编硬卧');
    });

    test('leaves anything unparsable untouched', () {
      expect(splitSeatType('硬座').coachSeatType, isNull);
      expect(splitSeatType('硬座').seatType, '硬座');
      // 前半段不是已知席别，不能当成代用，否则下拉里选不中。
      expect(splitSeatType('随便代硬座').seatType, '随便代硬座');
      expect(splitSeatType('随便代硬座').coachSeatType, isNull);
      // 后半段不是已知席别同理。
      expect(splitSeatType('硬卧代随便').seatType, '硬卧代随便');
      expect(splitSeatType('硬卧代随便').coachSeatType, isNull);
      expect(splitSeatType('代硬座').coachSeatType, isNull);
      expect(splitSeatType('硬座代').coachSeatType, isNull);
    });
  });

  group('parseTripSeat', () {
    test('reads 加车 into a flag instead of falling back to 其它', () {
      final parsed = parseTripSeat('二等座', '加1车12号');
      expect(parsed.seatMode, '席位');
      expect(parsed.isExtraCarriage, isTrue);
      expect(parsed.carriageNumber, 1);
      expect(parsed.primarySeatNumber, 12);
      expect(parsed.coachSeatType, isNull);
    });

    test('reads a 代用 seat type into base + coach', () {
      final parsed = parseTripSeat('硬卧代硬座', '5车12号');
      expect(parsed.seatType, '硬座');
      expect(parsed.coachSeatType, '硬卧');
      expect(parsed.seatMode, '席位');
    });

    test('accepts lowercase position letters from 12306 / OCR', () {
      final parsed = parseTripSeat('软卧代软座', '加2车19c号');
      expect(parsed.seatMode, '席位');
      expect(parsed.seatType, '软座');
      expect(parsed.coachSeatType, '软卧');
      expect(parsed.isExtraCarriage, isTrue);
      expect(parsed.carriageNumber, 2);
      expect(parsed.primarySeatNumber, 19);
      expect(parsed.secondarySeatNumber, 'C');

      expect(parseTripSeat('二等座', '5车19a号').secondarySeatNumber, 'A');
      expect(parseTripSeat('二等座', '5车19d号').secondarySeatNumber, 'D');
      expect(parseTripSeat('二等座', '5车19f号').secondarySeatNumber, 'F');
    });

    test('keeps 加车 and 代用 in the 无座 / 不对号 early exits', () {
      final noSeat = parseTripSeat('硬卧代硬座', '加1车无座');
      expect(noSeat.seatMode, '无座');
      expect(noSeat.seatType, '硬座');
      expect(noSeat.coachSeatType, '硬卧');
      expect(noSeat.isExtraCarriage, isTrue);

      final unreserved = parseTripSeat('硬座', '加1车不对号入座');
      expect(unreserved.seatMode, '不对号入座');
      expect(unreserved.isExtraCarriage, isTrue);
    });

    test('drops 加车 when the carriage is unknown', () {
      final parsed = parseTripSeat('二等座', '加0车12号');
      expect(parsed.isExtraCarriage, isFalse);
      expect(parsed.carriageNumber, SeatOptions.unknownNumber);
    });

    test('moves a legacy berth suffix from the seat type into the number', () {
      final parsed = parseTripSeat('硬卧代硬座上铺', '5车12号');
      expect(parsed.seatType, '硬座');
      expect(parsed.coachSeatType, '硬卧');
      expect(parsed.secondarySeatNumber, '上铺');
    });

    test('falls back to 其它 when either half of 代 is unknown', () {
      final unknownCoach = parseTripSeat('随便代硬座', '5车12号');
      expect(unknownCoach.seatMode, '其它');
      expect(unknownCoach.coachSeatType, isNull);
      expect(unknownCoach.isExtraCarriage, isFalse);
      expect(unknownCoach.customSeatType, '随便代硬座');
      expect(unknownCoach.customSeatNumber, '5车12号');

      final unknownSeat = parseTripSeat('硬卧代随便', '5车12号');
      expect(unknownSeat.seatMode, '其它');
      expect(unknownSeat.customSeatType, '硬卧代随便');
    });

    test('keeps free text in 其它 verbatim', () {
      final parsed = parseTripSeat('坐票', '随便坐');
      expect(parsed.seatMode, '其它');
      expect(parsed.customSeatType, '坐票');
      expect(parsed.customSeatNumber, '随便坐');
    });
  });

  group('生成 → 解析 → 再生成', () {
    final cases = <String, ({String type, String number})>{
      '普通席位': (type: '二等座', number: '5车12号'),
      '加挂车厢': (type: '二等座', number: '加1车12号'),
      '加挂车厢卧铺': (type: '硬卧', number: '加1车12号下铺'),
      '加挂车厢无座': (type: '硬座', number: '加1车无座'),
      '加挂车厢不对号': (type: '硬座', number: '加1车不对号入座'),
      '已知车厢不对号': (type: '硬座', number: '99车不对号入座'),
      '未知车厢': (type: '二等座', number: '0车12号'),
      '字母位置': (type: '二等座', number: '5车12A号'),
      '未知号码': (type: '二等座', number: '5车0号'),
      '席别代用': (type: '硬卧代硬座', number: '5车12号'),
      '席别代用加挂': (type: '硬卧代硬座', number: '加1车12号'),
      '席别代用无座': (type: '硬卧代硬座', number: '加1车无座'),
      '混编代用': (type: '混编硬卧代硬座', number: '加2车7号'),
    };

    cases.forEach((name, value) {
      test('$name 原样往返', () {
        final result = roundTrip(value.type, value.number);
        expect(result.seatType, value.type);
        expect(result.seatNumber, value.number);
      });
    });

    test('小写位置字母归一成大写', () {
      final result = roundTrip('软卧代软座', '加2车19c号');
      expect(result.seatType, '软卧代软座');
      expect(result.seatNumber, '加2车19C号');
    });

    test('认不出时不碰用户自由输入的大小写', () {
      expect(roundTrip('二等座', '5车19c座').seatNumber, '5车19c座');
    });

    test('铺位后缀归一到座位号，代用不丢', () {
      final result = roundTrip('硬卧代硬座上铺', '5车12号');
      expect(result.seatType, '硬卧代硬座');
      expect(result.seatNumber, '5车12号上铺');
    });

    test('认不出的整条走自定义输入，原文不动', () {
      final result = roundTrip('随便代硬座', '5车12号');
      expect(result.seatType, '随便代硬座');
      expect(result.seatNumber, '5车12号');
    });

    // 存量行为：只有「不指定车厢」这一种写法认得出，回写时会退化成 1 车。
    test('不指定车厢 退化成 1 车（既有行为）', () {
      final parsed = parseTripSeat('二等座', '不指定车厢12号');
      expect(parsed.seatMode, '席位');
      expect(parsed.carriageNumber, 1);
      expect(roundTrip('二等座', '不指定车厢12号').seatNumber, '1车12号');
    });
  });
}
