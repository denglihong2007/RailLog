import 'package:flutter/foundation.dart';
import 'package:raillog/src/services/db_helper.dart';

enum TicketDisplayStyle { red, blue, md3 }

class TicketGeneratorSettings extends ChangeNotifier {
  TicketGeneratorSettings._();

  static final TicketGeneratorSettings instance = TicketGeneratorSettings._();
  static const _styleKey = 'ticket_display_style';
  static const _passengerKey = 'ticket_default_passenger';
  static const _maskedIdKey = 'ticket_masked_id';
  static const _serialPrefixKey = 'ticket_serial_prefix';
  static const _showNewAirConditionedKey = 'ticket_show_new_air_conditioned';

  TicketDisplayStyle _displayStyle = TicketDisplayStyle.red;
  String _passenger = '川建国';
  String _maskedId = '1101021946****001X';
  String _serialPrefix = '4541331001';
  bool _showNewAirConditioned = false;

  TicketDisplayStyle get displayStyle => _displayStyle;
  String get passenger => _passenger;
  String get maskedId => _maskedId;
  String get serialPrefix => _serialPrefix;
  bool get showNewAirConditioned => _showNewAirConditioned;

  String get requestStyle => switch (_displayStyle) {
    TicketDisplayStyle.red => 'red',
    TicketDisplayStyle.blue => 'blue',
    TicketDisplayStyle.md3 => 'md3',
  };

  String get cacheKey =>
      '${_displayStyle.name}|$_passenger|$_maskedId|$_serialPrefix|$_showNewAirConditioned';

  Future<void> initialize() async {
    final storedStyle = await DbHelper.instance.getSetting(_styleKey);
    _displayStyle = TicketDisplayStyle.values.firstWhere(
      (value) => value.name == storedStyle,
      orElse: () => TicketDisplayStyle.red,
    );
    _passenger = await DbHelper.instance.getSetting(_passengerKey) ?? '川建国';
    _maskedId =
        await DbHelper.instance.getSetting(_maskedIdKey) ??
        '1101021946****001X';
    final storedSerialPrefix = await DbHelper.instance.getSetting(
      _serialPrefixKey,
    );
    _serialPrefix = _normalizeSerialPrefix(storedSerialPrefix);
    if (storedSerialPrefix != null && storedSerialPrefix != _serialPrefix) {
      await DbHelper.instance.setSetting(_serialPrefixKey, _serialPrefix);
    }
    _showNewAirConditioned =
        await DbHelper.instance.getSetting(_showNewAirConditionedKey) == 'true';
    notifyListeners();
  }

  Future<void> setDisplayStyle(TicketDisplayStyle value) async {
    if (_displayStyle == value) return;
    _displayStyle = value;
    notifyListeners();
    await DbHelper.instance.setSetting(_styleKey, value.name);
  }

  Future<void> setPassenger(String value) async {
    final normalized = value.trim();
    if (normalized.length > 30 || _passenger == normalized) {
      return;
    }
    _passenger = normalized;
    notifyListeners();
    await DbHelper.instance.setSetting(_passengerKey, normalized);
  }

  Future<void> setMaskedId(String value) async {
    final normalized = value.trim();
    if (normalized.length > 30 || _maskedId == normalized) {
      return;
    }
    _maskedId = normalized;
    notifyListeners();
    await DbHelper.instance.setSetting(_maskedIdKey, normalized);
  }

  Future<void> setSerialPrefix(String value) async {
    final normalized = value.trim();
    if (!RegExp(r'^\d{10}$').hasMatch(normalized) ||
        _serialPrefix == normalized) {
      return;
    }
    _serialPrefix = normalized;
    notifyListeners();
    await DbHelper.instance.setSetting(_serialPrefixKey, normalized);
  }

  static String _normalizeSerialPrefix(String? value) {
    final normalized = value?.trim() ?? '';
    if (RegExp(r'^\d{10}$').hasMatch(normalized)) return normalized;
    if (RegExp(r'^\d{14}$').hasMatch(normalized)) {
      return normalized.substring(0, 10);
    }
    return '4541331001';
  }

  Future<void> setShowNewAirConditioned(bool value) async {
    if (_showNewAirConditioned == value) return;
    _showNewAirConditioned = value;
    notifyListeners();
    await DbHelper.instance.setSetting(
      _showNewAirConditionedKey,
      value.toString(),
    );
  }
}
