import 'package:flutter/material.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';
import 'package:raillog/src/models/train_search_result.dart';
import 'package:raillog/src/pages/manual_trip_page.dart';
import 'package:raillog/src/pages/trip_details_page.dart';
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
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date != null && mounted) {
      setState(() {
        _travelDate = date;
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
    final results = await TrainService.searchTrains(query, _travelDate);
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
        builder: (context) => TripDetailsPage(
          trainNumber: train.trainNumber.replaceFirst(' 次', ''),
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

  void _clearSelectedTrain() {
    _selectedTrain = null;
    _scheduleStops = const [];
    _departureStopIndex = null;
    _arrivalStopIndex = null;
  }

  void _showUnavailableMessage(String feature) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$feature功能正在准备中')));
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
          trainNumberController: _trainNumberController,
          onPickDate: _pickTravelDate,
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
          description: '导入 12306 行程信息，快速生成行程记录',
          onTap: () => _showUnavailableMessage('12306 导入'),
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
          '行程会公开展示，建议在出行结束后录入',
          style: TextStyle(color: colors.onSecondaryContainer),
        ),
      ),
    );
  }
}
