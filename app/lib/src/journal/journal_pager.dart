import 'package:raillog/src/journal/journal_entry.dart';
import 'package:raillog/src/journal/journal_layout.dart';

/// 页面上一个行程槽位的内容。
///
/// 两种状态：
/// - [JournalBandData] 带 [entry]：印一趟行程的事实，留白区照常画。
/// - [JournalBandData.blank]：没有行程的槽位，事实区印字段名提示。
///   空白模板与自动导出末页的空槽**用的是同一种**——空槽就是一张
///   空白手账页，用户可以直接手写补记，不该是另一种版式。
class JournalBandData {
  const JournalBandData({this.entry, this.showCaptions = false});

  /// 没有行程的槽位：空白模板样式，印字段名与填空线。
  const JournalBandData.blank() : entry = null, showCaptions = true;

  final JournalEntry? entry;

  /// 是否在事实区印字段名提示（没有行程的槽位都为 true）。
  final bool showCaptions;

  bool get isEmpty => entry == null;
}

/// 把行程排进一页三带的版面。
abstract final class JournalPager {
  /// 一趟行程数占几页。
  static int pageCount(int tripCount) =>
      tripCount <= 0 ? 0 : (tripCount / JournalLayout.tripsPerPage).ceil();

  /// 按给定顺序分页，末页不足三个槽位时用空白模板位垫满。
  /// 展平后与入参顺序一致——手账是正序翻的，分页不能打乱它。
  static List<List<JournalBandData>> paginate(List<JournalEntry> entries) {
    if (entries.isEmpty) return const [];
    final pages = <List<JournalBandData>>[];
    for (var start = 0;
        start < entries.length;
        start += JournalLayout.tripsPerPage) {
      final band = <JournalBandData>[];
      for (var offset = 0; offset < JournalLayout.tripsPerPage; offset++) {
        final index = start + offset;
        band.add(
          index < entries.length
              ? JournalBandData(entry: entries[index])
              : const JournalBandData.blank(),
        );
      }
      pages.add(band);
    }
    return pages;
  }

  /// 空白模板：每页三带，全部为 blank。
  static List<List<JournalBandData>> blankPages(int pages) => List.generate(
    pages <= 0 ? 1 : pages,
    (_) => const [
      JournalBandData.blank(),
      JournalBandData.blank(),
      JournalBandData.blank(),
    ],
  );
}
