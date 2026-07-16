import 'package:flutter/material.dart';
import 'package:raillog/src/models/via_route_segment.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

typedef RouteDistanceResolver =
    Future<double?> Function(
      String routeName,
      String fromStation,
      String toStation,
    );
typedef RouteStationsResolver = Future<List<String>> Function(String routeName);

class RouteSegmentsEditor extends StatefulWidget {
  const RouteSegmentsEditor({
    super.key,
    required this.startStation,
    required this.endStation,
    required this.routeNames,
    required this.segments,
    required this.isLoading,
    required this.isRecognizing,
    required this.revision,
    required this.onRecognizeShortestPath,
    required this.resolveDistance,
    required this.resolveStations,
    required this.onChanged,
    this.usedShortestPath = false,
    this.unresolvedSections = const [],
    this.lookupFailed = false,
  });

  final String startStation;
  final String endStation;
  final List<String> routeNames;
  final List<ViaRouteSegment> segments;
  final bool isLoading;
  final bool isRecognizing;
  final int revision;
  final VoidCallback onRecognizeShortestPath;
  final RouteDistanceResolver resolveDistance;
  final RouteStationsResolver resolveStations;
  final ValueChanged<List<ViaRouteSegment>> onChanged;
  final bool usedShortestPath;
  final List<String> unresolvedSections;
  final bool lookupFailed;

  @override
  State<RouteSegmentsEditor> createState() => _RouteSegmentsEditorState();
}

class _RouteSegmentsEditorState extends State<RouteSegmentsEditor> {
  late List<Key> _segmentKeys;

  String get startStation => widget.startStation;
  String get endStation => widget.endStation;
  List<String> get routeNames => widget.routeNames;
  List<ViaRouteSegment> get segments => widget.segments;
  bool get isLoading => widget.isLoading;
  bool get isRecognizing => widget.isRecognizing;
  VoidCallback get onRecognizeShortestPath => widget.onRecognizeShortestPath;
  RouteDistanceResolver get resolveDistance => widget.resolveDistance;
  RouteStationsResolver get resolveStations => widget.resolveStations;
  ValueChanged<List<ViaRouteSegment>> get onChanged => widget.onChanged;
  bool get usedShortestPath => widget.usedShortestPath;
  List<String> get unresolvedSections => widget.unresolvedSections;
  bool get lookupFailed => widget.lookupFailed;

  @override
  void initState() {
    super.initState();
    _segmentKeys = List.generate(segments.length, (_) => UniqueKey());
  }

  @override
  void didUpdateWidget(covariant RouteSegmentsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      _segmentKeys = List.generate(segments.length, (_) => UniqueKey());
      return;
    }
    while (_segmentKeys.length < segments.length) {
      _segmentKeys.add(UniqueKey());
    }
    if (_segmentKeys.length > segments.length) {
      _segmentKeys.removeRange(segments.length, _segmentKeys.length);
    }
  }

  bool get _hasEndpoints =>
      startStation.trim().isNotEmpty && endStation.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EditorHeader(
          isLoading: isLoading,
          isRecognizing: isRecognizing,
          canEdit: _hasEndpoints,
          onAdd: _addSegment,
          onRecognize: onRecognizeShortestPath,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 16, color: colors.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '自动识别可能不准确，建议结合路路通时刻表的经由信息修改',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedSize(
          duration: m3MotionDuration,
          curve: Curves.easeOutCubic,
          child: M3FadeThroughSwitcher(
            alignment: Alignment.topCenter,
            child: _buildSegments(context),
          ),
        ),
        if (!isLoading && usedShortestPath && segments.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '当前经由包含最短路径识别结果',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.tertiary),
          ),
        ],
        if (!isLoading && unresolvedSections.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '未识别：${unresolvedSections.join('、')}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.error),
          ),
        ],
      ],
    );
  }

  Widget _buildSegments(BuildContext context) {
    if (isLoading) {
      return const LinearProgressIndicator(key: ValueKey('routes-loading'));
    }
    if (segments.isEmpty) {
      return Text(
        lookupFailed ? '线路数据库读取失败' : '尚未添加经由线路',
        key: const ValueKey('routes-empty'),
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return Column(
      key: const ValueKey('routes-list'),
      children: [
        for (var index = 0; index < segments.length; index++) ...[
          if (index > 0) const SizedBox(height: 10),
          _SegmentEditor(
            key: _segmentKeys[index],
            index: index,
            isLast: index == segments.length - 1,
            segment: segments[index],
            routeNames: routeNames,
            fixedEndStation: endStation,
            onChanged: (segment) => _updateSegment(index, segment),
            onRemove: () => _removeSegment(index),
            resolveDistance: resolveDistance,
            resolveStations: resolveStations,
          ),
        ],
      ],
    );
  }

  void _addSegment() {
    final updated = [...segments];
    _segmentKeys.add(UniqueKey());
    updated.add(
      ViaRouteSegment(
        routeName: '',
        fromStation: updated.isEmpty ? startStation : updated.last.toStation,
        toStation: endStation,
      ),
    );
    onChanged(_normalize(updated));
  }

  void _removeSegment(int index) {
    final updated = [...segments]..removeAt(index);
    _segmentKeys.removeAt(index);
    onChanged(_normalize(updated));
  }

  void _updateSegment(int index, ViaRouteSegment segment) {
    final updated = [...segments];
    updated[index] = segment;
    onChanged(_normalize(updated));
  }

  List<ViaRouteSegment> _normalize(List<ViaRouteSegment> source) {
    return normalizeViaRouteSegments(
      source,
      startStation: startStation,
      endStation: endStation,
    );
  }
}

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.isLoading,
    required this.isRecognizing,
    required this.canEdit,
    required this.onAdd,
    required this.onRecognize,
  });

  final bool isLoading;
  final bool isRecognizing;
  final bool canEdit;
  final VoidCallback onAdd;
  final VoidCallback onRecognize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alt_route_outlined, size: 18, color: colors.primary),
            const SizedBox(width: 8),
            Text('经由线路', style: Theme.of(context).textTheme.titleSmall),
          ],
        );
        final actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '添加线路',
              onPressed: isLoading || !canEdit ? null : onAdd,
              icon: const Icon(Icons.add),
            ),
            const SizedBox(width: 4),
            FilledButton.tonalIcon(
              onPressed: isLoading || isRecognizing || !canEdit
                  ? null
                  : onRecognize,
              icon: isRecognizing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.route_outlined),
              label: const Text('识别最短路径'),
            ),
          ],
        );
        if (constraints.maxWidth < 460) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        }
        return Row(children: [title, const Spacer(), actions]);
      },
    );
  }
}

class _SegmentEditor extends StatefulWidget {
  const _SegmentEditor({
    super.key,
    required this.index,
    required this.isLast,
    required this.segment,
    required this.routeNames,
    required this.fixedEndStation,
    required this.onChanged,
    required this.onRemove,
    required this.resolveDistance,
    required this.resolveStations,
  });

  final int index;
  final bool isLast;
  final ViaRouteSegment segment;
  final List<String> routeNames;
  final String fixedEndStation;
  final ValueChanged<ViaRouteSegment> onChanged;
  final VoidCallback onRemove;
  final RouteDistanceResolver resolveDistance;
  final RouteStationsResolver resolveStations;

  @override
  State<_SegmentEditor> createState() => _SegmentEditorState();
}

class _SegmentEditorState extends State<_SegmentEditor> {
  List<String> _routeStations = const [];
  String? _distanceError;
  bool _isLoadingStations = false;
  bool _isCalculatingDistance = false;
  int _stationRequestId = 0;
  int _distanceRequestId = 0;

  @override
  void initState() {
    super.initState();
    if (widget.segment.routeName.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _loadRouteStations(widget.segment.routeName);
        if (mounted) await _recalculateDistance();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _SegmentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final endpointsChanged =
        oldWidget.segment.fromStation != widget.segment.fromStation ||
        oldWidget.segment.toStation != widget.segment.toStation ||
        oldWidget.fixedEndStation != widget.fixedEndStation ||
        oldWidget.isLast != widget.isLast;
    if (endpointsChanged && widget.segment.routeName.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _recalculateDistance();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '第 ${widget.index + 1} 段',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const Spacer(),
                IconButton(
                  tooltip: '删除该段',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            _SearchPickerFormField(
              key: ValueKey('route-${widget.segment.routeName}'),
              label: '线路',
              value: widget.segment.routeName,
              options: widget.routeNames,
              icon: Icons.route_outlined,
              onSelected: _selectRoute,
              validator: (value) =>
                  !widget.routeNames.contains(value) ? '请选择数据库中的线路' : null,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _StationSummary(
                    label: '起点',
                    station: widget.segment.fromStation,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.arrow_forward,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: widget.isLast
                      ? _StationSummary(
                          label: '终点',
                          station: widget.fixedEndStation,
                          alignEnd: true,
                        )
                      : _SearchPickerFormField(
                          key: ValueKey(
                            'station-${widget.segment.routeName}-${widget.segment.toStation}',
                          ),
                          label: '换线站',
                          value: widget.segment.toStation,
                          options: _routeStations,
                          isLoading: _isLoadingStations,
                          onSelected: _selectEndStation,
                          validator: (value) => !_routeStations.contains(value)
                              ? '请选择当前线路车站'
                              : null,
                        ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 82,
                  child: FormField<double>(
                    validator: (_) {
                      if (_isLoadingStations || _isCalculatingDistance) {
                        return '读取中';
                      }
                      return _distanceError;
                    },
                    builder: (field) => _MileageSummary(
                      mileage: widget.segment.mileageKm,
                      isLoading: _isLoadingStations || _isCalculatingDistance,
                      errorText: field.errorText ?? _distanceError,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectRoute(String routeName) async {
    final updated = _copyWith(routeName: routeName);
    widget.onChanged(updated);
    final stations = await _loadRouteStations(routeName);
    if (!mounted) return;
    final end = widget.isLast
        ? widget.fixedEndStation
        : widget.segment.toStation;
    if (!stations.contains(end)) {
      if (!widget.isLast) {
        widget.onChanged(_copyWith(routeName: routeName, toStation: ''));
      }
      setState(() => _distanceError = '线路不包含终点');
      return;
    }
    await _recalculateDistance(routeName: routeName, toStation: end);
  }

  Future<void> _selectEndStation(String station) async {
    widget.onChanged(_copyWith(toStation: station));
    await _recalculateDistance(toStation: station);
  }

  Future<List<String>> _loadRouteStations(String routeName) async {
    final requestId = ++_stationRequestId;
    setState(() {
      _isLoadingStations = true;
      _distanceError = null;
    });
    final stations = await widget.resolveStations(routeName);
    if (!mounted || requestId != _stationRequestId) return const [];
    setState(() {
      _routeStations = stations;
      _isLoadingStations = false;
    });
    return stations;
  }

  Future<void> _recalculateDistance({
    String? routeName,
    String? toStation,
  }) async {
    final route = routeName ?? widget.segment.routeName;
    final start = widget.segment.fromStation.trim();
    final end =
        toStation ??
        (widget.isLast ? widget.fixedEndStation : widget.segment.toStation);
    if (route.isEmpty || start.isEmpty || end.isEmpty) return;

    final requestId = ++_distanceRequestId;
    setState(() {
      _isCalculatingDistance = true;
      _distanceError = null;
    });
    final distance = await widget.resolveDistance(route, start, end);
    if (!mounted || requestId != _distanceRequestId) return;
    if (distance == null) {
      setState(() {
        _isCalculatingDistance = false;
        _distanceError = '线路不连接起终点';
      });
      return;
    }
    setState(() {
      _isCalculatingDistance = false;
      _distanceError = null;
    });
    widget.onChanged(
      _copyWith(routeName: route, toStation: end, mileageKm: distance),
    );
  }

  ViaRouteSegment _copyWith({
    String? routeName,
    String? toStation,
    double? mileageKm,
  }) {
    return ViaRouteSegment(
      routeName: routeName ?? widget.segment.routeName,
      fromStation: widget.segment.fromStation,
      toStation: toStation ?? widget.segment.toStation,
      mileageKm: mileageKm ?? widget.segment.mileageKm,
    );
  }
}

class _SearchPickerFormField extends StatelessWidget {
  const _SearchPickerFormField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
    required this.validator,
    this.icon,
    this.isLoading = false,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onSelected;
  final FormFieldValidator<String> validator;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: value,
      validator: validator,
      builder: (field) {
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: isLoading || options.isEmpty
              ? null
              : () async {
                  final selected = await showModalBottomSheet<String>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (context) => _SearchPickerSheet(
                      title: label,
                      options: options,
                      selectedValue: field.value,
                    ),
                  );
                  if (selected == null) return;
                  field.didChange(selected);
                  onSelected(selected);
                },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              errorText: field.errorText,
              prefixIcon: icon == null ? null : Icon(icon),
              suffixIcon: isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Icon(Icons.search),
            ),
            child: Text(
              field.value?.isNotEmpty == true ? field.value! : '请选择',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
    );
  }
}

class _SearchPickerSheet extends StatefulWidget {
  const _SearchPickerSheet({
    required this.title,
    required this.options,
    required this.selectedValue,
  });

  final String title;
  final List<String> options;
  final String? selectedValue;

  @override
  State<_SearchPickerSheet> createState() => _SearchPickerSheetState();
}

class _SearchPickerSheetState extends State<_SearchPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = normalizedQuery.isEmpty
        ? widget.options
        : widget.options
              .where((option) => option.toLowerCase().contains(normalizedQuery))
              .toList();
    return FractionallySizedBox(
      heightFactor: 0.78,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            SearchBar(
              autoFocus: true,
              leading: const Icon(Icons.search),
              hintText: '搜索${widget.title}',
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('没有匹配项'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final option = filtered[index];
                        final selected = option == widget.selectedValue;
                        return ListTile(
                          title: Text(option),
                          trailing: selected ? const Icon(Icons.check) : null,
                          onTap: () => Navigator.of(context).pop(option),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationSummary extends StatelessWidget {
  const _StationSummary({
    required this.label,
    required this.station,
    this.alignEnd = false,
  });

  final String label;
  final String station;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          station,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _MileageSummary extends StatelessWidget {
  const _MileageSummary({
    required this.mileage,
    required this.isLoading,
    required this.errorText,
  });

  final double mileage;
  final bool isLoading;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('里程', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        if (isLoading)
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Text(
            '${_formatMileage(mileage)} km',
            maxLines: 1,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        if (errorText != null)
          Text(
            errorText!,
            maxLines: 2,
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.error),
          ),
      ],
    );
  }
}

String _formatMileage(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);
