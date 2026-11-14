import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:raillog/src/models/journey_stations.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/services/map_settings.dart';
import 'package:raillog/src/services/rail_track_service.dart';
import 'package:raillog/src/services/route_service.dart';
import 'package:raillog/src/services/trip_map_service.dart';
import 'package:raillog/src/widgets/trip_details/via_route_style.dart';
import 'package:raillog/src/widgets/trip_map_webview.dart';

/// 行程详情里的地图视图。
///
/// 只画当前这一趟行程：每一段折线使用 [lineStyles] 里同一条线路的颜色，
/// 与简图模式保持一致。
class TripViaRouteMap extends StatefulWidget {
  const TripViaRouteMap({
    super.key,
    required this.trip,
    required this.lineStyles,
  });

  final TripRecord trip;
  final List<ViaRouteLineStyle> lineStyles;

  @override
  State<TripViaRouteMap> createState() => _TripViaRouteMapState();
}

class _TripViaRouteMapState extends State<TripViaRouteMap> {
  late Future<TripMapData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _load();
  }

  @override
  void didUpdateWidget(covariant TripViaRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trip.clientId != widget.trip.clientId ||
        oldWidget.trip.updatedAt != widget.trip.updatedAt) {
      _dataFuture = _load();
    }
  }

  Future<TripMapData> _load() async {
    final results = await Future.wait([
      RouteService.resolveTripStations([widget.trip]),
      RailTrackService.loadData().catchError(
        (_) => const RailTrackData.empty(),
      ),
      TripMapService.loadCoordinatesCsv(),
    ]);
    final railData = results[1] as RailTrackData;
    // 与全量地图一致：管线车站表优先，coordinates.csv 只补缺。
    final coordinates = StationCoordinateIndex.fromSources(
      railData.stations.all,
      results[2] as String,
    );
    return TripMapService.buildData(
      [widget.trip],
      coordinates,
      journeyStations: results[0] as Map<String, JourneyStations>,
      tracks: railData.tracks,
      // 一趟车可能跨几条线；按线路拆开才画得出各自的颜色。
      mergeAcrossLines: false,
    );
  }

  Future<void> _retry() async {
    final future = _load();
    setState(() => _dataFuture = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = MediaQuery.sizeOf(context);
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : viewport.width;
        final height = math.min(
          math.min(640.0, viewport.height * 0.7),
          math.max(420.0, width * 0.9),
        );
        return SizedBox(
          height: height,
          child: FutureBuilder<TripMapData>(
            future: _dataFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _MapStatus(
                  icon: Icons.error_outline,
                  message: '读取行程地图失败',
                  onRetry: _retry,
                );
              }
              if (!snapshot.hasData) {
                return const _MapStatus(message: '正在生成铁路行程轨迹');
              }
              final data = snapshot.data!;
              if (data.routes.isEmpty) {
                return _MapStatus(
                  icon: Icons.location_off_outlined,
                  message: data.missingViaRouteCount > 0
                      ? '这条行程缺少经由线路，无法绘制'
                      : '这条行程的车站暂时无法定位',
                );
              }
              // 线路名对不上（例如整条经由都没记线路名）时退回第一条线路的
              // 颜色：地图至少和简图的第一条线同色，不会另起一种配色。
              final fallbackColor = widget.lineStyles.isNotEmpty
                  ? widget.lineStyles.first.color
                  : theme.colorScheme.primary;
              final routes = [
                for (final route in data.routes)
                  route.withColor(
                    _cssColor(
                      findViaRouteColor(route.lineName, widget.lineStyles) ??
                          fallbackColor,
                    ),
                  ),
              ];
              return TripMapWebView(
                backgroundColor: theme.colorScheme.surface,
                // 地图嵌在可滚动的详情页里，交给 WebView 自己处理拖动与点击。
                absorbGestures: true,
                html: buildAmapHtml(
                  routes,
                  darkMode: theme.brightness == Brightness.dark,
                  backgroundColor: _cssColor(theme.colorScheme.surface),
                  showStationMarkers: true,
                  endpoints: data.endpoints,
                  detailLevel: MapSettings.instance.detailLevel,
                  colorByRoute: true,
                  // 已经在这趟行程的详情里，弹窗里的车次再点一次没有去处。
                  tripLinks: false,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _MapStatus extends StatelessWidget {
  const _MapStatus({required this.message, this.icon, this.onRetry});

  final String message;
  final IconData? icon;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon == null)
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          else
            Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ],
      ),
    ),
  );
}

String _cssColor(Color color) {
  final value = color.toARGB32().toRadixString(16).padLeft(8, '0');
  return '#${value.substring(2)}';
}
