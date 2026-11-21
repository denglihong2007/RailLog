import 'package:material_ui/material_ui.dart';
import 'package:raillog/src/models/via_route_segment.dart';

/// 一条经由线路在简图与地图上的统一配色与里程。
///
/// 两种视图共用同一份样式，地图上的折线颜色才会和简图里的轨道颜色一致。
class ViaRouteLineStyle {
  const ViaRouteLineStyle({
    required this.route,
    required this.color,
    required this.mileageKm,
  });

  /// 展示用线路名（空线路名归一为「手动线路」）。
  final String route;
  final Color color;

  /// 本次行程在这条线路上走过的总里程；0 表示行程里没有记录。
  final double mileageKm;
}

const _routeColorSeeds = [
  Color(0xFF005AC1),
  Color(0xFFC43E00),
  Color(0xFF006B5E),
  Color(0xFF8E24AA),
  Color(0xFF7A5900),
  Color(0xFFB0005A),
];

List<Color> viaRoutePalette(ColorScheme colors) => [
  for (final seed in _routeColorSeeds)
    ColorScheme.fromSeed(
      seedColor: seed,
      brightness: colors.brightness,
    ).primary,
];

String viaRouteLabel(String routeName) {
  final value = routeName.trim();
  return value.isEmpty ? '手动线路' : value;
}

/// 按线路原名分配颜色；同一条线路的多段里程累加到一起。
///
/// 线路名只按行程里记录的原名比较，不做「铁路/线」「客专」之类的写法归一：
/// 兰新线 与 兰新客专线、胶济线 与 胶济客专线 是并行的两条线路，归一后图例里
/// 只剩先出现的那条名字，两条线还会被涂成同一种颜色。
List<ViaRouteLineStyle> buildViaRouteLineStyles(
  Iterable<ViaRouteSegment> segments,
  ColorScheme colors,
) {
  final palette = viaRoutePalette(colors);
  final styles = <String, _MutableLineStyle>{};
  for (final segment in segments) {
    final route = viaRouteLabel(segment.routeName);
    final style = styles.putIfAbsent(
      route,
      () => _MutableLineStyle(route, palette[styles.length % palette.length]),
    );
    if (segment.mileageKm > 0) style.mileageKm += segment.mileageKm;
  }
  return [for (final style in styles.values) style.freeze()];
}

Color? findViaRouteColor(String? lineName, List<ViaRouteLineStyle> styles) {
  final value = lineName?.trim() ?? '';
  if (value.isEmpty) return null;
  for (final style in styles) {
    if (style.route == value) return style.color;
  }
  return null;
}

class _MutableLineStyle {
  _MutableLineStyle(this.route, this.color);

  final String route;
  final Color color;
  double mileageKm = 0;

  ViaRouteLineStyle freeze() =>
      ViaRouteLineStyle(route: route, color: color, mileageKm: mileageKm);
}
