class RollingStockLookupResult {
  const RollingStockLookupResult({
    required this.rollingStock,
    required this.usedLatestFallback,
    required this.referenceTerminalDate,
  });

  final String rollingStock;
  final bool usedLatestFallback;
  final DateTime referenceTerminalDate;
}
