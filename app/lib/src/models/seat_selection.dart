abstract final class SeatOptions {
  static const unknownNumber = 0;

  static const types = [
    '硬座',
    '软座',
    '硬卧',
    '软卧',
    '高级软卧',
    '一等卧',
    '二等卧',
    '动卧',
    '高级动卧',
    '二等座',
    '一等座',
    '优选一等座',
    '特等座',
    '商务座',
    '多功能座',
    '二等软座',
    '一等软座',
    '特等软座',
    '一人软包',
    '混编软座',
    '混编软卧',
    '混编硬座',
    '混编硬卧',
    '包厢硬卧',
    '二等包座',
  ];

  static const secondaryNumbers = [
    '无',
    'A',
    'B',
    'C',
    'D',
    'F',
    '上铺',
    '中铺',
    '下铺',
  ];

  static const carriageNumbers = [
    unknownNumber,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    99,
  ];
}

/// 把席别与车体席别组合成落库用的字符串，即「车体席别代席别」。
/// 车体席别为空时原样返回席别——绝大多数车票都是这种。
String composeSeatType(String seatType, String? coachSeatType) {
  final coach = coachSeatType?.trim() ?? '';
  return coach.isEmpty ? seatType : '$coach代$seatType';
}

/// 把「车体席别代席别」拆回基准席别与车体席别。
/// 只在最后一个「代」处切分，并且要求两段都是已知席别，否则原样返回、车体席别为空。
/// 后半段必须是已知席别这一条，保证了拆出的车体席别一定能在下拉里选中。
({String seatType, String? coachSeatType}) splitSeatType(String value) {
  final index = value.lastIndexOf('代');
  if (index <= 0 || index == value.length - 1) {
    return (seatType: value, coachSeatType: null);
  }
  final coach = value.substring(0, index);
  final seatType = value.substring(index + 1);
  if (!SeatOptions.types.contains(coach) ||
      !SeatOptions.types.contains(seatType)) {
    return (seatType: value, coachSeatType: null);
  }
  return (seatType: seatType, coachSeatType: coach);
}

class SeatSelection {
  const SeatSelection({
    required this.mode,
    required this.carriageNumber,
    required this.primaryNumber,
    required this.secondaryNumber,
    this.isExtraCarriage = false,
  });

  final String mode;
  final int? carriageNumber;
  final int primaryNumber;
  final String secondaryNumber;

  /// 加挂车厢：车厢段写成「加X车」。车厢未知时加挂没有意义，直接忽略。
  final bool isExtraCarriage;

  String get seatNumber {
    final known =
        carriageNumber != null && carriageNumber != SeatOptions.unknownNumber;
    final prefix = isExtraCarriage && known ? '加' : '';
    final carriage = '$prefix${carriageNumber ?? 99}车';
    if (mode != '席位') return '$carriage$mode';
    if (primaryNumber == SeatOptions.unknownNumber) return '${carriage}0号';
    if (secondaryNumber == '无') return '$carriage$primaryNumber号';
    if (const {'上铺', '中铺', '下铺'}.contains(secondaryNumber)) {
      return '$carriage$primaryNumber号$secondaryNumber';
    }
    return '$carriage$primaryNumber$secondaryNumber号';
  }
}
