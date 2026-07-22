import 'package:flutter/material.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';
import 'package:raillog/src/models/train_search_result.dart';
import 'package:raillog/src/models/timetable_source.dart';
import 'package:raillog/src/pages/manual_trip_page.dart';
import 'package:raillog/src/pages/import_12306_page.dart';
import 'package:raillog/src/pages/train_trip_form_page.dart';
import 'package:raillog/src/services/train_service.dart';
import 'package:raillog/src/widgets/add_trip/entry_method_card.dart';
import 'package:raillog/src/widgets/add_trip/quick_add_card.dart';
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
  TrainSearchResult? _selectedTrain;
  List<TrainScheduleStop> _scheduleStops = const [];
  bool _isSearching = false;
  bool _isLoadingSchedule = false;
  int _searchRequestId = 0;
  int _scheduleRequestId = 0;
  int? _departureStopIndex;
  int? _arrivalStopIndex;

  @override
  void dispose() {
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

  Future<void> _selectTrain(TrainSearchResult result) async {
    final requestId = ++_scheduleRequestId;
    _trainNumberController.text = result.trainNumber.replaceFirst(' 次', '');
    setState(() {
      _selectedTrain = result;
      _searchResults = const [];
      _scheduleStops = const [];
      _departureStopIndex = null;
      _arrivalStopIndex = null;
      _isLoadingSchedule = true;
    });

    final stops = await TrainService.fetchTrainSchedule(
      result.trainNo,
      _travelDate,
      source: _timetableSource,
    );
    if (!mounted || requestId != _scheduleRequestId) return;

    setState(() {
      _scheduleStops = stops;
      _isLoadingSchedule = false;
    });
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

  Future<void> _open12306Import() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(m3PageRoute(builder: (context) => const Import12306Page()));
    if (saved == true && mounted) widget.onTripSaved();
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
      _clearSelectedTrain();
    });
    _searchTrains(_trainNumberController.text);
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
          isSearching: _isSearching,
          searchResults: _searchResults,
          onSearchChanged: _searchTrains,
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
          description: '逐项填写车次、站点、席别与票价等信息',
          onTap: _openManualEntry,
        ),
        const SizedBox(height: 12),
        EntryMethodCard(
          icon: Icons.download_for_offline_outlined,
          title: '12306 导入',
          description: '核验电子发票，导入近 180 天行程并逐条确认',
          onTap: _open12306Import,
        ),
      ],
    );
  }
}

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
