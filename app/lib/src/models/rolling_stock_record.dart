class RollingStockRecord {
  const RollingStockRecord({required this.date, required this.emuNumber});

  final DateTime date;
  final String emuNumber;

  static RollingStockRecord? tryFromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['date']?.toString() ?? '');
    final emuNumber = json['emu_no']?.toString().trim() ?? '';
    if (date == null || emuNumber.isEmpty) return null;
    return RollingStockRecord(date: date, emuNumber: emuNumber);
  }
}
