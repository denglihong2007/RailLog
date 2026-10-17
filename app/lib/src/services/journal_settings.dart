import 'package:flutter/foundation.dart';
import 'package:raillog/src/journal/journal_style.dart';
import 'package:raillog/src/services/db_helper.dart';

/// 手账的持久偏好：版式风格，以及空白模板默认印几页。
class JournalSettings extends ChangeNotifier {
  JournalSettings._();

  static final JournalSettings instance = JournalSettings._();

  static const _styleKey = 'journal_style';
  static const _blankPagesKey = 'journal_blank_template_pages';

  /// 空白模板一次能印的页数。它是拿去打印的，误触印出一沓废纸的代价很实际，
  /// 所以只给这几个档，且默认 1 页。
  static const List<int> blankPageOptions = [1, 2, 3, 5];
  static const int defaultBlankPages = 1;

  JournalStyle _style = JournalStyle.retro;
  int _blankPages = defaultBlankPages;

  JournalStyle get style => _style;
  int get blankPages => _blankPages;

  Future<void> initialize() async {
    _style = journalStyleFromName(await DbHelper.instance.getSetting(_styleKey));
    final stored = int.tryParse(
      await DbHelper.instance.getSetting(_blankPagesKey) ?? '',
    );
    _blankPages = blankPageOptions.contains(stored)
        ? stored!
        : defaultBlankPages;
    notifyListeners();
  }

  Future<void> setStyle(JournalStyle value) async {
    if (_style == value) return;
    _style = value;
    notifyListeners();
    await DbHelper.instance.setSetting(_styleKey, value.name);
  }

  Future<void> setBlankPages(int value) async {
    if (!blankPageOptions.contains(value) || _blankPages == value) return;
    _blankPages = value;
    notifyListeners();
    await DbHelper.instance.setSetting(_blankPagesKey, '$value');
  }
}
