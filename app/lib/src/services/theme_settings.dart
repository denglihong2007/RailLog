import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference { system, light, dark }

class ThemeSeedOption {
  const ThemeSeedOption({required this.label, required this.color});

  final String label;
  final Color color;
}

const themeSeedOptions = [
  ThemeSeedOption(label: '湖蓝', color: Color(0xFF1565C0)),
  ThemeSeedOption(label: '翡翠', color: Color(0xFF00897B)),
  ThemeSeedOption(label: '松绿', color: Color(0xFF2E7D32)),
  ThemeSeedOption(label: '石榴', color: Color(0xFFC62828)),
  ThemeSeedOption(label: '珊瑚', color: Color(0xFFE64A19)),
  ThemeSeedOption(label: '金黄', color: Color(0xFFF9A825)),
  ThemeSeedOption(label: '紫罗兰', color: Color(0xFF7B1FA2)),
  ThemeSeedOption(label: '靛青', color: Color(0xFF3949AB)),
];

class ThemeSettings extends ChangeNotifier {
  ThemeSettings._();

  static final ThemeSettings instance = ThemeSettings._();

  static const _modeKey = 'theme_mode';
  static const _systemColorKey = 'theme_use_system_color';
  static const _seedColorKey = 'theme_seed_color';

  SharedPreferences? _preferences;
  AppThemePreference _preference = AppThemePreference.system;
  bool _useSystemColor = true;
  Color _seedColor = themeSeedOptions.first.color;

  AppThemePreference get preference => _preference;
  bool get useSystemColor => _useSystemColor;
  Color get seedColor => _seedColor;

  ThemeMode get themeMode => switch (_preference) {
    AppThemePreference.system => ThemeMode.system,
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };

  String get seedColorLabel =>
      themeSeedOptions
          .where((option) => option.color.toARGB32() == _seedColor.toARGB32())
          .map((option) => option.label)
          .firstOrNull ??
      '自定义';

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    _preferences = preferences;
    _preference = AppThemePreference.values.firstWhere(
      (value) => value.name == preferences.getString(_modeKey),
      orElse: () => AppThemePreference.system,
    );
    _useSystemColor = preferences.getBool(_systemColorKey) ?? true;
    final storedColor = preferences.getInt(_seedColorKey);
    if (storedColor != null) _seedColor = Color(storedColor);
  }

  void setPreference(AppThemePreference value) {
    if (_preference == value) return;
    _preference = value;
    notifyListeners();
    unawaited(_preferences?.setString(_modeKey, value.name));
  }

  void setUseSystemColor(bool value) {
    if (_useSystemColor == value) return;
    _useSystemColor = value;
    notifyListeners();
    unawaited(_preferences?.setBool(_systemColorKey, value));
  }

  void setSeedColor(Color value) {
    if (_seedColor.toARGB32() == value.toARGB32()) return;
    _seedColor = value;
    notifyListeners();
    unawaited(_preferences?.setInt(_seedColorKey, value.toARGB32()));
  }
}
