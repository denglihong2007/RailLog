class RollingStockRecord {
  const RollingStockRecord({required this.date, required this.emuNumber});

  final DateTime date;
  final String emuNumber;

  static RollingStockRecord? tryFromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['runDate']?.toString() ?? '');
    final trainCodes = json['trainCode'];
    if (trainCodes is! List) return null;
    final emuNumber = trainCodes
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .join('&');
    if (date == null || emuNumber.isEmpty) return null;
    return RollingStockRecord(date: date, emuNumber: emuNumber);
  }
}
