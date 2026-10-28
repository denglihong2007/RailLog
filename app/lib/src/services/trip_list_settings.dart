import 'package:flutter/foundation.dart';
import 'package:raillog/src/services/db_helper.dart';

/// 「全部行程」列表的显示偏好。
class TripListSettings extends ChangeNotifier {
  TripListSettings._();

  static final TripListSettings instance = TripListSettings._();
  static const _compactModeKey = 'trip_list_compact_mode';

  bool _compactMode = false;

  /// 车票卡片是否使用紧凑视图：只显示车次、日期、起讫站与票价。
  bool get compactMode => _compactMode;

  Future<void> initialize() async {
    final stored = await DbHelper.instance.getSetting(_compactModeKey);
    _compactMode = stored == 'true';
    notifyListeners();
  }

  Future<void> setCompactMode(bool value) async {
    if (_compactMode == value) return;
    _compactMode = value;
    notifyListeners();
    await DbHelper.instance.setSetting(_compactModeKey, value.toString());
  }
}
