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

class SeatSelection {
  const SeatSelection({
    required this.mode,
    required this.carriageNumber,
    required this.primaryNumber,
    required this.secondaryNumber,
  });

  final String mode;
  final int? carriageNumber;
  final int primaryNumber;
  final String secondaryNumber;

  String get seatNumber {
    final carriage = '${carriageNumber ?? 99}车';
    if (mode != '席位') return '$carriage$mode';
    if (primaryNumber == SeatOptions.unknownNumber) return '${carriage}0号';
    if (secondaryNumber == '无') return '$carriage$primaryNumber号';
    if (const {'上铺', '中铺', '下铺'}.contains(secondaryNumber)) {
      return '$carriage$primaryNumber号$secondaryNumber';
    }
    return '$carriage$primaryNumber$secondaryNumber号';
  }
}
