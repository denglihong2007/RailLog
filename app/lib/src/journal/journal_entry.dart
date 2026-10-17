import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';

/// 一页手账上要预印的一条行程。字段都已是可直接落版的字符串，
/// 排版层不再做任何格式化判断。
class JournalEntry {
  const JournalEntry({
    required this.trainLabel,
    required this.dateLabel,
    required this.weekdayLabel,
    required this.fromStation,
    required this.toStation,
    required this.departLabel,
    required this.arriveLabel,
    required this.durationLabel,
    required this.mileageLabel,
    required this.priceLabel,
    required this.seatLabel,
    required this.rollingStockLabel,
    required this.routeLabel,
    required this.notesLabel,
    required this.kindLabel,
    required this.isRailTrip,
  });

  /// 车次（铁路）或班次（非铁路）。
  final String trainLabel;

  final String dateLabel;
  final String weekdayLabel;
  final String fromStation;
  final String toStation;
  final String departLabel;
  final String arriveLabel;
  final String durationLabel;
  final String mileageLabel;
  final String priceLabel;
  final String seatLabel;
  final String rollingStockLabel;

  /// 「经 京沪高速铁路」，无经由线路时为空串。
  final String routeLabel;

  /// 备注的截断版，无备注时为空串。
  final String notesLabel;

  final String kindLabel;
  final bool isRailTrip;

  factory JournalEntry.fromTrip(TripRecord trip) {
    return JournalEntry(
      trainLabel: JournalFormatter.train(trip),
      dateLabel: JournalFormatter.date(trip.departureTime),
      weekdayLabel: JournalFormatter.weekday(trip.departureTime),
      fromStation: JournalFormatter.truncate(trip.fromStation, 8),
      toStation: JournalFormatter.truncate(trip.toStation, 8),
      departLabel: JournalFormatter.time(trip.departureTime),
      arriveLabel: trip.arrivalTime == null
          ? JournalFormatter.unknown
          : JournalFormatter.time(trip.arrivalTime!),
      durationLabel: JournalFormatter.duration(
        trip.departureTime,
        trip.arrivalTime,
      ),
      mileageLabel: JournalFormatter.mileage(trip.mileageKm),
      priceLabel: JournalFormatter.price(trip.price),
      seatLabel: JournalFormatter.seat(trip.seatType, trip.seatNumber),
      // 编组不在这里截：它独占一整行，且大半是半角车组号
      // （CR400BF-5033&5044&…）。按固定字数截会把本来放得下的内容
      // 切出「…」，所以留给排版层按实际可用宽度裁。
      rollingStockLabel: trip.rollingStock?.trim() ?? '',
      routeLabel: JournalFormatter.truncate(
        JournalFormatter.routeSummary(trip.viaRouteSegments),
        26,
      ),
      notesLabel: JournalFormatter.truncate(trip.notes?.trim() ?? '', 34),
      kindLabel: trip.isRailTrip ? '铁路行程' : '非铁路行程',
      isRailTrip: trip.isRailTrip,
    );
  }
}

/// 手账上所有文本的格式化规则。放在这里而不是排版层，是为了能单独跑纯函数测试。
abstract final class JournalFormatter {
  /// 数据缺失时统一的占位符。
  static const String unknown = '—';

  static String date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static const List<String> _weekdays = [
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  static String weekday(DateTime value) => _weekdays[value.weekday - 1];

  static String time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  /// 「4时38分」。到达时刻缺失或早于出发时刻时返回空串。
  static String duration(DateTime departure, DateTime? arrival) {
    if (arrival == null || arrival.isBefore(departure)) return '';
    final span = arrival.difference(departure);
    final hours = span.inHours;
    final minutes = span.inMinutes.remainder(60);
    if (hours == 0) return '$minutes分';
    return minutes == 0 ? '$hours时' : '$hours时$minutes分';
  }

  /// 「1318 km」。0 表示没有记录，不印「0 km」误导人。
  static String mileage(double km) =>
      km <= 0 ? unknown : '${km.round()} km';

  /// 「¥662.00」。0 同上。
  static String price(double yuan) =>
      yuan <= 0 ? unknown : '¥${yuan.toStringAsFixed(2)}';

  static String seat(String? type, String? number) {
    final seatType = type?.trim() ?? '';
    final seatNumber = number?.trim() ?? '';
    if (seatType.isEmpty && seatNumber.isEmpty) return unknown;
    if (seatType.isEmpty) return seatNumber;
    if (seatNumber.isEmpty) return seatType;
    return '$seatType · $seatNumber';
  }

  /// 「经 京沪高速铁路」。多段经由用 / 连接，无经由线路时返回空串。
  static String routeSummary(List<ViaRouteSegment> segments) {
    final names = <String>[];
    for (final segment in segments) {
      final name = segment.routeName.trim();
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
    }
    if (names.isEmpty) return '';
    return '经 ${names.join(' / ')}';
  }

  /// 中文在 dart_pdf 里不会自动折行（只在空格处断），所有预印文本
  /// 必须先截断，否则会溢出到带外。
  ///
  /// 按 rune 数截而不是 code unit 数：备注里敲个 emoji 就落到代理对区间，
  /// 按 code unit 截会把代理对劈成半个字符，编进 PDF 是坏字节。
  static String truncate(String value, int maxChars) {
    final trimmed = value.trim();
    if (maxChars <= 0) return '';
    final runes = trimmed.runes.toList();
    if (runes.length <= maxChars) return trimmed;
    return '${String.fromCharCodes(runes.take(maxChars - 1))}…';
  }

  /// 放得下就原样返回，放不下才按估算宽度截。
  ///
  /// 编组这类字段大半是半角车组号（`CR400BF-5033&5044&5051`），按固定
  /// 字数截会把本来放得下的内容也切出「…」。所以它不走 [truncate]，
  /// 由排版层把实际可用的点数传进来。
  static String fit(
    String value, {
    required double maxWidth,
    required double fontSize,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (estimateWidth(trimmed, fontSize) <= maxWidth) return trimmed;
    // 给结尾的省略号留一个全角位。
    final budget = maxWidth - fontSize;
    final kept = <int>[];
    var width = 0.0;
    for (final rune in trimmed.runes) {
      final next = width + emWidth(rune) * fontSize;
      if (next > budget) break;
      kept.add(rune);
      width = next;
    }
    return kept.isEmpty ? '…' : '${String.fromCharCodes(kept)}…';
  }

  /// 估算一段文本在给定字号下的宽度（pt）。只用来判断放不放得下，
  /// 不参与实际排版，所以半角一律按 0.55em 粗算即可。
  static double estimateWidth(String value, double fontSize) {
    var em = 0.0;
    for (final rune in value.runes) {
      em += emWidth(rune);
    }
    return em * fontSize;
  }

  /// 半角（ASCII 与半角片假名）0.55em，其余按 1em 全角算。
  static double emWidth(int rune) =>
      rune <= 0x7E || (rune >= 0xFF61 && rune <= 0xFF9F) ? 0.55 : 1.0;

  /// 车次（铁路）或班次（非铁路）。空车次给一句能看懂的兜底。
  static String train(TripRecord trip) {
    final number = trip.trainNumber.trim();
    if (number.isEmpty) return trip.isRailTrip ? '车次未填' : '班次未填';
    return truncate(number, 12);
  }
}
