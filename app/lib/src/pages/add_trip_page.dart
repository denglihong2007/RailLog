import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';
import 'package:raillog/src/models/train_search_result.dart';
import 'package:raillog/src/models/timetable_source.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/pages/manual_trip_page.dart';
import 'package:raillog/src/pages/import_12306_page.dart';
import 'package:raillog/src/pages/train_trip_form_page.dart';
import 'package:raillog/src/services/train_service.dart';
import 'package:raillog/src/services/baidu_train_ticket_ocr_service.dart';
import 'package:raillog/src/widgets/add_trip/entry_method_card.dart';
import 'package:raillog/src/widgets/add_trip/quick_add_card.dart';
import 'package:raillog/src/widgets/excel_import_action.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

class AddTripPage extends StatefulWidget {
  const AddTripPage({super.key, required this.onTripSaved});

  final VoidCallback onTripSaved;

  @override
  State<AddTripPage> createState() => _AddTripPageState();
}

class _AddTripPageState extends State<AddTripPage> {
  final _trainNumberController = TextEditingController();
  DateTime _travelDate = DateTime.now();
  TimetableSource _timetableSource = TimetableSource.forYear(
    DateTime.now().year,
  );
  List<TrainSearchResult> _searchResults = const [];
  List<TrainSearchResult> _stationSearchResults = const [];
  List<String> _stationNames = const [];
  TrainSearchResult? _selectedTrain;
  List<TrainScheduleStop> _scheduleStops = const [];
  bool _isSearching = false;
  bool _isLoadingSchedule = false;
  int _searchRequestId = 0;
  int _scheduleRequestId = 0;
  Timer? _searchDebounce;
  int? _departureStopIndex;
  int? _arrivalStopIndex;
  bool _stationQueryMode = false;
  String _fromStation = '';
  String _toStation = '';
  bool _isSearchingBetween = false;
  bool _hasSearchedBetween = false;
  bool _isRecognizingTicket = false;
  bool _isImportingExcel = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _trainNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickTravelDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _travelDate,
      firstDate: DateTime(2009),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date != null && mounted) {
      setState(() {
        _travelDate = date;
        _timetableSource = TimetableSource.forYear(date.year);
        _stationQueryMode = false;
        _stationSearchResults = const [];
        _hasSearchedBetween = false;
        _stationNames = const [];
        _fromStation = '';
        _toStation = '';
        _clearSelectedTrain();
      });
      _searchTrains(_trainNumberController.text);
    }
  }

  Future<void> _searchTrains(String input) async {
    final query = input.trim().toUpperCase();
    final requestId = ++_searchRequestId;
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = const [];
        _clearSelectedTrain();
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _clearSelectedTrain();
    });
    final results = !_timetableSource.isOnline
        ? await _searchHistoricalTrain(query)
        : await TrainService.searchTrains(query, _travelDate);
    if (!mounted || requestId != _searchRequestId) return;
    setState(() {
      _isSearching = false;
      _searchResults = results;
    });
  }

  void _onSearchChanged(String input) {
    _searchDebounce?.cancel();
    _searchRequestId++;
    if (input.trim().isEmpty) {
      _searchTrains(input);
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _searchTrains(input),
    );
  }

  Future<void> _selectTrain(TrainSearchResult result) async {
    final requestId = ++_scheduleRequestId;
    _trainNumberController.text = result.trainNumber.replaceFirst(' 次', '');
    setState(() {
      _selectedTrain = result;
      _searchResults = const [];
      _stationSearchResults = const [];
      _hasSearchedBetween = false;
      _scheduleStops = const [];
      _departureStopIndex = null;
      _arrivalStopIndex = null;
      _isLoadingSchedule = true;
    });

    final stops = await TrainService.fetchTrainSchedule(
      result.trainNo,
      result.lookupDate ?? _travelDate,
      source: _timetableSource,
    );
    if (!mounted || requestId != _scheduleRequestId) return;

    setState(() {
      _scheduleStops = stops;
      _isLoadingSchedule = false;
      if (_stationQueryMode) {
        _departureStopIndex = _findStopIndex(
          stops,
          _fromStation,
          fallback: result.departureStation,
        );
        _arrivalStopIndex = _findStopIndex(
          stops,
          _toStation,
          fallback: result.arrivalStation,
          startAfter: _departureStopIndex,
        );
      }
    });
    if (_stationQueryMode &&
        _departureStopIndex != null &&
        _arrivalStopIndex != null) {
      await _continueQuickAdd();
    }
    if (!mounted) return;
    if (stops.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未获取到列车时刻表')));
    }
  }

  void _selectScheduleStop(int index) {
    setState(() {
      if (_departureStopIndex == null ||
          _arrivalStopIndex != null ||
          index <= _departureStopIndex!) {
        _departureStopIndex = index;
        _arrivalStopIndex = null;
        return;
      }
      _arrivalStopIndex = index;
    });
  }

  Future<void> _continueQuickAdd() async {
    final train = _selectedTrain;
    final departureIndex = _departureStopIndex;
    final arrivalIndex = _arrivalStopIndex;
    if (train == null || departureIndex == null || arrivalIndex == null) return;

    final resolvedStops = TrainService.resolveScheduleDateTimes(
      _scheduleStops,
      _travelDate,
      departureIndex,
    );
    final saved = await Navigator.of(context).push<bool>(
      m3PageRoute(
        builder: (context) => TrainTripFormPage(
          trainNumber: train.trainNumber.replaceFirst(' 次', ''),
          timetableSource: _timetableSource,
          scheduleStops: resolvedStops,
          departureStopIndex: departureIndex,
          arrivalStopIndex: arrivalIndex,
        ),
      ),
    );
    if (saved == true && mounted) widget.onTripSaved();
  }

  Future<void> _openManualEntry() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(m3PageRoute(builder: (context) => const ManualTripPage()));
    if (saved == true && mounted) widget.onTripSaved();
  }

  Future<void> _openTicketImport() async {
    if (_isRecognizingTicket) return;
    final credentials = await BaiduOcrSettings.load();
    if (!mounted) return;
    if (!credentials.isComplete) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在设置中填写百度 OCR API Key 和 Secret Key')),
        );
      }
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照识别'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('选择车票文件'),
              subtitle: const Text('支持图片文件'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    XFile? image;
    TrainTicketOcrResult? recognized;
    try {
      image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 2400,
      );
    } on StateError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前平台不支持直接调用相机，请改用选择车票文件')),
        );
      }
      return;
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开相机：${error.message ?? error.code}')),
        );
      }
      return;
    }
    if (image == null || !mounted) return;
    setState(() => _isRecognizingTicket = true);
    try {
      final bytes = await image.readAsBytes();
      final ticket = recognized = await BaiduTrainTicketOcrService().recognize(
        bytes,
        credentials,
      );
      final source = TimetableSource.forYear(ticket.departureTime.year);
      final candidates = source.isOnline
          ? await TrainService.searchTrains(
              ticket.trainNumber,
              ticket.departureTime,
            )
          : await TrainService.searchHistoricalTrains(
              ticket.trainNumber,
              source.year!,
            );
      final train = candidates.cast<TrainSearchResult?>().firstWhere(
        (candidate) =>
            candidate!.trainNumber.replaceFirst(' 次', '').toUpperCase() ==
            ticket.trainNumber.toUpperCase(),
        orElse: () => candidates.isEmpty ? null : candidates.first,
      );
      if (train == null) throw const BaiduOcrException('无法匹配识别到的车次时刻表');
      final stops = await TrainService.fetchTrainSchedule(
        train.trainNo,
        ticket.departureTime,
        source: source,
      );
      final departureIndex = _findStopIndex(stops, ticket.fromStation);
      final arrivalIndex = _findStopIndex(
        stops,
        ticket.toStation,
        startAfter: departureIndex,
      );
      if (departureIndex == null || arrivalIndex == null) {
        throw const BaiduOcrException('识别到的车站无法匹配车次时刻表');
      }
      final resolvedStops = TrainService.resolveScheduleDateTimes(
        stops,
        ticket.departureTime,
        departureIndex,
      );
      if (!mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        m3PageRoute(
          builder: (context) => TrainTripFormPage(
            trainNumber: train.trainNumber.replaceFirst(' 次', ''),
            timetableSource: source,
            scheduleStops: resolvedStops,
            departureStopIndex: departureIndex,
            arrivalStopIndex: arrivalIndex,
            initialSeatType: ticket.seatType,
            initialSeatNumber: ticket.seatNumber,
            initialPrice: ticket.price,
            initialPrompt: '车票信息已由百度 OCR 识别，请核对票面信息',
          ),
        ),
      );
      if (saved == true && mounted) widget.onTripSaved();
    } catch (error) {
      if (mounted) {
        final ticket = recognized;
        if (ticket != null) {
          final saved = await Navigator.of(context).push<bool>(
            m3PageRoute(
              builder: (context) => ManualTripPage(
                initialTrip: TripRecord(
                  id: 0,
                  trainNumber: ticket.trainNumber,
                  fromStation: ticket.fromStation,
                  toStation: ticket.toStation,
                  departureTime: ticket.departureTime,
                  viaRouteSegments: const [],
                  seatType: ticket.seatType,
                  seatNumber: ticket.seatNumber,
                  price: ticket.price ?? 0,
                ),
              ),
            ),
          );
          if (saved == true && mounted) widget.onTripSaved();
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('车票识别失败：$error')));
        }
      }
    } finally {
      if (mounted) setState(() => _isRecognizingTicket = false);
    }
  }

  Future<void> _open12306Import() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(m3PageRoute(builder: (context) => const Import12306Page()));
    if (saved == true && mounted) widget.onTripSaved();
  }

  Future<void> _openExcelImport() async {
    if (_isImportingExcel) return;
    await showExcelImportGuide(context, onPick: _pickAndImportExcel);
  }

  Future<void> _pickAndImportExcel() async {
    if (!mounted) return;
    setState(() => _isImportingExcel = true);
    final result = await pickAndImportExcel(context);
    if (result != null && mounted) widget.onTripSaved();
    if (mounted) setState(() => _isImportingExcel = false);
  }

  void _clearSelectedTrain() {
    _selectedTrain = null;
    _scheduleStops = const [];
    _departureStopIndex = null;
    _arrivalStopIndex = null;
  }

  Future<List<TrainSearchResult>> _searchHistoricalTrain(
    String trainNumber,
  ) async {
    return TrainService.searchHistoricalTrains(
      trainNumber,
      _timetableSource.year!,
    );
  }

  void _selectTimetableSource(TimetableSource source) {
    if (source == _timetableSource) return;
    setState(() {
      _timetableSource = source;
      _stationQueryMode = false;
      _stationSearchResults = const [];
      _hasSearchedBetween = false;
      _stationNames = const [];
      _fromStation = '';
      _toStation = '';
      _clearSelectedTrain();
    });
    _searchTrains(_trainNumberController.text);
  }

  Future<void> _setLookupMode(bool stationMode) async {
    if (stationMode && _timetableSource.isOnline) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('站站查询仅支持本地年度数据库')));
      return;
    }
    setState(() {
      _stationQueryMode = stationMode;
      _searchResults = const [];
      _stationSearchResults = const [];
      _hasSearchedBetween = false;
      _clearSelectedTrain();
    });
    if (stationMode && _stationNames.isEmpty) {
      final names = await TrainService.fetchHistoricalStations(
        _timetableSource.year!,
      );
      if (mounted && _stationQueryMode) setState(() => _stationNames = names);
    }
  }

  void _setFromStation(String value) {
    setState(() {
      _fromStation = value;
      _stationSearchResults = const [];
      _hasSearchedBetween = false;
      _clearSelectedTrain();
    });
    if (_toStation.trim().isNotEmpty) _searchBetweenStations();
  }

  void _setToStation(String value) {
    setState(() {
      _toStation = value;
      _stationSearchResults = const [];
      _hasSearchedBetween = false;
      _clearSelectedTrain();
    });
    if (_fromStation.trim().isNotEmpty) _searchBetweenStations();
  }

  Future<void> _searchBetweenStations() async {
    if (_fromStation.trim().isEmpty || _toStation.trim().isEmpty) return;
    setState(() {
      _isSearchingBetween = true;
      _hasSearchedBetween = true;
    });
    final results = await TrainService.searchHistoricalTrainsBetween(
      fromStation: _fromStation,
      toStation: _toStation,
      year: _timetableSource.year!,
    );
    if (!mounted) return;
    setState(() {
      _isSearchingBetween = false;
      _stationSearchResults = results;
    });
    if (!mounted) return;
    if (results.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未找到符合条件的车次')));
      return;
    }
  }

  int? _findStopIndex(
    List<TrainScheduleStop> stops,
    String station, {
    String? fallback,
    int? startAfter,
  }) {
    final target = _stationKey(station.isEmpty ? fallback ?? '' : station);
    if (target.isEmpty) return null;
    for (var index = (startAfter ?? -1) + 1; index < stops.length; index++) {
      if (_stationKey(stops[index].stationName) == target) return index;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        Text('添加行程', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('选择适合你的录入方式', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 16),
        const _PublicTripNotice(),
        const SizedBox(height: 24),
        QuickAddCard(
          travelDate: _travelDate,
          timetableSource: _timetableSource,
          trainNumberController: _trainNumberController,
          onPickDate: _pickTravelDate,
          onSelectTimetableSource: _selectTimetableSource,
          stationQueryMode: _stationQueryMode,
          onLookupModeChanged: _setLookupMode,
          stationNames: _stationNames,
          fromStation: _fromStation,
          toStation: _toStation,
          onFromStationChanged: _setFromStation,
          onToStationChanged: _setToStation,
          isSearchingBetween: _isSearchingBetween,
          hasSearchedBetween: _hasSearchedBetween,
          stationSearchResults: _stationSearchResults,
          onSearchBetween: _searchBetweenStations,
          isSearching: _isSearching,
          searchResults: _searchResults,
          onSearchChanged: _onSearchChanged,
          onSelectTrain: _selectTrain,
          selectedTrain: _selectedTrain,
          isLoadingSchedule: _isLoadingSchedule,
          scheduleStops: _scheduleStops,
          departureStopIndex: _departureStopIndex,
          arrivalStopIndex: _arrivalStopIndex,
          onSelectScheduleStop: _selectScheduleStop,
          onContinue: _continueQuickAdd,
        ),
        const SizedBox(height: 16),
        EntryMethodCard(
          icon: Icons.edit_note_outlined,
          title: '手动录入',
          description: '逐项填写车次、站点、座位等信息',
          onTap: _openManualEntry,
        ),
        const SizedBox(height: 12),
        EntryMethodCard(
          icon: Icons.upload_file_outlined,
          title: '从 Excel 导入',
          description: _isImportingExcel
              ? '正在导入行程...'
              : '按照规范整理表格后批量导入，重复行程将自动跳过',
          onTap: _openExcelImport,
        ),
        const SizedBox(height: 12),
        EntryMethodCard(
          icon: Icons.download_for_offline_outlined,
          title: '从 12306 导入',
          description: '核验电子发票，导入近 180 天行程并逐条确认',
          onTap: _open12306Import,
        ),
        const SizedBox(height: 12),
        EntryMethodCard(
          icon: Icons.document_scanner_outlined,
          title: '车票识别',
          description: _isRecognizingTicket
              ? '正在识别车票...'
              : '拍摄纸质车票或选择车票图片，自动补全信息',
          onTap: _openTicketImport,
        ),
      ],
    );
  }
}

String _stationKey(String value) => value
    .trim()
    .replaceAll(RegExp(r'\s+'), '')
    .replaceFirst(RegExp(r'(站|市)$'), '');

class _PublicTripNotice extends StatelessWidget {
  const _PublicTripNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: colors.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: Icon(Icons.public, color: colors.onSecondaryContainer),
        title: Text(
          '本地行程不会上传到云端并参加统计',
          style: TextStyle(color: colors.onSecondaryContainer),
        ),
      ),
    );
  }
}
