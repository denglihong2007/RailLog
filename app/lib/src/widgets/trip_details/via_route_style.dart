import 'package:flutter/material.dart';
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

/// 按线路首次出现的顺序分配颜色；同一条线路的多段里程累加到一起。
List<ViaRouteLineStyle> buildViaRouteLineStyles(
  Iterable<ViaRouteSegment> segments,
  ColorScheme colors,
) {
  final palette = viaRoutePalette(colors);
  final styles = <String, _MutableLineStyle>{};
  for (final segment in segments) {
    final route = viaRouteLabel(segment.routeName);
    // 同一条线可能在不同段里写成「京沪高速铁路」和「京沪高速线」，归一后共用
    // 一种颜色，里程也合并计算。
    final key = _styleKey(route);
    final style = styles.putIfAbsent(
      key,
      () => _MutableLineStyle(route, palette[styles.length % palette.length]),
    );
    if (segment.mileageKm > 0) style.mileageKm += segment.mileageKm;
  }
  return [for (final style in styles.values) style.freeze()];
}

String _styleKey(String route) {
  final key = viaRouteLineKey(route);
  return key.isEmpty ? route : key;
}

/// 地图折线用的是线路库里的规范名（京沪高速线），简图用的是行程里记录的名字
/// （京沪高速铁路）。去掉线别后缀后再比，才认得出是同一条线路。
String viaRouteLineKey(String value) {
  var key = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  // 逐个比后缀而不是用正则替换：正则从前往后扫描，会在「京沪高速铁路」里先命中
  // 中间的「高速铁路」，留下「京沪」；这里要的是整段后缀，得到「京沪高速」。
  for (final suffix in const ['客运专线', '客专线', '铁路', '线']) {
    if (key.endsWith(suffix)) {
      key = key.substring(0, key.length - suffix.length);
      break;
    }
  }
  return key;
}

Color? findViaRouteColor(String? lineName, List<ViaRouteLineStyle> styles) {
  final value = lineName?.trim() ?? '';
  if (value.isEmpty) return null;
  for (final style in styles) {
    if (style.route == value) return style.color;
  }
  final key = _styleKey(value);
  for (final style in styles) {
    if (_styleKey(style.route) == key) return style.color;
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
