@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:raillog/src/journal/journal_pager.dart';
import 'package:raillog/src/journal/journal_pdf_renderer.dart';
import 'package:raillog/src/journal/journal_style.dart';

import 'support/journal_fixtures.dart';

/// 直接读盘，不走 rootBundle。
///
/// rootBundle 在 widget 测试里会静默挂死；`flutter test` 的工作目录是包根，
/// 所以这里用 dart:io 读同一份文件，一样能守住「这两份子集 dart_pdf 解析得了」。
Future<pw.Font> loadFont(String assetPath) async {
  final bytes = await File(assetPath).readAsBytes();
  return pw.Font.ttf(ByteData.sublistView(bytes));
}

void main() {
  for (final style in JournalStyle.values) {
    test('${style.fontAsset} 是 dart_pdf 认得的 glyf 轮廓 TTF', () async {
      final font = await loadFont(style.fontAsset);
      expect(font, isNotNull);
    });

    test('${style.name} 用真字体能排出中文 PDF', () async {
      final bytes = await JournalPdfRenderer.render(
        pages: JournalPager.paginate([
          asciiEntry(
            // 换成真中文，验证子集里这些字形确实在。
            trainLabel: 'G1',
            fromStation: '北京南',
            toStation: '上海虹桥',
            seatLabel: '二等座 · 05车12F',
            priceLabel: '¥662.00',
            routeLabel: '经 京沪高速铁路',
            notesLabel: '第一次坐复兴号，天气很好。',
            kindLabel: '铁路行程',
          ),
        ]),
        style: style,
        fonts: JournalFonts(base: await loadFont(style.fontAsset)),
        documentTitle: 'RailLog 行程手账',
      );

      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('${style.name} 的空白模板也排得出来', () async {
      final bytes = await JournalPdfRenderer.render(
        pages: JournalPager.blankPages(1),
        style: style,
        fonts: JournalFonts(base: await loadFont(style.fontAsset)),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  }

  test('两个子集文件都不超过 5MB', () async {
    for (final style in JournalStyle.values) {
      final length = await File(style.fontAsset).length();
      expect(
        length,
        lessThan(5 * 1024 * 1024),
        reason: '${style.fontAsset} 太大，安装包会明显变沉',
      );
    }
  });
}
