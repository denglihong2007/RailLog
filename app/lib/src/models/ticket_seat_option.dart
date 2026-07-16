class TicketSeatOption {
  const TicketSeatOption({
    required this.seatType,
    required this.price,
    this.berth,
    this.isNoSeat = false,
  });

  final String seatType;
  final double price;
  final String? berth;
  final bool isNoSeat;
}

class TicketSeatAvailability {
  const TicketSeatAvailability({required this.seatOptions, this.noSeatOption});

  final List<TicketSeatOption> seatOptions;
  final TicketSeatOption? noSeatOption;

  bool get isEmpty => seatOptions.isEmpty && noSeatOption == null;
}
