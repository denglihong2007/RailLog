import 'package:flutter/material.dart';
import 'package:raillog/src/models/rolling_stock_lookup_result.dart';
import 'package:raillog/src/models/route_resolution.dart';
import 'package:raillog/src/models/seat_selection.dart';
import 'package:raillog/src/models/train_distance_info.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';
import 'package:raillog/src/models/ticket_seat_option.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/route_service.dart';
import 'package:raillog/src/services/train_service.dart';
import 'package:raillog/src/widgets/trip_details/form_section.dart';
import 'package:raillog/src/widgets/trip_details/route_segments_editor.dart';
import 'package:raillog/src/widgets/trip_details/seat_editor.dart';
import 'package:raillog/src/widgets/trip_details/trip_ticket.dart';

class TripDetailsPage extends StatefulWidget {
  const TripDetailsPage({
    super.key,
    required this.trainNumber,
    required this.scheduleStops,
    required this.departureStopIndex,
    required this.arrivalStopIndex,
  });

  final String trainNumber;
  final List<TrainScheduleStop> scheduleStops;
  final int departureStopIndex;
  final int arrivalStopIndex;

  @override
  State<TripDetailsPage> createState() => _TripDetailsPageState();
}

class _TripDetailsPageState extends State<TripDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  final _customSeatTypeController = TextEditingController();
  final _customSeatNumberController = TextEditingController();
  final _distanceController = TextEditingController();
  final _priceController = TextEditingController();
  final _companyController = TextEditingController();
  final _rollingStockController = TextEditingController();
  final _notesController = TextEditingController();

  String _seatType = '二等座';
  String _seatMode = '席位';
  int? _carriageNumber = 1;
  int _primarySeatNumber = 1;
  String _secondarySeatNumber = '无';
  bool _isLoadingRuntimeInfo = true;
  bool _isSaving = false;
  bool _usedLatestRollingStock = false;
  DateTime? _rollingStockReferenceTravelDate;
  bool _distanceLookupFailed = false;
  bool _rollingStockLookupFailed = false;
  TicketSeatAvailability? _ticketSeatAvailability;
  bool _ticketSeatLookupFailed = false;
  List<ViaRouteSegment> _viaRouteSegments = const [];
  List<String> _unresolvedRouteSections = const [];
  bool _usedShortestRoutePath = false;
  bool _isLoadingRouteInfo = true;
  bool _routeLookupFailed = false;
  List<String> _routeNames = const [];
  bool _isLoadingRouteCatalog = true;
  bool _isRecognizingShortestPath = false;
  int _routeEditorRevision = 0;

  TrainScheduleStop get _departureStop =>
      widget.scheduleStops[widget.departureStopIndex];
  TrainScheduleStop get _arrivalStop =>
      widget.scheduleStops[widget.arrivalStopIndex];
  DateTime get _departureTime => _departureStop.departureDateTime!;
  DateTime get _arrivalTime => _arrivalStop.arrivalDateTime!;

  @override
  void initState() {
    super.initState();
    _loadRuntimeInfo();
    _loadRouteCatalog();
  }

  @override
  void dispose() {
    _customSeatTypeController.dispose();
    _customSeatNumberController.dispose();
    _distanceController.dispose();
    _priceController.dispose();
    _companyController.dispose();
    _rollingStockController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadRuntimeInfo() async {
    final terminalStop = widget.scheduleStops.last;
    final terminalDate =
        terminalStop.arrivalDateTime ??
        terminalStop.departureDateTime ??
        _arrivalTime;
    final shouldFetchRollingStock = TrainService.shouldFetchRollingStock(
      widget.trainNumber,
    );
    final results = await Future.wait<dynamic>([
      TrainService.fetchDistanceInfo(
        trainNumber: widget.trainNumber,
        startStation: _departureStop.stationName,
        endStation: _arrivalStop.stationName,
      ),
      if (shouldFetchRollingStock)
        TrainService.fetchRollingStock(
          trainNumber: widget.trainNumber,
          terminalDate: terminalDate,
        )
      else
        Future<RollingStockLookupResult?>.value(),
      _resolveRoutes(),
      TrainService.fetchTicketSeatAvailability(
        trainNumber: widget.trainNumber,
        fromStation: _departureStop.stationName,
        toStation: _arrivalStop.stationName,
      ),
    ]);
    if (!mounted) return;

    final distanceInfo = results[0] as TrainDistanceInfo?;
    final rollingStock = results[1] as RollingStockLookupResult?;
    final routeResolution = results[2] as RouteResolution?;
    final ticketSeatAvailability = results[3] as TicketSeatAvailability?;
    setState(() {
      if (distanceInfo != null) {
        _distanceController.text = _formatNumber(distanceInfo.distance);
        _companyController.text = distanceInfo.companyName;
      } else {
        _distanceLookupFailed = true;
      }
      if (rollingStock != null) {
        _rollingStockController.text = rollingStock.rollingStock;
        _usedLatestRollingStock = rollingStock.usedLatestFallback;
        _rollingStockReferenceTravelDate = _boardingDateForTerminalDate(
          rollingStock.referenceTerminalDate,
        );
      } else if (shouldFetchRollingStock) {
        _rollingStockLookupFailed = true;
      }
      if (routeResolution != null) {
        _viaRouteSegments = _normalizeRouteSegments(routeResolution.segments);
        _unresolvedRouteSections = routeResolution.unresolvedSections;
        _usedShortestRoutePath = routeResolution.usedShortestPath;
        _routeEditorRevision++;
      } else {
        _routeLookupFailed = true;
      }
      if (ticketSeatAvailability != null) {
        _ticketSeatAvailability = ticketSeatAvailability;
        _applyInitialTicketSeat(ticketSeatAvailability);
      } else {
        _ticketSeatLookupFailed = true;
      }
      _isLoadingRouteInfo = false;
      _isLoadingRuntimeInfo = false;
    });
  }

  Future<RouteResolution?> _resolveRoutes() async {
    try {
      final sections = await TrainService.fetchStationPairDistances(
        widget.trainNumber,
        widget.scheduleStops,
        widget.departureStopIndex,
        widget.arrivalStopIndex,
      );
      return RouteService.resolveJourney(sections);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadRouteCatalog() async {
    try {
      final routeNames = await RouteService.getRouteNames();
      if (!mounted) return;
      setState(() {
        _routeNames = routeNames;
        _isLoadingRouteCatalog = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _routeLookupFailed = true;
        _isLoadingRouteCatalog = false;
      });
    }
  }

  Future<void> _recognizeShortestPath() async {
    setState(() => _isRecognizingShortestPath = true);
    try {
      final result = await RouteService.resolveShortestJourney(
        _departureStop.stationName,
        _arrivalStop.stationName,
      );
      if (!mounted) return;
      setState(() {
        _viaRouteSegments = _normalizeRouteSegments(result.segments);
        _unresolvedRouteSections = result.unresolvedSections;
        _usedShortestRoutePath = true;
        _routeLookupFailed = false;
        _isRecognizingShortestPath = false;
        _routeEditorRevision++;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _routeLookupFailed = true;
        _isRecognizingShortestPath = false;
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!hasValidRouteContinuity(
      _viaRouteSegments,
      startStation: _departureStop.stationName,
      endStation: _arrivalStop.stationName,
    )) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('经由线路必须首尾相接并覆盖乘车区间')));
      return;
    }
    setState(() => _isSaving = true);

    final isCustomSeat = _seatMode == '其它';
    final seatType = isCustomSeat
        ? _customSeatTypeController.text.trim()
        : _seatType;
    final seatNumber = isCustomSeat
        ? _customSeatNumberController.text.trim()
        : SeatSelection(
            mode: _seatMode,
            carriageNumber: _carriageNumber ?? 1,
            primaryNumber: _primarySeatNumber,
            secondaryNumber: _secondarySeatNumber,
          ).seatNumber;
    final trip = TripRecord(
      id: 0,
      trainNumber: widget.trainNumber,
      rollingStock: _nullableText(_rollingStockController.text),
      companyName: _nullableText(_companyController.text),
      fromStation: _departureStop.stationName,
      toStation: _arrivalStop.stationName,
      departureTime: _departureTime,
      arrivalTime: _arrivalTime,
      mileageKm: double.tryParse(_distanceController.text.trim()) ?? 0,
      viaRouteSegments: _viaRouteSegments,
      seatType: seatType,
      seatNumber: seatNumber,
      price: double.tryParse(_priceController.text.trim()) ?? 0,
      notes: _nullableText(_notesController.text),
    );

    try {
      await DbHelper.instance.insertTrip(trip);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('行程已保存')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      appBar: AppBar(title: const Text('详细信息'), scrolledUnderElevation: 0),
      body: Theme(
        data: theme.copyWith(
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            filled: true,
            fillColor: colors.surfaceContainerHighest,
            border: const OutlineInputBorder(
              borderSide: BorderSide.none,
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide.none,
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
        child: Form(
          key: _formKey,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = constraints.maxWidth >= 720
                  ? 24.0
                  : 16.0;
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  12,
                  horizontalPadding,
                  32,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 840),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TripTicket(
                            trainNumber: widget.trainNumber,
                            departureStop: _departureStop,
                            arrivalStop: _arrivalStop,
                          ),
                          const SizedBox(height: 20),
                          FormSection(
                            icon: Icons.event_seat_outlined,
                            title: '座位信息',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SeatEditor(
                                  seatTypes: SeatOptions.types,
                                  seatType: _seatType,
                                  seatMode: _seatMode,
                                  customSeatTypeController:
                                      _customSeatTypeController,
                                  customSeatNumberController:
                                      _customSeatNumberController,
                                  carriageNumber: _carriageNumber,
                                  primarySeatNumber: _primarySeatNumber,
                                  secondarySeatNumber: _secondarySeatNumber,
                                  secondarySeatNumbers:
                                      SeatOptions.secondaryNumbers,
                                  onSeatTypeChanged: _changeSeatType,
                                  onSeatModeChanged: _changeSeatMode,
                                  onCarriageChanged: (value) =>
                                      setState(() => _carriageNumber = value),
                                  onPrimaryChanged: (value) => setState(
                                    () => _primarySeatNumber = value,
                                  ),
                                  onSecondaryChanged: (value) => setState(
                                    () => _secondarySeatNumber = value,
                                  ),
                                  onTicketSeatOptionChanged: (option) =>
                                      setState(
                                        () => _applyTicketSeatOption(option),
                                      ),
                                  ticketSeatOptions:
                                      _ticketSeatAvailability?.seatOptions,
                                  noSeatOption:
                                      _ticketSeatAvailability?.noSeatOption,
                                ),
                                if (_ticketSeatLookupFailed) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '未获取到当前区间的席别与票价',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          FormSection(
                            icon: Icons.route_outlined,
                            title: '运行信息',
                            trailing: _isLoadingRuntimeInfo
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : null,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ResponsiveFieldWrap(
                                  children: [
                                    _buildDistanceField(),
                                    _buildPriceField(),
                                    TextFormField(
                                      controller: _companyController,
                                      decoration: const InputDecoration(
                                        labelText: '担当公司',
                                        prefixIcon: Icon(
                                          Icons.business_outlined,
                                        ),
                                      ),
                                    ),
                                    TextFormField(
                                      controller: _rollingStockController,
                                      decoration: InputDecoration(
                                        labelText: '车型',
                                        prefixIcon: const Icon(
                                          Icons.train_outlined,
                                        ),
                                        helperText: _usedLatestRollingStock
                                            ? '按照${_formatDate(_rollingStockReferenceTravelDate!)}乘车日期填入，请确认'
                                            : _rollingStockLookupFailed
                                            ? '未自动获取，请手动填写'
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                RouteSegmentsEditor(
                                  startStation: _departureStop.stationName,
                                  endStation: _arrivalStop.stationName,
                                  routeNames: _routeNames,
                                  segments: _viaRouteSegments,
                                  isLoading:
                                      _isLoadingRouteInfo ||
                                      _isLoadingRouteCatalog,
                                  isRecognizing: _isRecognizingShortestPath,
                                  revision: _routeEditorRevision,
                                  onRecognizeShortestPath:
                                      _recognizeShortestPath,
                                  resolveDistance:
                                      RouteService.getDistanceOnRoute,
                                  resolveStations:
                                      RouteService.getStationsForRoute,
                                  onChanged: (segments) {
                                    setState(() {
                                      _viaRouteSegments = segments;
                                      _unresolvedRouteSections = const [];
                                      _usedShortestRoutePath = false;
                                      _routeLookupFailed = false;
                                    });
                                  },
                                  usedShortestPath: _usedShortestRoutePath,
                                  unresolvedSections: _unresolvedRouteSections,
                                  lookupFailed: _routeLookupFailed,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          FormSection(
                            icon: Icons.notes_outlined,
                            title: '备注',
                            child: TextFormField(
                              controller: _notesController,
                              minLines: 3,
                              maxLines: 6,
                              decoration: const InputDecoration(
                                hintText: '记录这趟旅程的其它信息',
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: _isSaving ? null : _save,
                              icon: _isSaving
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: const Text('保存行程'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _changeSeatType(String value) {
    setState(() {
      final option = _ticketSeatAvailability?.seatOptions
          .where((item) => item.seatType == value)
          .firstOrNull;
      if (option == null) {
        _seatType = value;
      } else {
        _applyTicketSeatOption(option);
      }
    });
  }

  DateTime _boardingDateForTerminalDate(DateTime referenceTerminalDate) {
    final terminalStop = widget.scheduleStops.last;
    final currentTerminalDate =
        terminalStop.arrivalDateTime ??
        terminalStop.departureDateTime ??
        _arrivalTime;
    final terminalDay = DateTime(
      currentTerminalDate.year,
      currentTerminalDate.month,
      currentTerminalDate.day,
    );
    final boardingDay = DateTime(
      _departureTime.year,
      _departureTime.month,
      _departureTime.day,
    );
    final referenceDay = DateTime(
      referenceTerminalDate.year,
      referenceTerminalDate.month,
      referenceTerminalDate.day,
    );
    return referenceDay.subtract(
      Duration(days: terminalDay.difference(boardingDay).inDays),
    );
  }

  void _changeSeatMode(String value) {
    setState(() {
      _seatMode = value;
      _carriageNumber ??= 1;
      final availability = _ticketSeatAvailability;
      if (availability == null) return;
      if (value == '无座') {
        final option = availability.noSeatOption;
        if (option != null) {
          _seatType = option.seatType;
          _priceController.text = _formatNumber(option.price);
        }
        return;
      }
      final selected = availability.seatOptions
          .where((option) => option.seatType == _seatType)
          .firstOrNull;
      final option = selected ?? availability.seatOptions.firstOrNull;
      if (option != null) _applyTicketSeatOption(option);
    });
  }

  void _applyInitialTicketSeat(TicketSeatAvailability availability) {
    if (availability.seatOptions.isEmpty) {
      final noSeat = availability.noSeatOption;
      if (noSeat != null) {
        _seatMode = '无座';
        _seatType = noSeat.seatType;
        _priceController.text = _formatNumber(noSeat.price);
      }
      return;
    }
    if (_seatMode == '无座' && availability.noSeatOption == null) {
      _seatMode = '席位';
    }
    if (_seatMode == '其它') _seatMode = '席位';
    final selected = availability.seatOptions
        .where((option) => option.seatType == _seatType)
        .firstOrNull;
    final option = selected ?? availability.seatOptions.first;
    _applyTicketSeatOption(option);
  }

  void _applyTicketSeatOption(TicketSeatOption option) {
    _seatType = option.seatType;
    _priceController.text = _formatNumber(option.price);
    _secondarySeatNumber = option.berth ?? _secondarySeatNumber;
  }

  Widget _buildDistanceField() {
    return TextFormField(
      controller: _distanceController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: '里程',
        prefixIcon: const Icon(Icons.straighten_outlined),
        suffixText: 'km',
        suffixIcon: IconButton(
          tooltip: '按经由线路计算总里程',
          onPressed: _viaRouteSegments.isEmpty ? null : _calculateTotalMileage,
          icon: const Icon(Icons.calculate_outlined),
        ),
        helperText: _distanceLookupFailed ? '未自动获取，请手动填写' : null,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return null;
        final distance = double.tryParse(value.trim());
        return distance == null || distance < 0 ? '请输入有效里程' : null;
      },
    );
  }

  void _calculateTotalMileage() {
    final total = _viaRouteSegments.fold<double>(
      0,
      (sum, segment) => sum + segment.mileageKm,
    );
    setState(() => _distanceController.text = _formatNumber(total));
  }

  Widget _buildPriceField() {
    return TextFormField(
      controller: _priceController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: '票价',
        prefixIcon: Icon(Icons.payments_outlined),
        suffixText: '元',
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return null;
        final price = double.tryParse(value.trim());
        return price == null || price < 0 ? '请输入有效票价' : null;
      },
    );
  }

  List<ViaRouteSegment> _normalizeRouteSegments(List<ViaRouteSegment> source) {
    return normalizeViaRouteSegments(
      source,
      startStation: _departureStop.stationName,
      endStation: _arrivalStop.stationName,
    );
  }
}

String? _nullableText(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

String _formatNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

String _formatDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
