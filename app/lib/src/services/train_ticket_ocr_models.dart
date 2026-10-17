/// 车票识别的服务商。设置页用它记住用户的选择，识别时据此分派。
enum TrainTicketOcrProvider {
  baidu('baidu', '百度智能云'),
  aliyun('aliyun', '阿里云');

  const TrainTicketOcrProvider(this.preferenceValue, this.label);

  final String preferenceValue;
  final String label;

  static TrainTicketOcrProvider fromPreference(String? value) {
    for (final provider in values) {
      if (provider.preferenceValue == value) return provider;
    }
    return TrainTicketOcrProvider.baidu;
  }
}

/// 各服务商识别结果归一化后的车票信息。
class TrainTicketOcrResult {
  const TrainTicketOcrResult({
    required this.trainNumber,
    required this.fromStation,
    required this.toStation,
    required this.departureTime,
    required this.seatType,
    required this.seatNumber,
    required this.price,
  });

  final String trainNumber;
  final String fromStation;
  final String toStation;
  final DateTime departureTime;
  final String? seatType;
  final String? seatNumber;
  final double? price;
}

class TrainTicketOcrException implements Exception {
  const TrainTicketOcrException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 两家服务商返回的日期、票价、席别格式略有差异，解析规则放在一处。
abstract final class TrainTicketOcrParsing {
  static DateTime dateTime(String value) {
    final match = RegExp(
      r'(\d{4})\D+(\d{1,2})\D+(\d{1,2})(?:\D+(\d{1,2})[:：](\d{1,2}))?',
    ).firstMatch(value);
    if (match == null) {
      throw const TrainTicketOcrException('无法解析乘车日期');
    }
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.tryParse(match.group(4) ?? '') ?? 0,
      int.tryParse(match.group(5) ?? '') ?? 0,
    );
  }

  static double? price(String value) {
    return double.tryParse(value.replaceAll(RegExp(r'[^\d.]'), ''));
  }

  static String? seatType(String? value) {
    final normalized = value?.replaceAll('新空调', '').trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}
