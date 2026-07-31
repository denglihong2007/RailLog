class Ticket12306Order {
  const Ticket12306Order({
    required this.id,
    required this.sequenceNo,
    required this.startTime,
    required this.arriveTime,
    required this.trainCode,
    required this.fromStation,
    required this.toStation,
    required this.distance,
    required this.passengerName,
    required this.seatType,
    required this.coachName,
    required this.seatName,
    required this.price,
    required this.statusText,
  });

  final String id;
  final String sequenceNo;
  final DateTime startTime;
  final DateTime? arriveTime;
  final String trainCode;
  final String fromStation;
  final String toStation;
  final double distance;
  final String passengerName;
  final String seatType;
  final String coachName;
  final String seatName;
  final double price;
  final String statusText;

  String get seatDisplay {
    final number = [if (coachName.isNotEmpty) '$coachName车', seatName].join();
    return [seatType, number].where((part) => part.isNotEmpty).join(' ');
  }

  String? get seatNumber {
    final importedSeatName = coachName == '99' ? '不对号入座' : seatName;
    final value = [
      if (coachName.isNotEmpty) '$coachName车',
      importedSeatName,
    ].join();
    return value.isEmpty ? null : value;
  }

  bool get canImport => !const [
    '改签',
    '变更到站',
  ].any((keyword) => statusText.contains(keyword));
}
