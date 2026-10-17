/// 手账版式风格。两种风格共用同一份版面几何（见 [JournalLayout]），
/// 区别只在字体与装饰元素的画法。
///
/// 两种风格**都是白底灰阶**：这份东西是拿来黑白打印的，所以风格差异
/// 交给线型、边框和装饰，不交给颜色。
enum JournalStyle {
  /// 衬线字、整页双线边框、四角装饰与手写横线。
  retro('复古车票簿', '双线边框与四角装饰，像一册旧车票夹', 'assets/fonts/journal_kai.ttf'),

  /// 黑体、细框、左侧竖条、5mm 方格网。
  grid('简约方格本', '方格纸与左侧竖条，像一页方格笔记本', 'assets/fonts/journal_hei.ttf');

  const JournalStyle(this.label, this.description, this.fontAsset);

  final String label;
  final String description;

  /// 该风格排版时嵌入 PDF 的字体资源。
  final String fontAsset;
}

/// 读设置用：非法或缺失的名字回落到 [JournalStyle.retro]。
JournalStyle journalStyleFromName(String? name) => JournalStyle.values.firstWhere(
  (value) => value.name == name,
  orElse: () => JournalStyle.retro,
);
