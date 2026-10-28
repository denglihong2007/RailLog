import 'package:shared_preferences/shared_preferences.dart';

/// 环形统计图的显示偏好。
abstract final class PieChartSettings {
  static const _minPercentKey = 'pie_chart_min_percent';

  /// 低于该占比的项目合并为「其他」；0 表示全部单列。
  static const defaultMinPercent = 2;

  static const minPercentOptions = <int>[0, 1, 2, 5, 10];

  static Future<int> loadMinPercent() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final value = preferences.getInt(_minPercentKey);
      return value != null && minPercentOptions.contains(value)
          ? value
          : defaultMinPercent;
    } on Exception {
      return defaultMinPercent;
    }
  }

  static Future<void> saveMinPercent(int value) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(_minPercentKey, value);
    } on Exception {
      // 只是显示偏好，写入失败时保持本次会话的设置即可。
    }
  }
}
