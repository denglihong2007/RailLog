import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:raillog/src/journal/journal_layout.dart';

void main() {
  group('JournalLayout 整体几何', () {
    test('版心与带高', () {
      expect(JournalLayout.pageWidth, PdfPageFormat.a4.width);
      expect(JournalLayout.pageHeight, PdfPageFormat.a4.height);
      expect(
        JournalLayout.bandWidth,
        closeTo(JournalLayout.pageWidth - JournalLayout.pageMargin * 2, 0.001),
      );
      expect(JournalLayout.tripsPerPage, 3);
      expect(
        JournalLayout.bandHeight,
        closeTo(
          (JournalLayout.pageHeight - JournalLayout.pageMargin * 2) / 3,
          0.001,
        ),
      );
    });

    test('三带首尾相接铺满整页版心，中间无缝', () {
      final bands = [for (var i = 0; i < 3; i++) JournalBandLayout.forIndex(i)];

      expect(bands.first.rect.top, JournalLayout.pageRect.top);
      expect(bands.first.rect.left, JournalLayout.pageRect.left);
      expect(bands.first.rect.right, JournalLayout.pageRect.right);
      expect(bands.last.rect.bottom, closeTo(JournalLayout.pageRect.bottom, 0.001));
      for (var i = 1; i < bands.length; i++) {
        expect(bands[i].rect.top, closeTo(bands[i - 1].rect.bottom, 0.001));
        expect(bands[i].rect.overlaps(bands[i - 1].rect), isFalse);
      }
    });

    test('整页只认一个外框，三带共用', () {
      // 每带各画一圈框会读成三张卡片；外框只该有一份。
      final bands = [for (var i = 0; i < 3; i++) JournalBandLayout.forIndex(i)];
      for (final band in bands) {
        expect(JournalLayout.pageRect.contains(band.rect), isTrue);
      }
      expect(
        JournalLayout.pageRect.height,
        closeTo(JournalLayout.bandHeight * 3, 0.001),
      );
    });

    test('三带几何完全一致，只是整体下移一个带高', () {
      final top = JournalBandLayout.forIndex(0);
      for (var index = 1; index < 3; index++) {
        final band = JournalBandLayout.forIndex(index);
        expect(
          band.rect.top - top.rect.top,
          closeTo(JournalLayout.bandHeight * index, 0.001),
        );
        expect(band.writing.height, closeTo(top.writing.height, 0.001));
      }
    });
  });

  group('JournalBandLayout 区块', () {
    for (final index in [0, 1, 2]) {
      test('第 $index 带的四个区块互不重叠、都落在内区里', () {
        final band = JournalBandLayout.forIndex(index);
        final blocks = <String, JournalRect>{
          'header': band.header,
          'route': band.route,
          'facts': band.facts,
          'writing': band.writing,
        };

        for (final entry in blocks.entries) {
          expect(
            band.inner.contains(entry.value),
            isTrue,
            reason: '${entry.key} 应落在内区里：${entry.value} vs ${band.inner}',
          );
        }

        final names = blocks.keys.toList();
        for (var i = 0; i < names.length; i++) {
          for (var j = i + 1; j < names.length; j++) {
            expect(
              blocks[names[i]]!.overlaps(blocks[names[j]]!),
              isFalse,
              reason: '${names[i]} 与 ${names[j]} 不应重叠',
            );
          }
        }
      });
    }

    test('区块自上而下依次排列', () {
      final band = JournalBandLayout.forIndex(0);
      expect(band.header.bottom, lessThanOrEqualTo(band.route.top));
      expect(band.route.bottom, lessThanOrEqualTo(band.facts.top));
      expect(band.facts.bottom, lessThanOrEqualTo(band.writing.top));
    });

    test('留白比例守住「大部分纸面交给笔」这条产品承诺', () {
      final band = JournalBandLayout.forIndex(0);
      // 去掉贴票区之后，整块留白都归书写区：约 108pt，按面积算占一带
      // 的 39%（横向还有两侧内边距，所以比按高度算的 41% 低一点）。
      expect(band.writing.height, greaterThan(100));
      expect(band.writing.area / band.rect.area, greaterThan(0.38));
    });

    test('横线能排下四条，不是只剩一两条', () {
      final band = JournalBandLayout.forIndex(0);
      final first =
          JournalLayout.promptRowHeight + JournalLayout.firstRuleOffset;
      var count = 0;
      for (var y = first; y <= band.writing.height - 2; y += JournalLayout.ruleGap) {
        count++;
      }
      expect(count, greaterThanOrEqualTo(4));
    });

    test('每带高度取常量后仍有余量，不是被挤出来的', () {
      final band = JournalBandLayout.forIndex(0);
      expect(band.header.height, JournalLayout.headerHeight);
      expect(band.route.height, JournalLayout.routeHeight);
      expect(band.facts.height, JournalLayout.factsHeight);
      expect(
        band.writing.bottom,
        closeTo(band.rect.bottom - JournalLayout.bandPadding, 0.001),
      );
    });
  });

  group('JournalRect', () {
    test('pdfBottom 是唯一一处坐标翻转', () {
      final rect = JournalRect(10, 20, 30, 40);
      expect(rect.right, 40);
      expect(rect.bottom, 60);
      expect(rect.area, 1200);
      // 顶边 y=20 → PDF 坐标 821.889；底边 y=60 → 781.889。
      expect(rect.pdfBottom, closeTo(JournalLayout.pageHeight - 60, 0.001));
    });

    test('deflate 四边同时内收', () {
      final rect = JournalRect(10, 20, 30, 40).deflate(4);
      expect(rect.left, 14);
      expect(rect.top, 24);
      expect(rect.width, 22);
      expect(rect.height, 32);
    });

    test('相接但不重叠的矩形不算重叠', () {
      final a = JournalRect(0, 0, 10, 10);
      final b = JournalRect(0, 10, 10, 10);
      expect(a.overlaps(b), isFalse);
    });

    test('contains 容忍浮点误差', () {
      final outer = JournalRect(0, 0, 100, 100);
      expect(outer.contains(JournalRect(0, 0, 100, 100)), isTrue);
      expect(outer.contains(JournalRect(0, 0, 100, 100.5)), isFalse);
    });
  });

  group('格子步距', () {
    test('方格是 5mm', () {
      expect(JournalLayout.gridStep, closeTo(PdfPageFormat.mm * 5, 0.0001));
    });
  });
}
