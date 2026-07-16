import 'package:flutter/material.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';
import 'package:raillog/src/models/train_search_result.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

class QuickAddCard extends StatelessWidget {
  const QuickAddCard({
    super.key,
    required this.travelDate,
    required this.trainNumberController,
    required this.onPickDate,
    required this.isSearching,
    required this.searchResults,
    required this.onSearchChanged,
    required this.onSelectTrain,
    required this.selectedTrain,
    required this.isLoadingSchedule,
    required this.scheduleStops,
    required this.departureStopIndex,
    required this.arrivalStopIndex,
    required this.onSelectScheduleStop,
    required this.onContinue,
  });

  final DateTime travelDate;
  final TextEditingController trainNumberController;
  final VoidCallback onPickDate;
  final bool isSearching;
  final List<TrainSearchResult> searchResults;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<TrainSearchResult> onSelectTrain;
  final TrainSearchResult? selectedTrain;
  final bool isLoadingSchedule;
  final List<TrainScheduleStop> scheduleStops;
  final int? departureStopIndex;
  final int? arrivalStopIndex;
  final ValueChanged<int> onSelectScheduleStop;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt_outlined, color: colors.primary),
                const SizedBox(width: 12),
                Text('快捷添加', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 24),
            Text('出行日期', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              tileColor: colors.surfaceContainerHighest,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(
                travelDate.toIso8601String().substring(0, 10),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: onPickDate,
            ),
            const SizedBox(height: 24),
            Text('车次信息', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: trainNumberController,
              textCapitalization: TextCapitalization.characters,
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                labelText: '车次',
                hintText: '例如 G1234',
                prefixIcon: Icon(Icons.train_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            AnimatedSize(
              duration: m3MotionDuration,
              curve: Curves.easeOutCubic,
              child: M3FadeThroughSwitcher(
                alignment: Alignment.topCenter,
                child: _buildSearchState(context),
              ),
            ),
            AnimatedSize(
              duration: m3MotionDuration,
              curve: Curves.easeOutCubic,
              child: M3FadeThroughSwitcher(
                alignment: Alignment.topCenter,
                child: _buildTrainSelection(context, colors),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchState(BuildContext context) {
    if (isSearching) {
      return const Padding(
        key: ValueKey('search-loading'),
        padding: EdgeInsets.only(top: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (searchResults.isEmpty) {
      return const SizedBox.shrink(key: ValueKey('search-empty'));
    }
    return Padding(
      key: ValueKey('search-results-${searchResults.length}'),
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('选择车次', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _TrainSearchResults(
            results: searchResults,
            onSelectTrain: onSelectTrain,
          ),
        ],
      ),
    );
  }

  Widget _buildTrainSelection(BuildContext context, ColorScheme colors) {
    final train = selectedTrain;
    if (train == null) {
      return const SizedBox.shrink(key: ValueKey('train-unselected'));
    }
    return Padding(
      key: ValueKey('train-${train.trainNo}'),
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('选择乘车区间', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '先点始发站，再点终到站',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          AnimatedSize(
            duration: m3MotionDuration,
            curve: Curves.easeOutCubic,
            child: M3FadeThroughSwitcher(
              alignment: Alignment.topCenter,
              child: _buildScheduleState(),
            ),
          ),
          AnimatedSize(
            duration: m3MotionDurationShort,
            curve: Curves.easeOutCubic,
            child: M3FadeThroughSwitcher(
              alignment: Alignment.centerRight,
              child: departureStopIndex != null && arrivalStopIndex != null
                  ? Padding(
                      key: const ValueKey('continue-visible'),
                      padding: const EdgeInsets.only(top: 16),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: onContinue,
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('下一步'),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('continue-hidden')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleState() {
    if (isLoadingSchedule) {
      return const Center(
        key: ValueKey('schedule-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (scheduleStops.isEmpty) {
      return const Card.outlined(
        key: ValueKey('schedule-empty'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('暂未获取到该车次的时刻表'),
        ),
      );
    }
    return _ScheduleSnakeSelector(
      key: ValueKey('schedule-${scheduleStops.length}'),
      stops: scheduleStops,
      departureStopIndex: departureStopIndex,
      arrivalStopIndex: arrivalStopIndex,
      onSelectStop: onSelectScheduleStop,
    );
  }
}

class _TrainSearchResults extends StatefulWidget {
  const _TrainSearchResults({
    required this.results,
    required this.onSelectTrain,
  });

  final List<TrainSearchResult> results;
  final ValueChanged<TrainSearchResult> onSelectTrain;

  @override
  State<_TrainSearchResults> createState() => _TrainSearchResultsState();
}

class _TrainSearchResultsState extends State<_TrainSearchResults> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: widget.results.length < 4 ? widget.results.length * 72.0 : 288,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: ListView.separated(
            padding: EdgeInsets.zero,
            controller: _scrollController,
            primary: false,
            itemCount: widget.results.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final result = widget.results[index];
              return ListTile(
                leading: const Icon(Icons.train_outlined),
                title: Text(result.trainNumber),
                subtitle: Text(result.summary),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => widget.onSelectTrain(result),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ScheduleSnakeSelector extends StatelessWidget {
  const _ScheduleSnakeSelector({
    super.key,
    required this.stops,
    required this.departureStopIndex,
    required this.arrivalStopIndex,
    required this.onSelectStop,
  });

  final List<TrainScheduleStop> stops;
  final int? departureStopIndex;
  final int? arrivalStopIndex;
  final ValueChanged<int> onSelectStop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const preferredTileWidth = 132.0;
        final calculatedColumns = (constraints.maxWidth / preferredTileWidth)
            .floor();
        final columns = calculatedColumns.clamp(1, stops.length).toInt();
        final tileWidth = constraints.maxWidth / columns;
        final rows = <Widget>[];

        for (var start = 0; start < stops.length; start += columns) {
          final end = start + columns < stops.length
              ? start + columns
              : stops.length;
          final indexes = List<int>.generate(
            end - start,
            (offset) => start + offset,
          );
          final isOddRow = rows.length.isEven;
          final rowIndexes = isOddRow ? indexes : indexes.reversed;

          rows.add(
            Row(
              mainAxisAlignment: isOddRow
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.end,
              children: [
                for (final index in rowIndexes)
                  SizedBox(
                    width: tileWidth,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: _ScheduleStopTile(
                        stop: stops[index],
                        index: index,
                        isFirstStop: index == 0,
                        isLastStop: index == stops.length - 1,
                        isDeparture: index == departureStopIndex,
                        isArrival: index == arrivalStopIndex,
                        isBetween:
                            departureStopIndex != null &&
                            arrivalStopIndex != null &&
                            index > departureStopIndex! &&
                            index < arrivalStopIndex!,
                        onTap: () => onSelectStop(index),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        return Column(children: rows);
      },
    );
  }
}

class _ScheduleStopTile extends StatelessWidget {
  const _ScheduleStopTile({
    required this.stop,
    required this.index,
    required this.isFirstStop,
    required this.isLastStop,
    required this.isDeparture,
    required this.isArrival,
    required this.isBetween,
    required this.onTap,
  });

  final TrainScheduleStop stop;
  final int index;
  final bool isFirstStop;
  final bool isLastStop;
  final bool isDeparture;
  final bool isArrival;
  final bool isBetween;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = isDeparture || isArrival;
    final backgroundColor = selected
        ? colors.primaryContainer
        : isBetween
        ? colors.secondaryContainer
        : colors.surfaceContainerHighest;
    final foregroundColor = selected
        ? colors.onPrimaryContainer
        : isBetween
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: backgroundColor),
      duration: m3MotionDurationShort,
      curve: Curves.easeOutCubic,
      builder: (context, animatedColor, child) {
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Ink(
            height: 86,
            decoration: BoxDecoration(
              color: animatedColor ?? backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? colors.primary : colors.outlineVariant,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stop.stationName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: foregroundColor,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${index + 1}',
                        style: TextStyle(color: foregroundColor),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (!isFirstStop)
                    Text(
                      '到 ${stop.arriveTime}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: foregroundColor),
                    ),
                  if (!isLastStop)
                    Text(
                      '发 ${stop.startTime}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: foregroundColor),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
