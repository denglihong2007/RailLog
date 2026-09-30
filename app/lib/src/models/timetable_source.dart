/// 时刻表来源：在线查询，或本地历史数据库。
///
/// 历史数据库按「快照日期」版本化（见 [resolveTimetableVersion]），版本由行程日期自动推导，
/// 所以这里只区分在线/历史，不再逐个列出年份。
enum TimetableSource {
  online('在线'),
  historical('历史数据库');

  const TimetableSource(this.label);

  final String label;

  bool get isOnline => this == TimetableSource.online;
}
