import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:raillog/src/journal/journal_entry.dart';
import 'package:raillog/src/journal/journal_font_loader.dart';
import 'package:raillog/src/journal/journal_pager.dart';
import 'package:raillog/src/journal/journal_pdf_renderer.dart';
import 'package:raillog/src/journal/journal_style.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/services/download_file_service.dart';

class JournalExportResult {
  const JournalExportResult({
    required this.tripCount,
    required this.pageCount,
    required this.fileName,
    required this.savedPath,
  });

  /// 空白模板是 0 趟。
  final int tripCount;
  final int pageCount;
  final String fileName;
  final String savedPath;
}

class JournalExportException implements Exception {
  const JournalExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract final class JournalExportService {
  static const _tripTitle = 'RailLog 行程手账';
  static const _blankTitle = 'RailLog 空白手账模板';

  /// 把选中的行程排成 A4 手账。顺序由调用方定，这里不重排。
  static Future<JournalExportResult> exportTrips({
    required List<TripRecord> trips,
    required JournalStyle style,
  }) async {
    if (trips.isEmpty) {
      throw const JournalExportException('没有可导出的行程');
    }
    final pages = JournalPager.paginate(
      trips.map(JournalEntry.fromTrip).toList(growable: false),
    );
    return _finish(
      pages: pages,
      style: style,
      documentTitle: _tripTitle,
      namePrefix: 'RailLog_手账',
      tripCount: trips.length,
    );
  }

  /// 空白模板：同样的版面，只印字段名提示，打印后手填。
  static Future<JournalExportResult> exportBlankTemplate({
    required int pageCount,
    required JournalStyle style,
  }) => _finish(
    pages: JournalPager.blankPages(pageCount),
    style: style,
    documentTitle: _blankTitle,
    namePrefix: 'RailLog_空白手账模板',
    tripCount: 0,
  );

  static Future<JournalExportResult> _finish({
    required List<List<JournalBandData>> pages,
    required JournalStyle style,
    required String documentTitle,
    required String namePrefix,
    required int tripCount,
  }) async {
    final bytes = await _render(pages, style, documentTitle);
    final name = '${namePrefix}_${_fileTimestamp(DateTime.now())}';
    final savedPath = await DownloadFileService.save(
      name: name,
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
      androidMimeType: 'application/pdf',
    );
    return JournalExportResult(
      tripCount: tripCount,
      pageCount: pages.length,
      fileName: '$name.pdf',
      savedPath: savedPath,
    );
  }

  static Future<Uint8List> _render(
    List<List<JournalBandData>> pages,
    JournalStyle style,
    String documentTitle,
  ) async {
    try {
      final fonts = await JournalFontLoader.fonts(style);
      return await JournalPdfRenderer.render(
        pages: pages,
        style: style,
        fonts: fonts,
        documentTitle: documentTitle,
      );
    } catch (error) {
      throw JournalExportException('生成手账 PDF 失败：$error');
    }
  }
}

String _fileTimestamp(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}'
    '${value.month.toString().padLeft(2, '0')}'
    '${value.day.toString().padLeft(2, '0')}_'
    '${value.hour.toString().padLeft(2, '0')}'
    '${value.minute.toString().padLeft(2, '0')}'
    '${value.second.toString().padLeft(2, '0')}';
