import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/journal/journal_pager.dart';

import 'support/journal_fixtures.dart';

void main() {
  group('JournalPager.pageCount', () {
    test('没有行程就不出纸', () {
      expect(JournalPager.pageCount(0), 0);
      expect(JournalPager.pageCount(-3), 0);
    });

    test('每页三趟，向上取整', () {
      expect(JournalPager.pageCount(1), 1);
      expect(JournalPager.pageCount(2), 1);
      expect(JournalPager.pageCount(3), 1);
      expect(JournalPager.pageCount(4), 2);
      expect(JournalPager.pageCount(6), 2);
      expect(JournalPager.pageCount(7), 3);
    });
  });

  group('JournalPager.paginate', () {
    test('空列表分不出页', () {
      expect(JournalPager.paginate(const []), isEmpty);
    });

    test('每页恒为三个槽位', () {
      for (final count in [1, 2, 3, 4, 6, 7]) {
        final pages = JournalPager.paginate([
          for (var i = 0; i < count; i++) asciiEntry(trainLabel: 'T$i'),
        ]);
        expect(pages, hasLength(JournalPager.pageCount(count)));
        for (final page in pages) {
          expect(page, hasLength(3));
        }
      }
    });

    test('凑不满的末页用空白模板位垫满，不打乱顺序', () {
      final pages = JournalPager.paginate([
        for (var i = 0; i < 4; i++) asciiEntry(trainLabel: 'T$i'),
      ]);

      expect(pages, hasLength(2));
      expect(pages[0].map((band) => band.entry?.trainLabel), ['T0', 'T1', 'T2']);
      expect(pages[1][0].entry?.trainLabel, 'T3');

      for (final filler in pages[1].skip(1)) {
        expect(filler.isEmpty, isTrue);
        // 空余格位与空白模板同版式，可以直接手写补记。
        expect(filler.showCaptions, isTrue);
      }
      // 与 blankPages 产出的槽位完全一致。
      expect(
        pages[1].skip(1).map((band) => band.showCaptions),
        JournalPager.blankPages(1).first.skip(1).map(
          (band) => band.showCaptions,
        ),
      );
    });

    test('展平后与入参顺序一致', () {
      final entries = [
        for (var i = 0; i < 7; i++) asciiEntry(trainLabel: 'T$i'),
      ];
      final flat = JournalPager.paginate(entries).expand((page) => page).toList();
      final labels = flat
          .where((band) => !band.isEmpty)
          .map((band) => band.entry!.trainLabel)
          .toList();
      expect(labels, ['T0', 'T1', 'T2', 'T3', 'T4', 'T5', 'T6']);
    });
  });

  group('JournalPager.blankPages', () {
    test('每带都印字段名提示', () {
      final pages = JournalPager.blankPages(3);
      expect(pages, hasLength(3));
      for (final page in pages) {
        expect(page, hasLength(3));
        for (final band in page) {
          expect(band.isEmpty, isTrue);
          expect(band.showCaptions, isTrue);
        }
      }
    });

    test('页数下限是 1，免得导出个空文档', () {
      expect(JournalPager.blankPages(0), hasLength(1));
      expect(JournalPager.blankPages(-2), hasLength(1));
    });
  });
}
