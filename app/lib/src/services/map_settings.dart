import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 底图显示层级。高德 JS API 没有现成的「详细/一般/简略」档位，只有两个旋钮：
/// `features`（底图要素）和 `showLabel`（文字标注）。档位在这里一次性定义好两者，
/// 免得 JS 那侧再拼一遍映射。
///
/// 三档依次少掉：3D 建筑 → POI 图标与文字标注。
///
/// 另有一个不属于档位的开关：`isHotspot`（在 buildAmapHtml 里写死关闭），它管的是
/// 底图地名/POI 会不会悬停高亮、显得可以点。
enum MapDetailLevel {
  detailed(
    label: '详细',
    features: ['bg', 'point', 'road', 'building'],
    showLabel: true,
  ),
  normal(label: '一般', features: ['bg', 'point', 'road'], showLabel: true),
  simplified(label: '简略', features: ['bg', 'road'], showLabel: false);

  const MapDetailLevel({
    required this.label,
    required this.features,
    required this.showLabel,
  });

  final String label;

  /// 高德支持的四种底图要素：bg 陆水背景、point 兴趣点、road 道路、building 建筑。
  final List<String> features;

  final bool showLabel;
}

class MapSettings extends ChangeNotifier {
  MapSettings._();

  static final MapSettings instance = MapSettings._();

  static const _detailLevelKey = 'map_detail_level';

  SharedPreferences? _preferences;
  MapDetailLevel _detailLevel = MapDetailLevel.normal;

  MapDetailLevel get detailLevel => _detailLevel;

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    _preferences = preferences;
    _detailLevel = MapDetailLevel.values.firstWhere(
      (value) => value.name == preferences.getString(_detailLevelKey),
      orElse: () => MapDetailLevel.normal,
    );
  }

  void setDetailLevel(MapDetailLevel value) {
    if (_detailLevel == value) return;
    _detailLevel = value;
    notifyListeners();
    unawaited(_preferences?.setString(_detailLevelKey, value.name));
  }
}
