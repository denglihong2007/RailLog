import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

import 'journal_pdf_renderer.dart';
import 'journal_style.dart';

/// 从 asset 里取手账字体。
///
/// 解析一次就缓存住 Future：`pw.Font.ttf` 会把整个 TrueType 表结构读进内存，
/// 每页重新解析一遍既慢又白占内存，而一次导出最多也就两种风格。
abstract final class JournalFontLoader {
  static final Map<JournalStyle, Future<pw.Font>> _cache = {};

  static Future<pw.Font> font(JournalStyle style) => _cache.putIfAbsent(
    style,
    () async {
      final data = await rootBundle.load(style.fontAsset);
      return pw.Font.ttf(data);
    },
  );

  /// 给渲染器用的注入体。字体解析失败时向上抛，由导出服务兜成用户能看懂的话。
  static Future<JournalFonts> fonts(JournalStyle style) async =>
      JournalFonts(base: await font(style));

  /// 测试用：清掉缓存，免得上一个用例的失败解析赖着不走。
  static void resetCache() => _cache.clear();
}
