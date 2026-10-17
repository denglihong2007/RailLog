import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:raillog/src/journal/journal_pager.dart';
import 'package:raillog/src/journal/journal_pdf_renderer.dart';
import 'package:raillog/src/journal/journal_style.dart';

import 'support/journal_fixtures.dart';

/// 字体靠注入，所以这里完全不碰 rootBundle / widget binding，
/// 普通 test() 就能跑出真实 PDF 字节。
JournalFonts get _fonts => JournalFonts(base: pw.Font.helvetica());

Future<Uint8List> _render(
  List<List<JournalBandData>> pages,
  JournalStyle style,
) => JournalPdfRenderer.render(
  pages: pages,
  style: style,
  fonts: _fonts,
  documentTitle: 'RailLog Journal',
);

void expectValidPdf(Uint8List bytes, {String? reason}) {
  expect(bytes.length, greaterThan(1000), reason: reason);
  expect(
    String.fromCharCodes(bytes.take(5)),
    '%PDF-',
    reason: reason,
  );
}

void main() {
  for (final style in JournalStyle.values) {
    group('JournalPdfRenderer · ${style.name}', () {
      test('三趟行程排成一页', () async {
        final pages = JournalPager.paginate([
          for (var i = 0; i < 3; i++) asciiEntry(trainLabel: 'T$i'),
        ]);
        expect(pages, hasLength(1));
        expectValidPdf(await _render(pages, style), reason: '三趟一页');
      });

      test('四趟排成两页，末页其余两格是空白模板位', () async {
        final pages = JournalPager.paginate([
          for (var i = 0; i < 4; i++) asciiEntry(trainLabel: 'T$i'),
        ]);
        expect(pages, hasLength(2));
        expect(pages[1].skip(1).every((band) => band.isEmpty), isTrue);
        final bytes = await _render(pages, style);
        expectValidPdf(bytes, reason: '末页补位');
      });

      test('空白模板两页', () async {
        expectValidPdf(
          await _render(JournalPager.blankPages(2), style),
          reason: '空白模板',
        );
      });

      test('字段缺失也不能炸', () async {
        final pages = JournalPager.paginate([
          asciiEntry(
            trainLabel: '',
            arriveLabel: '--:--',
            durationLabel: '',
            mileageLabel: '-',
            priceLabel: '-',
            seatLabel: '-',
            rollingStockLabel: '',
            routeLabel: '',
            notesLabel: '',
            kindLabel: 'Bus',
            isRailTrip: false,
          ),
        ]);
        expectValidPdf(await _render(pages, style), reason: '全空字段');
      });

      test('超长不可断词不会把版面撑爆', () async {
        // dart_pdf 只在空格处断行，长串是不可断 token。这正是中文站名
        // 会遇到的处境，必须在渲染阶段就确认它不会抛。
        final pages = JournalPager.paginate([
          asciiEntry(
            trainLabel: 'X' * 60,
            fromStation: 'Y' * 80,
            toStation: 'Z' * 80,
            rollingStockLabel: 'R' * 60,
            seatLabel: 'S' * 60,
            routeLabel: 'via ${'W' * 80}',
            notesLabel: 'N' * 120,
          ),
        ]);
        expectValidPdf(await _render(pages, style), reason: '超长文本');
      });

      test('备注非空时多印一行', () async {
        final withNotes = await _render(
          JournalPager.paginate([asciiEntry(notesLabel: 'a note')]),
          style,
        );
        final without = await _render(
          JournalPager.paginate([asciiEntry()]),
          style,
        );
        expectValidPdf(withNotes);
        expect(withNotes.length, isNot(without.length));
      });
    });
  }

  test('两种风格产出不同的字节（字体与装饰确实分叉了）', () async {
    final pages = JournalPager.paginate([asciiEntry()]);
    final retro = await _render(pages, JournalStyle.retro);
    final grid = await _render(pages, JournalStyle.grid);
    expectValidPdf(retro);
    expectValidPdf(grid);
    expect(retro, isNot(equals(grid)));
  });

  test('页数越多字节越多', () async {
    final one = await _render(JournalPager.blankPages(1), JournalStyle.grid);
    final three = await _render(JournalPager.blankPages(3), JournalStyle.grid);
    expect(three.length, greaterThan(one.length));
  });
}
