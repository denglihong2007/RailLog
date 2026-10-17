import 'package:pdf/pdf.dart';

/// 版面上的一块矩形。
///
/// 坐标一律「左上原点、y 向下」，与 `pw.Positioned` / `pw.Stack` 一致。
/// `PdfGraphics` 是左下原点、y 向上，两套坐标的换算只在 [pdfBottom] 里做一次。
class JournalRect {
  const JournalRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get area => width * height;

  /// 本矩形下边缘在 `PdfGraphics` 坐标里的 y。
  /// `drawRect(x, pdfBottom, width, height)` 才是「左上原点」描述的那块矩形。
  double get pdfBottom => JournalLayout.pageHeight - bottom;

  bool contains(JournalRect other) =>
      other.left >= left - _epsilon &&
      other.top >= top - _epsilon &&
      other.right <= right + _epsilon &&
      other.bottom <= bottom + _epsilon;

  /// 四边同时向内收 [delta]。负数即向外放。
  JournalRect deflate(double delta) =>
      JournalRect(left + delta, top + delta, width - delta * 2, height - delta * 2);

  bool overlaps(JournalRect other) =>
      left < other.right - _epsilon &&
      right > other.left + _epsilon &&
      top < other.bottom - _epsilon &&
      bottom > other.top + _epsilon;

  static const double _epsilon = 0.01;

  @override
  String toString() =>
      'JournalRect(${left.toStringAsFixed(2)}, ${top.toStringAsFixed(2)}, '
      '${width.toStringAsFixed(2)}x${height.toStringAsFixed(2)})';
}

/// 一个行程带（整页纵向三等分中的一格）内部的区块几何。
///
/// 区块自上而下依次是：事实头 [header]、区间 [route]、事实尾 [facts]、
/// 手写区 [writing]。除 [writing] 吃掉剩余高度外，其余高度都是常量，
/// 改动集中在本文件。
class JournalBandLayout {
  const JournalBandLayout._({
    required this.rect,
    required this.inner,
    required this.header,
    required this.route,
    required this.facts,
    required this.writing,
  });

  /// 含边框与内边距的整带。
  final JournalRect rect;

  /// 去掉内边距后的可用区。
  final JournalRect inner;

  final JournalRect header;
  final JournalRect route;
  final JournalRect facts;

  /// 手写留白区：顶部一条勾选行，其余是横线/方格书写区。
  final JournalRect writing;

  /// 第 [index] 带（0 = 最上）的几何。
  static JournalBandLayout forIndex(int index) {
    final bandTop = JournalLayout.pageMargin + index * JournalLayout.bandHeight;
    final rect = JournalRect(
      JournalLayout.pageMargin,
      bandTop,
      JournalLayout.bandWidth,
      JournalLayout.bandHeight,
    );

    final innerLeft = rect.left + JournalLayout.bandPadding;
    final innerTop = rect.top + JournalLayout.bandPadding;
    final innerWidth = rect.width - JournalLayout.bandPadding * 2;

    var cursor = innerTop;
    JournalRect take(double height) {
      final block = JournalRect(innerLeft, cursor, innerWidth, height);
      cursor += height + JournalLayout.sectionGap;
      return block;
    }

    final header = take(JournalLayout.headerHeight);
    final route = take(JournalLayout.routeHeight);
    // 事实尾用手写区上方的块间距（更大一档）与后面隔开。
    final facts = JournalRect(
      innerLeft,
      cursor,
      innerWidth,
      JournalLayout.factsHeight,
    );
    cursor += JournalLayout.factsHeight + JournalLayout.blockGap;

    // 手写区吃掉剩余高度，保证各带底边平齐。
    final writingBottom = rect.bottom - JournalLayout.bandPadding;
    final writing = JournalRect(
      innerLeft,
      cursor,
      innerWidth,
      writingBottom - cursor,
    );

    return JournalBandLayout._(
      rect: rect,
      inner: JournalRect(
        innerLeft,
        innerTop,
        innerWidth,
        rect.height - JournalLayout.bandPadding * 2,
      ),
      header: header,
      route: route,
      facts: facts,
      writing: writing,
    );
  }
}

/// A4 纵向、一页三带的版面常量。
///
/// 尺寸单位都是 PDF 点（1pt = 1/72 inch）。A4 = 595.276 × 841.890pt。
///
/// 一页三带是**整页使用**的排法，不沿中线裁开——所以没有裁切线，
/// 整页只画一个外框，三带之间只用一条细分隔线断开，读起来是一张
/// 连续的手账纸而不是三张卡片；也不印页码，方便直接打进活页本。
abstract final class JournalLayout {
  static final double pageWidth = PdfPageFormat.a4.width;
  static final double pageHeight = PdfPageFormat.a4.height;

  /// 每页三个行程。
  static const int tripsPerPage = 3;

  static const double pageMargin = 28;
  static const double bandPadding = 12;

  static final double bandWidth = pageWidth - pageMargin * 2;

  /// 一页三等分后的带高，约 261.96pt（92mm）。
  static final double bandHeight =
      (pageHeight - pageMargin * 2) / tripsPerPage;

  /// 整页版心。三带共用这一个外框，四角装饰也只画在页的四角上。
  static final JournalRect pageRect = JournalRect(
    pageMargin,
    pageMargin,
    bandWidth,
    pageHeight - pageMargin * 2,
  );

  // 一页三带后每带只有约 92mm，各块都收紧过；写入区高度由这些常量算出来。
  static const double headerHeight = 32;
  static const double routeHeight = 50;
  static const double factsHeight = 28;

  /// 相邻区块之间的间距。
  static const double sectionGap = 5;

  /// 大块之间（事实尾↔手写区）的间距。留够一档，免得票价行贴上「天气」。
  static const double blockGap = 10;

  /// 手写区顶部的勾选行高度。
  static const double promptRowHeight = 16;

  /// 手写横线的行距，约 6.4mm。
  static const double ruleGap = 18;

  /// 第一条横线相对勾选行底部的下沉量。
  static const double firstRuleOffset = 10;

  /// 方格本的格距，5mm。
  static final double gridStep = PdfPageFormat.mm * 5;

  /// 「左上原点、y 向下」的 y 换算成 `PdfGraphics` 的 y。画单条横线时用。
  static double pdfY(double y) => pageHeight - y;

  /// 左侧竖条宽度（仅方格本风格使用）。
  static const double accentBarWidth = 6;

  /// 勾选行里的自填项。方框用 GB2312 收录的 □(U+25A1)，
  /// 不要用 ☐(U+2610)——字体子集里没有它，印出来是空框。
  static const String weatherPrompt = '天气  □晴 □阴 □雨 □雪';
  static const String moodPrompt = '心情  □愉悦 □平静 □疲惫';
  static const String ratingPrompt = '评分  □□□□□';
}
