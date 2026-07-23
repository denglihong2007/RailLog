import 'package:flutter/material.dart';
import 'package:raillog/src/models/rolling_stock_lookup_result.dart';
import 'package:raillog/src/models/route_resolution.dart';
import 'package:raillog/src/models/seat_selection.dart';
import 'package:raillog/src/models/station_pair_distance.dart';
import 'package:raillog/src/models/train_distance_info.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';
import 'package:raillog/src/models/timetable_source.dart';
import 'package:raillog/src/models/ticket_seat_option.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/route_service.dart';
import 'package:raillog/src/services/train_service.dart';
import 'package:raillog/src/widgets/trip_details/form_section.dart';
import 'package:raillog/src/widgets/trip_details/company_editor.dart';
import 'package:raillog/src/widgets/trip_details/route_segments_editor.dart';
import 'package:raillog/src/widgets/trip_details/trip_ticket.dart';
import 'package:raillog/src/widgets/trip_details/trip_form_common.dart';

class TrainTripFormPage extends StatefulWidget {
  const TrainTripFormPage({
    super.key,
    required this.trainNumber,
    required this.scheduleStops,
    this.timetableSource = TimetableSource.online,
    required this.departureStopIndex,
    required this.arrivalStopIndex,
    this.initialSeatType,
    this.initialSeatNumber,
    this.initialMileageKm,
    this.initialPrice,
    this.initialNotes,
    this.reviewPosition,
    this.reviewTotal,
  });

  final String trainNumber;
  final List<TrainScheduleStop> scheduleStops;
  final TimetableSource timetableSource;
  final int departureStopIndex;
  final int arrivalStopIndex;
  final String? initialSeatType;
  final String? initialSeatNumber;
  final double? initialMileageKm;
  final double? initialPrice;
  final String? initialNotes;
  final int? reviewPosition;
  final int? reviewTotal;

  @override
  State<TrainTripFormPage> createState() => _TrainTripFormPageState();
}

class _TrainTripFormPageState extends State<TrainTripFormPage> {
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
  bool _isLocalOnly = false;
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
    _initializeImportedTicket();
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
    final shouldFetchRollingStock =
        TrainService.shouldFetchRollingStock(widget.trainNumber) &&
        widget.timetableSource.isOnline;
    final results = await Future.wait<dynamic>([
      if (widget.timetableSource.isOnline)
        TrainService.fetchDistanceInfo(
          trainNumber: widget.trainNumber,
          startStation: _departureStop.stationName,
          endStation: _arrivalStop.stationName,
        )
      else
        Future<TrainDistanceInfo?>.value(),
      if (shouldFetchRollingStock)
        TrainService.fetchRollingStock(
          trainNumber: widget.trainNumber,
          terminalDate: terminalDate,
        )
      else
        Future<RollingStockLookupResult?>.value(),
      _resolveRoutes(),
      if (widget.timetableSource.isOnline)
        TrainService.fetchTicketSeatAvailability(
          trainNumber: widget.trainNumber,
          fromStation: _departureStop.stationName,
          toStation: _arrivalStop.stationName,
        )
      else
        Future<TicketSeatAvailability?>.value(),
    ]);
    if (!mounted) return;

    final distanceInfo = results[0] as TrainDistanceInfo?;
    final rollingStock = results[1] as RollingStockLookupResult?;
    final routeResolution = results[2] as RouteResolution?;
    final ticketSeatAvailability = results[3] as TicketSeatAvailability?;
    setState(() {
      if (distanceInfo != null) {
        if (_distanceController.text.isEmpty) {
          _distanceController.text = formatTripNumber(distanceInfo.distance);
        }
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
        if (!_hasImportedSeat) {
          _applyInitialTicketSeat(ticketSeatAvailability);
        }
      } else {
        _ticketSeatLookupFailed = true;
      }
      _isLoadingRouteInfo = false;
      _isLoadingRuntimeInfo = false;
    });
  }

  bool get _hasImportedSeat =>
      (widget.initialSeatType?.trim().isNotEmpty ?? false) ||
      (widget.initialSeatNumber?.trim().isNotEmpty ?? false);

  void _initializeImportedTicket() {
    final mileage = widget.initialMileageKm;
    if (mileage != null && mileage > 0) {
      _distanceController.text = formatTripNumber(mileage);
    }
    final price = widget.initialPrice;
    if (price != null && price >= 0) {
      _priceController.text = formatTripNumber(price);
    }
    _notesController.text = widget.initialNotes?.trim() ?? '';
    if (!_hasImportedSeat) return;
    final seat = parseTripSeat(
      widget.initialSeatType,
      widget.initialSeatNumber,
    );
    _seatType = seat.seatType;
    _seatMode = seat.seatMode;
    _carriageNumber = seat.carriageNumber;
    _primarySeatNumber = seat.primarySeatNumber;
    _secondarySeatNumber = seat.secondarySeatNumber;
    _customSeatTypeController.text = seat.customSeatType;
    _customSeatNumberController.text = seat.customSeatNumber;
  }

  Future<RouteResolution?> _resolveRoutes() async {
    try {
      if (!widget.timetableSource.isOnline) {
        final selectedStops = widget.scheduleStops.sublist(
          widget.departureStopIndex,
          widget.arrivalStopIndex + 1,
        );
        final hasHistoricalMileage = selectedStops.any(
          (stop) => stop.mileage != null && stop.mileage! > 0,
        );
        if (!hasHistoricalMileage) return null;

        final sections = <StationPairDistance>[];
        for (
          var index = widget.departureStopIndex;
          index < widget.arrivalStopIndex;
          index++
        ) {
          final from = widget.scheduleStops[index];
          final to = widget.scheduleStops[index + 1];
          final fromMileage = from.mileage;
          final toMileage = to.mileage;
          sections.add(
            StationPairDistance(
              fromStation: from.stationName,
              toStation: to.stationName,
              distanceKm: fromMileage != null && toMileage != null
                  ? (toMileage - fromMileage).abs()
                  : null,
            ),
          );
        }
        return RouteService.resolveJourney(sections);
      }
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
    final routeError = validateViaRouteSegments(
      _viaRouteSegments,
      startStation: _departureStop.stationName,
      endStation: _arrivalStop.stationName,
    );
    if (routeError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(routeError)));
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
      rollingStock: nullableTripText(_rollingStockController.text),
      companyName: nullableTripText(_companyController.text),
      fromStation: _departureStop.stationName,
      toStation: _arrivalStop.stationName,
      departureTime: _departureTime,
      arrivalTime: _arrivalTime,
      mileageKm: double.tryParse(_distanceController.text.trim()) ?? 0,
      viaRouteSegments: _viaRouteSegments,
      seatType: seatType,
      seatNumber: seatNumber,
      price: double.tryParse(_priceController.text.trim()) ?? 0,
      isLocalOnly: _isLocalOnly,
      notes: nullableTripText(_notesController.text),
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
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(
          widget.reviewPosition == null || widget.reviewTotal == null
              ? '详细信息'
              : '确认导入 ${widget.reviewPosition}/${widget.reviewTotal}',
        ),
        scrolledUnderElevation: 0,
        bottom: widget.reviewPosition == null || widget.reviewTotal == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value: widget.reviewPosition! / widget.reviewTotal!,
                  minHeight: 4,
                ),
              ),
      ),
      body: TripFormShell(
        formKey: _formKey,
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width >= 720 ? 24 : 16,
          12,
          MediaQuery.sizeOf(context).width >= 720 ? 24 : 16,
          32,
        ),
        children: [
          TripTicket(
            trainNumber: widget.trainNumber,
            departureStop: _departureStop,
            arrivalStop: _arrivalStop,
          ),
          const SizedBox(height: 20),
          TripSeatSection(
            seatType: _seatType,
            seatMode: _seatMode,
            customSeatTypeController: _customSeatTypeController,
            customSeatNumberController: _customSeatNumberController,
            carriageNumber: _carriageNumber,
            primarySeatNumber: _primarySeatNumber,
            secondarySeatNumber: _secondarySeatNumber,
            onSeatTypeChanged: _changeSeatType,
            onSeatModeChanged: _changeSeatMode,
            onCarriageChanged: (value) =>
                setState(() => _carriageNumber = value),
            onPrimaryChanged: (value) =>
                setState(() => _primarySeatNumber = value),
            onSecondaryChanged: (value) =>
                setState(() => _secondarySeatNumber = value),
            onTicketSeatOptionChanged: (option) =>
                setState(() => _applyTicketSeatOption(option)),
            ticketSeatOptions: _ticketSeatAvailability?.seatOptions,
            noSeatOption: _ticketSeatAvailability?.noSeatOption,
            lookupFailed: _ticketSeatLookupFailed,
          ),
          const SizedBox(height: 16),
          FormSection(
            icon: Icons.route_outlined,
            title: '运行信息',
            trailing: _isLoadingRuntimeInfo
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ResponsiveFieldWrap(
                  children: [
                    TripNumberField(
                      controller: _distanceController,
                      label: '里程',
                      suffix: 'km',
                      icon: Icons.straighten_outlined,
                      onCalculate: _viaRouteSegments.isEmpty
                          ? null
                          : _calculateTotalMileage,
                      helperText: _distanceLookupFailed ? '未自动获取，请手动填写' : null,
                    ),
                    TripPriceField(controller: _priceController),
                    CompanyEditor(controller: _companyController),
                    TextFormField(
                      controller: _rollingStockController,
                      decoration: InputDecoration(
                        labelText: '车型',
                        prefixIcon: const Icon(Icons.train_outlined),
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
                  isLoading: _isLoadingRouteInfo || _isLoadingRouteCatalog,
                  isRecognizing: _isRecognizingShortestPath,
                  revision: _routeEditorRevision,
                  onRecognizeShortestPath: _recognizeShortestPath,
                  resolveDistance: RouteService.getDistanceOnRoute,
                  resolveStations: RouteService.getStationsForRoute,
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
          TripPropertiesSection(
            isRailTrip: true,
            isLocalOnly: _isLocalOnly,
            enabled: !_isSaving,
            showRailTrip: false,
            onRailTripChanged: (_) {},
            onLocalOnlyChanged: (value) => setState(() => _isLocalOnly = value),
          ),
          const SizedBox(height: 16),
          TripNotesSection(controller: _notesController),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('保存行程'),
            ),
          ),
        ],
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
          _priceController.text = formatTripNumber(option.price);
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
        _priceController.text = formatTripNumber(noSeat.price);
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
    _priceController.text = formatTripNumber(option.price);
    _secondarySeatNumber = option.berth ?? _secondarySeatNumber;
  }

  void _calculateTotalMileage() {
    final total = _viaRouteSegments.fold<double>(
      0,
      (sum, segment) => sum + segment.mileageKm,
    );
    setState(() => _distanceController.text = formatTripNumber(total));
  }

  List<ViaRouteSegment> _normalizeRouteSegments(List<ViaRouteSegment> source) {
    return normalizeViaRouteSegments(
      source,
      startStation: _departureStop.stationName,
      endStation: _arrivalStop.stationName,
    );
  }
}

String _formatDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
