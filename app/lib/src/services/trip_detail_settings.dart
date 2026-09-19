import 'package:flutter/foundation.dart';
import 'package:raillog/src/services/db_helper.dart';

class TripDetailSettings extends ChangeNotifier {
  TripDetailSettings._();

  static final TripDetailSettings instance = TripDetailSettings._();
  static const _expandRouteStationsKey = 'trip_expand_route_stations';

  bool _expandRouteStationsByDefault = true;

  /// 打开行程详情时是否默认展开经由线路的中间车站。
  bool get expandRouteStationsByDefault => _expandRouteStationsByDefault;

  Future<void> initialize() async {
    final stored = await DbHelper.instance.getSetting(_expandRouteStationsKey);
    _expandRouteStationsByDefault = stored != 'false';
    notifyListeners();
  }

  Future<void> setExpandRouteStationsByDefault(bool value) async {
    if (_expandRouteStationsByDefault == value) return;
    _expandRouteStationsByDefault = value;
    notifyListeners();
    await DbHelper.instance.setSetting(
      _expandRouteStationsKey,
      value.toString(),
    );
  }
}
