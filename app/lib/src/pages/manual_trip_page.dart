import 'package:flutter/material.dart';
import 'package:raillog/src/models/seat_selection.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/route_service.dart';
import 'package:raillog/src/widgets/trip_details/form_section.dart';
import 'package:raillog/src/widgets/trip_details/company_editor.dart';
import 'package:raillog/src/widgets/trip_details/route_segments_editor.dart';
import 'package:raillog/src/widgets/trip_details/trip_form_common.dart';

class ManualTripPage extends StatefulWidget {
  const ManualTripPage({super.key, this.initialTrip});

  final TripRecord? initialTrip;

  @override
  State<ManualTripPage> createState() => _ManualTripPageState();
}

class _ManualTripPageState extends State<ManualTripPage> {
  final _formKey = GlobalKey<FormState>();
  final _trainNumberController = TextEditingController();
  final _fromStationController = TextEditingController();
  final _toStationController = TextEditingController();
  final _customSeatTypeController = TextEditingController();
  final _customSeatNumberController = TextEditingController();
  final _distanceController = TextEditingController();
  final _priceController = TextEditingController();
  final _companyController = TextEditingController();
  final _rollingStockController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _departureTime = DateTime.now();
  DateTime? _arrivalTime;
  String _seatType = '二等座';
  String _seatMode = '席位';
  int? _carriageNumber = 1;
  int _primarySeatNumber = 1;
  String _secondarySeatNumber = '无';
  bool _isRailTrip = true;
  bool _isLocalOnly = false;
  bool _isSaving = false;
  List<String> _routeNames = const [];
  List<ViaRouteSegment> _viaRouteSegments = const [];
  List<String> _unresolvedRouteSections = const [];
  bool _isLoadingRouteCatalog = true;
  bool _isRecognizingShortestPath = false;
  bool _routeLookupFailed = false;
  int _routeEditorRevision = 0;

  @override
  void initState() {
    super.initState();
    _initializeFromTrip();
    _loadRouteCatalog();
  }

  void _initializeFromTrip() {
    final trip = widget.initialTrip;
    if (trip == null) return;
    _trainNumberController.text = trip.trainNumber;
    _fromStationController.text = trip.fromStation;
    _toStationController.text = trip.toStation;
    _distanceController.text = trip.mileageKm > 0
        ? formatTripNumber(trip.mileageKm)
        : '';
    _priceController.text = formatTripNumber(trip.price);
    _companyController.text = trip.companyName ?? '';
    _rollingStockController.text = trip.rollingStock ?? '';
    _notesController.text = trip.notes ?? '';
    _departureTime = trip.departureTime;
    _arrivalTime = trip.arrivalTime;
    _isRailTrip = trip.isRailTrip;
    _isLocalOnly = trip.isLocalOnly;
    _viaRouteSegments = List.unmodifiable(trip.viaRouteSegments);
    _initializeSeat(trip);
  }

  void _initializeSeat(TripRecord trip) {
    final seat = parseTripSeat(trip.seatType, trip.seatNumber);
    _seatType = seat.seatType;
    _seatMode = seat.seatMode;
    _carriageNumber = seat.carriageNumber;
    _primarySeatNumber = seat.primarySeatNumber;
    _secondarySeatNumber = seat.secondarySeatNumber;
    _customSeatTypeController.text = seat.customSeatType;
    _customSeatNumberController.text = seat.customSeatNumber;
  }

  @override
  void dispose() {
    _trainNumberController.dispose();
    _fromStationController.dispose();
    _toStationController.dispose();
    _customSeatTypeController.dispose();
    _customSeatNumberController.dispose();
    _distanceController.dispose();
    _priceController.dispose();
    _companyController.dispose();
    _rollingStockController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDepartureTime() async {
    final value = await _pickDateTime(_departureTime);
    if (value != null && mounted) setState(() => _departureTime = value);
  }

  Future<void> _pickArrivalTime() async {
    final value = await _pickDateTime(_arrivalTime ?? _departureTime);
    if (value != null && mounted) setState(() => _arrivalTime = value);
  }

  Future<DateTime?> _pickDateTime(DateTime initialValue) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initialValue,
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialValue),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
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
    final fromStation = _fromStationController.text.trim();
    final toStation = _toStationController.text.trim();
    if (fromStation.isEmpty || toStation.isEmpty) return;
    setState(() => _isRecognizingShortestPath = true);
    try {
      final result = await RouteService.resolveShortestJourney(
        fromStation,
        toStation,
      );
      if (!mounted) return;
      setState(() {
        _viaRouteSegments = _normalizeRouteSegments(result.segments);
        _unresolvedRouteSections = result.unresolvedSections;
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
    if (_isRailTrip) {
      final routeError = validateViaRouteSegments(
        _viaRouteSegments,
        startStation: _fromStationController.text,
        endStation: _toStationController.text,
      );
      if (routeError != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(routeError)));
        return;
      }
    }
    if (_arrivalTime != null && _arrivalTime!.isBefore(_departureTime)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('终到时间不能早于始发时间')));
      return;
    }
    setState(() => _isSaving = true);

    final isCustomSeat = _seatMode == '其它';
    final seatType = isCustomSeat
        ? nullableTripText(_customSeatTypeController.text)
        : _seatType;
    final seatNumber = isCustomSeat
        ? nullableTripText(_customSeatNumberController.text)
        : SeatSelection(
            mode: _seatMode,
            carriageNumber: _carriageNumber ?? 1,
            primaryNumber: _primarySeatNumber,
            secondaryNumber: _secondarySeatNumber,
          ).seatNumber;
    final existingTrip = widget.initialTrip;
    final trip = TripRecord(
      id: existingTrip?.id ?? 0,
      ticketId: existingTrip?.ticketId,
      clientId: existingTrip?.clientId,
      ownerUserId: existingTrip?.ownerUserId,
      createdAt: existingTrip?.createdAt,
      trainNumber: _trainNumberController.text.trim(),
      rollingStock: nullableTripText(_rollingStockController.text),
      companyName: nullableTripText(_companyController.text),
      fromStation: _fromStationController.text.trim(),
      toStation: _toStationController.text.trim(),
      departureTime: _departureTime,
      arrivalTime: _arrivalTime,
      mileageKm: double.tryParse(_distanceController.text.trim()) ?? 0,
      viaRouteSegments: _isRailTrip ? _viaRouteSegments : const [],
      seatType: seatType,
      seatNumber: seatNumber,
      price: double.tryParse(_priceController.text.trim()) ?? 0,
      isRailTrip: _isRailTrip,
      isLocalOnly: _isLocalOnly,
      notes: nullableTripText(_notesController.text),
    );

    try {
      if (existingTrip == null) {
        await DbHelper.instance.insertTrip(trip);
      } else {
        final updated = await DbHelper.instance.updateTrip(trip);
        if (updated == 0) throw StateError('行程不存在或已被删除');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(existingTrip == null ? '行程已保存' : '行程已更新')),
      );
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
        title: Text(widget.initialTrip == null ? '手动录入' : '编辑行程'),
        scrolledUnderElevation: 0,
      ),
      body: TripFormShell(
        formKey: _formKey,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          FormSection(
            icon: Icons.edit_location_alt_outlined,
            title: '行程信息',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _requiredTextField(
                  controller: _trainNumberController,
                  label: _isRailTrip ? '车次' : '班次或名称',
                  icon: Icons.tag_outlined,
                ),
                const SizedBox(height: 12),
                ResponsiveFieldWrap(
                  children: [
                    _requiredTextField(
                      controller: _fromStationController,
                      label: '始发站',
                      icon: Icons.trip_origin_outlined,
                      onChanged: (_) => _syncRouteEndpoints(),
                    ),
                    _requiredTextField(
                      controller: _toStationController,
                      label: '终到站',
                      icon: Icons.location_on_outlined,
                      onChanged: (_) => _syncRouteEndpoints(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ResponsiveFieldWrap(
                  children: [
                    _DateTimeInput(
                      label: '始发时间',
                      value: _departureTime,
                      onTap: _pickDepartureTime,
                    ),
                    _DateTimeInput(
                      label: '终到时间（可选）',
                      value: _arrivalTime,
                      onTap: _pickArrivalTime,
                      onClear: _arrivalTime == null
                          ? null
                          : () => setState(() => _arrivalTime = null),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
            allowEmptyCustomSeat:
                widget.initialTrip != null &&
                (widget.initialTrip!.seatType?.trim().isEmpty ?? true) &&
                (widget.initialTrip!.seatNumber?.trim().isEmpty ?? true),
          ),
          const SizedBox(height: 16),
          FormSection(
            icon: Icons.route_outlined,
            title: '运行信息',
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
                      onCalculate: !_isRailTrip || _viaRouteSegments.isEmpty
                          ? null
                          : _calculateTotalMileage,
                    ),
                    TripPriceField(controller: _priceController),
                    CompanyEditor(controller: _companyController),
                    TextFormField(
                      controller: _rollingStockController,
                      decoration: const InputDecoration(
                        labelText: '车型',
                        hintText: '重联车组车号请用“&”连接',
                        prefixIcon: Icon(Icons.train_outlined),
                      ),
                    ),
                  ],
                ),
                if (_isRailTrip) ...[
                  const SizedBox(height: 20),
                  RouteSegmentsEditor(
                    startStation: _fromStationController.text,
                    endStation: _toStationController.text,
                    routeNames: _routeNames,
                    segments: _viaRouteSegments,
                    isLoading: _isLoadingRouteCatalog,
                    isRecognizing: _isRecognizingShortestPath,
                    revision: _routeEditorRevision,
                    onRecognizeShortestPath: _recognizeShortestPath,
                    resolveDistance: RouteService.getDistanceOnRoute,
                    resolveStations: RouteService.getStationsForRoute,
                    onChanged: (segments) {
                      setState(() {
                        _viaRouteSegments = segments;
                        _unresolvedRouteSections = const [];
                        _routeLookupFailed = false;
                      });
                    },
                    unresolvedSections: _unresolvedRouteSections,
                    lookupFailed: _routeLookupFailed,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          TripPropertiesSection(
            isRailTrip: _isRailTrip,
            isLocalOnly: _isLocalOnly,
            enabled: !_isSaving,
            onRailTripChanged: (value) => setState(() => _isRailTrip = value),
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
              label: Text(widget.initialTrip == null ? '保存行程' : '保存修改'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _requiredTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      validator: (value) =>
          value == null || value.trim().isEmpty ? '请填写$label' : null,
    );
  }

  void _changeSeatType(String value) {
    setState(() => _seatType = value);
  }

  void _calculateTotalMileage() {
    final total = _viaRouteSegments.fold<double>(
      0,
      (sum, segment) => sum + segment.mileageKm,
    );
    setState(() => _distanceController.text = formatTripNumber(total));
  }

  void _changeSeatMode(String value) {
    setState(() {
      _seatMode = value;
      _carriageNumber ??= 1;
    });
  }

  void _syncRouteEndpoints() {
    if (_viaRouteSegments.isEmpty) {
      setState(() {});
      return;
    }
    setState(() {
      _viaRouteSegments = _normalizeRouteSegments(_viaRouteSegments);
    });
  }

  List<ViaRouteSegment> _normalizeRouteSegments(List<ViaRouteSegment> source) {
    return normalizeViaRouteSegments(
      source,
      startStation: _fromStationController.text,
      endStation: _toStationController.text,
    );
  }
}

class _DateTimeInput extends StatelessWidget {
  const _DateTimeInput({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.schedule_outlined, color: colors.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 2),
                    Text(
                      value == null ? '未填写' : _formatDateTime(value!),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
              if (onClear != null)
                IconButton(
                  tooltip: '清除终到时间',
                  onPressed: onClear,
                  icon: const Icon(Icons.clear),
                )
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
