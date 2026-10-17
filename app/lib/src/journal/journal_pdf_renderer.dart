import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'journal_entry.dart';
import 'journal_layout.dart';
import 'journal_pager.dart';
import 'journal_style.dart';

/// 落版时要嵌进 PDF 的字体。
///
/// 字体是**从外面传进来的**，渲染器自己一个字节都不读——所以整个排版能在
/// 普通 `test()` 里用 `pw.Font.helvetica()` 跑通，不必启 widget binding，
/// 也就不会踩上 sqflite / rootBundle 在测试里静默挂死那个坑。
class JournalFonts {
  const JournalFonts({
    required this.base,
    this.bold,
    this.fallback = const [],
  });

  final pw.Font base;

  /// 粗体字重用的字体。楷体/黑体子集都只有一个字重，所以导出时留空，
  /// 由 [theme] 回落到 [base]——同一个 Font 对象在 PDF 里仍只嵌一份。
  final pw.Font? bold;

  /// 兜底字体。两份子集来自同一份字符集，互相兜底是空转，
  /// 所以导出时留空，缺字交给 `--notdef-outline` 画成看得见的空框。
  final List<pw.Font> fallback;

  pw.ThemeData get theme => pw.ThemeData.withFont(
    base: base,
    bold: bold ?? base,
    fontFallback: fallback.isEmpty ? null : fallback,
  );
}

/// 一种风格用到的全部颜色。
///
/// **只有灰阶**：这份东西是拿来黑白打印的，彩色条目在激光打印机上会
/// 变成一坨不均匀的中灰，比纯黑难看得多。风格之间的差异交给线型、
/// 边框和装饰，不交给颜色。
class _Palette {
  const _Palette({
    required this.ink,
    required this.inkSoft,
    required this.frameOuter,
    required this.frameInner,
    required this.hairline,
    required this.accentRail,
    required this.accentNonRail,
    required this.accentEmpty,
  });

  final PdfColor ink;
  final PdfColor inkSoft;
  final PdfColor frameOuter;
  final PdfColor frameInner;
  final PdfColor hairline;
  final PdfColor accentRail;
  final PdfColor accentNonRail;
  final PdfColor accentEmpty;

  /// 复古车票簿：整页双线框 + 四角三角 + 手写横线。
  static const retro = _Palette(
    ink: PdfColor.fromInt(0x212121),
    inkSoft: PdfColor.fromInt(0x6E6E6E),
    frameOuter: PdfColor.fromInt(0x3A3A3A),
    frameInner: PdfColor.fromInt(0x9A9A9A),
    hairline: PdfColor.fromInt(0xC4C4C4),
    accentRail: PdfColor.fromInt(0x3A3A3A),
    accentNonRail: PdfColor.fromInt(0x6E6E6E),
    accentEmpty: PdfColor.fromInt(0xCFCFCF),
  );

  /// 简约方格本：细框 + 左侧竖条 + 5mm 格子。
  static const grid = _Palette(
    ink: PdfColor.fromInt(0x212121),
    inkSoft: PdfColor.fromInt(0x6E6E6E),
    frameOuter: PdfColor.fromInt(0xB4B4B4),
    frameInner: PdfColor.fromInt(0xB4B4B4),
    hairline: PdfColor.fromInt(0xDCDCDC),
    accentRail: PdfColor.fromInt(0x212121),
    accentNonRail: PdfColor.fromInt(0x7A7A7A),
    accentEmpty: PdfColor.fromInt(0xD0D0D0),
  );

  /// 左侧竖条的颜色：铁路黑 / 非铁路中灰 / 空格子浅灰。
  PdfColor accentFor(JournalBandData band) {
    final entry = band.entry;
    if (entry == null) return accentEmpty;
    return entry.isRailTrip ? accentRail : accentNonRail;
  }
}

/// 把分好页的行程排成 A4 PDF。排版逻辑全在纯函数里，只有 [render] 碰 `pdf` 包。
abstract final class JournalPdfRenderer {
  /// [pages] 每项是一页，固定 [JournalLayout.tripsPerPage] 个槽位。
  ///
  /// 不印页码：这份东西是打进活页本的，页码没有意义，还会在重新装订
  /// 之后变成错的。文件身份交给 PDF 元数据里的 [documentTitle]。
  static Future<Uint8List> render({
    required List<List<JournalBandData>> pages,
    required JournalStyle style,
    required JournalFonts fonts,
    String documentTitle = 'RailLog 行程手账',
  }) async {
    assert(pages.isNotEmpty, '空文档不是合法 PDF，调用方要先保证至少一页');
    final palette = style == JournalStyle.grid ? _Palette.grid : _Palette.retro;
    final document = pw.Document(
      title: documentTitle,
      author: 'RailLog',
      creator: 'RailLog',
      producer: 'RailLog',
    );

    for (final bands in pages) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          // 必须显式清零：pw.Page 默认约 2cm 边距，不清零所有坐标整体下移。
          margin: pw.EdgeInsets.zero,
          theme: fonts.theme,
          build: (context) => pw.Stack(
            children: [
              // 非 Positioned 的整页 CustomPaint 定出 Stack 尺寸，
              // 不依赖「只有 Positioned 时撑满约束」那个隐式行为。
              pw.CustomPaint(
                size: PdfPoint(JournalLayout.pageWidth, JournalLayout.pageHeight),
                painter: (canvas, size) =>
                    _paintPage(canvas, size, bands, style, palette),
              ),
              for (var band = 0; band < bands.length; band++)
                ..._bandContent(
                  bands[band],
                  JournalBandLayout.forIndex(band),
                  palette,
                ),
            ],
          ),
        ),
      );
    }
    return document.save();
  }
}

// ---------------------------------------------------------------- 装饰层
// 本段全部在 PdfGraphics 上作画，坐标是左下原点、y 向上。
// 每处 y 都过一遍 JournalLayout.pdfY / JournalRect.pdfBottom，别手写翻转。

void _paintPage(
  PdfGraphics canvas,
  PdfPoint size,
  List<JournalBandData> bands,
  JournalStyle style,
  _Palette palette,
) {
  final page = JournalLayout.pageRect;

  // 一页只画一套外框、只在页的四角画装饰。三带各自封边会读成三张卡片，
  // 一页纸就不连续了。
  if (style == JournalStyle.retro) {
    _strokeRect(canvas, page, color: palette.frameOuter, width: 1.2, bottom: true);
    _strokeRect(
      canvas,
      page.deflate(4),
      color: palette.frameInner,
      width: 0.5,
      bottom: true,
    );
    _cornerTriangles(canvas, page.deflate(4), palette.frameOuter);
  } else {
    // 左侧竖条按带着色，但段与段首尾相接，整页看下来是一条连续竖线。
    for (var index = 0; index < bands.length; index++) {
      final rect = JournalBandLayout.forIndex(index).rect;
      canvas
        ..setFillColor(palette.accentFor(bands[index]))
        ..drawRect(
          page.left,
          rect.pdfBottom,
          JournalLayout.accentBarWidth,
          rect.height,
        )
        ..fillPath();
    }
    _strokeRect(canvas, page, color: palette.frameOuter, width: 0.5, bottom: true);
  }

  // 行程之间的分隔线。比外框轻一档，和书写线区分开：
  // 它只负责「这里是下一趟」，不该像框一样把纸切断。
  for (var index = 0; index < bands.length - 1; index++) {
    _separator(
      canvas,
      JournalBandLayout.forIndex(index).rect.bottom,
      style,
      palette,
    );
  }

  for (var index = 0; index < bands.length; index++) {
    _paintBand(canvas, JournalBandLayout.forIndex(index), style, palette);
  }
}

void _paintBand(
  PdfGraphics canvas,
  JournalBandLayout band,
  JournalStyle style,
  _Palette palette,
) {
  if (style == JournalStyle.retro) {
    _writingRules(canvas, band.writing, palette.hairline);
  } else {
    // 5mm 方格只铺书写区，且**让开勾选行**：
    // 天气/心情/评分那几个字压在格线上会糊成一团。
    // 不另画横线，否则两套步距叠出摩尔纹。
    _grid(
      canvas,
      JournalRect(
        band.writing.left,
        band.writing.top + JournalLayout.promptRowHeight,
        band.writing.width,
        band.writing.height - JournalLayout.promptRowHeight,
      ),
      palette.hairline,
    );
  }
}

/// 带与带之间的分隔线。复古风用一实一虚两条细线（像票根的骑缝），
/// 方格本用一条和格线同粗的实线，看上去仍是同一张格子纸。
void _separator(
  PdfGraphics canvas,
  double y,
  JournalStyle style,
  _Palette palette,
) {
  final page = JournalLayout.pageRect;
  final inset = style == JournalStyle.retro ? 4.0 : 0.0;
  final left = page.left + inset;
  final right = page.right - inset;

  if (style == JournalStyle.retro) {
    canvas
      ..setStrokeColor(palette.frameInner)
      ..setLineWidth(0.7)
      ..drawLine(left, JournalLayout.pdfY(y - 1.4), right, JournalLayout.pdfY(y - 1.4))
      ..strokePath()
      ..setStrokeColor(palette.hairline)
      ..setLineWidth(0.4)
      ..setLineDashPattern(const [2, 2])
      ..drawLine(left, JournalLayout.pdfY(y + 1.4), right, JournalLayout.pdfY(y + 1.4))
      ..strokePath()
      ..setLineDashPattern();
  } else {
    canvas
      ..setStrokeColor(palette.frameOuter)
      ..setLineWidth(0.5)
      ..drawLine(left, JournalLayout.pdfY(y), right, JournalLayout.pdfY(y))
      ..strokePath();
  }
}

/// 画整页外框。顶边恒画，底边按 [bottom] 决定（末页总是要底边的）。
void _strokeRect(
  PdfGraphics canvas,
  JournalRect rect, {
  required PdfColor color,
  required double width,
  required bool bottom,
}) {
  final yTop = JournalLayout.pdfY(rect.top);
  final yBottom = JournalLayout.pdfY(rect.bottom);
  canvas
    ..setStrokeColor(color)
    ..setLineWidth(width)
    ..drawLine(rect.left, yTop, rect.left, yBottom)
    ..drawLine(rect.right, yTop, rect.right, yBottom)
    ..drawLine(rect.left, yTop, rect.right, yTop);
  if (bottom) canvas.drawLine(rect.left, yBottom, rect.right, yBottom);
  canvas.strokePath();
}

void _cornerTriangles(PdfGraphics canvas, JournalRect rect, PdfColor color) {
  const leg = 12.0;
  canvas.setFillColor(color);
  _triangle(canvas, rect.left, rect.top, 1, 1, leg);
  _triangle(canvas, rect.right, rect.top, -1, 1, leg);
  _triangle(canvas, rect.left, rect.bottom, 1, -1, leg);
  _triangle(canvas, rect.right, rect.bottom, -1, -1, leg);
}

/// 在 ([x], [y]) 处向 ([dx], [dy]) 方向铺一个直角边为 [leg] 的实心三角。
void _triangle(
  PdfGraphics canvas,
  double x,
  double y,
  double dx,
  double dy,
  double leg,
) {
  canvas
    ..moveTo(x, JournalLayout.pdfY(y))
    ..lineTo(x + dx * leg, JournalLayout.pdfY(y))
    ..lineTo(x, JournalLayout.pdfY(y + dy * leg))
    ..closePath()
    ..fillPath();
}

void _writingRules(PdfGraphics canvas, JournalRect writing, PdfColor color) {
  canvas
    ..setStrokeColor(color)
    ..setLineWidth(0.5)
    ..setLineDashPattern(const [1.5, 2.5]);
  var y =
      writing.top + JournalLayout.promptRowHeight + JournalLayout.firstRuleOffset;
  while (y <= writing.bottom - 2) {
    canvas.drawLine(
      writing.left,
      JournalLayout.pdfY(y),
      writing.right,
      JournalLayout.pdfY(y),
    );
    y += JournalLayout.ruleGap;
  }
  canvas
    ..strokePath()
    ..setLineDashPattern();
}

void _grid(PdfGraphics canvas, JournalRect region, PdfColor color) {
  final step = JournalLayout.gridStep;
  canvas
    ..setStrokeColor(color)
    ..setLineWidth(0.25);
  for (var x = region.left; x <= region.right + 0.01; x += step) {
    canvas.drawLine(
      x,
      JournalLayout.pdfY(region.top),
      x,
      JournalLayout.pdfY(region.bottom),
    );
  }
  for (var y = region.top; y <= region.bottom + 0.01; y += step) {
    canvas.drawLine(
      region.left,
      JournalLayout.pdfY(y),
      region.right,
      JournalLayout.pdfY(y),
    );
  }
  canvas.strokePath();
}

// ---------------------------------------------------------------- 内容层
// 本段是普通 pw widget，坐标是左上原点、y 向下，直接用 JournalRect 的字段。

pw.TextStyle _text(double size, PdfColor color, {double height = 1.2}) =>
    pw.TextStyle(fontSize: size, color: color, height: height);

pw.Widget _at(JournalRect rect, pw.Widget child) => pw.Positioned(
  left: rect.left,
  top: rect.top,
  child: pw.SizedBox(width: rect.width, height: rect.height, child: child),
);

List<pw.Widget> _bandContent(
  JournalBandData data,
  JournalBandLayout band,
  _Palette palette,
) {
  final entry = data.entry;
  return [
    if (entry != null) ...[
      _at(band.header, _header(entry, palette)),
      _at(band.route, _route(entry, palette)),
      _at(band.facts, _facts(entry, palette, band.facts.width)),
    ] else if (data.showCaptions) ...[
      _at(band.header, _blankHeader(palette)),
      _at(band.route, _blankRoute(palette)),
      _at(band.facts, _blankFacts(palette)),
    ],
    // 勾选行两支风格都有，空格子也印——它属于留白区，不属于事实区。
    _at(band.writing, _writing(entry?.notesLabel ?? '', palette)),
  ];
}

// ---------------------------------------------------------------- 已填内容

pw.Widget _header(JournalEntry entry, _Palette palette) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.center,
  children: [
    pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            entry.trainLabel,
            style: _text(18, palette.ink, height: 1.1),
            maxLines: 1,
          ),
          pw.Text(entry.kindLabel, style: _text(7.5, palette.inkSoft), maxLines: 1),
        ],
      ),
    ),
    pw.Text(
      '${entry.dateLabel}  ${entry.weekdayLabel}',
      style: _text(10, palette.ink),
      maxLines: 1,
    ),
  ],
);

pw.Widget _route(JournalEntry entry, _Palette palette) => pw.Column(
  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
  children: [
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _station(
            entry.fromStation,
            entry.departLabel,
            pw.CrossAxisAlignment.start,
            palette,
          ),
        ),
        pw.SizedBox(
          width: 30,
          child: pw.Center(
            child: pw.Text('→', style: _text(14, palette.inkSoft)),
          ),
        ),
        pw.Expanded(
          child: _station(
            entry.toStation,
            entry.arriveLabel,
            pw.CrossAxisAlignment.end,
            palette,
          ),
        ),
      ],
    ),
    _routeMeta(entry, palette),
  ],
);

pw.Widget _station(
  String name,
  String time,
  pw.CrossAxisAlignment align,
  _Palette palette,
) => pw.Column(
  crossAxisAlignment: align,
  children: [
    pw.Text(name, style: _text(14, palette.ink, height: 1.1), maxLines: 1),
    pw.Text(time, style: _text(10.5, palette.inkSoft), maxLines: 1),
  ],
);

/// 「历时 4时38分   里程 1318 km」贴左，「经 京沪高速铁路」贴右。
pw.Widget _routeMeta(JournalEntry entry, _Palette palette) {
  final parts = <String>[
    if (entry.durationLabel.isNotEmpty) '历时 ${entry.durationLabel}',
    if (entry.mileageLabel != JournalFormatter.unknown) '里程 ${entry.mileageLabel}',
  ];
  return pw.Row(
    children: [
      pw.Expanded(
        child: pw.Text(
          parts.join('   '),
          style: _text(8.5, palette.inkSoft),
          maxLines: 1,
        ),
      ),
      if (entry.routeLabel.isNotEmpty)
        pw.Expanded(
          child: pw.Text(
            entry.routeLabel,
            style: _text(8.5, palette.inkSoft),
            textAlign: pw.TextAlign.right,
            maxLines: 1,
          ),
        ),
    ],
  );
}

/// 两行：编组独占一行（这样动车组号串不会被挤成「…」），
/// 第二行左边席别、右边票价。
///
/// 编组按 [width] 估算宽度后再决定要不要截——它是半角车组号串，
/// 固定字数截会把明明放得下的内容切掉。
pw.Widget _facts(JournalEntry entry, _Palette palette, double width) =>
    pw.Column(
  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
  children: [
    pw.Text(
      JournalFormatter.fit(
        entry.rollingStockLabel,
        maxWidth: width,
        fontSize: 9.5,
      ),
      style: _text(9.5, palette.inkSoft),
      maxLines: 1,
    ),
    pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            entry.seatLabel,
            style: _text(9.5, palette.ink),
            maxLines: 1,
          ),
        ),
        pw.Text(entry.priceLabel, style: _text(11.5, palette.ink), maxLines: 1),
      ],
    ),
  ],
);

/// 勾选行 + 一条备注。备注贴着第一条横线印，像已经写上去的一行。
pw.Widget _writing(String notesLabel, _Palette palette) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
  children: [
    pw.SizedBox(
      height: JournalLayout.promptRowHeight,
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(JournalLayout.weatherPrompt, style: _text(8, palette.inkSoft)),
          pw.Text(JournalLayout.moodPrompt, style: _text(8, palette.inkSoft)),
          pw.Text(JournalLayout.ratingPrompt, style: _text(8, palette.inkSoft)),
        ],
      ),
    ),
    if (notesLabel.isNotEmpty)
      pw.Text(
        '备注  $notesLabel',
        style: _text(8, palette.inkSoft, height: 1),
        maxLines: 1,
      ),
  ],
);

// ---------------------------------------------------------------- 空白模板
// 结构与已填版**逐块对应**：同样的 header/route/facts 三段、同样的字号层级、
// 同样的位置，只是把数据换成「字段名 + 填空线」。这样印出来的空白模板
// 和自动生成的手账是同一张纸，混装进活页本不会有两种版式。

/// 填空线。`_` 在 ASCII 里，字体子集一定收录。
String _fill(int count) => '_' * count;

pw.Widget _blankHeader(_Palette palette) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.center,
  children: [
    pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        // 拉开两行：紧挨着的话「类型」会贴上「车次」的填空线。
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '车次 ${_fill(10)}',
            style: _text(13, palette.inkSoft, height: 1.1),
            maxLines: 1,
          ),
          pw.Text(
            '行程类型 ${_fill(8)}',
            style: _text(7.5, palette.inkSoft),
            maxLines: 1,
          ),
        ],
      ),
    ),
    pw.Text(
      '日期 ${_fill(12)}  星期 ____',
      style: _text(10, palette.inkSoft),
      maxLines: 1,
    ),
  ],
);

pw.Widget _blankRoute(_Palette palette) => pw.Column(
  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
  children: [
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _blankStation('出发站 ${_fill(8)}', pw.CrossAxisAlignment.start, palette),
        ),
        pw.SizedBox(
          width: 30,
          child: pw.Center(
            child: pw.Text('→', style: _text(14, palette.inkSoft)),
          ),
        ),
        pw.Expanded(
          child: _blankStation('到达站 ${_fill(8)}', pw.CrossAxisAlignment.end, palette),
        ),
      ],
    ),
    pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            '历时 ${_fill(8)}   里程 ${_fill(6)} km',
            style: _text(8.5, palette.inkSoft),
            maxLines: 1,
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            '经 ${_fill(20)}',
            style: _text(8.5, palette.inkSoft),
            textAlign: pw.TextAlign.right,
            maxLines: 1,
          ),
        ),
      ],
    ),
  ],
);

pw.Widget _blankStation(
  String label,
  pw.CrossAxisAlignment align,
  _Palette palette,
) => pw.Column(
  crossAxisAlignment: align,
  children: [
    pw.Text(label, style: _text(11, palette.inkSoft, height: 1.1), maxLines: 1),
    pw.Text('__:__', style: _text(10.5, palette.inkSoft), maxLines: 1),
  ],
);

pw.Widget _blankFacts(_Palette palette) => pw.Column(
  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
  children: [
    pw.Text(
      '编组 ${_fill(50)}',
      style: _text(9.5, palette.inkSoft),
      maxLines: 1,
    ),
    pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            '席别 ${_fill(12)}',
            style: _text(9.5, palette.inkSoft),
            maxLines: 1,
          ),
        ),
        pw.Text(
          '票价 ${_fill(10)}',
          style: _text(11.5, palette.inkSoft),
          maxLines: 1,
        ),
      ],
    ),
  ],
);
